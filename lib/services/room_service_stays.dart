part of 'room_service.dart';

/// Stays operations for RoomService.
///
/// Creating, extending, and completing patient stays.
extension RoomServiceStays on RoomService {
  Future<Map<String, dynamic>> _patientSnapshot(String patientId) async {
    final data = isPostgres
        ? await backendApi!.get('patients/$patientId')
        : await rtdb.get('patients/$patientId');
    if (data is! Map) return {};
    final snapshot = <String, dynamic>{
      for (final key in ['registrationNumber', 'photoRef', 'admissionDate'])
        key: data[key],
    };
    final attendants = data['attendants'];
    if (attendants is List) {
      snapshot['attendants'] = [
        for (final attendant in attendants)
          if (attendant is Map)
            (Map<String, dynamic>.from(attendant)..remove('photoDataUrl')),
      ];
    }
    return snapshot;
  }
  // --- Stays ---

  Stream<List<StayModel>> getStaysStream() {
    final sourceStream = isPostgres
        ? backendApi!.stream(staysPath)
        : rtdb.stream(staysPath);
    return sourceStream.map((data) {
      final stays = parseStaysFromData(data);
      stays.sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
      return stays;
    });
  }

  Stream<List<StayModel>> getActiveStaysStream() {
    if (isPostgres) {
      return _filteredPostgresStaysStream({
        'status': 'active',
      }).map((stays) => stays.where((s) => s.status == 'active').toList());
    }
    return rtdb
        .queryStream(staysPath, orderBy: 'status', equalTo: 'active')
        .map(parseStaysFromData);
  }

  Stream<List<StayModel>> getStaysByRoomStream(String roomId) {
    if (isPostgres) {
      return _filteredPostgresStaysStream({
        'roomId': roomId,
        'status': 'active',
      }).map(
        (stays) => stays
            .where((s) => s.roomId == roomId && s.status == 'active')
            .toList(),
      );
    }
    return rtdb
        .queryStream(staysPath, orderBy: 'roomId', equalTo: roomId)
        .map(
          (data) => parseStaysFromData(
            data,
          ).where((s) => s.roomId == roomId && s.status == 'active').toList(),
        );
  }

  Stream<List<StayModel>> getStaysByPatientStream(String patientId) {
    if (isPostgres) {
      return _filteredPostgresStaysStream({
        'patientId': patientId,
      }).map((stays) => stays.where((s) => s.patientId == patientId).toList());
    }
    return rtdb
        .queryStream(staysPath, orderBy: 'patientId', equalTo: patientId)
        .map(parseStaysFromData);
  }

  Stream<List<StayModel>> _filteredPostgresStaysStream(
    Map<String, String> filters,
  ) {
    final path = Uri(
      path: staysPath,
      queryParameters: {...filters, 'format': 'map'},
    ).toString();
    return backendApi!.stream(path).map((data) {
      final stays = parseStaysFromData(data);
      stays.sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
      return stays;
    });
  }

