import 'dart:async';
import '../models/patient_model.dart';
import 'firebase_rtdb_rest_service.dart';
import 'service_locator.dart';
import '../models/room_model.dart';

class PaymentService {
  final FirebaseRTDBRestService _rtdb;

  Future<bool> _isPrivateAccommodation(PatientModel patient) async {
    if (patient.lobby?.trim().isNotEmpty == true) return false;
    if (patient.roomNumber?.trim().isNotEmpty == true) {
      return RoomModel.isPrivateRoomIdentifier(patient.roomNumber!);
    }

    // Room fields are cleared on discharge. Use the most recent historical
    // stay instead of guessing the room type from an advance amount.
    final stays = await ServiceLocator().roomService
        .getStaysByPatientStream(patient.id)
        .first;
    if (stays.isNotEmpty) {
      stays.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return stays.first.roomType.toLowerCase() == 'private';
    }
    return false;
  }

  final String _path = 'payments';

  PaymentService(this._rtdb);

  double _currentCyclePaymentTotal(PatientModel patient) {
    final payments = patient.payments;
    if (payments == null) return patient.totalPaidAmount ?? 0;

    return payments.fold<double>(0, (total, payment) {
      if (payment.date.isBefore(patient.admissionDate)) return total;
      return total + payment.amount;
    });
  }

