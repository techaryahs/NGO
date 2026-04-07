import 'dart:async';
import '../models/room_model.dart';
import '../models/stay_model.dart';
import 'firebase_rtdb_rest_service.dart';

/// Service layer for Room & Stay management.
///
/// Handles room CRUD, bed/attendant tracking, stay creation,
/// extensions, and dynamic pricing from admin settings.
class RoomService {
  final FirebaseRTDBRestService _rtdb;

  static const String _roomsPath = 'rooms';
  static const String _staysPath = 'stays';
  static const String _pricingPath = 'admin_settings/pricing';

  RoomService({required FirebaseRTDBRestService rtdbService})
      : _rtdb = rtdbService;

  // ===========================================================================
  // ADMIN SETTINGS — Dynamic Pricing
  // ===========================================================================

  /// Default pricing values (used as seed if admin_settings/pricing is empty).
  static const Map<String, dynamic> defaultPricing = {
    'privateRoomBasePrice': 600,
    'privateRoomIncludedAttendants': 2,
    'privateRoomExtraAttendantFee': 200,
    'privateRoomMaxAttendants': 5,
    'generalRoomBedPrice': 150,
    'generalRoomDefaultBeds': 4,
    'generalRoomIncludedAttendants': 1,
    'generalRoomMaxAttendants': 2,
  };

  /// Fetch dynamic pricing from /admin_settings/pricing.
  /// Seeds default values if the node doesn't exist yet.
  Future<Map<String, dynamic>> getPricing() async {
    try {
      final data = await _rtdb.get(_pricingPath);
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      // Seed default pricing if empty
      await _rtdb.put(_pricingPath, Map<String, dynamic>.from(defaultPricing));
      return Map<String, dynamic>.from(defaultPricing);
    } catch (e) {
      throw Exception('Failed to fetch pricing: $e');
    }
  }

  /// Update pricing settings.
  Future<void> updatePricing(Map<String, dynamic> pricing) async {
    try {
      await _rtdb.patch(_pricingPath, pricing);
    } catch (e) {
      throw Exception('Failed to update pricing: $e');
    }
  }

  /// Stream of pricing settings.
  Stream<Map<String, dynamic>> getPricingStream() {
    return _rtdb.stream(_pricingPath).map((data) {
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return Map<String, dynamic>.from(defaultPricing);
    });
  }

  // ===========================================================================
  // ROOMS — CRUD
  // ===========================================================================

