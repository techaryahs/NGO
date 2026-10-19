part of 'room_service.dart';

/// Reconciliation operations for RoomService.
///
/// Ensures Room and Stay statuses are fully synchronized and self-healed.
extension RoomServiceReconciliation on RoomService {
  // --- Reconciliations ---

  Future<bool> reconcileRoomStatus(String roomId) async {
    // A reservation precedes its stay write. Allow that short window to finish
    // before treating a bed without a stay as an orphan.
    const reservationGrace = Duration(minutes: 5);
    for (var attempt = 0; attempt < 4; attempt++) {
      final snapshot = await rtdb.getWithEtag('$roomsPath/$roomId');
      if (snapshot.value is! Map || snapshot.etag == null) return false;
      final rawRoom = Map<String, dynamic>.from(snapshot.value);
      final room = RoomModel.fromMap(roomId, rawRoom);
      final rawStays = await rtdb.getByChildValue(
        staysPath, child: 'roomId', value: roomId,
      );
      final activeStays = parseStaysFromData(rawStays)
          .where((stay) => stay.status == 'active').toList();
      final activeIds = activeStays.map((stay) => stay.id).toSet();
      final orphaned = room.beds.any((bed) =>
          bed.currentStayId != null && !activeIds.contains(bed.currentStayId));
      final lastChanged = rawRoom['lastUpdated'] is num
          ? (rawRoom['lastUpdated'] as num).toInt()
          : rawRoom['updatedAt'] is num
              ? (rawRoom['updatedAt'] as num).toInt()
              : 0;
      if (orphaned && DateTime.now().millisecondsSinceEpoch - lastChanged <
          reservationGrace.inMilliseconds) {
        return false;
      }
      final fixedBeds = room.beds.map((bed) {
        if (bed.currentStayId == null || activeIds.contains(bed.currentStayId)) {
          return bed;
        }
        return bed.copyWith(
          status: 'available', clearPatientId: true, clearStayId: true,
        );
      }).toList();
      final occupied = fixedBeds.where((bed) => bed.isOccupied).length;
      final status = room.status == 'maintenance'
          ? 'maintenance'
          : occupied == 0
              ? 'available'
              : occupied >= room.actualTotalBeds
                  ? 'occupied'
                  : 'partially_occupied';
      final attendants = room.isPrivate
          ? activeStays.fold<int>(0, (sum, stay) => sum + stay.attendantCount)
          : room.currentAttendants;
      if (!orphaned && room.status == status &&
          room.currentAttendants == attendants && room.occupiedBeds == occupied) {
        return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final next = <String, dynamic>{
        ...rawRoom,
        'beds': bedsToRtdbMap(fixedBeds),
        'occupiedBeds': occupied,
        'currentAttendants': attendants,
        'status': status,
        'updatedAt': now,
        'lastUpdated': now,
        'version': (room.version ?? 0) + 1,
      };
      if (await rtdb.putIfMatch('$roomsPath/$roomId', next, snapshot.etag!)) {
        return true;
      }
    }
    throw StateError('Room changed during reconciliation; retry later');
  }

  Future<int> reconcileAllRooms() async {
    try {
      final roomsData = await rtdb.get(roomsPath);
      if (roomsData == null || roomsData is! Map) return 0;

      final map = Map<String, dynamic>.from(roomsData);
      int corrected = 0;
      for (final roomId in map.keys) {
        try {
          if (await reconcileRoomStatus(roomId)) corrected++;
        } catch (_) {}
      }
      return corrected;
    } catch (e) {
      throw Exception('Failed to reconcile all rooms: $e');
    }
  }

  Future<bool> refreshRoomStatus(String roomId) => reconcileRoomStatus(roomId);
  Future<int> refreshAllRoomStatuses() => reconcileAllRooms();
}
