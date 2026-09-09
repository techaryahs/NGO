import '../models/patient_model.dart';
import '../models/stay_model.dart';
import '../models/room_model.dart';
import '../utils/stay_billing.dart';
import '../utils/pricing_helper.dart';
import 'firebase_rtdb_rest_service.dart';
import 'payment_service.dart';

class StayHistoryService {
  final FirebaseRTDBRestService db;
  StayHistoryService(this.db);

  Future<void> deleteAdmission(
    String patientId,
    List<StayModel> segments,
  ) async {
    if (segments.isEmpty) return;
    final patientRaw = await db.get('patients/$patientId');
    if (patientRaw is! Map) throw StateError('Patient not found');
    final patientData = Map<String, dynamic>.from(patientRaw);
    final patient = PatientModel.fromMap(patientId, patientData);
    final paymentService = PaymentService(db);
    final allStays = await paymentService.loadStays(patientId);
    final cycleId = StayBilling.cycleFor(segments.first, patient);
    if (segments.any(
      (stay) => StayBilling.cycleFor(stay, patient) != cycleId,
    )) {
      throw ArgumentError('The stay card contains different admissions.');
    }
    final cyclePayments = (patient.payments ?? const <PaymentModel>[]).where(
      (payment) =>
          payment.cycleId == cycleId ||
          (payment.cycleId == null &&
              StayBilling.paymentCycle(payment, patient, allStays) == cycleId),
    );
    if (cyclePayments.isNotEmpty) {
      throw StateError(
        'Delete this admission’s payment and refund transactions before deleting its stay card.',
      );
    }

    final ids = segments.map((stay) => stay.id).toSet();
    final root = <String, dynamic>{for (final id in ids) 'stays/$id': null};
    for (final roomId
        in segments
            .where((stay) => stay.roomType != 'lobby')
            .map((stay) => stay.roomId)
            .toSet()) {
      final roomRaw = await db.get('rooms/$roomId');
      if (roomRaw is! Map) continue;
      final room = RoomModel.fromMap(roomId, roomRaw);
      final beds = room.beds
          .map(
            (bed) => ids.contains(bed.currentStayId)
                ? bed.copyWith(
                    status: 'available',
                    clearPatientId: true,
                    clearStayId: true,
                  )
                : bed,
          )
          .toList();
      final removedAttendants = segments
          .where(
            (stay) => stay.isActive && stay.roomId == roomId && room.isPrivate,
          )
          .fold<int>(0, (sum, stay) => sum + stay.attendantCount);
      final occupied = beds.where((bed) => bed.isOccupied).length;
      root.addAll({
        'rooms/$roomId/beds': {for (final bed in beds) bed.id: bed.toMap()},
        'rooms/$roomId/occupiedBeds': occupied,
        'rooms/$roomId/currentAttendants':
            (room.currentAttendants - removedAttendants).clamp(0, 999),
        'rooms/$roomId/status': room.status == 'maintenance'
            ? 'maintenance'
            : occupied == 0
            ? 'available'
            : 'occupied',
        'rooms/$roomId/updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    final remaining = allStays.where((stay) => !ids.contains(stay.id)).toList();
    if (cycleId == StayBilling.currentCycle(patient)) {
      patientData.addAll({
        'roomId': null,
        'roomNumber': null,
        'lobby': null,
        'floor': null,
        'bedIds': <String>[],
        'bedLabels': <String>[],
        'billingAmountOverride': null,
      });
      for (final key in [
        'roomId',
        'roomNumber',
        'lobby',
        'floor',
        'bedIds',
        'bedLabels',
        'billingAmountOverride',
      ]) {
        root['patients/$patientId/$key'] = patientData[key];
      }
    }
    root.addAll(
      await paymentService.billingUpdates(
        patientId,
        patientData: patientData,
        stays: remaining,
      ),
    );
    await db.patch('', root);
  }

  Future<void> updateShiftTimeline(
    String patientId,
    List<({StayModel stay, DateTime start, DateTime end})> edits, {
    List<double?>? costOverrides,
    bool noPlannedExitDate = false,
  }) async {
    if (edits.length < 2) return;
    if (costOverrides != null && costOverrides.length != edits.length) {
      throw ArgumentError('A charge value is required for every placement.');
    }
    final patientRaw = await db.get('patients/$patientId');
    if (patientRaw is! Map) throw StateError('Patient not found');
    final patientData = Map<String, dynamic>.from(patientRaw);
    final patient = PatientModel.fromMap(patientId, patientData);
    final paymentService = PaymentService(db);
    final allStays = await paymentService.loadStays(patientId);
    final cycleId = StayBilling.cycleFor(edits.first.stay, patient);
    if (edits.any(
      (edit) => StayBilling.cycleFor(edit.stay, patient) != cycleId,
    )) {
      throw ArgumentError('All placements must belong to one admission.');
    }
    for (var index = 0; index < edits.length; index++) {
      final edit = edits[index];
      if (!edit.end.isAfter(edit.start)) {
        throw ArgumentError(
          '${edit.stay.roomNumber}: end time must be after start time.',
        );
      }
      if (index < edits.length - 1 && edit.end != edits[index + 1].start) {
        throw ArgumentError(
          'The end of ${edit.stay.roomNumber} must match the start of ${edits[index + 1].stay.roomNumber}.',
        );
      }
    }
    final revisedById = <String, StayModel>{};
    final root = <String, dynamic>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var editIndex = 0; editIndex < edits.length; editIndex++) {
      final edit = edits[editIndex];
      final raw = await db.get('stays/${edit.stay.id}');
      if (raw is! Map) throw StateError('A stay record could not be found.');
      final current = StayModel.fromMap(edit.stay.id, raw);
      if (current.updatedAt != edit.stay.updatedAt) {
        throw StateError('Stay history changed elsewhere. Reopen the editor.');
      }
      final data = Map<String, dynamic>.from(raw);
      data['admissionDate'] = edit.start.millisecondsSinceEpoch;
      final override = costOverrides?[editIndex];
      if (override != null && (!override.isFinite || override < 0)) {
        throw ArgumentError('Charged amounts must be zero or greater.');
      }
      data['costOverride'] = override;
      if (current.isActive) {
        data['expectedDischargeDate'] = edit.end.millisecondsSinceEpoch;
      } else {
        data['completedAt'] = edit.end.millisecondsSinceEpoch;
      }
      data['durationDays'] = PricingHelper.calculateStayDays(
        edit.start,
        edit.end,
      );
      data['updatedAt'] = now;
      data['cycleId'] = cycleId;
      revisedById[current.id] = StayModel.fromMap(current.id, data);
      for (final entry in data.entries) {
        root['stays/${current.id}/${entry.key}'] = entry.value;
      }
    }
    final updatedStays = allStays
        .map((stay) => revisedById[stay.id] ?? stay)
        .toList();
    final first = edits.first;
    final last = edits.last;
    if (cycleId == StayBilling.currentCycle(patient)) {
      patientData['registrationDate'] = first.start.millisecondsSinceEpoch;
      patientData['exitDate'] = last.stay.isActive && noPlannedExitDate
          ? null
          : last.end.millisecondsSinceEpoch;
      root['patients/$patientId/registrationDate'] =
          first.start.millisecondsSinceEpoch;
      root['patients/$patientId/exitDate'] = patientData['exitDate'];
      if (last.stay.isActive && last.stay.roomType != 'lobby') {
        root['rooms/${last.stay.roomId}/expectedVacancyDate'] =
            last.end.millisecondsSinceEpoch;
      }
    }
    root.addAll(
      await paymentService.billingUpdates(
        patientId,
        patientData: patientData,
        stays: updatedStays,
      ),
    );
    await db.patch('', root);
  }

  Future<void> updateStay(
    String stayId,
    Map<String, dynamic> changes, {
    required DateTime expectedUpdatedAt,
  }) async {
    final raw = await db.get('stays/$stayId');
    if (raw is! Map)
      throw StateError('Stay not found. Refresh the patient and try again.');
    final original = StayModel.fromMap(stayId, raw);
    if (original.updatedAt != expectedUpdatedAt)
      throw StateError(
        'This stay was changed elsewhere. Reopen the edit form.',
      );
    final patientRaw = await db.get('patients/${original.patientId}');
    if (patientRaw is! Map) throw StateError('Patient not found');
    final patientData = Map<String, dynamic>.from(patientRaw);
    final patient = PatientModel.fromMap(original.patientId, patientData);
    final paymentService = PaymentService(db);
    final allStays = await paymentService.loadStays(patient.id);
    final cycleId = StayBilling.cycleFor(original, patient);
    final editable = <String>{
      'patientName',
      'patientSnapshot',
      'admissionDate',
      'completedAt',
      'expectedDischargeDate',
      'roomId',
      'roomNumber',
      'roomType',
      'bedId',
      'bedLabel',
      'attendantCount',
      'attendantLabels',
      'dailyRate',
      'dailyRateIsManual',
      'longStayDailyRate',
      'costOverride',
      'notes',
    };
    if (changes.keys.any((key) => !editable.contains(key)))
      throw ArgumentError('Unsupported stay field');
    final merged = <String, dynamic>{...raw, ...changes, 'cycleId': cycleId};
    final revised = StayModel.fromMap(stayId, merged);
    final end = revised.isActive
        ? revised.expectedDischargeDate
        : revised.completedAt;
    if (end == null || !end.isAfter(revised.admissionDate))
      throw ArgumentError('End date must be after the start date');
    if (end.difference(revised.admissionDate).inDays > 3650)
      throw ArgumentError('Stay cannot exceed 10 years');
    if (!{'private', 'general', 'lobby'}.contains(revised.roomType))
      throw ArgumentError('Select a valid room type');
    if (revised.isActive && revised.roomType == 'lobby') {
      final staysRaw = await db.get('stays');
      if (staysRaw is Map &&
          staysRaw.entries.any((entry) {
            if (entry.key.toString() == stayId || entry.value is! Map) {
              return false;
            }
            final other = StayModel.fromMap(entry.key.toString(), entry.value);
            return other.isActive &&
                other.roomType == 'lobby' &&
                other.roomNumber.trim().toLowerCase() ==
                    revised.roomNumber.trim().toLowerCase();
          })) {
        throw StateError('${revised.roomNumber} is already occupied');
      }
    }
    for (final rate in [
      revised.dailyRate,
      revised.longStayDailyRate,
      revised.costOverride,
    ]) {
      if (rate != null && (!rate.isFinite || rate < 0))
        throw ArgumentError('Charges must be zero or greater');
    }
    final snapshot = Map<String, dynamic>.from(revised.patientSnapshot);
    snapshot['admissionDate'] =
        int.tryParse(cycleId) ?? original.patientSnapshot['admissionDate'];
    merged['patientSnapshot'] = snapshot;
    final registration =
        snapshot['registrationNumber']?.toString().trim() ?? '';
    if (registration.isNotEmpty) {
      final patients = await db.get('patients');
      if (patients is Map &&
          patients.entries.any(
            (e) =>
                e.key != patient.id &&
                e.value is Map &&
                e.value['registrationNumber']
                        ?.toString()
                        .trim()
                        .toLowerCase() ==
                    registration.toLowerCase(),
          )) {
        throw ArgumentError(
          'Registration number already belongs to another patient',
        );
      }
    }
    final cycle =
        allStays
            .where((s) => StayBilling.cycleFor(s, patient) == cycleId)
            .toList()
          ..sort((a, b) => a.admissionDate.compareTo(b.admissionDate));
    final patches = <String, Map<String, dynamic>>{stayId: merged};
    // Keep adjoining transfer boundaries together when the shift date is corrected.
    for (final other in cycle.where((s) => s.id != stayId)) {
      final data = other.toMap();
      if (!other.isActive &&
          (other.completedAt ?? other.updatedAt) == original.admissionDate) {
        data['completedAt'] = revised.admissionDate.millisecondsSinceEpoch;
      }
      if (!original.isActive &&
          other.admissionDate == (original.completedAt ?? original.updatedAt)) {
        data['admissionDate'] = end.millisecondsSinceEpoch;
      }
      data['cycleId'] = cycleId;
      data['patientName'] = revised.patientName;
      data['patientSnapshot'] = {
        ...other.patientSnapshot,
        'registrationNumber': registration,
      };
      patches[other.id] = data;
    }
    final updatedStays = allStays
        .map(
          (s) => patches.containsKey(s.id)
              ? StayModel.fromMap(s.id, patches[s.id]!)
              : s,
        )
        .toList();
    final revisedCycle = updatedStays
        .where((s) => StayBilling.cycleFor(s, patient) == cycleId)
        .toList();
    for (final a in revisedCycle) {
      final aEnd = a.isActive
          ? a.expectedDischargeDate
          : a.completedAt ?? a.updatedAt;
      if (!aEnd.isAfter(a.admissionDate))
        throw ArgumentError('The dates would make an adjoining stay invalid');
      for (final b in revisedCycle.where((b) => b.id != a.id)) {
        if (a.roomId == b.roomId && a.admissionDate == b.admissionDate)
          continue;
        final bEnd = b.isActive
            ? b.expectedDischargeDate
            : b.completedAt ?? b.updatedAt;
        if (a.admissionDate.isBefore(bEnd) && b.admissionDate.isBefore(aEnd)) {
          throw ArgumentError(
            'These dates overlap another room segment in this admission',
          );
        }
      }
    }
    final root = <String, dynamic>{};
    RoomModel? target;
    if (revised.roomType != 'lobby') {
      final roomRaw = await db.get('rooms/${revised.roomId}');
      if (roomRaw is Map) target = RoomModel.fromMap(revised.roomId, roomRaw);
      if (revised.isActive && target == null)
        throw ArgumentError('Select an existing room');
      if (target != null && target.roomType != revised.roomType)
        throw ArgumentError('Room type does not match the selected room');
    }
    if (revised.isActive) {
      if (patient.status.toLowerCase() == 'discharged')
        throw StateError('Rejoin the patient before assigning a bed');
      final roomIds = {original.roomId, revised.roomId};
      for (final roomId in roomIds) {
        final roomRaw = await db.get('rooms/$roomId');
        if (roomRaw is! Map) continue;
        final room = RoomModel.fromMap(roomId, roomRaw);
        final beds = room.beds
            .map(
              (b) => b.currentStayId == stayId
                  ? b.copyWith(
                      status: 'available',
                      clearPatientId: true,
                      clearStayId: true,
                    )
                  : b,
            )
            .toList();
        if (roomId == revised.roomId && revised.roomType != 'lobby') {
          final index = beds.indexWhere((b) => b.id == revised.bedId);
          if (index < 0 || !beds[index].isAvailable)
            throw StateError('Selected bed is not available');
          if (room.status == 'maintenance' || room.status == 'unavailable')
            throw StateError('Selected room is not available');
          beds[index] = beds[index].copyWith(
            status: 'occupied',
            currentPatientId: patient.id,
            currentStayId: stayId,
          );
        }
        final attendants =
            room.currentAttendants -
            (roomId == original.roomId && room.isPrivate
                ? original.attendantCount
                : 0) +
            (roomId == revised.roomId && room.isPrivate
                ? revised.attendantCount
                : 0);
        if (attendants > room.maxAttendants)
          throw ArgumentError('Private room attendant capacity exceeded');
        final occupied = beds.where((b) => b.isOccupied).length;
        root.addAll({
          'rooms/$roomId/beds': {for (final b in beds) b.id: b.toMap()},
          'rooms/$roomId/occupiedBeds': occupied,
          'rooms/$roomId/currentAttendants': attendants.clamp(0, 999),
          'rooms/$roomId/status': room.status == 'maintenance'
              ? 'maintenance'
              : occupied == 0
              ? 'available'
              : 'occupied',
          'rooms/$roomId/updatedAt': DateTime.now().millisecondsSinceEpoch,
          'rooms/$roomId/expectedVacancyDate': end.millisecondsSinceEpoch,
        });
      }
    }
    final currentCycle = cycleId == StayBilling.currentCycle(patient);
    final latest = cycle.isNotEmpty && cycle.last.id == stayId;
    if (currentCycle) {
      patientData['registrationNumber'] = registration;
      patientData['fullName'] = revised.patientName;
      patientData['searchKey'] = revised.patientName.toLowerCase();
      patientData['billingAmountOverride'] = null;
      if (cycle.first.id == stayId)
        patientData['registrationDate'] =
            revised.admissionDate.millisecondsSinceEpoch;
      if (latest) {
        patientData.addAll({
          'fullName': revised.patientName,
          'searchKey': revised.patientName.toLowerCase(),
          'photoDataUrl': snapshot['photoDataUrl'],
          'attendants': snapshot['attendants'],
          'exitDate': end.millisecondsSinceEpoch,
          if (!revised.isActive) 'dischargeDate': end.millisecondsSinceEpoch,
        });
      }
      if (revised.isActive) {
        patientData.addAll({
          'roomId': revised.roomType == 'lobby' ? null : revised.roomId,
          'roomNumber': revised.roomType == 'lobby' ? null : revised.roomNumber,
          'lobby': revised.roomType == 'lobby' ? revised.roomNumber : null,
          'floor': target?.floor,
          'bedIds': [
            for (final s in updatedStays.where((s) => s.isActive))
              if (s.bedId != null) s.bedId,
          ],
          'bedLabels': [
            for (final s in updatedStays.where((s) => s.isActive))
              if (s.bedLabel != null) s.bedLabel,
          ],
        });
      }
      for (final key in [
        'registrationNumber',
        'billingAmountOverride',
        'registrationDate',
        'fullName',
        'searchKey',
        'photoDataUrl',
        'attendants',
        'exitDate',
        'dischargeDate',
        'roomId',
        'roomNumber',
        'lobby',
        'floor',
        'bedIds',
        'bedLabels',
      ]) {
        if (patientData[key] != patientRaw[key])
          root['patients/${patient.id}/$key'] = patientData[key];
      }
    }
    for (final entry in patches.entries) {
      final changed = StayModel.fromMap(entry.key, entry.value);
      entry.value['durationDays'] = PricingHelper.calculateStayDays(
        changed.admissionDate,
        changed.isActive
            ? changed.expectedDischargeDate
            : changed.completedAt ?? changed.updatedAt,
      );
      entry.value['expiryDate'] =
          changed.expectedDischargeDate.millisecondsSinceEpoch;
      entry.value['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      for (final field in entry.value.entries)
        root['stays/${entry.key}/${field.key}'] = field.value;
    }
    root.addAll(
      await paymentService.billingUpdates(
        patient.id,
        patientData: patientData,
        stays: updatedStays,
      ),
    );
    await db.patch('', root);
  }
}
