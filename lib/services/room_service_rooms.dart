part of 'room_service.dart';

/// Rooms operations for RoomService.
///
/// Handles CRUD for rooms, reading rooms and computing statuses.
extension RoomServiceRooms on RoomService {
  // --- Rooms ---

  Stream<List<RoomModel>> streamRooms() {
    return RoomService.combineLatest2(rtdb.stream(roomsPath), rtdb.stream(staysPath), (roomsData, staysData) {
      return _processRoomsData(roomsData, staysData);
    });
  }

  Stream<List<RoomModel>> getRoomsStream() {
    return streamRooms();
  }

  List<RoomModel> _processRoomsData(dynamic roomsData, dynamic staysData) {
    final rooms = <RoomModel>[];
    if (roomsData != null && roomsData is Map) {
      final mapData = Map<String, dynamic>.from(roomsData);
      mapData.forEach((key, value) {
        if (value is Map) {
          rooms.add(RoomModel.fromMap(key, Map<String, dynamic>.from(value)));
        }
      });
    }

    final activeStays = parseStaysFromData(staysData)
        .where((s) => s.status == 'active')
        .toList();

    final now = DateTime.now();
    final List<RoomModel> enriched = rooms.map((room) {
      final roomStays = activeStays.where((s) => s.roomId == room.id).toList();
      final meta = computeStatusMeta(room, roomStays, now);
      return room.copyWith(
        status: meta.dbStatus,
        occupiedBeds: room.actualOccupiedBeds,
        expectedVacancyDate: meta.expectedVacancyDate,
      );
    }).toList();

    enriched.sort((a, b) => a.roomIdentifier.compareTo(b.roomIdentifier));
    return enriched;
  }

  Stream<List<RoomModel>> getAvailableRoomsStream() {
    return streamRooms().map((rooms) {
      return rooms.where((room) {
        if (room.isPrivate) {
          return room.occupiedCount == 0;
        }
        return room.occupiedCount < room.actualTotalBeds;
      }).toList();
    });
  }

  Stream<List<RoomModel>> getRoomsByTypeStream(String type) {
    return streamRooms().map((rooms) => rooms.where((r) => r.roomType == type).toList());
  }

  Stream<List<RoomModel>> getRoomsByFloorStream(int floor) {
    return streamRooms().map((rooms) => rooms.where((r) => r.floor == floor).toList());
  }

  Future<RoomModel?> getRoom(String roomId) async {
    try {
      final data = await rtdb.get('$roomsPath/$roomId');
      if (data == null || data is! Map) return null;

      final room = RoomModel.fromMap(roomId, Map<String, dynamic>.from(data));
      final staysData = await rtdb.get(staysPath);
      final roomStays = parseStaysFromData(staysData)
          .where((s) => s.roomId == roomId && s.status == 'active')
          .toList();
          
      final meta = computeStatusMeta(room, roomStays, DateTime.now());
      return room.copyWith(
        status: meta.dbStatus,
        occupiedBeds: room.actualOccupiedBeds,
        expectedVacancyDate: meta.expectedVacancyDate,
      );
    } catch (e) {
      throw Exception('Failed to fetch room: $e');
    }
  }

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
      if (floor < 1 || floor > 2) throw Exception('Invalid floor: Only Floor 1 and Floor 2 are supported');

      final upperIdentifier = roomIdentifier.toUpperCase();
      if (!RoomModel.validateIdentifierForFloor(upperIdentifier, floor)) {
        final validRooms = RoomModel.getValidIdentifiersForFloor(floor);
        throw Exception('Room identifier "$roomIdentifier" is not valid for Floor $floor. Valid identifiers: ${validRooms.join(", ")}');
      }

      final now = DateTime.now();
      final pricing = await getPricing();

      final List<BedModel> beds = [];
      if (roomType == 'general') {
        if (bedLabels != null && bedLabels.isNotEmpty) {
          for (final label in bedLabels) beds.add(BedModel.create(roomId: 'temp', bedLabel: label));
        } else {
          final bedCount = totalBeds ?? parseIntSafe(pricing['generalRoomDefaultBeds'], 6);
          final clampedCount = bedCount.clamp(1, 6);
          for (int i = 1; i <= clampedCount; i++) {
            beds.add(BedModel.create(roomId: 'temp', bedLabel: 'bed$i'));
          }
        }
      } else {
        final bedCount = totalBeds ?? 2;
        for (int i = 1; i <= bedCount; i++) beds.add(BedModel.create(roomId: 'temp', bedLabel: i.toString()));
      }