  double _paymentTotalFromMap(List<dynamic> payments, DateTime cycleStart) {
    return payments.fold<double>(0, (total, payment) {
      if (payment is! Map) return total;
      final amount = (payment['amount'] ?? 0).toDouble();
      final rawDate = payment['date'];
      final date = rawDate is int
          ? DateTime.fromMillisecondsSinceEpoch(rawDate)
          : DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(rawDate?.toString() ?? '') ?? 0,
            );
      if (date.isBefore(cycleStart)) return total;
      return total + amount;
    });
  }

  /// Records a new payment and links it to a patient.
  /// This stores the payment in a global collection for fast retrieval across all patients.
  Future<String> recordPayment({
    required String patientId,
    required String patientName,
    required PaymentModel payment,
  }) async {
    try {
      final data = payment.toMap();
      data['patientId'] = patientId;
      data['patientName'] = patientName;
      data['timestamp'] = DateTime.now().millisecondsSinceEpoch;

      // 1. Save to global payments root (for the dashboard)
      final paymentId = await _rtdb.push(_path, data);
      data['id'] = paymentId;

      // Also save to paymentHistory/ as requested for ledger
      await _rtdb.patch('paymentHistory/$paymentId', data);

      // 2. Also update the individual patient's record (for the profile view)
      // This provides redundancy and ensures fast local retrieval for patient-specific views.
      final patientData = await _rtdb.get('patients/$patientId');
      if (patientData != null && patientData is Map) {
        final List<dynamic> currentPayments = patientData['payments'] != null
            ? List.from(patientData['payments'])
            : [];
        currentPayments.add(data);

        // Auto-recalculate pending amounts for this patient
        final rawAdmissionDate = patientData['admissionDate'];
        final admissionDate = rawAdmissionDate is int
            ? DateTime.fromMillisecondsSinceEpoch(rawAdmissionDate)
            : DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(rawAdmissionDate?.toString() ?? '') ?? 0,
              );
        final totalPaid = _paymentTotalFromMap(
          currentPayments,
          admissionDate,
        );

        final advanceBilled = (patientData['advanceBilledAmount'] ?? 0)
            .toDouble();
        final attendanceCharges = (patientData['attendanceCharges'] ?? 0)
            .toDouble();
        final totalBill = advanceBilled + attendanceCharges;

        double currentDue = totalBill - totalPaid;
        if (currentDue < 0) currentDue = 0;

        String paymentStatus = 'Unpaid';
        if (totalPaid > 0 && currentDue > 0) {
          paymentStatus = 'Partially Paid';
        } else if (currentDue == 0 && totalPaid > 0) {
          paymentStatus = 'Paid';
        } else if (currentDue == 0 && totalPaid == 0 && totalBill == 0) {
          paymentStatus = 'Paid';
        }

        await _rtdb.patch('patients/$patientId', {
          'payments': currentPayments,
          'totalPaidAmount': totalPaid,
          'currentDueAmount': currentDue,
          'paymentPending': currentDue > 0,
          'paymentStatus': paymentStatus,
        });
      }

      return paymentId;
    } catch (e) {
      throw Exception('Failed to record payment: $e');
    }
  }

  /// Stream of all payments for the global dashboard.
  /// Retrieves from the dedicated root for maximum performance.
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

  Future<void> updatePaymentDetails(
    String patientId,
    String paymentId,
    String transactionNumber,
    DateTime paymentDate, {
    String? embeddedPaymentId,
  }) async {
    final value = transactionNumber.trim();
    final updates = <String, dynamic>{
      'transactionId': value.isEmpty ? null : value,
      'date': paymentDate.millisecondsSinceEpoch,
    };
    await _rtdb.patch('$_path/$paymentId', updates);
    await _rtdb.patch('paymentHistory/$paymentId', updates);
    final patient = await ServiceLocator().patientService.getPatient(patientId);
    if (patient == null) return;
    final payments = (patient.payments ?? []).map((payment) {
      final data = payment.toMap();
      // Update only the selected embedded transaction. Updating every
      // MANUAL_ONLINE placeholder caused one number to appear on all rows.
      if (payment.id == paymentId || payment.id == embeddedPaymentId) {
        data.addAll(updates);
      }
      return data;
    }).toList();
    await ServiceLocator().patientService.updatePatient(patientId, {
      'payments': payments,
    });
  }

  Future<void> updateTransactionNumber(
    String patientId,
    String paymentId,
    String transactionNumber,
  ) async {
    final payment = await _rtdb.get('$_path/$paymentId');
    final timestamp = payment is Map ? payment['date'] : null;
    final date = timestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
    await updatePaymentDetails(patientId, paymentId, transactionNumber, date);
  }

  /// Get total summary stats from the global root
  Future<Map<String, double>> getPaymentStats() async {
    final snapshot = await _rtdb.get(_path);
    double total = 0;
    double cash = 0;
    double online = 0;
    double check = 0;

    void process(dynamic value) {
      if (value is Map) {
        final amount = (value['amount'] ?? 0).toDouble();
        final method = value['method']?.toString().toLowerCase() ?? '';
        total += amount;
        if (method.contains('cash'))
          cash += amount;
        else if (method.contains('online'))
          online += amount;
        else if (method.contains('check'))
          check += amount;
      }
    }

    if (snapshot is Map) {
      snapshot.forEach((_, v) => process(v));
    } else if (snapshot is List) {
      for (final v in snapshot) {
        process(v);
      }
    }

    return {'total': total, 'cash': cash, 'online': online, 'check': check};
  }

  // ── Smart Attendance-Based Billing ─────────────────────────────────────────

  /// Lazy-evaluation engine that checks if patients have crossed the 7-day advance period.
  // Future<void> recalculateAllActivePatientsBilling() async {
  //   final patientService = ServiceLocator().patientService;
  //   final allPatients = await patientService.getPatientsStream().first;
  //   // We update all patients to fix historical data
  //   final patientsToUpdate = allPatients;

  //   for (final patient in patientsToUpdate) {
  //     bool isAdvancePeriod = patient.totalPresentDays < 7;

  //     final isPrivate = patient.roomNumber?.toUpperCase().endsWith('A') == true ||
  //                       patient.roomNumber?.toUpperCase().endsWith('B') == true ||
  //                       patient.advanceBilledAmount >= 3500.0;
  //     final dailyRate = isPrivate
  //         ? 700.0 + ((patient.attendants?.length ?? 0) * 200.0)
  //         : (1 + (patient.attendants?.length ?? 0)) * 200.0;

  //     int chargeableDays = patient.totalPresentDays > 7 ? patient.totalPresentDays - 7 : 0;
  //     double newCharges = chargeableDays * dailyRate;

  //     // Re-calculate due amount
  //     final totalBill = patient.advanceBilledAmount + newCharges;

  //     double totalPaid = 0;
  //     if (patient.payments != null) {
  //       for (var p in patient.payments!) {
  //         totalPaid += p.amount;
  //       }
  //     } else {
  //       totalPaid = patient.totalPaidAmount ?? 0;
  //     }

  //     double currentDue = totalBill - totalPaid;
  //     if (currentDue < 0) currentDue = 0;

  //     String paymentStatus = 'Unpaid';
  //     if (totalPaid > 0 && currentDue > 0) {
  //       paymentStatus = 'Partially Paid';
  //     } else if (currentDue == 0 && totalPaid > 0) {
  //       paymentStatus = 'Paid';
  //     } else if (currentDue == 0 && totalPaid == 0 && totalBill == 0) {
  //       paymentStatus = 'Paid';
  //     }

  //     await patientService.updatePatient(patient.id, {
  //       'isAdvancePeriod': isAdvancePeriod,
  //       'attendanceCharges': newCharges,
  //       'totalPaidAmount': totalPaid,
  //       'currentDueAmount': currentDue,
  //       'paymentPending': currentDue > 0,
  //       'paymentStatus': paymentStatus,
  //     });
  //   }
  // }
  Future<void> recalculateAllActivePatientsBilling({String? patientId}) async {
    final patientService = ServiceLocator().patientService;
    final allPatients = await patientService.getPatientsStream().first;

    final patients = patientId == null
        ? allPatients
        : allPatients.where((patient) => patient.id == patientId);
    for (final patient in patients) {
      final isPrivate = await _isPrivateAccommodation(patient);

      final int attendantCount = patient.attendants?.length ?? 0;
      final int occupantCount = 1 + attendantCount;
      // Billing is based only on days explicitly marked Present. Absent and
      // unmarked dates remain visible in attendance but are not chargeable.
      final int totalPresent = patient.totalPresentDays;

      // ── Two-slab calculation ──────────────────────────────────────────
      final int phase1Days = totalPresent.clamp(0, 60);
      final int phase2Days = (totalPresent - 60).clamp(0, 999999);

      double grossCharges;
      if (isPrivate) {
        const double p1Patient = 700.0, p1Attendant = 200.0;
        const double p2Patient = 900.0, p2Attendant = 300.0;
        // The room price includes the patient and one attendant. Charge only
        // attendants beyond that included person.
        final phase1AttendantCharge = attendantCount > 1
            ? (attendantCount - 1) * p1Attendant
            : 0.0;
        final phase2AttendantCharge = attendantCount > 1
            ? (attendantCount - 1) * p2Attendant
            : 0.0;
        grossCharges =
            (phase1Days * (p1Patient + phase1AttendantCharge)) +
            (phase2Days * (p2Patient + phase2AttendantCharge));
      } else {
        const double p1Rate = 200.0;
        const double p2Rate = 250.0;
        grossCharges =
            (phase1Days * occupantCount * p1Rate) +
            (phase2Days * occupantCount * p2Rate);
      }

      // An advance is an estimate, not an additional or minimum final bill.
      // Once discharged, explicitly Present days determine the final total.
      final isDischarged = patient.status.toLowerCase() == 'discharged';
      final double totalBill = isDischarged
          ? grossCharges
          : grossCharges < patient.advanceBilledAmount
          ? patient.advanceBilledAmount
          : grossCharges;
      final double newCharges = (totalBill - patient.advanceBilledAmount).clamp(
        0.0,
        double.infinity,
      );

      final totalPaid = _currentCyclePaymentTotal(patient);

      double currentDue = totalBill - totalPaid;
      if (currentDue < 0) currentDue = 0;

      String paymentStatus = 'Unpaid';
      if (totalPaid > 0 && currentDue > 0) {
        paymentStatus = 'Partially Paid';
      } else if (currentDue == 0 && totalPaid > 0) {
        paymentStatus = 'Paid';
      } else if (currentDue == 0 && totalPaid == 0 && totalBill == 0) {
        paymentStatus = 'Paid';
      }

      await patientService.updatePatient(patient.id, {
        'isAdvancePeriod': totalPresent < 60,
        'attendanceCharges': newCharges,
        'totalPaidAmount': totalPaid,
        'currentDueAmount': currentDue,
        'paymentPending': currentDue > 0,
        'paymentStatus': paymentStatus,
      });
    }
  }

  /// Calculates explicitly recorded attendance from registration through
  /// discharge (or today for an active patient). Unmarked dates are ignored.
  Future<void> recalculatePatientAttendanceAndBilling(
    String patientId, {
    bool updateBilling = true,
  }) async {
    final patientService = ServiceLocator().patientService;
    final patient = await patientService.getPatient(patientId);
    if (patient == null) return;

    DateTime dateOnly(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    final start = dateOnly(patient.registrationDate ?? patient.admissionDate);
    final exit = patient.exitDate ?? patient.dischargeDate;
    var end = dateOnly(exit ?? DateTime.now());
    if (exit != null &&
        (exit.hour < 9 || (exit.hour == 9 && exit.minute == 0))) {
      end = end.subtract(const Duration(days: 1));
    }

    var present = 0;
    var absent = 0;
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      final key =
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final record = await _rtdb.get('attendance/daily/$key/$patientId');
      if (record is Map) {
        if (record['status']?.toString() == 'Absent') {
          absent++;
        } else if (record['status']?.toString() == 'Present') {
          present++;
        }
      }
    }

    await patientService.updatePatient(patientId, {
      'totalPresentDays': present,
      'totalAbsentDays': absent,
    });
    if (updateBilling) {
      await recalculateAllActivePatientsBilling(patientId: patientId);
    }
  }

  /// Repairs historical records, including patients added before automatic
  /// attendance was introduced.
  Future<void> recalculateAllPatientsAttendanceAndBilling() async {
    final patients = await ServiceLocator().patientService
        .getPatientsStream()
        .first;
    for (final patient in patients) {
      await recalculatePatientAttendanceAndBilling(
        patient.id,
        updateBilling: false,
      );
    }
    await recalculateAllActivePatientsBilling();
  }

  // Called by `markAttendance` to incrementally update attendance charges.
  // Future<void> updatePatientBillingFromAttendance({
  //   required String patientId,
  //   required DateTime dateMarked,
  //   required bool isPresent,
  //   required bool? wasPresent,
  // }) async {
  //   final patientService = ServiceLocator().patientService;
  //   final patient = await patientService.getPatient(patientId);
  //   if (patient == null) return;

  //   int newPresent = patient.totalPresentDays;
  //   int newAbsent = patient.totalAbsentDays;

  //   if (wasPresent == null) {
  //     if (isPresent) newPresent++;
  //     else newAbsent++;
  //   } else if (wasPresent && !isPresent) {
  //     newPresent--;
  //     newAbsent++;
  //   } else if (!wasPresent && isPresent) {
  //     newAbsent--;
  //     newPresent++;
  //   } else {
  //     // No change in status
  //     return;
  //   }

  //   final isPrivate = patient.roomNumber?.toUpperCase().endsWith('A') == true ||
  //                     patient.roomNumber?.toUpperCase().endsWith('B') == true ||
  //                     patient.advanceBilledAmount >= 3500.0;
  //   final dailyRate = isPrivate
  //       ? 700.0 + ((patient.attendants?.length ?? 0) * 200.0)
  //       : (1 + (patient.attendants?.length ?? 0)) * 200.0;

  //   int chargeableDays = newPresent > 7 ? newPresent - 7 : 0;
  //   double newCharges = chargeableDays * dailyRate;

  //   // Recalculate total
  //   final totalBill = patient.advanceBilledAmount + newCharges;

  //   double totalPaid = 0;
  //   if (patient.payments != null) {
  //     for (var p in patient.payments!) {
  //       totalPaid += p.amount;
  //     }
  //   } else {
  //     totalPaid = patient.totalPaidAmount ?? 0;
  //   }

  //   double currentDue = totalBill - totalPaid;
  //   if (currentDue < 0) currentDue = 0;

  //   String paymentStatus = 'Unpaid';
  //   if (totalPaid > 0 && currentDue > 0) {
  //     paymentStatus = 'Partially Paid';
  //   } else if (currentDue == 0 && totalPaid > 0) {
  //     paymentStatus = 'Paid';
  //   } else if (currentDue == 0 && totalPaid == 0 && totalBill == 0) {
  //     paymentStatus = 'Paid';
  //   }

  //   await patientService.updatePatient(patientId, {
  //     'totalPresentDays': newPresent,
  //     'totalAbsentDays': newAbsent,
  //     'isAdvancePeriod': newPresent < 7,
  //     'attendanceCharges': newCharges,
  //     'totalPaidAmount': totalPaid,
  //     'currentDueAmount': currentDue,
  //     'paymentPending': currentDue > 0,
  //     'paymentStatus': paymentStatus,
  //   });
  // }
  Future<void> updatePatientBillingFromAttendance({
    required String patientId,
    required DateTime dateMarked,
    required bool isPresent,
    required bool? wasPresent,
  }) async {
    final patientService = ServiceLocator().patientService;
    final patient = await patientService.getPatient(patientId);
    if (patient == null) return;

    int newPresent = patient.totalPresentDays;
    int newAbsent = patient.totalAbsentDays;

    if (wasPresent == null) {
      if (isPresent)
        newPresent++;
      else
        newAbsent++;
    } else if (wasPresent && !isPresent) {
      newPresent--;
      newAbsent++;
    } else if (!wasPresent && isPresent) {
      newAbsent--;
      newPresent++;
    } else {
      return; // no change
    }
    final isPrivate = await _isPrivateAccommodation(patient);

    final int attendantCount = patient.attendants?.length ?? 0;
    final int occupantCount = 1 + attendantCount;

    // ── Two-slab calculation ──────────────────────────────────────────
    final int phase1Days = newPresent.clamp(0, 60);
    final int phase2Days = (newPresent - 60).clamp(0, 999999);

    double grossCharges;
    if (isPrivate) {
      const double p1Patient = 700.0, p1Attendant = 200.0;
      const double p2Patient = 900.0, p2Attendant = 300.0;
      final phase1AttendantCharge = attendantCount > 1
          ? (attendantCount - 1) * p1Attendant
          : 0.0;
      final phase2AttendantCharge = attendantCount > 1
          ? (attendantCount - 1) * p2Attendant
          : 0.0;
      grossCharges =
          (phase1Days * (p1Patient + phase1AttendantCharge)) +
          (phase2Days * (p2Patient + phase2AttendantCharge));
    } else {
      const double p1Rate = 200.0;
      const double p2Rate = 250.0;
      grossCharges =
          (phase1Days * occupantCount * p1Rate) +
          (phase2Days * occupantCount * p2Rate);
    }

    final isDischarged = patient.status.toLowerCase() == 'discharged';
    final double totalBill = isDischarged
        ? grossCharges
        : grossCharges < patient.advanceBilledAmount
        ? patient.advanceBilledAmount
        : grossCharges;
    final double newCharges = (totalBill - patient.advanceBilledAmount).clamp(
      0.0,
      double.infinity,
    );

    final totalPaid = _currentCyclePaymentTotal(patient);

    double currentDue = totalBill - totalPaid;
    if (currentDue < 0) currentDue = 0;

    String paymentStatus = 'Unpaid';
    if (totalPaid > 0 && currentDue > 0) {
      paymentStatus = 'Partially Paid';
    } else if (currentDue == 0 && totalPaid > 0) {
      paymentStatus = 'Paid';
    } else if (currentDue == 0 && totalPaid == 0 && totalBill == 0) {
      paymentStatus = 'Paid';
    }

    await patientService.updatePatient(patientId, {
      'totalPresentDays': newPresent,
      'totalAbsentDays': newAbsent,
      'isAdvancePeriod': newPresent < 60,
      'attendanceCharges': newCharges,
      'totalPaidAmount': totalPaid,
      'currentDueAmount': currentDue,
      'paymentPending': currentDue > 0,
      'paymentStatus': paymentStatus,
    });
  }
}
