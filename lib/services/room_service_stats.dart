part of 'room_service.dart';

/// Stats and Analytics operations for RoomService.
///
/// Handles real-time census and dashboard room streams.
extension RoomServiceStats on RoomService {
  // --- Statistics & Census ---

  Stream<Map<String, int>> getRoomStatsStream() {
    return getRoomsStream().map((rooms) {
      final totalRooms = rooms.length;
      final privateRooms = rooms.where((r) => r.isPrivate).length;
      final generalRooms = rooms.where((r) => r.isGeneral).length;
      final occupiedRooms = rooms.where((r) => r.status == 'occupied').length;
      final availableRooms = rooms.where((r) => r.status == 'available').length;
      final totalBeds = rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualTotalBeds);
      final occupiedBeds = rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualOccupiedBeds);

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

  Stream<Map<String, int>> getCensusSummaryStream() {
    return getActiveStaysStream().map((stays) {
      final totalPatients = stays.length;
      final totalAttendants = stays.where((s) => s.roomType == 'private').fold(0, (sum, s) => sum + s.attendantCount);
      final totalInHouse = totalPatients + totalAttendants;

      return {
        'totalPatients': totalPatients,
        'totalAttendants': totalAttendants,
        'totalInHouse': totalInHouse,
      };
    });
  }

  Stream<Map<String, dynamic>> getFullCensusStream() {
    return RoomService.combineLatest2(getCensusSummaryStream(), getRoomsStream(), (census, rooms) {
      final vacantBeds = rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualAvailableBeds);
      return {...census, 'vacantBeds': vacantBeds};
    });
  }
}
