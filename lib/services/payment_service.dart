import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/patient_model.dart';
import '../models/stay_model.dart';
import '../utils/stay_billing.dart';
import '../utils/pricing_helper.dart';
import 'backend_api_service.dart';
import 'firebase_rtdb_rest_service.dart';
import 'service_locator.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../utils/upi_payment.dart';

class PaymentReferenceException extends StateError {
  PaymentReferenceException()
    : super(
        'This reference is already recorded for an earlier payment. '
        'Enter the new transfer\'s UTR / UPI reference. '
        'No additional payment was recorded.',
      );
  @override
  String toString() => message;
}

class PaymentService {
  final FirebaseRTDBRestService? _injectedRtdb;
  final BackendApiService? _injectedBackendApi;
  final String _path = 'payments';

  // ── Debounced background billing ───────────────────────────────────────────
  // Rapid attendance clicks are coalesced into one recalculation that runs
  // after the writes have landed, so a checkbox never blocks on the billing
  // waterfall and duplicate recalculation passes are avoided.
  final Map<String, Timer> _scheduledBilling = {};
  final Map<String, Future<void>> _runningBilling = {};
  final Map<String, List<Completer<void>>> _scheduledCompleters = {};
  int _schedulerGeneration = 0;

  PaymentService([FirebaseRTDBRestService? rtdb, BackendApiService? backendApi])
    : _injectedRtdb = rtdb,
      _injectedBackendApi = backendApi;

  BackendApiService? get _backendApi {
    if (_injectedBackendApi != null) return _injectedBackendApi;
    if (_injectedRtdb != null) return null;
    try {
      return ServiceLocator().backendApiService;
    } catch (_) {
      return null;
    }
  }

  bool get isPostgres => _backendApi != null || _injectedRtdb == null;

  FirebaseRTDBRestService get _safeRtdb {
    if (_injectedRtdb != null) return _injectedRtdb;
    return ServiceLocator().rtdbService;
  }

