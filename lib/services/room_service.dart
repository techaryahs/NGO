import 'dart:async';
import '../models/room_model.dart';
import '../models/stay_model.dart';
import '../models/bed_model.dart';
import 'firebase_rtdb_rest_service.dart';

/// Service layer for Room, Bed & Stay management.
///
/// Handles room CRUD, hierarchical bed tracking, stay creation,
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
  // ROOMS — CRUD with Hierarchical Bed Support
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
        rooms.sort((a, b) => a.roomIdentifier.compareTo(b.roomIdentifier));
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

  /// Add a new room with optional bed labels (for non-sequential bed numbering).
  /// 
  /// [bedLabels] - List of bed labels (e.g., ["23", "21", "19"]).
  /// If not provided, sequential beds will be created based on totalBeds.
  /// 
  /// Floor validation is enforced:
  /// - Floor 1: Rooms 1A, 1B, 1C, 1D
  /// - Floor 2: Rooms 2A, 2B, 2C, 2D, 2E
  Future<String> addRoom({
    required String roomNumber,
    required String roomIdentifier,
    required int floor,
    required String roomType,
    int? maxAttendants,
    int? totalBeds,
    List<String>? bedLabels,
    String? notes,
  }) async {
    try {
      // Validate floor (only 1 or 2 allowed)
      if (floor < 1 || floor > 2) {
        throw Exception('Invalid floor: Only Floor 1 and Floor 2 are supported');
      }

      // Validate room identifier matches floor
      final upperIdentifier = roomIdentifier.toUpperCase();
      if (!RoomModel.validateIdentifierForFloor(upperIdentifier, floor)) {
        final validRooms = RoomModel.getValidIdentifiersForFloor(floor);
        throw Exception(
          'Room identifier "$roomIdentifier" is not valid for Floor $floor. '
          'Valid identifiers: ${validRooms.join(", ")}'
        );
      }

      final now = DateTime.now();
      final pricing = await getPricing();

      // Create beds for general rooms
      List<BedModel> beds = [];
      if (roomType == 'general') {
        if (bedLabels != null && bedLabels.isNotEmpty) {
          // Use provided bed labels (non-sequential)
          for (final label in bedLabels) {
            beds.add(BedModel.create(roomId: 'temp', bedLabel: label));
          }
        } else {
          // Create sequential beds (support up to 20 for large wards)
          final bedCount = totalBeds ?? _parseIntSafe(pricing['generalRoomDefaultBeds'], 4);
          for (int i = 1; i <= bedCount; i++) {
            beds.add(BedModel.create(roomId: 'temp', bedLabel: i.toString()));
          }
        }
      } else if (roomType == 'private') {
        // Private rooms have beds too (default 2)
        final bedCount = totalBeds ?? 2;
        for (int i = 1; i <= bedCount; i++) {
          beds.add(BedModel.create(roomId: 'temp', bedLabel: i.toString()));
        }
      }

      final room = RoomModel(
        id: 'temp',
        roomNumber: roomNumber,
        roomIdentifier: upperIdentifier,
        floor: floor,
        roomType: roomType,
        status: 'available',
        maxAttendants: maxAttendants ??
            (roomType == 'private'
                ? _parseIntSafe(pricing['privateRoomMaxAttendants'], 5)
                : _parseIntSafe(pricing['generalRoomMaxAttendants'], 2)),
        totalBeds: beds.isNotEmpty ? beds.length : (totalBeds ?? 4),
        beds: beds,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      );

      final roomId = await _rtdb.push(_roomsPath, room.toMap());
      
      // Update bed IDs with actual room ID
      if (beds.isNotEmpty) {
        final updatedBeds = beds.map((b) => b.copyWith(id: BedModel.generateId(roomId, b.bedLabel))).toList();
        await _rtdb.patch('$_roomsPath/$roomId', {
          'id': roomId,
          'beds': updatedBeds.map((b) => b.toMap()).toList(),
        });
      } else {
        await _rtdb.patch('$_roomsPath/$roomId', {'id': roomId});
      }
      
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
  // BEDS — Hierarchical Bed Management
  // ===========================================================================

  /// Get a specific bed from a room
  BedModel? getBedByLabel(RoomModel room, String bedLabel) {
    try {
      return room.beds.firstWhere((b) => b.bedLabel == bedLabel);
    } catch (e) {
      return null;
    }
  }

  /// Update a specific bed's status
  Future<void> updateBedStatus({
    required String roomId,
    required String bedId,
    required String status,
    String? patientId,
    String? stayId,
  }) async {
    try {
      final room = await getRoom(roomId);
      if (room == null) throw Exception('Room not found');

      final updatedBeds = room.beds.map((bed) {
        if (bed.id == bedId) {
          return bed.copyWith(
            status: status,
            currentPatientId: patientId,
            currentStayId: stayId,
            clearPatientId: patientId == null,
            clearStayId: stayId == null,
          );
        }
        return bed;
      }).toList();

      final occupiedCount = updatedBeds.where((b) => b.isOccupied).length;
      final roomStatus = occupiedCount >= updatedBeds.length ? 'occupied' : 'available';

      await updateRoom(roomId, {
        'beds': updatedBeds.map((b) => b.toMap()).toList(),
        'occupiedBeds': occupiedCount,
        'status': roomStatus,
      });
    } catch (e) {
      throw Exception('Failed to update bed status: $e');
    }
  }

  /// Find an available bed in a general room
  BedModel? findAvailableBed(RoomModel room) {
    if (!room.isGeneral) return null;
    try {
      return room.beds.firstWhere((b) => b.isAvailable);
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // STAYS — CRUD & Business Logic with Bed Tracking
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

  /// Create a new stay — assigns patient to room/bed + calculates pricing.
  /// 
  /// For Private Rooms: Stay creation updates room status, pricing is attendant-based.
  /// For General Rooms: Stay creation updates specific BedModel, pricing is bed-based.
  Future<String> createStay({
    required String patientId,
    required String patientName,
    required String roomId,
    required String roomNumber,
    required String roomType,
    required DateTime admissionDate,
    required int durationDays,
    required int attendantCount,
    String? bedId,
    String? bedLabel,
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
        bedId: bedId,
        bedNumber: bedLabel != null ? int.tryParse(bedLabel) : null,
        notes: notes,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );

      final stayId = await _rtdb.push(_staysPath, stay.toMap());
      await _rtdb.patch('$_staysPath/$stayId', {'id': stayId});

      // Update room/bed status based on room type
      if (roomType == 'private') {
        await updateRoom(roomId, {
          'status': 'occupied',
          'currentAttendants': attendantCount,
        });
      } else if (bedId != null) {
        // General room: update specific bed
        await updateBedStatus(
          roomId: roomId,
          bedId: bedId,
          status: 'occupied',
          patientId: patientId,
          stayId: stayId,
        );
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

  /// Complete / end a stay — resets bed status for general rooms.
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

      // Free up the room/bed
      if (stay.roomType == 'private') {
        await updateRoom(stay.roomId, {
          'status': 'available',
          'currentAttendants': 0,
        });
      } else if (stay.bedId != null) {
        // General room: reset specific bed
        await updateBedStatus(
          roomId: stay.roomId,
          bedId: stay.bedId!,
          status: 'available',
        );
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
  // STATISTICS & CENSUS
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
          rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualTotalBeds);
      int occupiedBeds = rooms
          .where((r) => r.isGeneral)
          .fold(0, (sum, r) => sum + r.actualOccupiedBeds);

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

  /// Census Summary Stream - Real-time in-house analytics
  /// Returns: Total Patients, Total Attendants, Total In-House, Vacant Beds
  Stream<Map<String, int>> getCensusSummaryStream() {
    return getActiveStaysStream().map((stays) {
      int totalPatients = stays.length;
      
      // Sum attendants from private room stays
      int totalAttendants = stays
          .where((s) => s.roomType == 'private')
          .fold(0, (sum, s) => sum + s.attendantCount);
      
      int totalInHouse = totalPatients + totalAttendants;
      
      return {
        'totalPatients': totalPatients,
        'totalAttendants': totalAttendants,
        'totalInHouse': totalInHouse,
      };
    });
  }

  /// Combined census with vacant beds
  Stream<Map<String, dynamic>> getFullCensusStream() {
    return Rx.combineLatest2(
      getCensusSummaryStream(),
      getRoomsStream(),
      (census, rooms) {
        int vacantBeds = rooms
            .where((r) => r.isGeneral)
            .fold(0, (sum, r) => sum + r.actualAvailableBeds);
        
        return {
          ...census,
          'vacantBeds': vacantBeds,
        };
      },
    );
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

/// Rx combine utility for streams
class Rx {
  static Stream<T> combineLatest2<A, B, T>(
    Stream<A> streamA,
    Stream<B> streamB,
    T Function(A, B) combiner,
  ) {
    A? latestA;
    B? latestB;
    bool hasA = false;
    bool hasB = false;
    
    late StreamController<T> controller;
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;

    controller = StreamController<T>(
      onListen: () {
        subA = streamA.listen((a) {
          latestA = a;
          hasA = true;
          if (hasA && hasB) {
            controller.add(combiner(latestA as A, latestB as B));
          }
        });
        subB = streamB.listen((b) {
          latestB = b;
          hasB = true;
          if (hasA && hasB) {
            controller.add(combiner(latestA as A, latestB as B));
          }
        });
      },
      onCancel: () {
        subA?.cancel();
        subB?.cancel();
      },
    );

    return controller.stream;
  }
}