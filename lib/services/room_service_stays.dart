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
    return getStaysStream().map(
      (stays) => stays.where((s) => s.status == 'active').toList(),
    );
  }

  Stream<List<StayModel>> getStaysByRoomStream(String roomId) {
    return getStaysStream().map(
      (stays) => stays
          .where((s) => s.roomId == roomId && s.status == 'active')
          .toList(),
    );
  }

  Stream<List<StayModel>> getStaysByPatientStream(String patientId) {
    return getStaysStream().map(
      (stays) => stays.where((s) => s.patientId == patientId).toList(),
    );
  }

  /// Records a lobby admission in stay history without reserving a room bed.
  Future<String> createLobbyStay({
    required String patientId,
    required String patientName,
    required String lobbyName,
    required DateTime admissionDate,
    required int durationDays,
    required int attendantCount,
    List<String> attendantLabels = const [],
    required String createdBy,
    String status = 'active',
    DateTime? completedAt,
  }) async {
    final now = completedAt ?? DateTime.now();
    final stayId = generateStayId();
    final end = completedAt ?? admissionDate.add(Duration(days: durationDays));
    final costs = _calculateStayCosts(
      roomType: 'general',
      durationDays: durationDays,
      attendantCount: attendantCount,
      pricing: await getPricing(),
    );
    final stay = StayModel(
      id: stayId,
      patientId: patientId,
      patientName: patientName,
      roomId: 'lobby:$lobbyName',
      roomNumber: lobbyName,
      roomType: 'lobby',
      admissionDate: admissionDate,
      durationDays: durationDays,
      expectedDischargeDate: end,
      expiryDate: end,
      attendantCount: attendantCount,
      attendantLabels: attendantLabels,
      totalCost: costs.totalCost,
      baseCost: costs.baseCost,
      extraAttendantCost: costs.extraAttendantCost,
      status: status,
      notes: 'Lobby admission',
      createdAt: status == 'active' ? DateTime.now() : admissionDate,
      updatedAt: now,
      createdBy: createdBy,
    );
    await rtdb.patch('$staysPath/$stayId', stay.toMap());
    return stayId;
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
    List<String> attendantLabels = const [],
    String? bedId,
    String? bedLabel,
    String? notes,
    required String createdBy,
  }) async {
    try {
      final room = await getRoom(roomId);
      if (room == null) throw Exception('Room not found');
      final pricing = await getPricing();

      final resolvedRoomType = room.roomType;
      BedModel? targetBed;

      if (resolvedRoomType == 'private') {
        final projectedAttendants = room.currentAttendants + attendantCount;
        if (projectedAttendants > room.maxAttendants) {
          throw Exception(
            'Private room attendant limit exceeded (${room.maxAttendants})',
          );
        }
        if (bedId != null)
          targetBed = room.beds.where((b) => b.id == bedId).firstOrNull;
        targetBed ??= room.beds
            .where((b) => b.status == 'available')
            .firstOrNull;
        if (targetBed == null)
          throw Exception('No available bed found in private room');
      } else {
        final maxAttendants = parseIntSafe(
          pricing['generalRoomMaxAttendants'],
          2,
        );
        if (attendantCount > maxAttendants) {
          throw Exception(
            'General room attendant limit exceeded ($maxAttendants)',
          );
        }
        if (bedId != null)
          targetBed = room.beds.where((b) => b.id == bedId).firstOrNull;
        targetBed ??= room.beds
            .where((b) => b.status == 'available')
            .firstOrNull;
        if (targetBed == null || targetBed.status != 'available')
          throw Exception('Selected bed is no longer available');
      }

      final costs = _calculateStayCosts(
        roomType: resolvedRoomType,
        durationDays: durationDays,
        attendantCount: attendantCount,
        pricing: pricing,
      );

      final expectedDischargeDate = admissionDate.add(
        Duration(days: durationDays),
      );
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
        attendantLabels: attendantLabels,
        totalCost: costs.totalCost,
        baseCost: costs.baseCost,
        extraAttendantCost: costs.extraAttendantCost,
        status: 'active',
        bedId: targetBed.id,
        bedNumber: int.tryParse(targetBed.bedLabel),
        bedLabel: targetBed.bedLabel,
        notes: notes,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );

      final nextOccupiedCount = room.actualOccupiedBeds + 1;

      // Perform atomic multipath update to sync stay + bed + room status
      final updates = <String, dynamic>{
        'stays/$stayId': stay.toMap(),
        'rooms/$roomId/occupiedBeds': nextOccupiedCount,
        'rooms/$roomId/currentAttendants': resolvedRoomType == 'private'
            ? room.currentAttendants + attendantCount
            : room.currentAttendants,
        'rooms/$roomId/expectedVacancyDate':
            expectedDischargeDate.millisecondsSinceEpoch,
        'rooms/$roomId/lastUpdated': now.millisecondsSinceEpoch,
        'rooms/$roomId/updatedAt': now.millisecondsSinceEpoch,
      };

      {
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
      final newExpiry = stay.expectedDischargeDate.add(
        Duration(days: newTotalExtended),
      );
      final newTotalCost = stay.totalCost + costs.totalCost;

      await rtdb.patch('$staysPath/$stayId', {
        'totalExtendedDays': newTotalExtended,
        // Make sure both legacy and new date formats are updated
        'expectedDischargeDate': newExpiry
            .millisecondsSinceEpoch, // Added based on new stay model requirement
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

  Future<void> completeStay(
    String stayId, {
    DateTime? completedAt,
    DateTime? billingAdmissionDate,
    double? totalCost,
    double? paidAmount,
    double? pendingAmount,
  }) async {
    try {
      final data = await rtdb.get('$staysPath/$stayId');
      if (data == null || data is! Map) throw Exception('Stay not found');

      final stay = StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      final room = await getRoom(stay.roomId);
      final now = completedAt ?? DateTime.now();
      if (room == null) {
        // Legacy/imported stays can point to a room that was renamed or
        // removed. Completing the historical stay must not block discharge
        // or deletion when there is no physical bed left to release.
        await rtdb.patch('$staysPath/$stayId', {
          'status': 'completed',
          'updatedAt': now.millisecondsSinceEpoch,
          if (billingAdmissionDate != null)
            'admissionDate': billingAdmissionDate.millisecondsSinceEpoch,
          if (billingAdmissionDate != null)
            'durationDays': PricingHelper.calculateStayDays(
              billingAdmissionDate,
              now,
            ),
          if (totalCost != null) 'totalCost': totalCost,
          if (paidAmount != null) 'paidAmount': paidAmount,
          if (pendingAmount != null) 'pendingAmount': pendingAmount,
        });
        return;
      }

      var targetBed = stay.bedId != null
          ? room.beds.where((b) => b.id == stay.bedId).firstOrNull
          : room.beds.where((b) => b.currentStayId == stay.id).firstOrNull;
      targetBed ??= room.beds
          .where((b) => b.currentStayId == stay.id)
          .firstOrNull;
      targetBed ??= room.beds
          .where((b) => b.currentPatientId == stay.patientId && b.isOccupied)
          .firstOrNull;

      final fixedBeds = targetBed == null
          ? room.beds
          : room.beds.map((b) {
              if (b.id == targetBed!.id) {
                return b.copyWith(
                  status: 'available',
                  clearPatientId: true,
                  clearStayId: true,
                );
              }
              return b;
            }).toList();
      final nextOccupiedCount = fixedBeds
          .where((bed) => bed.isOccupied)
          .length;

      final updates = <String, dynamic>{
        'stays/$stayId/status': 'completed',
        'stays/$stayId/updatedAt': now.millisecondsSinceEpoch,
        if (billingAdmissionDate != null)
          'stays/$stayId/admissionDate':
              billingAdmissionDate.millisecondsSinceEpoch,
        if (billingAdmissionDate != null)
          'stays/$stayId/durationDays': PricingHelper.calculateStayDays(
            billingAdmissionDate,
            now,
          ),
        if (totalCost != null) 'stays/$stayId/totalCost': totalCost,
        if (paidAmount != null) 'stays/$stayId/paidAmount': paidAmount,
        if (pendingAmount != null)
          'stays/$stayId/pendingAmount': pendingAmount,
        'rooms/${room.id}/occupiedBeds': nextOccupiedCount,
        'rooms/${room.id}/currentAttendants': room.isPrivate
            ? (room.currentAttendants > stay.attendantCount
                  ? room.currentAttendants - stay.attendantCount
                  : 0)
            : room.currentAttendants,
        'rooms/${room.id}/lastUpdated': now.millisecondsSinceEpoch,
        'rooms/${room.id}/updatedAt': now.millisecondsSinceEpoch,
      };

      if (targetBed != null) {
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

  Future<void> updateStayDates(
    String stayId, {
    required DateTime admissionDate,
    DateTime? exitDate,
  }) async {
    final durationDays = PricingHelper.calculateStayDays(admissionDate, exitDate);
    final end = exitDate ?? admissionDate.add(Duration(days: durationDays));
    await rtdb.patch('$staysPath/$stayId', {
      'admissionDate': admissionDate.millisecondsSinceEpoch,
      'durationDays': durationDays,
      'expectedDischargeDate': end.millisecondsSinceEpoch,
      'expiryDate': end.millisecondsSinceEpoch,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
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
      final basePrice = parseDoubleSafe(pricing['privateRoomBasePrice'], 700);
      final includedAttendants = parseIntSafe(
        pricing['privateRoomIncludedAttendants'],
        1,
      );
      final extraFee = parseDoubleSafe(
        pricing['privateRoomExtraAttendantFee'],
        200,
      );

      baseCost = basePrice * durationDays;
      final chargedAttendants = attendantCount > includedAttendants
          ? attendantCount - includedAttendants
          : 0;
      extraAttendantCost = chargedAttendants * extraFee * durationDays;
    } else {
      final bedPrice = parseDoubleSafe(pricing['generalRoomBedPrice'], 150);
      baseCost = bedPrice * (1 + attendantCount) * durationDays;
    }

    return CostBreakdown(
      baseCost: baseCost,
      extraAttendantCost: extraAttendantCost,
      totalCost: baseCost + extraAttendantCost,
    );
  }

  /// Keeps a stay's stored pricing in sync when attendants are edited after
  /// admission. The private-room base includes the configured free attendant.
  Future<void> updateStayAttendantCount(
    String stayId,
    int attendantCount, {
    List<String> attendantLabels = const [],
  }) async {
    final stay = await getStay(stayId);
    if (stay == null) throw Exception('Stay not found');
    final costs = _calculateStayCosts(
      roomType: stay.roomType,
      durationDays: stay.totalDays,
      attendantCount: attendantCount,
      pricing: await getPricing(),
    );
    final updates = <String, dynamic>{
      'attendantCount': attendantCount,
      'attendantLabels': attendantLabels,
      'baseCost': costs.baseCost,
      'extraAttendantCost': costs.extraAttendantCost,
      'totalCost': costs.totalCost,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (stay.roomType == 'private') {
      final room = await getRoom(stay.roomId);
      if (room != null) {
        final projectedAttendants =
            room.currentAttendants - stay.attendantCount + attendantCount;
        if (projectedAttendants < 0 ||
            projectedAttendants > room.maxAttendants) {
          throw Exception(
            'Private room attendant limit exceeded (${room.maxAttendants})',
          );
        }
        final rootUpdates = <String, dynamic>{
          for (final entry in updates.entries)
            'stays/$stayId/${entry.key}': entry.value,
          'rooms/${stay.roomId}/currentAttendants': projectedAttendants,
        };
        await rtdb.patch('', rootUpdates);
        return;
      }
    }
    await rtdb.patch('$staysPath/$stayId', updates);
  }
}