  /// Schedules a debounced billing recalculation for one patient.
  ///
  /// The returned future completes when the recalculation finishes (or
  /// fails). Callers that do not care may ignore it, but MUST attach an error
  /// handler when using `unawaited`.
  /// Explicit saves use [immediate] after their complete attendance batch has
  /// been acknowledged; background changes retain the debounce.
  Future<void> schedulePatientBilling(
    String patientId, {
    bool immediate = false,
  }) {
    _scheduledBilling[patientId]?.cancel();
    final completer = Completer<void>();
    final generation = _schedulerGeneration;
    _scheduledCompleters.putIfAbsent(patientId, () => []).add(completer);
    _scheduledBilling[patientId] = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 1200),
      () async {
        _scheduledBilling.remove(patientId);
        final completers =
            _scheduledCompleters.remove(patientId) ?? <Completer<void>>[];
        final running = _runningBilling[patientId];
        if (running != null) {
          try {
            await running;
          } catch (_) {
            // A previously failed pass must not block the fresh one.
          }
        }
        if (generation != _schedulerGeneration) {
          for (final pending in completers) {
            if (!pending.isCompleted) pending.complete();
          }
          return;
        }
        final task = recalculatePatientAttendanceAndBilling(patientId);
        _runningBilling[patientId] = task;
        try {
          await task;
          for (final pending in completers) {
            if (!pending.isCompleted) pending.complete();
          }
        } catch (e, s) {
          for (final pending in completers) {
            if (!pending.isCompleted) pending.completeError(e, s);
          }
        } finally {
          if (identical(_runningBilling[patientId], task)) {
            _runningBilling.remove(patientId);
          }
        }
      },
    );
    return completer.future;
  }

  /// Cancels any pending scheduled recalculation for a patient.
  void cancelScheduledBilling(String patientId) {
    _scheduledBilling.remove(patientId)?.cancel();
    final completers =
        _scheduledCompleters.remove(patientId) ?? <Completer<void>>[];
    for (final completer in completers) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  void disposeScheduler() {
    _schedulerGeneration++;
    for (final timer in _scheduledBilling.values) {
      timer.cancel();
    }
    _scheduledBilling.clear();
    for (final completers in _scheduledCompleters.values) {
      for (final completer in completers) {
        if (!completer.isCompleted) completer.complete();
      }
    }
    _scheduledCompleters.clear();
  }

  Future<List<StayModel>> loadStays(String patientId) async {
    if (isPostgres) {
      final dynamic data = await _backendApi!.get(
        'stays?patientId=$patientId&format=map',
      );
      return [
        if (data is Map)
          for (final entry in data.entries)
            if (entry.value is Map && entry.value['patientId'] == patientId)
              StayModel.fromMap(entry.key.toString(), entry.value),
      ];
    }
    final data = await _safeRtdb.getByChildValue(
      'stays',
      child: 'patientId',
      value: patientId,
    );
    return [
      if (data is Map)
        for (final entry in data.entries)
          if (entry.value is Map && entry.value['patientId'] == patientId)
            StayModel.fromMap(entry.key.toString(), entry.value),
    ];
  }

  /// Uses the existing invoice projection; never reads an earlier receipt's UTR.
  Future<({double total, double paid, double due, String? cycleId})>
  collectionBalance(String patientId) async {
    final values = await billingUpdates(patientId);
    final reconciliation =
        values['patients/$patientId/financialReconciliation'];
    final admission = values['patients/$patientId/admissionDate'];
    final balances = values['patients/$patientId/admissionBalances'];
    final cycleBalance = balances is Map
        ? balances[admission?.toString()]
        : null;
    if (reconciliation is Map &&
        (cycleBalance is Map &&
                cycleBalance.containsKey('reconciliationRequired')
            ? cycleBalance['reconciliationRequired'] == true
            : reconciliation['required'] == true)) {
      final patient = PatientModel.fromMap(patientId, {
        for (final entry in values.entries)
          if (entry.key.startsWith('patients/$patientId/'))
            entry.key.substring('patients/$patientId/'.length): entry.value,
      });
      throw StateError(patient.financialReviewReasons.join('\n'));
    }
    double amount(String field) =>
        (values['patients/$patientId/$field'] as num?)?.toDouble() ?? 0;
    return (
      total: amount('advanceBilledAmount') + amount('attendanceCharges'),
      paid: amount('totalPaidAmount'),
      due: amount('currentDueAmount'),
      cycleId: admission?.toString(),
    );
  }

  Future<Map<String, dynamic>> billingUpdates(
    String patientId, {
    Map<String, dynamic>? patientData,
    List<StayModel>? stays,
    DateTime? checkoutAt,
    Map<String, String?> patientAttendanceOverrides = const {},
    Map<String, Map<String, String?>> attendantAttendanceOverrides = const {},
  }) async {
    if (isPostgres &&
        patientData == null &&
        patientAttendanceOverrides.isEmpty &&
        attendantAttendanceOverrides.isEmpty) {
      final snapshot = await _backendApi!.financialSnapshot(
        patientId,
        checkoutAt: checkoutAt,
      );
      final patient = Map<String, dynamic>.from(snapshot['patient'] as Map);
      if (snapshot['reconciliation'] is Map &&
          patient['financialReconciliation'] == null) {
        patient['financialReconciliation'] = snapshot['reconciliation'];
      }
      return {
        'financialSnapshot/stays': snapshot['stays'],
        for (final entry in patient.entries)
          'patients/$patientId/${entry.key}': entry.value,
      };
    }
    final raw =
        patientData ??
        (isPostgres
            ? await _backendApi!.get('patients/$patientId')
            : await _safeRtdb.get('patients/$patientId'));
    if (raw is! Map) throw StateError('Patient not found');
    final patient = PatientModel.fromMap(patientId, raw);
    stays ??= await loadStays(patientId);
    // Older admissions saved their initial patient + attendant estimate as a
    // fixed daily rate. That prevents later attendance marks from reducing
    // the bill. Recognize only that generated value and migrate it back to a
    // dynamic rate; manually edited rates remain untouched.
    final migratedDynamicRateIds = <String>{};
    stays = stays.map((stay) {
      final isGeneratedRate =
          stay.costOverride == null &&
          !stay.dailyRateIsManual &&
          stay.dailyRate != null;
      if (!isGeneratedRate) return stay;
      migratedDynamicRateIds.add(stay.id);
      final data = stay.toMap()..['dailyRate'] = null;
      return StayModel.fromMap(stay.id, data);
    }).toList();
    final patientRange = StayBilling.attendanceDateRange(patient);
    final rangeStarts = <DateTime>[
      DateTime.parse(patientRange.start),
      ...stays.map((stay) => stay.admissionDate),
    ];
    final rangeEnds = <DateTime>[
      DateTime.parse(patientRange.end),
      ...stays.map((stay) => stay.completedAt ?? stay.expectedDischargeDate),
    ];
    rangeStarts.sort();
    rangeEnds.sort();
    final startKey = StayBilling.dateKey(rangeStarts.first);
    final endKey = StayBilling.dateKey(rangeEnds.last);
    final reads = await Future.wait<dynamic>([
      isPostgres
          ? _backendApi!.getSettingsCategory('pricing')
          : _safeRtdb.get('admin_settings/pricing'),
      isPostgres
          ? _backendApi!.getAttendanceRange(
              kind: 'attendance',
              startKey: startKey,
              endKey: endKey,
              patientId: patientId,
              allowCacheFallback: false,
            )
          : _safeRtdb.getByKeyRange(
              'attendance/daily',
              startKey: startKey,
              endKey: endKey,
            ),
      isPostgres
          ? _backendApi!.getAttendanceRange(
              kind: 'attendant_attendance',
              startKey: startKey,
              endKey: endKey,
              patientId: patientId,
              allowCacheFallback: false,
            )
          : _safeRtdb.getByKeyRange(
              'attendant_attendance/daily',
              startKey: startKey,
              endKey: endKey,
            ),
    ]);
    final rawPricing = reads[0];
    final pricing = PricingHelper.approvedPricing(
      rawPricing is Map
          ? Map<String, dynamic>.from(rawPricing)
          : <String, dynamic>{},
    );
    final records = reads[1];
    final attendance = <String, String>{};
    if (records is Map) {
      for (final entry in records.entries) {
        if (entry.value is Map && entry.value[patientId] is Map) {
          attendance[entry.key.toString()] =
              entry.value[patientId]['status']?.toString() ?? '';
        }
      }
    }
    for (final entry in patientAttendanceOverrides.entries) {
      if (entry.value == null) {
        attendance.remove(entry.key);
      } else {
        attendance[entry.key] = entry.value!;
      }
    }
    final attendantRecords = reads[2];
    final attendantAttendance = <String, Map<String, String>>{};
    if (attendantRecords is Map) {
      for (final dateEntry in attendantRecords.entries) {
        final daily = dateEntry.value;
        if (daily is! Map || daily[patientId] is! Map) continue;
        final statuses = <String, String>{};
        for (final entry in (daily[patientId] as Map).entries) {
          final record = entry.value;
          if (record is Map && record['attendantName'] != null) {
            statuses[(record['attendantId'] ?? entry.key).toString()] =
                record['status']?.toString() ?? '';
          }
        }
        attendantAttendance[dateEntry.key.toString()] = statuses;
      }
    }
    for (final dateEntry in attendantAttendanceOverrides.entries) {
      final statuses = attendantAttendance.putIfAbsent(
        dateEntry.key,
        () => <String, String>{},
      );
      for (final entry in dateEntry.value.entries) {
        if (entry.value == null) {
          statuses.remove(entry.key);
        } else {
          statuses[entry.key] = entry.value!;
        }
      }
    }
    final balances = StayBilling.calculate(
      calendarDayBilling: isPostgres,
      patient: patient,
      stays: stays,
      pricing: pricing,
      attendance: attendance,
      attendantAttendance: attendantAttendance,
    );
    final current = balances.firstWhere(
      (b) => b.id == StayBilling.currentCycle(patient),
    );
    final start = DateTime.parse(patientRange.start);
    final end = DateTime.parse(patientRange.end);
    final cycleAttendance = attendance.entries.where((entry) {
      final date = DateTime.tryParse(entry.key);
      return date != null && !date.isBefore(start) && !date.isAfter(end);
    });
    final updates = <String, dynamic>{
      'patients/$patientId/advanceBilledAmount': current.total,
      'patients/$patientId/attendanceCharges': 0.0,
      // Stay charges are the source of truth once an admission has segments.
      // Remove old admission-form estimates that would otherwise freeze the
      // total after dates or attendant attendance change.
      if (stays.isNotEmpty) 'patients/$patientId/billingAmountOverride': null,
      'patients/$patientId/totalPaidAmount': current.netPaid,
      'patients/$patientId/currentDueAmount': current.due,
      'patients/$patientId/refundDueAmount': current.refundDue,
      'patients/$patientId/totalRefundDueAmount': balances.fold<double>(
        0,
        (sum, b) => sum + b.refundDue,
      ),
      'patients/$patientId/totalRefundedAmount': balances.fold<double>(
        0,
        (sum, b) => sum + b.refunded,
      ),
      'patients/$patientId/paymentPending': current.due > 0,
      'patients/$patientId/paymentStatus': current.status,
      'patients/$patientId/admissionBalances': {
        for (final b in balances) b.id: b.toMap(),
      },
      'patients/$patientId/totalPresentDays': cycleAttendance
          .where((e) => e.value == 'Present')
          .length,
      'patients/$patientId/totalAbsentDays': cycleAttendance
          .where((e) => e.value == 'Absent')
          .length,
      'patients/$patientId/updatedAt': DateTime.now().millisecondsSinceEpoch,
      for (final stayId in migratedDynamicRateIds)
        'stays/$stayId/dailyRate': null,
      // Note: the legacy ₹150 → ₹200 pricing migration is applied in-memory
      // (above) for the calculation. The persisted value is updated by an
      // admin through Pricing Settings — writing admin_settings from a staff
      // billing pass would be rejected by the security rules.
    };
    for (final balance in balances) {
      for (final stay in balance.stays) {
        updates.addAll({
          if (stay.patientSnapshot.isEmpty &&
              balance.id == StayBilling.currentCycle(patient))
            'stays/${stay.id}/patientSnapshot': {
              'registrationNumber': patient.registrationNumber,
              'photoRef': patient.photoRef,
              'attendants': patient.attendants
                  ?.map((a) => a.toMap()..remove('photoDataUrl'))
                  .toList(),
              'admissionDate': patient.admissionDate.millisecondsSinceEpoch,
            },
          'stays/${stay.id}/cycleId': balance.id,
          'stays/${stay.id}/totalCost': balance.charges[stay.id],
          'stays/${stay.id}/billableDays': balance.days[stay.id],
          'stays/${stay.id}/billingSummary': {
            ...stay.billingSummary,
            ...balance.toMap(),
            'pricing': stay.billingSummary['pricing'] ?? pricing,
          },
          if (!stay.isActive)
            'stays/${stay.id}/completedAt':
                (stay.completedAt ?? stay.updatedAt).millisecondsSinceEpoch,
        });
      }
    }
    return updates;
  }

  /// Legacy/offline quote uses the same attendance engine as its final bill.
  /// PostgreSQL quotes are supplied directly by the server's invoice engine.
  Future<double> quoteLegacyStayExtension(
    StayModel stay,
    int additionalDays,
  ) async {
    if (additionalDays < 1 || additionalDays > 3650) {
      throw ArgumentError('Extension days must be between 1 and 3650');
    }
    final raw = await _safeRtdb.get('patients/${stay.patientId}');
    if (raw is! Map) throw StateError('Patient not found');
    final data = Map<String, dynamic>.from(raw);
    final patient = PatientModel.fromMap(stay.patientId, data);
    if (!stay.isActive || patient.status.toLowerCase() == 'discharged') {
      throw StateError('Only active stays can be extended');
    }
    final stays = await loadStays(stay.patientId);
    final before = await billingUpdates(
      stay.patientId,
      patientData: data,
      stays: stays,
    );
    final afterData = {
      ...data,
      if (patient.exitDate != null)
        'exitDate': patient.exitDate!
            .add(Duration(days: additionalDays))
            .millisecondsSinceEpoch,
    };
    final afterStays = stays
        .map(
          (segment) => segment.id != stay.id
              ? segment
              : StayModel.fromMap(segment.id, {
                  ...segment.toMap(),
                  'expectedDischargeDate': segment.expectedDischargeDate
                      .add(Duration(days: additionalDays))
                      .millisecondsSinceEpoch,
                }),
        )
        .toList();
    final after = await billingUpdates(
      stay.patientId,
      patientData: afterData,
      stays: afterStays,
    );
    final key = 'patients/${stay.patientId}/advanceBilledAmount';
    return (((after[key] as num).toDouble() - (before[key] as num).toDouble()) *
                100)
            .round() /
        100;
  }

  Future<void> recalculatePatientAttendanceAndBilling(
    String patientId, {
    bool updateBilling = true,
    Map<String, String?> patientAttendanceOverrides = const {},
    Map<String, Map<String, String?>> attendantAttendanceOverrides = const {},
  }) {
    final running = _runningBilling[patientId];
    if (running != null &&
        patientAttendanceOverrides.isEmpty &&
        attendantAttendanceOverrides.isEmpty) {
      return running;
    }
    late final Future<void> task;
    task =
        () async {
          if (running != null) {
            try {
              await running;
            } catch (_) {
              /* Allow a fresh pass after failure. */
            }
          }
          await _recalculatePatientAttendanceAndBilling(
            patientId,
            updateBilling: updateBilling,
            patientAttendanceOverrides: patientAttendanceOverrides,
            attendantAttendanceOverrides: attendantAttendanceOverrides,
          );
        }().whenComplete(() {
          if (identical(_runningBilling[patientId], task)) {
            _runningBilling.remove(patientId);
          }
        });
    _runningBilling[patientId] = task;
    return task;
  }

  Future<void> _recalculatePatientAttendanceAndBilling(
    String patientId, {
    bool updateBilling = true,
    Map<String, String?> patientAttendanceOverrides = const {},
    Map<String, Map<String, String?>> attendantAttendanceOverrides = const {},
    bool waitForPaymentSubmission = true,
    int conflictRetries = 1,
  }) async {
    if (!updateBilling) return;
    final paymentSubmission = _paymentSubmissions[patientId];
    if (waitForPaymentSubmission && paymentSubmission != null) {
      try {
        await paymentSubmission;
      } catch (_) {
        /* Recalculate after a failed receipt too. */
      }
    }
    if (isPostgres) {
      // Attendance has already been acknowledged before billing is scheduled.
      // The server reads charges and receipts under the patient's lock.
      await _backendApi!.recalculateBilling(patientId);
      return;
    }
    final snapshots = await Future.wait<dynamic>([
      isPostgres
          ? _backendApi!.get('patients/$patientId', allowCacheFallback: false)
          : _safeRtdb.get('patients/$patientId'),
      isPostgres
          ? _backendApi!.get(
              'stays?patientId=$patientId&format=map',
              allowCacheFallback: false,
            )
          : _safeRtdb.getByChildValue(
              'stays',
              child: 'patientId',
              value: patientId,
            ),
    ]);
    if (snapshots[0] is! Map) throw StateError('Patient not found');
    final patientData = Map<String, dynamic>.from(snapshots[0] as Map);
    final stayData = snapshots[1] is Map ? snapshots[1] as Map : const {};
    final updates = await billingUpdates(
      patientId,
      patientData: patientData,
      stays: [
        for (final entry in stayData.entries)
          if (entry.value is Map)
            StayModel.fromMap(entry.key.toString(), entry.value),
      ],
      patientAttendanceOverrides: patientAttendanceOverrides,
      attendantAttendanceOverrides: attendantAttendanceOverrides,
    );
    updates.removeWhere((path, value) {
      if (path.endsWith('/updatedAt')) return true;
      final parts = path.split('/');
      dynamic previous = parts.first == 'patients'
          ? patientData
          : stayData[parts[1]];
      for (final key in parts.skip(2)) {
        previous = previous is Map ? previous[key] : null;
      }
      return valuesEqual(previous, value);
    });
    if (updates.isNotEmpty) {
      if (isPostgres) {
        try {
          await _applyBillingUpdatesToPostgres(
            patientId,
            updates,
            expectedVersion: (patientData['version'] as num?)?.toInt(),
          );
        } on BackendApiException catch (error) {
          if (error.statusCode != 409 || conflictRetries == 0) rethrow;
          // Rebuild from a fresh server snapshot; never attach a newer version
          // to amounts calculated before another financial mutation.
          await _recalculatePatientAttendanceAndBilling(
            patientId,
            updateBilling: updateBilling,
            patientAttendanceOverrides: patientAttendanceOverrides,
            attendantAttendanceOverrides: attendantAttendanceOverrides,
            waitForPaymentSubmission: waitForPaymentSubmission,
            conflictRetries: conflictRetries - 1,
          );
        }
      } else {
        await _safeRtdb.patch('', updates);
      }
    }
  }

  Future<void> _reconcileAcknowledgedPayment(String patientId) async {
    try {
      // The backend committed the receipt and resulting balances together.
      // Refresh that acknowledged state; do not restate historical invoices.
      await _backendApi!.refresh('patients/$patientId');
      await _backendApi!.refresh('stays?patientId=$patientId&format=map');
    } catch (_) {
      // A reconciliation failure must not invite a duplicate ledger write.
      // Publish authoritative server balances if the targeted read succeeds.
      try {
        await _backendApi!.refresh('patients/$patientId');
      } catch (_) {}
      debugPrint('[PaymentService] Receipt saved; billing refresh needs retry');
    }
  }

  Future<void> _applyBillingUpdatesToPostgres(
    String patientId,
    Map<String, dynamic> updates, {
    required int? expectedVersion,
  }) async {
    final api = _backendApi;
    if (api == null || updates.isEmpty) return;
    final patientUpdates = <String, dynamic>{};
    final stayUpdates = <String, Map<String, dynamic>>{};

    for (final entry in updates.entries) {
      final parts = entry.key.split('/');
      if (parts.length == 3 &&
          parts[0] == 'patients' &&
          parts[1] == patientId) {
        final field = parts[2];
        if (field != 'updatedAt' && field != 'payments') {
          patientUpdates[field] = entry.value;
        }
      } else if (parts.length == 3 && parts[0] == 'stays') {
        final stayId = parts[1];
        final field = parts[2];
        if (field != 'updatedAt' && field != 'patientSnapshot') {
          stayUpdates.putIfAbsent(stayId, () => <String, dynamic>{})[field] =
              entry.value;
        }
      }
    }

    if (patientUpdates.isNotEmpty || stayUpdates.isNotEmpty) {
      // Protect the financial calculation with the version of the patient
      // snapshot it used. A newer payment must reject this stale update.
      if (expectedVersion != null) {
        patientUpdates['expectedVersion'] = expectedVersion;
      }
      if (stayUpdates.isNotEmpty) {
        patientUpdates['stayBillingUpdates'] = stayUpdates;
      }
      await api.updatePatient(patientId, patientUpdates);
    }
    for (final stayId in stayUpdates.keys) {
      try {
        await api.refresh('stays/$stayId');
      } catch (_) {
        debugPrint('[PaymentService] Billing saved; stay refresh needs retry');
      }
    }
  }

  static bool valuesEqual(dynamic a, dynamic b) {
    // Firebase omits empty collections and null fields; legacy arrays may
    // also be returned as objects once a keyed receipt is appended.
    if (a is List) {
      a = <String, dynamic>{
        for (final entry in a.asMap().entries)
          entry.key.toString(): entry.value,
      };
    }
    if (b is List) {
      b = <String, dynamic>{
        for (final entry in b.asMap().entries)
          entry.key.toString(): entry.value,
      };
    }
    if (a == null && b is Map) {
      return b.values.every((value) => valuesEqual(null, value));
    }
    if (b == null && a is Map) {
      return a.values.every((value) => valuesEqual(value, null));
    }
    if (a is Map && b is Map) {
      final keys = {...a.keys, ...b.keys};
      return keys.every((key) => valuesEqual(a[key], b[key]));
    }
    return a == b;
  }

  Future<void> recalculateAllActivePatientsBilling({String? patientId}) async {
    if (patientId != null) {
      return recalculatePatientAttendanceAndBilling(patientId);
    }
    final patients = isPostgres
        ? await _backendApi!.get('patients')
        : await _safeRtdb.get('patients');
    if (patients is Map) {
      for (final entry in patients.entries) {
        if (entry.value is Map) {
          await recalculatePatientAttendanceAndBilling(entry.key.toString());
        }
      }
    }
  }

  Future<void> recalculateAllPatientsAttendanceAndBilling() =>
      recalculateAllActivePatientsBilling();
  Future<void> updatePatientBillingFromAttendance({
    required String patientId,
    required DateTime dateMarked,
    required bool isPresent,
    required bool? wasPresent,
  }) => recalculatePatientAttendanceAndBilling(patientId);
  final Map<String, Future<String>> _paymentSubmissions = {};

  Future<String> recordPayment({
    required String patientId,
    required String patientName,
    required PaymentModel payment,
    bool collectOutstanding = false,
  }) {
    final running = _paymentSubmissions[patientId];
    if (running != null) {
      return Future.error(StateError('A payment is already being recorded.'));
    }
    final billing = _runningBilling[patientId];
    final requestId =
        'payreq_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    late final Future<String> task;
    task =
        (() async {
          if (billing != null) {
            try {
              await billing;
            } catch (_) {
              /* The receipt recalculates billing. */
            }
          }
          debugPrint('[Payment] requestId=$requestId phase=validating');
          try {
            final id = await _recordPayment(
              patientId: patientId,
              patientName: patientName,
              payment: payment,
              collectOutstanding: collectOutstanding,
              requestId: requestId,
            );
            debugPrint('[Payment] requestId=$requestId phase=acknowledged');
            return id;
          } catch (error) {
            final category = error is PaymentReferenceException
                ? 'reference_reuse'
                : error is BackendApiException
                ? 'http_error'
                : error is TimeoutException
                ? 'timeout'
                : error is ArgumentError
                ? 'validation'
                : 'client_error';
            final status = error is BackendApiException
                ? error.statusCode.toString()
                : 'none';
            final returnedId = error is BackendApiException
                ? error.requestId
                : null;
            final serverId =
                returnedId != null &&
                    RegExp(
                      r'^(payreq_[A-Za-z0-9_-]{1,80}|[0-9a-fA-F-]{36})$',
                    ).hasMatch(returnedId)
                ? returnedId
                : requestId;
            debugPrint(
              '[Payment] requestId=$serverId phase=failed category=$category status=$status',
            );
            rethrow;
          }
        })().whenComplete(() {
          if (identical(_paymentSubmissions[patientId], task)) {
            _paymentSubmissions.remove(patientId);
          }
        });
    _paymentSubmissions[patientId] = task;
    return task;
  }

  Future<String> _recordPayment({
    required String patientId,
    required String patientName,
    required PaymentModel payment,
    required bool collectOutstanding,
    required String requestId,
  }) async {
    if (!payment.amount.isFinite || payment.amount <= 0) {
      throw ArgumentError('Enter a positive payment amount');
    }
    final raw = isPostgres
        ? await _backendApi!.refresh('patients/$patientId')
        : await _safeRtdb.get('patients/$patientId');
    if (raw is! Map) throw StateError('Patient not found');
    final data = Map<String, dynamic>.from(raw);
    final currentPatient = PatientModel.fromMap(patientId, data);
    final online = payment.method.toUpperCase() == 'ONLINE';
    final reference = payment.transactionId?.trim().toUpperCase() ?? '';
    if (online && UpiPayment.validateReference(reference) != null) {
      throw ArgumentError(UpiPayment.validateReference(reference));
    }
    final id = online
        ? 'upi_${sha256.convert(utf8.encode('$patientId:$reference')).toString().substring(0, 60)}'
        : payment.id;
    if (id.isEmpty || RegExp(r'[.#$\[\]/]').hasMatch(id)) {
      throw ArgumentError('Invalid payment ID');
    }
    final existing = (currentPatient.payments ?? [])
        .where(
          (p) =>
              p.id == id ||
              (online &&
                  p.method.toUpperCase() == 'ONLINE' &&
                  (p.transactionId?.trim().toUpperCase() ?? '') == reference),
        )
        .firstOrNull;
    if (existing != null) {
      if (existing.amount != payment.amount ||
          (existing.transactionId?.trim().toUpperCase() ?? '') != reference ||
          existing.method.toUpperCase() != payment.method.toUpperCase() ||
          (payment.cycleId != null && existing.cycleId != payment.cycleId)) {
        throw PaymentReferenceException();
      }
      // A retry of this collection retains its timestamp and financial
      // snapshot. Reusing an old reference for a different collection must not
      // report that new money was received, even on the same invoice or when
      // a legacy receipt has no bill metadata.
      final sameCollectionAttempt =
          existing.date.millisecondsSinceEpoch ==
              payment.date.millisecondsSinceEpoch &&
          existing.totalAmount == payment.totalAmount &&
          existing.paidAmount == payment.paidAmount &&
          existing.pendingAmount == payment.pendingAmount;
      if (collectOutstanding && !sameCollectionAttempt) {
        throw PaymentReferenceException();
      }
      // Other receipt workflows retain their established reference-based
      // idempotency; the existing ledger owns its original metadata.
      if (isPostgres) {
        // A receipt committed by another session may be in the patient response
        // while the watched ledger still has its earlier collection snapshot.
        try {
          await _backendApi!.refresh('payments/${existing.id}');
        } catch (_) {
          debugPrint(
            '[PaymentService] Receipt already saved; ledger refresh needs retry',
          );
        }
        await _reconcileAcknowledgedPayment(patientId);
      }
      return existing.id;
    }
    final pMap = payment.toMap()
      ..addAll({
        'id': id,
        'method': online ? 'ONLINE' : payment.method,
        if (online) 'transactionId': reference,
        'cycleId': payment.cycleId ?? StayBilling.currentCycle(currentPatient),
        'patientId': patientId,
        'patientName': patientName,
        'type': 'payment',
        if (collectOutstanding) 'collectOutstanding': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

    if (isPostgres) {
      debugPrint(
        '[Payment] requestId=$requestId phase=submitting endpoint=POST:/api/payments',
      );
      final res = await _backendApi!.createPayment(pMap, requestId: requestId);
      final committedId = res['id']?.toString();
      if (committedId == null || committedId.isEmpty) {
        throw StateError(
          'Payment server did not confirm a saved transaction. Retry with the same reference.',
        );
      }
      await _reconcileAcknowledgedPayment(patientId);
      return committedId;
    }

    final stays = await loadStays(patientId);
    final payments =
        (currentPatient.payments ?? []).map((p) => p.toMap()).toList()
          ..add(pMap);
    data['payments'] = payments;
    final updates = await billingUpdates(
      patientId,
      patientData: data,
      stays: stays,
    );
    updates.addAll({
      'payments/$id': pMap,
      'paymentHistory/$id': pMap,
      'patients/$patientId/payments/$id': pMap,
    });
    await _safeRtdb.patch('', updates);
    return id;
  }

  Future<String> recordRefund({
    required String patientId,
    required String cycleId,
    required double amount,
    required DateTime date,
    required String method,
    String receiptNumber = '',
    String transactionId = '',
    String? requestId,
    DateTime? checkoutAt,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Enter a positive refund amount');
    }
    final payment = {
      'id':
          requestId ??
          'refund_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
      'amount': -amount,
      'date': date.millisecondsSinceEpoch,
      'method': method,
      'receiptNumber': receiptNumber.trim(),
      'transactionId': transactionId.trim(),
      'cycleId': cycleId,
      'type': 'refund',
      'notes': checkoutAt == null
          ? 'Refund recorded'
          : 'Early checkout refund for proposed checkout ${checkoutAt.toUtc().toIso8601String()}',
      if (checkoutAt != null) 'checkoutAt': checkoutAt.millisecondsSinceEpoch,
    };
    final raw = isPostgres
        ? await _backendApi!.refresh('patients/$patientId')
        : await _safeRtdb.get('patients/$patientId');
    if (raw is! Map) throw StateError('Patient not found');
    final data = Map<String, dynamic>.from(raw);
    final currentPatient = PatientModel.fromMap(patientId, data);
    final priorRefund = requestId == null
        ? null
        : currentPatient.payments
              ?.where((entry) => entry.id == requestId)
              .firstOrNull;
    if (priorRefund != null) {
      if (priorRefund.amount != -amount ||
          priorRefund.cycleId != cycleId ||
          priorRefund.method.toUpperCase() != method.toUpperCase() ||
          (priorRefund.transactionId ?? '').trim() != transactionId.trim()) {
        throw StateError('This refund ID is already recorded differently.');
      }
      // Preserve existing ordinary refund retries. Checkout refunds must reach
      // the server so a reused ID cannot silently change its settlement date.
      if (!isPostgres || checkoutAt == null) return priorRefund.id;
    }
    final stays = await loadStays(patientId);
    final before = await billingUpdates(
      patientId,
      patientData: isPostgres ? null : Map<String, dynamic>.from(raw),
      stays: stays,
      checkoutAt: checkoutAt,
    );
    final balance =
        (before['patients/$patientId/admissionBalances'] as Map?)?[cycleId];
    if (priorRefund == null &&
        (balance is! Map ||
            amount >
                ((balance['refundDue'] as num?)?.toDouble() ?? 0) + 0.005)) {
      throw StateError('Refund exceeds the remaining excess payment');
    }
    final id =
        requestId ??
        'refund_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
    payment.addAll({
      'id': id,
      'patientId': patientId,
      'patientName': currentPatient.fullName,
      'type': 'refund',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final payments =
        (currentPatient.payments ?? []).map((p) => p.toMap()).toList()
          ..add(payment);
    data['payments'] = payments;
    if (isPostgres) {
      final res = await _backendApi!.createPayment(payment);
      await _reconcileAcknowledgedPayment(patientId);
      return res['id']?.toString() ?? id;
    }
    final updates = await billingUpdates(
      patientId,
      patientData: data,
      stays: stays,
    );
    updates.addAll({
      'payments/$id': payment,
      'paymentHistory/$id': payment,
      'patients/$patientId/payments': payments,
    });
    await _safeRtdb.patch('', updates);
    return id;
  }

  Future<void> updatePaymentDetails(
    String patientId,
    String paymentId,
    String transactionNumber,
    DateTime paymentDate, {
    String? embeddedPaymentId,
    double? amount,
    String? receiptNumber,
    String? cycleId,
  }) async {
    if (amount != null && (!amount.isFinite || amount <= 0)) {
      throw ArgumentError('Amount must be greater than zero');
    }
    await _mutatePayment(patientId, paymentId, embeddedPaymentId, {
      'transactionId': transactionNumber.trim(),
      'date': paymentDate.millisecondsSinceEpoch,
      if (amount != null) 'amount': amount,
      if (receiptNumber != null) 'receiptNumber': receiptNumber.trim(),
      if (cycleId != null) 'cycleId': cycleId,
    });
  }

  Future<void> deletePayment(
    String patientId,
    String paymentId, {
    String? embeddedPaymentId,
  }) => _mutatePayment(patientId, paymentId, embeddedPaymentId, null);
  Future<void> _mutatePayment(
    String patientId,
    String paymentId,
    String? embeddedPaymentId,
    Map<String, dynamic>? changes,
  ) async {
    final raw = isPostgres
        ? await _backendApi!.refresh('patients/$patientId')
        : await _safeRtdb.get('patients/$patientId');
    if (raw is! Map) throw StateError('Patient not found');
    final data = Map<String, dynamic>.from(raw);
    final patient = PatientModel.fromMap(patientId, data);
    final global = isPostgres
        ? await _backendApi!.get(
            'payments/$paymentId',
            allowCacheFallback: false,
          )
        : await _safeRtdb.get('payments/$paymentId');
    if (global is Map && global['patientId'] != patientId) {
      throw StateError('Payment belongs to another patient');
    }
    final payments = (patient.payments ?? []).map((p) => p.toMap()).toList();
    final index = payments.indexWhere(
      (p) =>
          p['id'] == paymentId ||
          (embeddedPaymentId != null && p['id'] == embeddedPaymentId),
    );
    if (index < 0 && global is! Map) {
      if (changes == null) return; // An acknowledged deletion is safe to retry.
      throw StateError('Payment not found');
    }
    final original = global is Map
        ? Map<String, dynamic>.from(global)
        : payments[index];
    final stays = await loadStays(patientId);
    final cycleId =
        changes?['cycleId']?.toString() ??
        StayBilling.paymentCycle(
          PaymentModel.fromMap(paymentId, original),
          patient,
          stays,
        );
    final refund = (original['amount'] as num) < 0;
    final updated = changes == null
        ? null
        : <String, dynamic>{
            ...original,
            ...changes,
            'id': paymentId,
            'patientId': patientId,
            'patientName': patient.fullName,
            'cycleId': cycleId,
            if (refund && changes.containsKey('amount'))
              'amount': -(changes['amount'] as num).abs(),
          };
    if (index >= 0) payments.removeAt(index);
    if (updated != null) payments.add(updated);
    data['payments'] = payments;
    if (refund && updated != null) {
      final before = await billingUpdates(
        patientId,
        patientData: Map<String, dynamic>.from(raw),
        stays: stays,
      );
      final previous =
          (before['patients/$patientId/admissionBalances'] as Map?)?[cycleId];
      if (previous is! Map ||
          (updated['amount'] as num).abs() >
              (original['amount'] as num).abs() +
                  ((previous['refundDue'] as num?)?.toDouble() ?? 0) +
                  0.005) {
        throw StateError('Refund exceeds the available excess');
      }
    }
    if (isPostgres) {
      if (updated == null) {
        await _backendApi!.delete('payments/$paymentId');
      } else {
        await _backendApi!.patch('payments/$paymentId', updated);
      }
      await _reconcileAcknowledgedPayment(patientId);
      return;
    }
    final updates = await billingUpdates(
      patientId,
      patientData: data,
      stays: stays,
    );
    updates.addAll({
      'payments/$paymentId': updated,
      'paymentHistory/$paymentId': updated,
      'patients/$patientId/payments': payments,
    });
    await _safeRtdb.patch('', updates);
  }

  Future<void> updateTransactionNumber(
    String patientId,
    String paymentId,
    String transactionNumber,
  ) async {
    final data = isPostgres
        ? await _backendApi!.get('payments/$paymentId')
        : await _safeRtdb.get('payments/$paymentId');
    final date = data is Map
        ? DateTime.fromMillisecondsSinceEpoch(data['date'] as int)
        : DateTime.now();
    await updatePaymentDetails(patientId, paymentId, transactionNumber, date);
  }

  Future<Map<String, double>> getPaymentStats() async {
    final data = isPostgres
        ? await _backendApi!.get(_path)
        : await _safeRtdb.get(_path);
    final totals = <String, double>{
      'total': 0,
      'cash': 0,
      'online': 0,
      'check': 0,
      'refunded': 0,
    };
    for (final row
        in data is Map
            ? data.values
            : data is List
            ? data
            : []) {
      if (row is! Map || row['status'] == 'void') continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      totals['total'] = totals['total']! + amount;
      if (amount < 0) totals['refunded'] = totals['refunded']! - amount;
      final method = row['method']?.toString().toLowerCase() ?? '';
      if (totals.containsKey(method)) totals[method] = totals[method]! + amount;
    }
    return totals;
  }

  Stream<List<Map<String, dynamic>>> getAllPaymentsStream() {
    final sourceStream = isPostgres
        ? _backendApi!.stream(_path)
        : _safeRtdb.stream(_path);
    return sourceStream.map<List<Map<String, dynamic>>>((snapshot) {
      if (snapshot == null) return <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> payments = [];

      if (snapshot is Map) {
        snapshot.forEach((key, value) {
          if (value is Map && value['status'] != 'void') {
            final data = Map<String, dynamic>.from(value);
            payments.add({
              ...data,
              '_localId': data['id']?.toString(),
              // The Firebase collection key is the authoritative ID used for
              // editing. Older rows also contain a local `id` field.
              'id': key,
            });
          }
        });
      } else if (snapshot is List) {
        for (int i = 0; i < snapshot.length; i++) {
          final value = snapshot[i];
          if (value is Map && value['status'] != 'void') {
            final data = Map<String, dynamic>.from(value);
            payments.add({
              ...data,
              '_localId': data['id']?.toString(),
              'id': i.toString(),
            });
          }
        }
      }

      // Sort by date descending (newest first)
      payments.sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));
      return payments;
    });
  }
}