  /// Records a lobby admission in stay history without reserving a room bed.
  Future<String> createLobbyStay({
    required String patientId,
    required String patientName,
    required String lobbyName,
    required DateTime admissionDate,
    required int durationDays,
    int? projectedBillableDays,
    required int attendantCount,
    List<String> attendantLabels = const [],
    required String createdBy,
    String status = 'active',
    DateTime? completedAt,
    String? deterministicStayId,
  }) async {
    if (status == 'active') {
      final lobbyStays = isPostgres
          ? await backendApi!.get('$staysPath?status=active&format=map')
          : await rtdb.getByChildValue(
              staysPath,
              child: 'roomNumber',
              value: lobbyName,
            );
      final occupied = parseStaysFromData(lobbyStays).any(
        (stay) =>
            stay.roomType == 'lobby' &&
            stay.status == 'active' &&
            stay.roomNumber.trim().toLowerCase() ==
                lobbyName.trim().toLowerCase() &&
            stay.patientId != patientId,
      );
      if (occupied) {
        throw Exception('$lobbyName is already occupied');
      }
    }
    final now = completedAt ?? DateTime.now();
    final stayId = deterministicStayId ?? generateStayId();
    final end = completedAt ?? admissionDate.add(Duration(days: durationDays));
    final costs = _calculateStayCosts(
      roomType: 'general',
      durationDays: durationDays,
      projectedBillableDays: projectedBillableDays,
      attendantCount: attendantCount,
      pricing: await getPricing(),
    );
    final staySnapshot = await _patientSnapshot(patientId);
    final stay = StayModel(
      id: stayId,
      patientId: patientId,
      patientName: patientName,
      patientSnapshot: staySnapshot,
      cycleId: staySnapshot['admissionDate']?.toString(),
      // The admission estimate may include attendants, but the final daily
      // charge is attendance-driven. Leaving this unset lets billing add only
      // attendants explicitly marked Present for each billable date.
      dailyRate: null,
      completedAt: status == 'active' ? null : completedAt,
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
    if (isPostgres) {
      await backendApi!.createStay(stay.toMap());
      return stayId;
    }
    await rtdb.patch('$staysPath/$stayId', stay.toMap());
    return stayId;
  }

  Future<String> createStay({
    String? id,
    required String patientId,
    required String patientName,
    required String roomId,
    required String roomNumber,
    required String roomType,
    required DateTime admissionDate,
    required int durationDays,
    int? projectedBillableDays,
    required int attendantCount,
    List<String> attendantLabels = const [],
    String? bedId,
    String? bedLabel,
    String? notes,
    required String createdBy,
  }) async {
    try {
      if (isPostgres) {
        String? resolvedBedId = bedId;
        String? resolvedBedLabel = bedLabel;
        if (resolvedBedId == null) {
          final room = await getRoomDirect(roomId);
          final availableBed = room?.beds
              .where((b) => b.status == 'available')
              .firstOrNull;
          if (availableBed != null) {
            resolvedBedId = availableBed.id;
            resolvedBedLabel ??= availableBed.bedLabel;
          }
        }
        final pricing = await getPricing();
        final costs = _calculateStayCosts(
          roomType: roomType,
          durationDays: durationDays,
          projectedBillableDays: projectedBillableDays,
          attendantCount: attendantCount,
          pricing: pricing,
        );
        final expectedDischargeDate = admissionDate.add(
          Duration(days: durationDays),
        );
        final staySnapshot = await _patientSnapshot(patientId);
        final stayId = id ?? generateStayId();
        final stayData = {
          'id': stayId,
          'patientId': patientId,
          'patientName': patientName,
          'patientSnapshot': staySnapshot,
          'cycleId': staySnapshot['admissionDate']?.toString(),
          'roomId': roomId,
          'roomNumber': roomNumber,
          'roomType': roomType,
          'admissionDate': admissionDate.millisecondsSinceEpoch,
          'durationDays': durationDays,
          'expectedDischargeDate': expectedDischargeDate.millisecondsSinceEpoch,
          'expiryDate': expectedDischargeDate.millisecondsSinceEpoch,
          'attendantCount': attendantCount,
          'attendantLabels': attendantLabels,
          'totalCost': costs.totalCost,
          'baseCost': costs.baseCost,
          'extraAttendantCost': costs.extraAttendantCost,
          'status': 'active',
          'bedId': resolvedBedId,
          'bedLabel': resolvedBedLabel,
          'notes': notes,
          'createdBy': createdBy,
        };
        try {
          final res = await backendApi!.createStay(stayData);
          return res['id']?.toString() ?? stayId;
        } on BackendApiException catch (e) {
          if (e.statusCode == 409) {
            throw bedConflict(e.message);
          }
          rethrow;
        }
      }

      // Direct room read — no full stays collection download.
      final room = await getRoomDirect(roomId);
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
        if (bedId != null) {
          targetBed = room.beds.where((b) => b.id == bedId).firstOrNull;
        }
        targetBed ??= room.beds
            .where((b) => b.status == 'available')
            .firstOrNull;
        if (targetBed == null) {
          throw Exception('No available bed found in private room');
        }
      } else {
        final maxAttendants = room.maxAttendants;
        if (attendantCount > maxAttendants) {
          throw Exception(
            'General room attendant limit exceeded ($maxAttendants)',
          );
        }
        if (bedId != null) {
          targetBed = room.beds.where((b) => b.id == bedId).firstOrNull;
        }
        targetBed ??= room.beds
            .where((b) => b.status == 'available')
            .firstOrNull;
        if (targetBed == null || targetBed.status != 'available') {
          throw Exception('Selected bed is no longer available');
        }
      }

      final costs = _calculateStayCosts(
        roomType: resolvedRoomType,
        durationDays: durationDays,
        projectedBillableDays: projectedBillableDays,
        attendantCount: attendantCount,
        pricing: pricing,
      );

      final expectedDischargeDate = admissionDate.add(
        Duration(days: durationDays),
      );
      final now = DateTime.now();
      final stayId = id ?? generateStayId();

      final staySnapshot = await _patientSnapshot(patientId);
      final stay = StayModel(
        id: stayId,
        patientId: patientId,
        patientName: patientName,
        patientSnapshot: staySnapshot,
        cycleId: staySnapshot['admissionDate']?.toString(),
        // Keep the initial total as an estimate; the daily rate must remain
        // dynamic so absent or unmarked attendants are not charged.
        dailyRate: null,
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

      // Server-enforced compare-and-swap: two receptionists cannot both win
      // the same bed. On conflict the operation retries against fresh state.
      await reserveBeds(
        roomId: roomId,
        bedIds: [targetBed.id],
        patientId: patientId,
        stayIds: [stayId],
        attendantCount: resolvedRoomType == 'private' ? attendantCount : 0,
        expectedDischargeDate: expectedDischargeDate,
      );

      try {
        await rtdb.patch('$staysPath/$stayId', stay.toMap());
      } catch (e) {
        // A timed-out REST response is ambiguous: the stay may have been
        // committed. Never release its bed until a read proves it is absent.
        final saved = await rtdb.get('$staysPath/$stayId');
        if (saved is Map) return stayId;
        await releaseBeds(
          roomId: roomId,
          patientId: patientId,
          stayIds: [stayId],
          attendantCount: resolvedRoomType == 'private' ? attendantCount : 0,
        );
        rethrow;
      }
      return stayId;
    } catch (e) {
      if (e is BedConflictException) rethrow;
      throw Exception('Failed to create stay: $e');
    }
  }

  /// Creates one stay per selected bed and reserves ALL beds atomically.
  ///
  /// Multi-bed admissions are all-or-nothing: every bed is validated and
  /// reserved in a single conditional write; the stays are then persisted in
  /// one multi-path update. A failure at any point releases every bed.
  Future<List<String>> createStaysForBeds({
    required String patientId,
    required String patientName,
    required String roomId,
    required DateTime admissionDate,
    required int durationDays,
    int? projectedBillableDays,
    required int attendantCount,
    required List<String> bedIds,
    List<String> attendantLabels = const [],
    String? notes,
    required String createdBy,
    Map<String, dynamic>? patientSnapshot,
    RoomModel? initialRoom,
    List<String>? deterministicStayIds,
  }) async {
    try {
      final room = initialRoom ?? await getRoomDirect(roomId);
      if (room == null) throw Exception('Room not found');
      final pricing = await getPricing();

      if (bedIds.isEmpty) throw Exception('Select at least one bed');
      if (!isPostgres) {
        final missing = bedIds
            .where((id) => room.beds.every((bed) => bed.id != id))
            .toList();
        if (missing.isNotEmpty) {
          throw Exception('Selected bed(s) no longer exist in this room');
        }
      }
      if (room.isPrivate) {
        final projectedAttendants = room.currentAttendants + attendantCount;
        if (projectedAttendants > room.maxAttendants) {
          throw Exception(
            'Private room attendant limit exceeded (${room.maxAttendants})',
          );
        }
      } else if (attendantCount > room.maxAttendants) {
        throw Exception(
          'General room attendant limit exceeded (${room.maxAttendants})',
        );
      }

      final costs = _calculateStayCosts(
        roomType: room.roomType,
        durationDays: durationDays,
        projectedBillableDays: projectedBillableDays,
        attendantCount: attendantCount,
        pricing: pricing,
      );
      final expectedDischargeDate = admissionDate.add(
        Duration(days: durationDays),
      );
      final now = DateTime.now();
      final staySnapshot = patientSnapshot ?? await _patientSnapshot(patientId);

      final stays = <String, StayModel>{};
      for (var i = 0; i < bedIds.length; i++) {
        final bedId = bedIds[i];
        final bed = room.beds.where((b) => b.id == bedId).firstOrNull;
        final stayId =
            (deterministicStayIds != null && i < deterministicStayIds.length)
            ? deterministicStayIds[i]
            : generateStayId();
        final resolvedLabel = bed?.bedLabel ?? bedId;
        stays[stayId] = StayModel(
          id: stayId,
          patientId: patientId,
          patientName: patientName,
          patientSnapshot: staySnapshot,
          cycleId: staySnapshot['admissionDate']?.toString(),
          dailyRate: null,
          roomId: roomId,
          roomNumber: room.roomIdentifier,
          roomType: room.roomType,
          admissionDate: admissionDate,
          durationDays: durationDays,
          expectedDischargeDate: expectedDischargeDate,
          expiryDate: expectedDischargeDate,
          attendantCount: attendantCount,
          attendantLabels: attendantLabels,
          totalCost: costs.totalCost,
          baseCost: costs.baseCost,
          extraAttendantCost: costs.extraAttendantCost,
          status: 'active',
          bedId: bedId,
          bedNumber: int.tryParse(resolvedLabel),
          bedLabel: resolvedLabel,
          notes: notes,
          createdAt: now,
          updatedAt: now,
          createdBy: createdBy,
        );
      }
      final stayIds = stays.keys.toList();

      if (isPostgres) {
        try {
          return await backendApi!.createStaysBatch(
            stays.values.map((s) => s.toMap()).toList(),
          );
        } on BackendApiException catch (e) {
          if (e.statusCode == 409) {
            throw bedConflict(e.message);
          }
          rethrow;
        }
      }

      // All-or-nothing reservation of every selected bed.
      await reserveBeds(
        roomId: roomId,
        bedIds: bedIds,
        patientId: patientId,
        stayIds: stayIds,
        attendantCount: room.isPrivate ? attendantCount : 0,
        expectedDischargeDate: expectedDischargeDate,
      );

      try {
        final updates = <String, dynamic>{
          for (final stay in stays.values) 'stays/${stay.id}': stay.toMap(),
        };
        await rtdb.patch('', updates);
      } catch (e) {
        // Multi-path updates are atomic, but a network timeout may occur
        // after Firebase committed them. Verify before compensation.
        final saved = await rtdb.get('$staysPath/${stayIds.first}');
        if (saved is Map) return stayIds;
        await releaseBeds(
          roomId: roomId,
          patientId: patientId,
          stayIds: stayIds,
          attendantCount: room.isPrivate ? attendantCount : 0,
        );
        rethrow;
      }
      return stayIds;
    } catch (e) {
      if (e is BedConflictException) rethrow;
      throw Exception('Failed to create stays: $e');
    }
  }

  /// Moves an admission between placements without changing its billing cycle.
  Future<void> transferPatient({
    required String patientId,
    required List<String> expectedStayIds,
    required String roomId,
    required String roomNumber,
    required String roomType,
    String? bedId,
    required DateTime shiftedAt,
    DateTime? exitDate,
    String? requestId,
  }) async {
    if (!isPostgres) {
      throw UnsupportedError('Atomic transfer requires PostgreSQL');
    }
    await backendApi!.transferPatient(patientId, {
      'requestId': requestId ?? generateStayId(),
      'expectedStayIds': expectedStayIds,
      'roomId': roomId,
      'roomNumber': roomNumber,
      'roomType': roomType,
      'bedId': bedId,
      'shiftedAt': shiftedAt.millisecondsSinceEpoch,
      'exitDate': exitDate?.millisecondsSinceEpoch,
    });
  }

  Future<double> quoteStayExtension({
    required String stayId,
    required int additionalDays,
  }) async {
    if (additionalDays < 1 || additionalDays > 3650) {
      throw ArgumentError('Extension days must be between 1 and 3650');
    }
    if (isPostgres) {
      final quote = await backendApi!.get(
        'stays/extension-quote?stayId=${Uri.encodeQueryComponent(stayId)}&additionalDays=$additionalDays',
        allowCacheFallback: false,
      );
      final amount = quote is Map ? quote['additionalCost'] : null;
      if (amount is! num || !amount.isFinite || amount < 0) {
        throw StateError('Invalid server extension quote');
      }
      return amount.toDouble();
    }
    final raw = await rtdb.get('$staysPath/$stayId');
    if (raw is! Map) throw StateError('Stay not found');
    return PaymentService(rtdb).quoteLegacyStayExtension(
      StayModel.fromMap(stayId, Map<String, dynamic>.from(raw)),
      additionalDays,
    );
  }

  Future<void> extendStay({
    required String stayId,
    required int additionalDays,
    String reason = '',
    String? requestId,
  }) async {
    try {
      if (additionalDays <= 0 || additionalDays > 3650) {
        throw ArgumentError.value(
          additionalDays,
          'additionalDays',
          'must be between 1 and 3650',
        );
      }
      final effectiveRequestId = requestId ?? generateStayId();
      if (isPostgres) {
        // Send the increment. The server applies it and the patient extension
        // fields together while holding the current stay and patient locks.
        await backendApi!.updateStay(stayId, {
          'additionalDays': additionalDays,
          'reason': reason,
          'extensionRequestId': effectiveRequestId,
        });
        return;
      }
      final data = isPostgres
          ? await backendApi!.get('$staysPath/$stayId')
          : await rtdb.get('$staysPath/$stayId');
      if (data == null || data is! Map) throw Exception('Stay not found');

      final stay = StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      final priorRequest = stay.extensions
          .where((extension) => extension.requestId == effectiveRequestId)
          .firstOrNull;
      if (priorRequest != null) {
        if (priorRequest.additionalDays != additionalDays ||
            priorRequest.reason != reason) {
          throw StateError('Extension request ID already used differently');
        }
        return;
      }
      final additionalCost = await PaymentService(
        rtdb,
      ).quoteLegacyStayExtension(stay, additionalDays);

      final extensionEntry = StayExtension(
        requestId: effectiveRequestId,
        additionalDays: additionalDays,
        extendedOn: DateTime.now(),
        reason: reason,
        additionalCost: additionalCost,
      );

      final updatedExtensions = [...stay.extensions, extensionEntry];
      final newTotalExtended = stay.totalExtendedDays + additionalDays;
      final newExpiry = stay.expectedDischargeDate.add(
        Duration(days: additionalDays),
      );
      final newTotalCost = stay.totalCost + additionalCost;
      final stayUpdates = {
        // durationDays is the original admission period. Extensions are
        // tracked only in totalExtendedDays so StayModel.totalDays cannot
        // count the same extension twice.
        'totalExtendedDays': newTotalExtended,
        // Make sure both legacy and new date formats are updated
        'expectedDischargeDate': newExpiry
            .millisecondsSinceEpoch, // Added based on new stay model requirement
        'expiryDate': newExpiry.millisecondsSinceEpoch,
        'totalCost': newTotalCost,
        'extensions': updatedExtensions.map((e) => e.toMap()).toList(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      await rtdb.patch('$staysPath/$stayId', stayUpdates);

      await updateRoomStatus(stay.roomId);

      // Sync extension with PatientModel
      try {
        final patientData = await rtdb.get('patients/${stay.patientId}');

        if (patientData != null && patientData is Map) {
          final currentExtensionDays =
              (patientData['extensionDays'] ?? 0) as int;

          await rtdb.patch('patients/${stay.patientId}', {
            'extensionDays': currentExtensionDays + additionalDays,
            'extensionApproved': true,
            if (patientData['exitDate'] != null)
              'exitDate': DateTime.fromMillisecondsSinceEpoch(
                parseIntSafe(patientData['exitDate'], 0),
              ).add(Duration(days: additionalDays)).millisecondsSinceEpoch,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      } catch (e) {
        debugPrint('Failed to sync patient extension: $e');
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
      final now = completedAt ?? DateTime.now();
      if (isPostgres) {
        final updates = <String, dynamic>{
          'status': 'completed',
          'completedAt': now.millisecondsSinceEpoch,
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
        };
        await backendApi!.updateStay(stayId, updates);
        return;
      }

      final data = await rtdb.get('$staysPath/$stayId');
      if (data == null || data is! Map) throw Exception('Stay not found');

      final stay = StayModel.fromMap(stayId, Map<String, dynamic>.from(data));
      if (stay.patientSnapshot.isEmpty) {
        await rtdb.patch('$staysPath/$stayId', {
          'patientSnapshot': await _patientSnapshot(stay.patientId),
        });
      }
      final room = await getRoomDirect(stay.roomId);
      if (room == null) {
        // Legacy/imported stays can point to a room that was renamed or
        // removed. Completing the historical stay must not block discharge
        // or deletion when there is no physical bed left to release.
        await rtdb.patch('$staysPath/$stayId', {
          'status': 'completed',
          'completedAt': now.millisecondsSinceEpoch,
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

      // Release the bed under compare-and-swap so a concurrent transfer or
      // re-admission cannot be overwritten by a stale room snapshot.
      final released = await _updateRoomBedsWithCas(
        room.id,
        (fresh) {
          var targetBed = stay.bedId != null
              ? fresh.beds
                    .where(
                      (b) => b.id == stay.bedId && b.currentStayId == stay.id,
                    )
                    .firstOrNull
              : fresh.beds.where((b) => b.currentStayId == stay.id).firstOrNull;
          targetBed ??= fresh.beds
              .where((b) => b.currentStayId == stay.id)
              .firstOrNull;
          if (targetBed == null) return fresh.beds;
          return fresh.beds.map((b) {
            if (b.id == targetBed!.id) {
              return b.copyWith(
                status: 'available',
                clearPatientId: true,
                clearStayId: true,
              );
            }
            return b;
          }).toList();
        },
        attendantDelta:
            room.isPrivate && room.currentAttendants >= stay.attendantCount
            ? -stay.attendantCount
            : 0,
      );
      if (!released) {
        throw BedConflictException('Room changed while releasing the bed');
      }

      await rtdb.patch('$staysPath/$stayId', {
        'status': 'completed',
        'completedAt': now.millisecondsSinceEpoch,
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
    } catch (e) {
      throw Exception('Failed to complete stay: $e');
    }
  }

  Future<StayModel?> getStay(String stayId) async {
    try {
      final data = isPostgres
          ? await backendApi!.get('$staysPath/$stayId')
          : await rtdb.get('$staysPath/$stayId');
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
    final durationDays = PricingHelper.calculateStayDays(
      admissionDate,
      exitDate,
    );
    final end = exitDate ?? admissionDate.add(Duration(days: durationDays));
    final updates = {
      'admissionDate': admissionDate.millisecondsSinceEpoch,
      'durationDays': durationDays,
      'expectedDischargeDate': end.millisecondsSinceEpoch,
      'expiryDate': end.millisecondsSinceEpoch,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (isPostgres) {
      await backendApi!.updateStay(stayId, updates);
      return;
    }
    await rtdb.patch('$staysPath/$stayId', updates);
  }

  CostBreakdown _calculateStayCosts({
    required String roomType,
    required int durationDays,
    int? projectedBillableDays,
    required int attendantCount,
    required Map<String, dynamic> pricing,
  }) {
    final days = (projectedBillableDays ?? durationDays).clamp(1, 3650);
    final isPrivate = roomType.toLowerCase() == 'private';
    final patientOnlyCost = PricingHelper.calculateProjectedStayCost(
      isPrivate,
      0,
      days,
      pricing: pricing,
    );
    final totalCost = PricingHelper.calculateProjectedStayCost(
      isPrivate,
      attendantCount,
      days,
      pricing: pricing,
    );
    final baseCost = isPrivate ? patientOnlyCost : totalCost;
    final extraAttendantCost = isPrivate ? totalCost - baseCost : 0.0;

    return CostBreakdown(
      baseCost: baseCost,
      extraAttendantCost: extraAttendantCost,
      totalCost: totalCost,
    );
  }

  /// Keeps a stay's stored pricing in sync when attendants are edited after
  /// admission. The private-room base includes the configured free attendant.
  Future<void> updateStayAttendantCount(
    String stayId,
    int attendantCount, {
    List<String> attendantLabels = const [],
    List<Map<String, dynamic>>? attendants,
  }) async {
    final stay = await getStay(stayId);
    if (stay == null) throw Exception('Stay not found');
    final room = await getRoom(stay.roomId);
    if (room != null && attendantCount > room.maxAttendants) {
      throw Exception(
        '${room.isPrivate ? 'Private room' : 'General room'} attendant limit exceeded (${room.maxAttendants})',
      );
    }
    final costs = _calculateStayCosts(
      roomType: stay.roomType,
      durationDays: stay.totalDays,
      attendantCount: attendantCount,
      pricing: await getPricing(),
    );
    final updates = <String, dynamic>{
      'attendantCount': attendantCount,
      'attendantLabels': attendantLabels,
      if (attendants != null)
        'patientSnapshot/attendants': [
          for (final attendant in attendants)
            (Map<String, dynamic>.from(attendant)..remove('photoDataUrl')),
        ],
      // Changing the attendant list must not turn the estimate into a fixed
      // daily charge. Attendance determines the attendant portion per day.
      'dailyRate': null,
      'baseCost': costs.baseCost,
      'extraAttendantCost': costs.extraAttendantCost,
      'totalCost': costs.totalCost,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (isPostgres) {
      await backendApi!.updateStay(stayId, updates);
      return;
    }
    if (stay.roomType == 'private') {
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

  /// Updates a stay's historical patient snapshot via the active backend.
  Future<void> updateStaySnapshot(
    String stayId,
    Map<String, dynamic> snapshot,
  ) async {
    if (isPostgres) {
      await backendApi!.updateStay(stayId, {'patientSnapshot': snapshot});
      return;
    }
    await rtdb.patch('$staysPath/$stayId', {'patientSnapshot': snapshot});
  }

  /// Builds the initial stay payloads for atomic registration (`POST /api/patients/register`).
  Future<List<Map<String, dynamic>>> buildRegistrationStaysPayload({
    required String patientId,
    required String patientName,
    required DateTime admissionDate,
    required int durationDays,
    int? projectedBillableDays,
    required int attendantCount,
    List<String> attendantLabels = const [],
    required String createdBy,
    Map<String, dynamic>? patientSnapshot,
    String? lobbyName,
    RoomModel? room,
    List<String> bedIds = const [],
    String? notes,
  }) async {
    final pricing = await getPricing();
    final now = DateTime.now();
    final expectedDischargeDate = admissionDate.add(
      Duration(days: durationDays),
    );
    final snapshot = patientSnapshot ?? const <String, dynamic>{};
    final payloads = <Map<String, dynamic>>[];

    if (lobbyName != null && lobbyName.trim().isNotEmpty) {
      final sanitizedLobby = lobbyName.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final stayId = 'stay_${patientId}_lobby_$sanitizedLobby';
      final costs = _calculateStayCosts(
        roomType: 'general',
        durationDays: durationDays,
        projectedBillableDays: projectedBillableDays,
        attendantCount: attendantCount,
        pricing: pricing,
      );
      final stay = StayModel(
        id: stayId,
        patientId: patientId,
        patientName: patientName,
        patientSnapshot: snapshot,
        cycleId: snapshot['admissionDate']?.toString(),
        dailyRate: null,
        roomId: 'lobby:$lobbyName',
        roomNumber: lobbyName,
        roomType: 'lobby',
        admissionDate: admissionDate,
        durationDays: durationDays,
        expectedDischargeDate: expectedDischargeDate,
        expiryDate: expectedDischargeDate,
        attendantCount: attendantCount,
        attendantLabels: attendantLabels,
        totalCost: costs.totalCost,
        baseCost: costs.baseCost,
        extraAttendantCost: costs.extraAttendantCost,
        status: 'active',
        notes: 'Lobby admission',
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
      );
      payloads.add(stay.toMap());
    }

    if (room != null && bedIds.isNotEmpty) {
      if (room.isPrivate) {
        final projectedAttendants = room.currentAttendants + attendantCount;
        if (projectedAttendants > room.maxAttendants) {
          throw Exception(
            'Private room attendant limit exceeded (${room.maxAttendants})',
          );
        }
      } else if (attendantCount > room.maxAttendants) {
        throw Exception(
          'General room attendant limit exceeded (${room.maxAttendants})',
        );
      }
      final costs = _calculateStayCosts(
        roomType: room.roomType,
        durationDays: durationDays,
        projectedBillableDays: projectedBillableDays,
        attendantCount: attendantCount,
        pricing: pricing,
      );
      for (final bedId in bedIds) {
        final bed = room.beds.where((b) => b.id == bedId).firstOrNull;
        final resolvedLabel = bed?.bedLabel ?? bedId;
        final stayId = 'stay_${patientId}_$bedId';
        final stay = StayModel(
          id: stayId,
          patientId: patientId,
          patientName: patientName,
          patientSnapshot: snapshot,
          cycleId: snapshot['admissionDate']?.toString(),
          dailyRate: null,
          roomId: room.id,
          roomNumber: room.roomIdentifier,
          roomType: room.roomType,
          admissionDate: admissionDate,
          durationDays: durationDays,
          expectedDischargeDate: expectedDischargeDate,
          expiryDate: expectedDischargeDate,
          attendantCount: attendantCount,
          attendantLabels: attendantLabels,
          totalCost: costs.totalCost,
          baseCost: costs.baseCost,
          extraAttendantCost: costs.extraAttendantCost,
          status: 'active',
          bedId: bedId,
          bedNumber: int.tryParse(resolvedLabel),
          bedLabel: resolvedLabel,
          notes: notes,
          createdAt: now,
          updatedAt: now,
          createdBy: createdBy,
        );
        payloads.add(stay.toMap());
      }
    }

    return payloads;
  }
}
