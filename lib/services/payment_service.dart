import 'dart:async';
import '../models/patient_model.dart';
import 'firebase_rtdb_rest_service.dart';
import 'service_locator.dart';

class PaymentService {
  final FirebaseRTDBRestService _rtdb;
  final String _path = 'payments';

  PaymentService(this._rtdb);

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
        double totalPaid = 0;
        for (var p in currentPayments) {
          totalPaid += (p['amount'] ?? 0).toDouble();
        }
        
        final advanceBilled = (patientData['advanceBilledAmount'] ?? 0).toDouble();
        final attendanceCharges = (patientData['attendanceCharges'] ?? 0).toDouble();
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
    return _rtdb.stream(_path).map((snapshot) {
      if (snapshot == null) return [];
      final List<Map<String, dynamic>> payments = [];
      
      if (snapshot is Map) {
        snapshot.forEach((key, value) {
          if (value is Map) {
            payments.add({
              'id': key, 
              ...Map<String, dynamic>.from(value)
            });
          }
        });
      } else if (snapshot is List) {
        for (int i = 0; i < snapshot.length; i++) {
          final value = snapshot[i];
          if (value is Map) {
            payments.add({
              'id': i.toString(), 
              ...Map<String, dynamic>.from(value)
            });
          }
        }
      }
      
      // Sort by date descending (newest first)
      payments.sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));
      return payments;
    });
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
        if (method.contains('cash')) cash += amount;
        else if (method.contains('online')) online += amount;
        else if (method.contains('check')) check += amount;
      }
    }

    if (snapshot is Map) {
      snapshot.forEach((_, v) => process(v));
    } else if (snapshot is List) {
      for (final v in snapshot) {
        process(v);
      }
    }

    return {
      'total': total,
      'cash': cash,
      'online': online,
      'check': check,
    };
  }

  // ── Smart Attendance-Based Billing ─────────────────────────────────────────

  /// Lazy-evaluation engine that checks if patients have crossed the 7-day advance period.
  Future<void> recalculateAllActivePatientsBilling() async {
    final patientService = ServiceLocator().patientService;
    final allPatients = await patientService.getPatientsStream().first;
    // We update all patients to fix historical data
    final patientsToUpdate = allPatients; 

    for (final patient in patientsToUpdate) {
      bool isAdvancePeriod = patient.totalPresentDays < 7;
      
      final isPrivate = patient.roomNumber?.toUpperCase().endsWith('A') == true || 
                        patient.roomNumber?.toUpperCase().endsWith('B') == true ||
                        patient.advanceBilledAmount >= 3500.0;
      final dailyRate = isPrivate 
          ? 700.0 + ((patient.attendants?.length ?? 0) * 200.0) 
          : (1 + (patient.attendants?.length ?? 0)) * 200.0;

      int chargeableDays = patient.totalPresentDays > 7 ? patient.totalPresentDays - 7 : 0;
      double newCharges = chargeableDays * dailyRate;

      // Re-calculate due amount
      final totalBill = patient.advanceBilledAmount + newCharges;
      
      double totalPaid = 0;
      if (patient.payments != null) {
        for (var p in patient.payments!) {
          totalPaid += p.amount;
        }
      } else {
        totalPaid = patient.totalPaidAmount ?? 0;
      }
      
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
        'isAdvancePeriod': isAdvancePeriod,
        'attendanceCharges': newCharges,
        'totalPaidAmount': totalPaid,
        'currentDueAmount': currentDue,
        'paymentPending': currentDue > 0,
        'paymentStatus': paymentStatus,
      });
    }
  }

  /// Called by `markAttendance` to incrementally update attendance charges.
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
      if (isPresent) newPresent++;
      else newAbsent++;
    } else if (wasPresent && !isPresent) {
      newPresent--;
      newAbsent++;
    } else if (!wasPresent && isPresent) {
      newAbsent--;
      newPresent++;
    } else {
      // No change in status
      return;
    }

    final isPrivate = patient.roomNumber?.toUpperCase().endsWith('A') == true || 
                      patient.roomNumber?.toUpperCase().endsWith('B') == true ||
                      patient.advanceBilledAmount >= 3500.0;
    final dailyRate = isPrivate 
        ? 700.0 + ((patient.attendants?.length ?? 0) * 200.0) 
        : (1 + (patient.attendants?.length ?? 0)) * 200.0;
    
    int chargeableDays = newPresent > 7 ? newPresent - 7 : 0;
    double newCharges = chargeableDays * dailyRate;

    // Recalculate total
    final totalBill = patient.advanceBilledAmount + newCharges;
    
    double totalPaid = 0;
    if (patient.payments != null) {
      for (var p in patient.payments!) {
        totalPaid += p.amount;
      }
    } else {
      totalPaid = patient.totalPaidAmount ?? 0;
    }

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
      'isAdvancePeriod': newPresent < 7,
      'attendanceCharges': newCharges,
      'totalPaidAmount': totalPaid,
      'currentDueAmount': currentDue,
      'paymentPending': currentDue > 0,
      'paymentStatus': paymentStatus,
    });
  }
}