  /// Stream of ALL rooms
  Stream<List<RoomModel>> getRoomsStream() {
    return _rtdb.stream(_roomsPath).map((data) {
      final List<RoomModel> rooms = [];
      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        mapData.forEach((key, value) {
          if (value is Map) {
            rooms.add(
              RoomModel.fromMap(key, Map<String, dynamic>.from(value)),
            );
          }
        });
        rooms.sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
      }
      return rooms;
    }).handleError((error) {
      return <RoomModel>[];
    });
  }

  /// Stream of rooms filtered by type ('private' or 'general')
  Stream<List<RoomModel>> getRoomsByTypeStream(String type) {
    return getRoomsStream().map(
      (rooms) => rooms.where((r) => r.roomType == type).toList(),
    );
  }

  /// Stream of rooms on a specific floor
  Stream<List<RoomModel>> getRoomsByFloorStream(int floor) {
    return getRoomsStream().map(
      (rooms) => rooms.where((r) => r.floor == floor).toList(),
    );
  }

  /// Fetch a single room
  Future<RoomModel?> getRoom(String roomId) async {
    try {
      final data = await _rtdb.get('$_roomsPath/$roomId');
      if (data != null && data is Map) {
        return RoomModel.fromMap(roomId, Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch room: $e');
    }
  }

  /// Add a new room.
  Future<String> addRoom({
    required String roomNumber,
    required int floor,
    required String roomType,
    int? maxAttendants,
    int? totalBeds,
    String? notes,
  }) async {
    try {
      final now = DateTime.now();
      final pricing = await getPricing();

      final room = RoomModel(
        id: 'temp',
        roomNumber: roomNumber,
        floor: floor,
        roomType: roomType,
        status: 'available',
        maxAttendants: maxAttendants ??
            (roomType == 'private'
                ? _parseIntSafe(pricing['privateRoomMaxAttendants'], 5)
                : _parseIntSafe(pricing['generalRoomMaxAttendants'], 2)),
        totalBeds: totalBeds ??
            (roomType == 'general'
                ? _parseIntSafe(pricing['generalRoomDefaultBeds'], 4)
                : 0),
        notes: notes,
        createdAt: now,
        updatedAt: now,
      );

      final roomId = await _rtdb.push(_roomsPath, room.toMap());
      await _rtdb.patch('$_roomsPath/$roomId', {'id': roomId});
      return roomId;
    } catch (e) {
      throw Exception('Failed to add room: $e');
    }
  }

  /// Update a room.
  Future<void> updateRoom(
      String roomId, Map<String, dynamic> updates) async {
    try {
      updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      await _rtdb.patch('$_roomsPath/$roomId', updates);
    } catch (e) {
      throw Exception('Failed to update room: $e');
    }
  }

  /// Delete a room.
  Future<void> deleteRoom(String roomId) async {
    try {
      await _rtdb.delete('$_roomsPath/$roomId');
    } catch (e) {
      throw Exception('Failed to delete room: $e');
    }
  }

  // ===========================================================================
  // STAYS — CRUD & Business Logic
  // ===========================================================================

  /// Stream of ALL stays
  Stream<List<StayModel>> getStaysStream() {
    return _rtdb.stream(_staysPath).map((data) {
      final List<StayModel> stays = [];
      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        mapData.forEach((key, value) {
          if (value is Map) {
            stays.add(
              StayModel.fromMap(key, Map<String, dynamic>.from(value)),
            );
          }
        });
        stays.sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
      }
      return stays;
    });
  }

  /// Stream of active stays
  Stream<List<StayModel>> getActiveStaysStream() {
    return getStaysStream().map(
      (stays) => stays.where((s) => s.status == 'active').toList(),
    );
  }

  /// Stream of stays for a specific room
  Stream<List<StayModel>> getStaysByRoomStream(String roomId) {
    return getStaysStream().map(
      (stays) =>
          stays.where((s) => s.roomId == roomId && s.status == 'active').toList(),
    );
  }

  /// Stream of stays for a specific patient
  Stream<List<StayModel>> getStaysByPatientStream(String patientId) {
    return getStaysStream().map(
      (stays) => stays.where((s) => s.patientId == patientId).toList(),
    );
  }

  /// Create a new stay — assigns patient to room + calculates pricing.
  Future<String> createStay({
    required String patientId,
    required String patientName,
    required String roomId,
    required String roomNumber,
    required String roomType,
    required DateTime admissionDate,
    required int durationDays,
    required int attendantCount,
    int? bedNumber,
    String? notes,
    required String createdBy,
  }) async {
    try {
      final pricing = await getPricing();
      final now = DateTime.now();

      // Calculate costs
      double baseCost = 0;
      double extraAttendantCost = 0;

      if (roomType == 'private') {
        final basePrice =
            _parseDoubleSafe(pricing['privateRoomBasePrice'], 600);
        final includedAttendants =
            _parseIntSafe(pricing['privateRoomIncludedAttendants'], 2);
        final extraFee =
            _parseDoubleSafe(pricing['privateRoomExtraAttendantFee'], 200);

        baseCost = basePrice * durationDays;
        final extras = attendantCount > includedAttendants
            ? attendantCount - includedAttendants
            : 0;
        extraAttendantCost = extras * extraFee * durationDays;
      } else {
        final bedPrice =
            _parseDoubleSafe(pricing['generalRoomBedPrice'], 150);
        baseCost = bedPrice * durationDays;
      }

      final totalCost = baseCost + extraAttendantCost;
      final expiryDate = admissionDate.add(Duration(days: durationDays));

      final stay = StayModel(
        id: 'temp',
        patientId: patientId,
        patientName: patientName,
        roomId: roomId,
        roomNumber: roomNumber,
        roomType: roomType,
        admissionDate: admissionDate,
        durationDays: durationDays,
        expiryDate: expiryDate,
        attendantCount: attendantCount,
        totalCost: totalCost,
        baseCost: baseCost,
        extraAttendantCost: extraAttendantCost,
        status: 'active',
        bedNumber: bedNumber,
        notes: notes,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );

      final stayId = await _rtdb.push(_staysPath, stay.toMap());
      await _rtdb.patch('$_staysPath/$stayId', {'id': stayId});

      // Update room status
      if (roomType == 'private') {
        await updateRoom(roomId, {
          'status': 'occupied',
          'currentAttendants': attendantCount,
        });
      } else {
        // General room: increment occupied beds
        final room = await getRoom(roomId);
        if (room != null) {
          final newOccupied = room.occupiedBeds + 1;
          await updateRoom(roomId, {
            'occupiedBeds': newOccupied,
            'status': newOccupied >= room.totalBeds ? 'occupied' : 'available',
          });
        }
      }

      return stayId;
    } catch (e) {
      throw Exception('Failed to create stay: $e');
    }
  }

  /// Extend an active stay by [additionalDays].
  Future<void> extendStay({
    required String stayId,
    required int additionalDays,
    String reason = '',
  }) async {
    try {
      final data = await _rtdb.get('$_staysPath/$stayId');
      if (data == null || data is! Map) {
        throw Exception('Stay not found');
      }

      final stay = StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      final pricing = await getPricing();

      // Calculate additional cost
      double additionalCost = 0;
      if (stay.roomType == 'private') {
        final basePrice =
            _parseDoubleSafe(pricing['privateRoomBasePrice'], 600);
        final includedAttendants =
            _parseIntSafe(pricing['privateRoomIncludedAttendants'], 2);
        final extraFee =
            _parseDoubleSafe(pricing['privateRoomExtraAttendantFee'], 200);

        additionalCost = basePrice * additionalDays;
        final extras = stay.attendantCount > includedAttendants
            ? stay.attendantCount - includedAttendants
            : 0;
        additionalCost += extras * extraFee * additionalDays;
      } else {
        final bedPrice =
            _parseDoubleSafe(pricing['generalRoomBedPrice'], 150);
        additionalCost = bedPrice * additionalDays;
      }

      // Build updated extensions list
      final extensionEntry = StayExtension(
        additionalDays: additionalDays,
        extendedOn: DateTime.now(),
        reason: reason,
        additionalCost: additionalCost,
      );

      final updatedExtensions = [...stay.extensions, extensionEntry];
      final newTotalExtended = stay.totalExtendedDays + additionalDays;
      final newExpiry =
          stay.admissionDate.add(Duration(days: stay.durationDays + newTotalExtended));
      final newTotalCost = stay.totalCost + additionalCost;

      await _rtdb.patch('$_staysPath/$stayId', {
        'totalExtendedDays': newTotalExtended,
        'expiryDate': newExpiry.millisecondsSinceEpoch,
        'totalCost': newTotalCost,
        'extensions':
            updatedExtensions.map((e) => e.toMap()).toList(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      throw Exception('Failed to extend stay: $e');
    }
  }

  /// Complete / end a stay
  Future<void> completeStay(String stayId) async {
    try {
      final data = await _rtdb.get('$_staysPath/$stayId');
      if (data == null || data is! Map) {
        throw Exception('Stay not found');
      }

      final stay = StayModel.fromMap(stayId, Map<String, dynamic>.from(data));

      // Update stay status
      await _rtdb.patch('$_staysPath/$stayId', {
        'status': 'completed',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Free up the room
      if (stay.roomType == 'private') {
        await updateRoom(stay.roomId, {
          'status': 'available',
          'currentAttendants': 0,
        });
      } else {
        final room = await getRoom(stay.roomId);
        if (room != null) {
          final newOccupied = (room.occupiedBeds - 1).clamp(0, room.totalBeds);
          await updateRoom(stay.roomId, {
            'occupiedBeds': newOccupied,
            'status': 'available',
          });
        }
      }
    } catch (e) {
      throw Exception('Failed to complete stay: $e');
    }
  }

  /// Fetch a single stay
  Future<StayModel?> getStay(String stayId) async {
    try {
      final data = await _rtdb.get('$_staysPath/$stayId');
      if (data != null && data is Map) {
        return StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch stay: $e');
    }
  }

  // ===========================================================================
  // STATISTICS
  // ===========================================================================

  /// Room stats stream
  Stream<Map<String, int>> getRoomStatsStream() {
    return getRoomsStream().map((rooms) {
      int totalRooms = rooms.length;
      int privateRooms = rooms.where((r) => r.isPrivate).length;
      int generalRooms = rooms.where((r) => r.isGeneral).length;
      int occupiedRooms =
          rooms.where((r) => r.status == 'occupied').length;
      int availableRooms =
          rooms.where((r) => r.status == 'available').length;
      int totalBeds =
          rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.totalBeds);
      int occupiedBeds = rooms
          .where((r) => r.isGeneral)
          .fold(0, (sum, r) => sum + r.occupiedBeds);

      return {
        'totalRooms': totalRooms,
        'privateRooms': privateRooms,
        'generalRooms': generalRooms,
        'occupiedRooms': occupiedRooms,
        'availableRooms': availableRooms,
        'totalBeds': totalBeds,
        'occupiedBeds': occupiedBeds,
        'availableBeds': totalBeds - occupiedBeds,
      };
    });
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static int _parseIntSafe(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double _parseDoubleSafe(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }
}
