part of 'room_service.dart';

/// Beds operations for RoomService.
///
/// All bed mutations go through server-enforced compare-and-swap (Firebase
/// RTDB `If-Match` conditional writes): the client reads the room with its
/// ETag, validates availability and writes the new bed state only while the
/// room is unchanged. A competing terminal's write invalidates the ETag and
/// the operation retries against the fresh state, so the same bed can never
/// be allocated twice.
extension RoomServiceBeds on RoomService {
  static const int _maxCasAttempts = 4;

  /// Raised when a bed cannot be allocated (taken by another terminal or the
  /// room kept changing). The caller should refresh its view and retry.
  BedConflictException bedConflict(String message) =>
      BedConflictException(message);

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

  /// Reads a room directly without downloading the stays collection.
  Future<RoomModel?> getRoomDirect(String roomId) async {
    final data = await rtdb.get('$roomsPath/$roomId');
    if (data == null || data is! Map) return null;
    return RoomModel.fromMap(roomId, Map<String, dynamic>.from(data));
  }

  /// Concurrency-safe bed status change for a single bed.
  Future<void> updateBedStatus({
    required String roomId,
    required String bedId,
    required String status,
    String? patientId,
    String? stayId,
  }) async {
    try {
      final success = await _updateRoomBedsWithCas(roomId, (room) {
        final bed = room.beds.where((b) => b.id == bedId).firstOrNull;
        if (bed == null) {
          throw bedConflict('Bed $bedId does not exist in this room');
        }
        if (status == 'occupied' && !bed.isAvailable) {
          throw bedConflict('Bed is no longer available');
        }
        return room.beds.map((b) {
          if (b.id == bedId) {
            return b.copyWith(
              status: status,
              currentPatientId: patientId,
              currentStayId: stayId,
              clearPatientId: patientId == null,
              clearStayId: stayId == null,
            );
          }
          return b;
        }).toList();
      });
      if (!success) throw bedConflict('Room changed while updating the bed');
    } catch (e) {
      if (e is BedConflictException) rethrow;
      throw Exception('Failed to update bed status: $e');
    }
  }

  /// Atomically reserves every selected bed of one room under CAS protection.
  ///
  /// Either all beds are reserved or none are. The returned room snapshot is
  /// the exact state the reservation was written against.
  Future<RoomModel> reserveBeds({
    required String roomId,
    required List<String> bedIds,
    required String patientId,
    required List<String> stayIds,
    int attendantCount = 0,
    DateTime? expectedDischargeDate,
  }) async {
    for (var attempt = 0; attempt < _maxCasAttempts; attempt++) {
      final snapshot = await rtdb.getWithEtag('$roomsPath/$roomId');
      if (snapshot.value is! Map) throw Exception('Room not found');
      final etag = snapshot.etag;
      if (etag == null) {
        throw Exception('Room version unavailable; retry allocation');
      }
      final room = RoomModel.fromMap(
        roomId,
        Map<String, dynamic>.from(snapshot.value),
      );
      if (room.isPrivate &&
          room.currentAttendants + attendantCount > room.maxAttendants) {
        throw bedConflict('Private room attendant limit was reached');
      }
      for (final bedId in bedIds) {
        final bed = room.beds.where((b) => b.id == bedId).firstOrNull;
        if (bed == null) {
          throw bedConflict('Bed $bedId does not exist in this room');
        }
        if (!bed.isAvailable && bed.currentPatientId != patientId) {
          throw bedConflict('Bed is no longer available');
        }
      }
      if (bedIds.toSet().length != bedIds.length || stayIds.length != bedIds.length) {
        throw ArgumentError('Each selected bed requires a unique stay');
      }
      final stayByBed = <String, String>{
        for (var index = 0; index < bedIds.length; index++) bedIds[index]: stayIds[index],
      };
      final fixedBeds = room.beds.map((bed) {
        if (stayByBed.containsKey(bed.id)) {
          return bed.copyWith(
            status: 'occupied',
            currentPatientId: patientId,
            currentStayId: stayByBed[bed.id],
          );
        }
        return bed;
      }).toList();
      final occupied = fixedBeds.where((bed) => bed.isOccupied).length;
      final updates = <String, dynamic>{
        'beds': bedsToRtdbMap(fixedBeds),
        'occupiedBeds': occupied,
        if (room.isPrivate)
          'currentAttendants': (room.currentAttendants + attendantCount)
              .clamp(0, 999),
        'expectedVacancyDate': expectedDischargeDate?.millisecondsSinceEpoch,
        'status': occupied >= room.actualTotalBeds
            ? 'occupied'
            : occupied == 0
            ? 'available'
            : 'partially_occupied',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'version': (room.version ?? 0) + 1,
      };
      final applied = await rtdb.putIfMatch(
        '$roomsPath/$roomId',
        {...Map<String, dynamic>.from(snapshot.value), ...updates},
        etag,
      );
      if (applied) return room;
      // Another terminal changed the room; retry against the fresh state.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw bedConflict(
      'Room state kept changing. Please check the room and try again.',
    );
  }

