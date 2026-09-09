import 'dart:math';
import '../models/patient_model.dart';
import '../models/stay_model.dart';
import '../utils/stay_billing.dart';
import 'firebase_rtdb_rest_service.dart';

class PaymentService {
  final FirebaseRTDBRestService _rtdb;
  final String _path = 'payments';
  PaymentService(this._rtdb);
  Future<List<StayModel>> loadStays(String patientId) async {
    final data = await _rtdb.getByChildValue(
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

  Future<Map<String, dynamic>> billingUpdates(
    String patientId, {
    Map<String, dynamic>? patientData,
    List<StayModel>? stays,
  }) async {
    final raw = patientData ?? await _rtdb.get('patients/$patientId');
    if (raw is! Map) throw StateError('Patient not found');
    final patient = PatientModel.fromMap(patientId, raw);
    stays ??= await loadStays(patientId);
    // Older admissions saved their initial patient + attendant estimate as a
    // fixed daily rate. That prevents later attendance marks from reducing
    // the bill. Recognize only that generated value and migrate it back to a
    // dynamic rate; manually edited rates remain untouched.
    final migratedDynamicRateIds = <String>{};
    stays = stays.map((stay) {
      final isGeneratedRate = stay.costOverride == null &&
          !stay.dailyRateIsManual &&
          stay.dailyRate != null;
      if (!isGeneratedRate) return stay;
      migratedDynamicRateIds.add(stay.id);
      final data = stay.toMap()..['dailyRate'] = null;
      return StayModel.fromMap(stay.id, data);
    }).toList();
    final rangeStarts = <DateTime>[
      patient.registrationDate ?? patient.admissionDate,
      ...stays.map((stay) => stay.admissionDate),
    ];
    final rangeEnds = <DateTime>[
      patient.exitDate ?? patient.dischargeDate ?? DateTime.now(),
      ...stays.map(
        (stay) => stay.completedAt ?? stay.expectedDischargeDate,
      ),
    ];
    rangeStarts.sort();
    rangeEnds.sort();
    final startKey = StayBilling.dateKey(rangeStarts.first);
    final endKey = StayBilling.dateKey(rangeEnds.last);
    final reads = await Future.wait<dynamic>([
      _rtdb.get('admin_settings/pricing'),
      _rtdb.getByKeyRange(
        'attendance/daily',
        startKey: startKey,
        endKey: endKey,
      ),
      _rtdb.getByKeyRange(
        'attendant_attendance/daily',
        startKey: startKey,
        endKey: endKey,
      ),
    ]);
    final rawPricing = reads[0];
    final pricing = rawPricing is Map
        ? Map<String, dynamic>.from(rawPricing)
        : <String, dynamic>{};
    final savedGeneralRate =
        (pricing['generalRoomBedPrice'] as num?)?.toDouble();
    final migrateGeneralRate =
        savedGeneralRate == null || savedGeneralRate == 150;
    if (migrateGeneralRate) pricing['generalRoomBedPrice'] = 200;
    final records = reads[1];
    final attendance = <String, String>{};
    if (records is Map)
      for (final entry in records.entries) {
        if (entry.value is Map && entry.value[patientId] is Map) {
          attendance[entry.key.toString()] =
              entry.value[patientId]['status']?.toString() ?? '';
        }
      }
    final attendantRecords = reads[2];
    final attendantAttendance = <String, Map<String, String>>{};
    if (attendantRecords is Map) {
      for (final dateEntry in attendantRecords.entries) {
        final daily = dateEntry.value;
        if (daily is! Map || daily[patientId] is! Map) continue;
        final statuses = <String, String>{};
        for (final record in (daily[patientId] as Map).values) {
          if (record is Map && record['attendantName'] != null) {
            statuses[record['attendantName'].toString()] =
                record['status']?.toString() ?? '';
          }
        }
        attendantAttendance[dateEntry.key.toString()] = statuses;
      }
    }
    final balances = StayBilling.calculate(
      patient: patient,
      stays: stays,
      pricing: pricing,
      attendance: attendance,
      attendantAttendance: attendantAttendance,
    );
    final current = balances.firstWhere(
      (b) => b.id == StayBilling.currentCycle(patient),
    );
    final start = StayBilling.day(
      patient.registrationDate ?? patient.admissionDate,
    );
    final end = StayBilling.day(
      patient.exitDate ?? patient.dischargeDate ?? DateTime.now(),
    );
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
      if (migrateGeneralRate) 'admin_settings/pricing/generalRoomBedPrice': 200,
    };
    for (final balance in balances)
      for (final stay in balance.stays) {
        updates.addAll({
          if (stay.patientSnapshot.isEmpty &&
              balance.id == StayBilling.currentCycle(patient))
            'stays/${stay.id}/patientSnapshot': {
              'registrationNumber': patient.registrationNumber,
              'photoDataUrl': patient.photoDataUrl,
              'attendants': patient.attendants?.map((a) => a.toMap()).toList(),
              'admissionDate': patient.admissionDate.millisecondsSinceEpoch,
            },
          'stays/${stay.id}/cycleId': balance.id,
          'stays/${stay.id}/totalCost': balance.charges[stay.id],
          'stays/${stay.id}/billableDays': balance.days[stay.id],
          'stays/${stay.id}/billingSummary': balance.toMap(),
          if (!stay.isActive)
            'stays/${stay.id}/completedAt':
                (stay.completedAt ?? stay.updatedAt).millisecondsSinceEpoch,
        });
      }
    return updates;
  }

  Future<void> recalculatePatientAttendanceAndBilling(
    String patientId, {
    bool updateBilling = true,
  }) async {
    await _rtdb.patch('', await billingUpdates(patientId));
  }

  Future<void> recalculateAllActivePatientsBilling({String? patientId}) async {
    if (patientId != null)
      return recalculatePatientAttendanceAndBilling(patientId);
    final patients = await _rtdb.get('patients');
    if (patients is Map)
      for (final entry in patients.entries) {
        if (entry.value is Map)
          await recalculatePatientAttendanceAndBilling(entry.key.toString());
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
  Future<String> recordPayment({
    required String patientId,
    required String patientName,
    required PaymentModel payment,
  }) async {
    if (!payment.amount.isFinite || payment.amount <= 0)
      throw ArgumentError('Enter a positive payment amount');
    return _record(patientId, payment.toMap(), refund: false);
  }

  Future<String> recordRefund({
    required String patientId,
    required String cycleId,
    required double amount,
    required DateTime date,
    required String method,
    String receiptNumber = '',
    String transactionId = '',
  }) async {
    if (!amount.isFinite || amount <= 0)
      throw ArgumentError('Enter a positive refund amount');
    return _record(patientId, {
      'amount': -amount,
      'date': date.millisecondsSinceEpoch,
      'method': method,
      'receiptNumber': receiptNumber.trim(),
      'transactionId': transactionId.trim(),
      'cycleId': cycleId,
      'type': 'refund',
      'notes': 'Refund recorded',
    }, refund: true);
  }

  Future<String> _record(
    String patientId,
    Map<String, dynamic> payment, {
    required bool refund,
  }) async {
    final raw = await _rtdb.get('patients/$patientId');
    if (raw is! Map) throw StateError('Patient not found');
    final data = Map<String, dynamic>.from(raw);
    final patient = PatientModel.fromMap(patientId, data);
    final stays = await loadStays(patientId);
    payment['cycleId'] ??= StayBilling.currentCycle(patient);
    if (refund) {
      final before = await billingUpdates(
        patientId,
        patientData: data,
        stays: stays,
      );
      final balance =
          (before['patients/$patientId/admissionBalances']
              as Map)[payment['cycleId']];
      if (balance is! Map ||
          -(payment['amount'] as num) > (balance['refundDue'] as num) + 0.005) {
        throw StateError('Refund exceeds the remaining excess payment');
      }
    }
    final id =
        '${refund ? 'refund' : 'payment'}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
    payment.addAll({
      'id': id,
      'patientId': patientId,
      'patientName': patient.fullName,
      'type': refund ? 'refund' : 'payment',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final payments = (patient.payments ?? []).map((p) => p.toMap()).toList()
      ..add(payment);
    data['payments'] = payments;
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
    await _rtdb.patch('', updates);
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
    if (amount != null && (!amount.isFinite || amount <= 0))
      throw ArgumentError('Amount must be greater than zero');
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
    final raw = await _rtdb.get('patients/$patientId');
    if (raw is! Map) throw StateError('Patient not found');
    final data = Map<String, dynamic>.from(raw);
    final patient = PatientModel.fromMap(patientId, data);
    final global = await _rtdb.get('payments/$paymentId');
    if (global is Map && global['patientId'] != patientId)
      throw StateError('Payment belongs to another patient');
    final payments = (patient.payments ?? []).map((p) => p.toMap()).toList();
    final index = payments.indexWhere(
      (p) =>
          p['id'] == paymentId ||
          (embeddedPaymentId != null && p['id'] == embeddedPaymentId),
    );
    if (index < 0 && global is! Map) throw StateError('Payment not found');
    final original = global is Map
        ? Map<String, dynamic>.from(global)
        : payments[index];
    final stays = await loadStays(patientId);
    final cycleId = changes?['cycleId']?.toString() ??
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
    final updates = await billingUpdates(
      patientId,
      patientData: data,
      stays: stays,
    );
    if (refund && updated != null) {
      final before = await billingUpdates(
        patientId,
        patientData: Map<String, dynamic>.from(raw),
        stays: stays,
      );
      final previous =
          (before['patients/$patientId/admissionBalances'] as Map)[cycleId];
      if (previous is! Map ||
          (updated['amount'] as num).abs() >
              (original['amount'] as num).abs() +
                  (previous['refundDue'] as num) +
                  0.005) {
        throw StateError('Refund exceeds the available excess');
      }
    }
    updates.addAll({
      'payments/$paymentId': updated,
      'paymentHistory/$paymentId': updated,
      'patients/$patientId/payments': payments,
    });
    await _rtdb.patch('', updates);
  }

  Future<void> updateTransactionNumber(
    String patientId,
    String paymentId,
    String transactionNumber,
  ) async {
    final data = await _rtdb.get('payments/$paymentId');
    final date = data is Map
        ? DateTime.fromMillisecondsSinceEpoch(data['date'] as int)
        : DateTime.now();
    await updatePaymentDetails(patientId, paymentId, transactionNumber, date);
  }

  Future<Map<String, double>> getPaymentStats() async {
    final data = await _rtdb.get(_path);
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
      if (row is! Map) continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      totals['total'] = totals['total']! + amount;
      if (amount < 0) totals['refunded'] = totals['refunded']! - amount;
      final method = row['method']?.toString().toLowerCase() ?? '';
      if (totals.containsKey(method)) totals[method] = totals[method]! + amount;
    }
    return totals;
  }

  Stream<List<Map<String, dynamic>>> getAllPaymentsStream() {
    return _rtdb.stream(_path).map<List<Map<String, dynamic>>>((snapshot) {
      if (snapshot == null) return <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> payments = [];

      if (snapshot is Map) {
        snapshot.forEach((key, value) {
          if (value is Map) {
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
          if (value is Map) {
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
    }).asBroadcastStream();
  }
}
