part of 'room_service.dart';

/// Stays operations for RoomService.
///
/// Creating, extending, and completing patient stays.
extension RoomServiceStays on RoomService {
  // --- Stays ---

  Stream<List<StayModel>> getStaysStream() {
    return rtdb.stream(staysPath).map((data) {
      final stays = parseStaysFromData(data);
      stays.sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
      return stays;
    });
  }

  Stream<List<StayModel>> getActiveStaysStream() {
    return getStaysStream().map((stays) => stays.where((s) => s.status == 'active').toList());
  }

  Stream<List<StayModel>> getStaysByRoomStream(String roomId) {
    return getStaysStream().map((stays) => stays.where((s) => s.roomId == roomId && s.status == 'active').toList());
  }

  Stream<List<StayModel>> getStaysByPatientStream(String patientId) {
    return getStaysStream().map((stays) => stays.where((s) => s.patientId == patientId).toList());
  }

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
      final room = await getRoom(roomId);
      if (room == null) throw Exception('Room not found');

      final resolvedRoomType = room.roomType;
      BedModel? targetBed;

      if (resolvedRoomType == 'private') {
        if (room.occupiedCount > 0) throw Exception('Private room already occupied by another patient');

        if (bedId != null) targetBed = room.beds.where((b) => b.id == bedId).firstOrNull;
        targetBed ??= room.beds.where((b) => b.status == 'available').firstOrNull;
        if (targetBed == null) throw Exception('No available bed found in private room');
      } else {
        if (bedId != null) targetBed = room.beds.where((b) => b.id == bedId).firstOrNull;
        targetBed ??= room.beds.where((b) => b.status == 'available').firstOrNull;
        if (targetBed == null || targetBed.status != 'available') throw Exception('Selected bed is no longer available');
      }

      final pricing = await getPricing();
      final costs = _calculateStayCosts(
        roomType: resolvedRoomType,
        durationDays: durationDays,
        attendantCount: attendantCount,
        pricing: pricing,
      );

      final expectedDischargeDate = admissionDate.add(Duration(days: durationDays));
      final now = DateTime.now();
      final stayId = generateStayId();

      final stay = StayModel(
        id: stayId,
        patientId: patientId,
        patientName: patientName,
        roomId: roomId,
        roomNumber: room.roomIdentifier,
        roomType: resolvedRoomType,
        admissionDate: admissionDate,
        durationDays: durationDays,
        expectedDischargeDate: expectedDischargeDate,
        expiryDate: expectedDischargeDate, // Sync legacy field
        attendantCount: attendantCount,
        totalCost: costs.totalCost,
        baseCost: costs.baseCost,
        extraAttendantCost: costs.extraAttendantCost,
        status: 'active',
        bedId: targetBed.id,
        bedNumber: int.tryParse(targetBed.bedLabel),
        notes: notes,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );

      final nextOccupiedCount = resolvedRoomType == 'private' 
          ? room.beds.length 
          : room.actualOccupiedBeds + 1; // Projecting new occupancy

      // Perform atomic multipath update to sync stay + bed + room status
      final updates = <String, dynamic>{
        'stays/$stayId': stay.toMap(),
        'rooms/$roomId/occupiedBeds': nextOccupiedCount,
        'rooms/$roomId/currentAttendants': resolvedRoomType == 'private' ? attendantCount : room.currentAttendants,
        'rooms/$roomId/expectedVacancyDate': expectedDischargeDate.millisecondsSinceEpoch,
        'rooms/$roomId/lastUpdated': now.millisecondsSinceEpoch,
        'rooms/$roomId/updatedAt': now.millisecondsSinceEpoch,
      };

      if (resolvedRoomType == 'private') {
        final fixedBeds = room.beds.map((b) => b.copyWith(
          status: 'occupied',
          currentPatientId: patientId,
          currentStayId: stayId,
        )).toList();
        updates['rooms/$roomId/beds'] = bedsToRtdbMap(fixedBeds);
      } else {
        final fixedBeds = room.beds.map((b) {
          if (b.id == targetBed!.id) {
            return b.copyWith(
              status: 'occupied',
              currentPatientId: patientId,
              currentStayId: stayId,
            );
          }
          return b;
        }).toList();
        updates['rooms/$roomId/beds'] = bedsToRtdbMap(fixedBeds);
      }