  /// Releases beds that were reserved by [patientId] or [stayIds] (best-effort
  /// rollback after a failed follow-up write).
  Future<void> releaseBeds({
    required String roomId,
    required String patientId,
    List<String>? stayIds,
    int attendantCount = 0,
  }) async {
    final ids = stayIds?.toSet();
    try {
      for (var attempt = 0; attempt < _maxCasAttempts; attempt++) {
        final snapshot = await rtdb.getWithEtag('$roomsPath/$roomId');
        if (snapshot.value is! Map) return;
        final etag = snapshot.etag;
        if (etag == null) return;
        final room = RoomModel.fromMap(
          roomId,
          Map<String, dynamic>.from(snapshot.value),
        );
        var changed = false;
        final fixedBeds = room.beds.map((bed) {
          final matchesReservation = ids == null
              ? bed.currentPatientId == patientId
              : bed.currentPatientId == patientId &&
                  bed.currentStayId != null &&
                  ids.contains(bed.currentStayId);
          if (!matchesReservation) return bed;
          changed = true;
          return bed.copyWith(
            status: 'available',
            clearPatientId: true,
            clearStayId: true,
          );
        }).toList();
        if (!changed) return;
        final occupied = fixedBeds.where((bed) => bed.isOccupied).length;
        final updates = <String, dynamic>{
          'beds': bedsToRtdbMap(fixedBeds),
          'occupiedBeds': occupied,
          if (room.isPrivate)
            'currentAttendants': (room.currentAttendants - attendantCount)
                .clamp(0, 999),
          'status': occupied == 0
              ? 'available'
              : occupied >= room.actualTotalBeds
              ? 'occupied'
              : 'partially_occupied',
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'version': (room.version ?? 0) + 1,
        };
        final applied = await rtdb.putIfMatch(
          '$roomsPath/$roomId',
          {...Map<String, dynamic>.from(snapshot.value), ...updates},
          etag,
        );
        if (applied) return;
      }
    } catch (error) {
      throw StateError('Could not release reserved beds: $error');
    }
    throw StateError('Could not release reserved beds after concurrent updates');
  }

  /// CAS helper shared by the bed mutators. [transform] returns the new bed
  /// list computed from the fresh room snapshot; returns true when applied.
  Future<bool> _updateRoomBedsWithCas(
    String roomId,
    List<BedModel> Function(RoomModel room) transform, {
    int attendantDelta = 0,
  }) async {
    for (var attempt = 0; attempt < _maxCasAttempts; attempt++) {
      final snapshot = await rtdb.getWithEtag('$roomsPath/$roomId');
      if (snapshot.value is! Map) throw Exception('Room not found');
      final etag = snapshot.etag;
      if (etag == null) {
        throw Exception('Room version unavailable; retry allocation');
      }
      final room = RoomModel.fromMap(
        roomId,
        Map<String, dynamic>.from(snapshot.value),
      );
      final fixedBeds = transform(room);
      if (identical(fixedBeds, room.beds)) return true;
      final occupied = fixedBeds.where((bed) => bed.isOccupied).length;
      final updates = <String, dynamic>{
        'beds': bedsToRtdbMap(fixedBeds),
        'occupiedBeds': occupied,
        if (room.isPrivate)
          'currentAttendants': (room.currentAttendants + attendantDelta)
              .clamp(0, 999),
        'status': occupied == 0
            ? 'available'
            : occupied >= room.actualTotalBeds
            ? 'occupied'
            : 'partially_occupied',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'version': (room.version ?? 0) + 1,
      };
      final applied = await rtdb.putIfMatch(
        '$roomsPath/$roomId',
        {...Map<String, dynamic>.from(snapshot.value), ...updates},
        etag,
      );
      if (applied) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return false;
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

/// Signals that a bed could not be allocated because another terminal owns
/// the room state. Never leaves a half-written allocation behind.
class BedConflictException implements Exception {
  final String message;
  BedConflictException(this.message);
  @override
  String toString() => message;
}
