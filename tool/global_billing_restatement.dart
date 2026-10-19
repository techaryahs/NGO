import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/utils/pricing_helper.dart';
import 'package:ngo/utils/stay_billing.dart';

/// Only persistence mapping lives here. All charges, stay selection, overrides,
/// dates, payment-cycle attribution and refunds come from production StayBilling.
const patientFields = {
  'advanceBilledAmount',
  'attendanceCharges',
  'totalPaidAmount',
  'currentDueAmount',
  'refundDueAmount',
  'totalRefundDueAmount',
  'totalRefundedAmount',
  'paymentPending',
  'paymentStatus',
  'admissionBalances',
  'totalPresentDays',
  'totalAbsentDays',
};
const stayFields = {
  'totalCost',
  'billableDays',
  'billingSummary',
  'baseCost',
  'extraAttendantCost',
};
const summaryFields = {
  'cycleId',
  'total',
  'paid',
  'refunded',
  'netPaid',
  'due',
  'refundDue',
  'status',
  'segmentCharges',
  'segmentDays',
};

bool allowedPath(String path) {
  final parts = path.split('/');
  if (parts.length < 3 || parts.any((part) => part.isEmpty)) return false;
  if (parts.first == 'patients') {
    if (!patientFields.contains(parts[2])) return false;
    if (parts[2] != 'admissionBalances') return parts.length == 3;
    return parts.length >= 5 && summaryPath(parts.sublist(4));
  }
  if (parts.first != 'stays' || !stayFields.contains(parts[2])) return false;
  return parts[2] == 'billingSummary'
      ? summaryPath(parts.sublist(3))
      : parts.length == 3;
}

bool summaryPath(List<String> parts) =>
    parts.isNotEmpty &&
    summaryFields.contains(parts.first) &&
    ({'segmentCharges', 'segmentDays'}.contains(parts.first)
        ? parts.length == 2
        : parts.length == 1);

dynamic at(dynamic root, String path) {
  for (final part in path.split('/')) {
    if (root is! Map) return null;
    root = root[part];
  }
  return root;
}

bool equalValue(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys};
    return keys.every((key) => equalValue(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (index) => index,
        ).every((index) => equalValue(a[index], b[index]));
  }
  return a == b;
}

bool validDate(dynamic value) =>
    int.tryParse(value?.toString() ?? '') != null &&
    int.parse(value.toString()) > 0;
double number(dynamic value) => (value as num?)?.toDouble() ?? 0;
Map<String, dynamic> object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