      await rtdb.patch('', updates); // Atomic root-level multipath
      await updateRoomStatus(roomId);
      return stayId;
    } catch (e) {
      throw Exception('Failed to create stay: $e');
    }
  }

  Future<void> extendStay({
    required String stayId,
    required int additionalDays,
    String reason = '',
  }) async {
    try {
      final data = await rtdb.get('$staysPath/$stayId');
      if (data == null || data is! Map) throw Exception('Stay not found');

      final stay = StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      final pricing = await getPricing();
      final costs = _calculateStayCosts(
        roomType: stay.roomType,
        durationDays: additionalDays,
        attendantCount: stay.attendantCount,
        pricing: pricing,
      );

      final extensionEntry = StayExtension(
        additionalDays: additionalDays,
        extendedOn: DateTime.now(),
        reason: reason,
        additionalCost: costs.totalCost,
      );

      final updatedExtensions = [...stay.extensions, extensionEntry];
      final newTotalExtended = stay.totalExtendedDays + additionalDays;
      final newExpiry = stay.expectedDischargeDate.add(Duration(days: newTotalExtended));
      final newTotalCost = stay.totalCost + costs.totalCost;

      await rtdb.patch('$staysPath/$stayId', {
        'totalExtendedDays': newTotalExtended,
        // Make sure both legacy and new date formats are updated
        'expectedDischargeDate': newExpiry.millisecondsSinceEpoch, // Added based on new stay model requirement
        'expiryDate': newExpiry.millisecondsSinceEpoch,
        'totalCost': newTotalCost,
        'extensions': updatedExtensions.map((e) => e.toMap()).toList(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      await updateRoomStatus(stay.roomId);

      // Sync extension with PatientModel
      // Sync extension with PatientModel
      try {
        final patientData = await rtdb.get('patients/${stay.patientId}');

        if (patientData != null && patientData is Map) {
          final currentExtensionDays =
          (patientData['extensionDays'] ?? 0) as int;

          await rtdb.patch('patients/${stay.patientId}', {
            'extensionDays': currentExtensionDays + additionalDays,
            'extensionApproved': true,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      } catch (e) {
        print('Failed to sync patient extension: $e');
      }
    } catch (e) {
      throw Exception('Failed to extend stay: $e');
    }
  }

  Future<void> completeStay(String stayId) async {
    try {
      final data = await rtdb.get('$staysPath/$stayId');
      if (data == null || data is! Map) throw Exception('Stay not found');

      final stay = StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      final room = await getRoom(stay.roomId);
      if (room == null) throw Exception('Room not found');

      final targetBed = stay.bedId != null
          ? room.beds.where((b) => b.id == stay.bedId).firstOrNull
          : room.beds.where((b) => b.currentStayId == stay.id).firstOrNull;
      if (targetBed == null) throw Exception('No assigned bed found for this stay');

      final nextOccupiedCount = room.isPrivate ? 0 : (room.actualOccupiedBeds > 0 ? room.actualOccupiedBeds - 1 : 0);
      final now = DateTime.now();

      final updates = <String, dynamic>{
        'stays/$stayId/status': 'completed',
        'stays/$stayId/updatedAt': now.millisecondsSinceEpoch,
        'rooms/${room.id}/occupiedBeds': nextOccupiedCount,
        'rooms/${room.id}/currentAttendants': room.isPrivate ? 0 : room.currentAttendants,
        'rooms/${room.id}/lastUpdated': now.millisecondsSinceEpoch,
        'rooms/${room.id}/updatedAt': now.millisecondsSinceEpoch,
      };

      if (room.isPrivate) {
        final fixedBeds = room.beds.map((b) => b.copyWith(
          status: 'available',
          clearPatientId: true,
          clearStayId: true,
        )).toList();
        updates['rooms/${room.id}/beds'] = bedsToRtdbMap(fixedBeds);
      } else {
        final fixedBeds = room.beds.map((b) {
          if (b.id == targetBed.id) {
            return b.copyWith(
              status: 'available',
              clearPatientId: true,
              clearStayId: true,
            );
          }
          return b;
        }).toList();
        updates['rooms/${room.id}/beds'] = bedsToRtdbMap(fixedBeds);
      }

      await rtdb.patch('', updates); // Atomic root-level multi-path update
      await updateRoomStatus(room.id);
    } catch (e) {
      throw Exception('Failed to complete stay: $e');
    }
  }

  Future<StayModel?> getStay(String stayId) async {
    try {
      final data = await rtdb.get('$staysPath/$stayId');
      if (data != null && data is Map) {
        return StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch stay: $e');
    }
  }

  CostBreakdown _calculateStayCosts({
    required String roomType,
    required int durationDays,
    required int attendantCount,
    required Map<String, dynamic> pricing,
  }) {
    double baseCost = 0;
    double extraAttendantCost = 0;

    if (roomType == 'private') {
      final basePrice = parseDoubleSafe(pricing['privateRoomBasePrice'], 600);
      final includedAttendants = parseIntSafe(pricing['privateRoomIncludedAttendants'], 2);
      final extraFee = parseDoubleSafe(pricing['privateRoomExtraAttendantFee'], 200);

      baseCost = basePrice * durationDays;
      final extras = attendantCount > includedAttendants ? attendantCount - includedAttendants : 0;
      extraAttendantCost = extras * extraFee * durationDays;
    } else {
      final bedPrice = parseDoubleSafe(pricing['generalRoomBedPrice'], 150);
      baseCost = bedPrice * durationDays;
    }

    return CostBreakdown(
      baseCost: baseCost,
      extraAttendantCost: extraAttendantCost,
      totalCost: baseCost + extraAttendantCost,
    );
  }
}
