import 'dart:async';
import '../models/patient_model.dart';
import 'firebase_rtdb_rest_service.dart';

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
      
      // 2. Also update the individual patient's record (for the profile view)
      // This provides redundancy and ensures fast local retrieval for patient-specific views.
      final patientData = await _rtdb.get('patients/$patientId');
      if (patientData != null && patientData is Map) {
        final List<dynamic> currentPayments = patientData['payments'] != null 
            ? List.from(patientData['payments']) 
            : [];
        currentPayments.add(data);
        await _rtdb.patch('patients/$patientId', {'payments': currentPayments});
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
}
