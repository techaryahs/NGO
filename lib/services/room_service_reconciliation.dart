part of 'room_service.dart';

/// Reconciliation operations for RoomService.
///
/// Ensures Room and Stay statuses are fully synchronized and self-healed.
extension RoomServiceReconciliation on RoomService {
  // --- Reconciliations ---
  
  Future<bool> reconcileRoomStatus(String roomId) async {
    try {
      final room = await getRoom(roomId);
      if (room == null) return false;

      final staysData = await rtdb.get(staysPath);
      final List<StayModel> activeStays = parseStaysFromData(staysData)
          .where((s) => s.roomId == roomId && s.status == 'active')
          .toList();

      final hasActiveStay = activeStays.isNotEmpty;
      final updates = <String, dynamic>{};

      if (room.isPrivate) {
        final shouldBeOccupied = hasActiveStay;
        final correctStatus = shouldBeOccupied ? 'occupied' : 'available';
        final correctAttendants = shouldBeOccupied ? activeStays.fold(0, (sum, s) => sum + s.attendantCount) : 0;

        if (room.status != correctStatus) updates['status'] = correctStatus;
        if (room.currentAttendants != correctAttendants) updates['currentAttendants'] = correctAttendants;

        if (room.beds.isNotEmpty) {
          final bedStatus = shouldBeOccupied ? 'occupied' : 'available';
          final needsBedUpdate = room.beds.any((b) => b.status != bedStatus);
          if (needsBedUpdate) {
            final fixedBeds = room.beds.map((b) {
              if (shouldBeOccupied) {
                return b.copyWith(
                  status: 'occupied',
                  currentPatientId: activeStays.first.patientId,
                  currentStayId: activeStays.first.id,
                );
              }
              return b.copyWith(status: 'available', clearPatientId: true, clearStayId: true);
            }).toList();
            updates['beds'] = bedsToRtdbMap(fixedBeds);
            updates['occupiedBeds'] = shouldBeOccupied ? fixedBeds.length : 0;
          }
        }
      } else {
        final occupiedBedCount = room.actualOccupiedBeds;
        String correctStatus;
        if (room.status == 'maintenance') {
          correctStatus = 'maintenance';
        } else if (occupiedBedCount == 0) {
          correctStatus = 'available';
        } else if (occupiedBedCount >= room.actualTotalBeds) {
          correctStatus = 'occupied';
        } else {
          correctStatus = 'available';
        }

        if (room.status != correctStatus) updates['status'] = correctStatus;
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
        await rtdb.patch('$roomsPath/$roomId', updates);
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('Failed to reconcile room status: $e');
    }
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