Map<String, dynamic> restatementPlan(
  Map<String, dynamic> source,
  DateTime asOf,
) {
  final patients = object(source['patients']);
  final stays = object(source['stays']);
  final pricing = object(source['admin_settings/pricing']);
  final updates = <String, dynamic>{};
  final changes = <Map<String, dynamic>>[];
  final blocked = <Map<String, dynamic>>[];
  final records = <Map<String, dynamic>>[];
  final inventory = <String, int>{};
  final byPatient = <String, List<StayModel>>{};
  final evaluableStayIds = <String>{};
  final evaluableRecords = <String>{};
  final blockedStayIds = <String>{};
  var positive = 0.0;
  var negative = 0.0;
  var calculatedOld = 0.0;
  var calculatedNew = 0.0;
  var cyclesEvaluated = 0;

  void block(
    String collection,
    String id,
    String reason, {
    String? field,
    String? cycle,
  }) {
    blocked.add({
      'collection': collection,
      'id': id,
      if (field != null) 'field': field,
      if (cycle != null) 'cycleId': cycle,
      'reason': reason,
    });
  }

  void propose(String path, dynamic value) {
    if (!allowedPath(path)) throw StateError('Unsafe write path: $path');
    if (value is num && (!value.isFinite || value < 0)) {
      throw StateError('Invalid derived value: $path');
    }
    evaluableRecords.add(path.split('/').take(2).join('/'));
    final old = at(source, path);
    if (equalValue(old, value)) return;
    if (updates.containsKey(path)) throw StateError('Duplicate write: $path');
    updates[path] = value;
    changes.add({
      'path': path,
      'oldValue': old,
      'newValue': value,
      if (old is num && value is num) 'delta': value - old,
      'reason':
          'Production StayBilling calculation from source attendance, dates, pricing and immutable receipts',
    });
  }

  void summary(String path, AdmissionBalance balance, {bool financial = true}) {
    final values = balance.toMap();
    for (final entry in values.entries) {
      if (!financial &&
          !{
            'cycleId',
            'total',
            'segmentCharges',
            'segmentDays',
          }.contains(entry.key)) {
        continue;
      }
      if (entry.value is Map) {
        final previous = object(at(source, '$path/${entry.key}'));
        final current = object(entry.value);
        for (final key in {...previous.keys, ...current.keys}) {
          propose('$path/${entry.key}/$key', current[key]);
        }
      } else {
        propose('$path/${entry.key}', entry.value);
      }
    }
  }

  for (final collection in ['patients', 'stays']) {
    for (final entry in object(source[collection]).entries) {
      for (final field in object(entry.value).keys) {
        final key = '$collection/$field';
        inventory[key] = (inventory[key] ?? 0) + 1;
      }
    }
  }
  for (final entry in stays.entries) {
    final raw = object(entry.value);
    if (!patients.containsKey(raw['patientId'])) {
      block(
        'stays',
        entry.key,
        'Patient source record is missing; cannot resolve admission cycles or patient checkout context.',
      );
      blockedStayIds.add(entry.key);
      continue;
    }
    if (!validDate(raw['admissionDate']) ||
        !validDate(raw['createdAt']) ||
        !validDate(raw['updatedAt']) ||
        !{'active', 'completed', 'cancelled'}.contains(raw['status'])) {
      block(
        'stays',
        entry.key,
        'Missing/invalid admission, creation, update date or stay status.',
      );
      blockedStayIds.add(entry.key);
      continue;
    }
    if (!{'general', 'private', 'lobby'}.contains(raw['roomType'])) {
      block(
        'stays',
        entry.key,
        'Room type is missing or not supported by production pricing.',
      );
      blockedStayIds.add(entry.key);
      continue;
    }
    final stay = StayModel.fromMap(entry.key, raw);
    byPatient.putIfAbsent(stay.patientId, () => []).add(stay);
  }

  for (final entry in patients.entries) {
    final id = entry.key;
    final raw = object(entry.value);
    final segments = byPatient[id] ?? <StayModel>[];
    if (!validDate(raw['admissionDate']) ||
        (raw['registrationDate'] != null &&
            !validDate(raw['registrationDate'])) ||
        !{'active', 'discharged', 'transferred'}.contains(raw['status'])) {
      block(
        'patients',
        id,
        'Patient admission/registration date or status is missing/invalid.',
      );
      for (final stay in segments) {
        block(
          'stays',
          stay.id,
          'Patient admission/registration source is invalid.',
        );
        blockedStayIds.add(stay.id);
      }
      continue;
    }
    for (final key in ['exitDate', 'dischargeDate']) {
      if (raw[key] != null && !validDate(raw[key])) {
        throw StateError('Invalid explicit patient date: $id/$key');
      }
    }
    // Empty-cycle fallback may use a stored bill in the UI. It is prohibited
    // as a migration calculation input. Such cycles are explicitly blocked.
    final patient = PatientModel.fromMap(id, {
      ...raw,
      'advanceBilledAmount': 0.0,
      'attendanceCharges': 0.0,
    });
    final currentCycle = StayBilling.currentCycle(patient);
    final cycleBlocks = <String>{};
    final cycleSegments = <String, List<StayModel>>{};
    for (final stay in segments.where((stay) => stay.status != 'cancelled')) {
      final cycle = StayBilling.cycleFor(stay, patient);
      cycleSegments.putIfAbsent(cycle, () => []).add(stay);
      final checkout = stay.completedAt ?? stay.updatedAt;
      if (!stay.isActive && checkout.isBefore(stay.admissionDate)) {
        cycleBlocks.add(cycle);
        block(
          'stays',
          stay.id,
          'Production completedAt/updatedAt checkout fallback precedes admission.',
          cycle: cycle,
        );
      }
      for (final rate in [
        stay.dailyRate,
        stay.longStayDailyRate,
        stay.costOverride,
      ]) {
        if (rate != null && (!rate.isFinite || rate < 0)) {
          throw StateError('Invalid source price: ${stay.id}');
        }
      }
    }
    final hasCurrentStays = cycleSegments[currentCycle]?.isNotEmpty ?? false;
    if (!hasCurrentStays) {
      cycleBlocks.add(currentCycle);
      block(
        'patients',
        id,
        'Current admission has no stay source; legacy stored-bill fallback cannot establish a recalculated charge.',
        cycle: currentCycle,
      );
    }
    for (final stay in segments.where((stay) => stay.status == 'cancelled')) {
      block(
        'stays',
        stay.id,
        'Production engine excludes cancelled stays; no settlement policy for their stored estimates.',
      );
      blockedStayIds.add(stay.id);
    }
    // Stay records rejected before parsing can affect allocation within their
    // admission. Do not manufacture a cycle from invalid source data.
    final unparsed = stays.entries
        .where(
          (entry) =>
              object(entry.value)['patientId'] == id &&
              !segments.any((stay) => stay.id == entry.key),
        )
        .toList();
    if (unparsed.isNotEmpty) {
      for (final cycle in cycleSegments.keys) {
        cycleBlocks.add(cycle);
      }
      block(
        'patients',
        id,
        'A linked stay has invalid source data; cycle allocation cannot be established for affected linked stays.',
      );
    }
    final attendance = <String, String>{};
    for (final date in object(at(source, 'attendance/daily')).entries) {
      final record = object(object(date.value)[id]);
      if (record.isNotEmpty) {
        attendance[date.key] = record['status']?.toString() ?? '';
      }
    }
    final attendantAttendance = <String, Map<String, String>>{};
    for (final date in object(
      at(source, 'attendant_attendance/daily'),
    ).entries) {
      final daily = object(object(date.value)[id]);
      final statuses = <String, String>{};
      for (final value in daily.values) {
        final record = object(value);
        if (record['attendantName'] != null) {
          statuses[record['attendantName'].toString()] =
              record['status']?.toString() ?? '';
        }
      }
      if (statuses.isNotEmpty) attendantAttendance[date.key] = statuses;
    }
    final financial =
        raw['payments'] != null || number(raw['totalPaidAmount']) == 0;
    if (!financial) {
      block(
        'patients',
        id,
        'No embedded ledger; nonzero legacy totalPaidAmount has no independently readable receipt allocation.',
        field: 'payment-derived balances',
      );
    }
    final balances = StayBilling.calculate(
      patient: patient,
      stays: segments,
      pricing: pricing,
      attendance: attendance,
      attendantAttendance: attendantAttendance,
      now: asOf,
    );
    final assigned = <String>{};
    for (final balance in balances) {
      if (cycleBlocks.contains(balance.id)) {
        for (final stay in balance.stays) {
          blockedStayIds.add(stay.id);
          block(
            'stays',
            stay.id,
            'Another unresolved source in the same admission prevents deterministic segment allocation.',
            cycle: balance.id,
          );
        }
        continue;
      }
      if (!balance.total.isFinite || balance.total < 0) {
        throw StateError('Invalid total for $id/${balance.id}');
      }
      cyclesEvaluated++;
      summary(
        'patients/$id/admissionBalances/${balance.id}',
        balance,
        financial: financial,
      );
      for (final stay in balance.stays) {
        if (!assigned.add(stay.id)) {
          throw StateError('Duplicate stay aggregation: ${stay.id}');
        }
        evaluableStayIds.add(stay.id);
        final total = balance.charges[stay.id]!;
        final days = balance.days[stay.id]!;
        final stored = object(stays[stay.id]);
        calculatedOld += number(stored['totalCost']);
        calculatedNew += total;
        final delta = total - number(stored['totalCost']);
        if (delta > 0) positive += delta;
        if (delta < 0) negative += delta;
        propose('stays/${stay.id}/totalCost', total);
        propose('stays/${stay.id}/billableDays', days);
        summary(
          'stays/${stay.id}/billingSummary',
          balance,
          financial: financial,
        );
        // RoomService's existing schema puts every general/lobby occupant
        // charge in baseCost. Private room extras are a separate component.
        // Overrides and private long-stay allocations lack a component policy.
        final componentAmbiguous =
            stay.costOverride != null ||
            (stay.dailyRateIsManual && stay.dailyRate != null) ||
            (stay.roomType == 'private' &&
                balance.days.values.fold<int>(0, (a, b) => a + b) > 60);
        if (componentAmbiguous) {
          for (final field in ['baseCost', 'extraAttendantCost']) {
            if (stored.containsKey(field)) {
              block(
                'stays',
                stay.id,
                'Production engine defines the total but no component allocation for manual/cost overrides or private long-stay charges.',
                field: field,
              );
            }
          }
        } else {
          final base = stay.roomType == 'private'
              ? PricingHelper.calculateDailyCharge(true, 0, pricing: pricing) *
                    days
              : total;
          final extra = total - base;
          if (extra < -0.000001) {
            throw StateError('Invalid component decomposition: ${stay.id}');
          }
          if (stored.containsKey('baseCost')) {
            propose('stays/${stay.id}/baseCost', base);
          }
          if (stored.containsKey('extraAttendantCost')) {
            propose(
              'stays/${stay.id}/extraAttendantCost',
              extra.abs() < 0.000001 ? 0.0 : extra,
            );
          }
        }
        for (final field in ['paidAmount', 'pendingAmount']) {
          if (stored.containsKey(field)) {
            block(
              'stays',
              stay.id,
              'Stay completion accepts these values directly; production admission ledger has no per-stay allocation policy. Preserve the settlement input.',
              field: field,
            );
          }
        }
      }
    }
    final current = balances.firstWhere(
      (balance) => balance.id == currentCycle,
    );
    if (!cycleBlocks.contains(currentCycle)) {
      propose('patients/$id/advanceBilledAmount', current.total);
      propose('patients/$id/attendanceCharges', 0.0);
      if (financial) {
        propose('patients/$id/totalPaidAmount', current.netPaid);
        propose('patients/$id/currentDueAmount', current.due);
        propose('patients/$id/refundDueAmount', current.refundDue);
        propose('patients/$id/paymentPending', current.due > 0);
        propose('patients/$id/paymentStatus', current.status);
      }
    }
    if (cycleBlocks.isEmpty && financial) {
      propose(
        'patients/$id/totalRefundDueAmount',
        balances.fold<double>(0, (sum, balance) => sum + balance.refundDue),
      );
      propose(
        'patients/$id/totalRefundedAmount',
        balances.fold<double>(0, (sum, balance) => sum + balance.refunded),
      );
    }
    final range = StayBilling.attendanceDateRange(patient, now: asOf);
    final cycleAttendance = attendance.entries.where(
      (entry) =>
          entry.key.compareTo(range.start) >= 0 &&
          entry.key.compareTo(range.end) <= 0,
    );
    propose(
      'patients/$id/totalPresentDays',
      cycleAttendance.where((entry) => entry.value == 'Present').length,
    );
    propose(
      'patients/$id/totalAbsentDays',
      cycleAttendance.where((entry) => entry.value == 'Absent').length,
    );
  }

  final changedRecordPaths = updates.keys
      .map((path) => path.split('/').take(2).join('/'))
      .toSet();
  final blockedRecordPaths = blocked
      .map((record) => '${record['collection']}/${record['id']}')
      .toSet();
  final fieldChanges = <String, int>{};
  for (final path in updates.keys) {
    final parts = path.split('/');
    final key = '${parts.first}/${parts[2]}';
    fieldChanges[key] = (fieldChanges[key] ?? 0) + 1;
  }
  for (final collection in ['patients', 'stays']) {
    for (final id in object(source[collection]).keys) {
      final path = '$collection/$id';
      final supported = evaluableRecords.contains(path);
      records.add({
        'path': path,
        'changed': changedRecordPaths.contains(path),
        'eligibility': supported
            ? (blockedRecordPaths.contains(path) ? 'partial' : 'eligible')
            : 'blocked',
        'changes': changes
            .where((change) => (change['path'] as String).startsWith('$path/'))
            .toList(),
      });
    }
  }
  final oldAll = stays.values.fold<double>(
    0,
    (sum, raw) => sum + number(object(raw)['totalCost']),
  );
  return {
    'asOf': asOf.toIso8601String(),
    'engine': 'lib/utils/stay_billing.dart: StayBilling.calculate',
    'summary': {
      'patientsScanned': patients.length,
      'staysScanned': stays.length,
      'activeStays': stays.values
          .where((raw) => object(raw)['status'] == 'active')
          .length,
      'historicalCompletedStays': stays.values
          .where((raw) => object(raw)['status'] == 'completed')
          .length,
      'multipleStayPatients': byPatient.values
          .where((list) => list.length > 1)
          .length,
      'cyclesEvaluated': cyclesEvaluated,
      'automaticallyEvaluatedRecords': records
          .where((record) => record['eligibility'] != 'blocked')
          .length,
      'fullyBlockedRecords': records
          .where((record) => record['eligibility'] == 'blocked')
          .length,
      'recordsWithBlockedScopes': blockedRecordPaths.length,
      'partiallyEligibleRecords': records
          .where((record) => record['eligibility'] == 'partial')
          .length,
      'changedRecords': changedRecordPaths.length,
      'unchangedEvaluableRecords': records
          .where(
            (record) =>
                record['eligibility'] != 'blocked' &&
                record['changed'] == false,
          )
          .length,
      'oldAggregateBilledAmount': oldAll,
      'newAggregateBilledAmount': oldAll + calculatedNew - calculatedOld,
      'calculatedStayOldAmount': calculatedOld,
      'calculatedStayNewAmount': calculatedNew,
      'blockedStayStoredAmount': oldAll - calculatedOld,
      'positiveAggregateDelta': positive,
      'negativeAggregateDelta': negative,
      'aggregateBasis':
          'All stay totalCost fields, counted once; blocked stays retain their old stored amount. Patient rollups are not counted twice.',
      'changedFields': updates.length,
      'fieldChangeCounts': fieldChanges,
    },
    'fieldClassification': {
      'patientDerivedAllowlist': patientFields.toList()..sort(),
      'stayDerivedAllowlist': stayFields.toList()..sort(),
      'protected': [
        'all payment/receipt/refund records',
        'all attendance',
        'all identity and source dates',
        'room/bed assignments',
        'patientSnapshot',
        'cycleId outside derived summaries',
        'updatedAt',
        'dailyRate',
        'dailyRateIsManual',
        'longStayDailyRate',
        'costOverride',
        'billingAmountOverride',
        'all other fields not explicitly allowlisted',
      ],
      'deferred': [
        'ambiguous stay component allocations',
        'stay paidAmount/pendingAmount completion inputs',
      ],
    },
    'fieldInventory': inventory,
    'records': records,
    'blocked': blocked,
    'updates': updates,
    'journal': changes,
    'safety': {
      'unsafePaths': updates.keys.where((path) => !allowedPath(path)).toList(),
      'calculatedStayIds': evaluableStayIds.toList()..sort(),
      'blockedStayIds': blockedStayIds.toList()..sort(),
      'derivedBillingInputsExcluded': [
        'advanceBilledAmount',
        'attendanceCharges',
      ],
      'productionUpdatedAtFallback': true,
      'frozenAsOf': true,
    },
  };
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError(
      'Usage: dart run tool/global_billing_restatement.dart SNAPSHOT OUTPUT',
    );
  }
  final source = object(jsonDecode(File(arguments[0]).readAsStringSync()));
  final asOf = DateTime.parse(
    source['calculationAsOf']?.toString() ?? source['capturedAt'].toString(),
  ).toLocal();
  final report = restatementPlan(source, asOf);
  report['engineSha256'] = {
    for (final path in [
      'lib/utils/stay_billing.dart',
      'lib/utils/pricing_helper.dart',
      'lib/models/patient_model.dart',
      'lib/models/stay_model.dart',
      'tool/global_billing_restatement.dart',
    ])
      path: sha256.convert(File(path).readAsBytesSync()).toString(),
  };
  final output = File(arguments[1]);
  if (output.existsSync()) {
    throw StateError('Report already exists; refusing to replace it');
  }
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  stdout.writeln(jsonEncode(report['summary']));
}