      final roomId = await rtdb.push(roomsPath, {'id': 'temp'});
      final updatedBeds = beds.map((b) => b.copyWith(id: BedModel.generateId(roomId, b.bedLabel))).toList();

      final room = RoomModel(
        id: roomId,
        roomNumber: roomNumber,
        roomIdentifier: upperIdentifier,
        floor: floor,
        roomType: roomType,
        status: 'available',
        maxAttendants: maxAttendants ?? (roomType == 'private' ? parseIntSafe(pricing['privateRoomMaxAttendants'], 5) : parseIntSafe(pricing['generalRoomMaxAttendants'], 2)),
        currentAttendants: 0,
        beds: updatedBeds,
        totalBeds: updatedBeds.length,
        occupiedBeds: 0,
        notes: notes,
        createdAt: now,
        updatedAt: now,
        lastUpdated: now,
      );

      final roomData = room.toMap();
      roomData['beds'] = bedsToRtdbMap(updatedBeds);
      roomData['expectedVacancyDate'] = null;
      roomData['lastUpdated'] = now.millisecondsSinceEpoch;

      await rtdb.patch('$roomsPath/$roomId', roomData);
      return roomId;
    } catch (e) {
      throw Exception('Failed to add room: $e');
    }
  }

  Future<void> updateRoom(String roomId, Map<String, dynamic> updates) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      updates['updatedAt'] = now;
      updates['lastUpdated'] = now;
      await rtdb.patch('$roomsPath/$roomId', updates);
    } catch (e) {
      throw Exception('Failed to update room: $e');
    }
  }

  Future<String> updateRoomStatus(String roomId) async {
    try {
      final roomData = await rtdb.get('$roomsPath/$roomId');
      if (roomData == null || roomData is! Map) throw Exception('Room not found');

      final room = RoomModel.fromMap(roomId, Map<String, dynamic>.from(roomData));
      final staysData = await rtdb.get(staysPath);
      final activeStays = parseStaysFromData(staysData)
          .where((s) => s.roomId == roomId && s.status == 'active')
          .toList();

      final computed = computeStatusMeta(room, activeStays, DateTime.now());
      await rtdb.patch('$roomsPath/$roomId', {
        'status': computed.dbStatus,
        'occupiedBeds': room.actualOccupiedBeds,
        'expectedVacancyDate': computed.expectedVacancyDate?.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      return computed.uiStatus;
    } catch (e) {
      throw Exception('Failed to update room status: $e');
    }
  }

  Future<void> deleteRoom(String roomId) async {
    try {
      final room = await getRoom(roomId);
      if (room == null) throw Exception('Room not found');
      if (room.actualOccupiedBeds > 0) throw Exception('Cannot delete room while one or more beds are occupied');

      final staysData = await rtdb.get(staysPath);
      final hasActiveStay = parseStaysFromData(staysData).any((s) => s.roomId == roomId && s.status == 'active');
      if (hasActiveStay) throw Exception('Cannot delete room with active stays');

      await rtdb.delete('$roomsPath/$roomId');
    } catch (e) {
      throw Exception('Failed to delete room: $e');
    }
  }

  RoomStatusMeta computeStatusMeta(RoomModel room, List<StayModel> activeStays, DateTime now) {
    if (room.status == 'maintenance') {
      return const RoomStatusMeta(dbStatus: 'maintenance', uiStatus: 'Maintenance', expectedVacancyDate: null);
    }

    final hasPendingDischarge = activeStays.any((stay) {
      return now.isAfter(stay.expectedDischargeDate) && stay.totalExtendedDays == 0;
    });

    final occupiedCount = room.actualOccupiedBeds;
    if (hasPendingDischarge) {
      return RoomStatusMeta(
        dbStatus: 'pending_discharge',
        uiStatus: 'Pending Discharge',
        expectedVacancyDate: earliestExpectedVacancy(activeStays),
      );
    }

    final isFull = room.isPrivate ? occupiedCount > 0 : occupiedCount >= room.actualTotalBeds;
    if (isFull) {
      return RoomStatusMeta(
        dbStatus: 'occupied',
        uiStatus: 'Full',
        expectedVacancyDate: earliestExpectedVacancy(activeStays),
      );
    }

    if (occupiedCount > 0 && !room.isPrivate) {
      return RoomStatusMeta(
        dbStatus: 'partially_occupied', // Using 'partially_occupied' for accuracy, although original just used available
        uiStatus: 'Partially Occupied',
        expectedVacancyDate: earliestExpectedVacancy(activeStays),
      );
    }

    return RoomStatusMeta(
      dbStatus: 'available',
      uiStatus: 'Available',
      expectedVacancyDate: earliestExpectedVacancy(activeStays),
    );
  }
}
