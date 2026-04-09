part of 'room_service.dart';

/// Beds operations for RoomService.
///
/// Querying and updating individual beds.
extension RoomServiceBeds on RoomService {
  // --- Beds ---

  BedModel? getBedByLabel(RoomModel room, String bedLabel) {
    try {
      return room.beds.firstWhere((b) => b.bedLabel == bedLabel);
    } catch (_) {
      return null;
    }
  }

  Future<List<BedModel>> getAvailableBeds(String roomId) async {
    final room = await getRoom(roomId);
    if (room == null) return <BedModel>[];
    return room.beds.where((bed) => bed.status == 'available').toList();
  }

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

      final nextBeds = room.beds.map((bed) {
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
      final occupiedCount = nextBeds.where((b) => b.status == 'occupied').length;

      final updates = <String, dynamic>{
        'rooms/$roomId/beds/$bedId/status': status,
        'rooms/$roomId/beds/$bedId/currentPatientId': patientId,
        'rooms/$roomId/beds/$bedId/currentStayId': stayId,
        'rooms/$roomId/occupiedBeds': occupiedCount,
        'rooms/$roomId/lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'rooms/$roomId/updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await rtdb.patch('', updates);
      await updateRoomStatus(roomId);
    } catch (e) {
      throw Exception('Failed to update bed status: $e');
    }
  }

  BedModel? findAvailableBed(RoomModel room) {
    if (!room.isGeneral) return null;
    try {
      return room.beds.firstWhere((b) => b.isAvailable);
    } catch (_) {
      return null;
    }
  }
}
