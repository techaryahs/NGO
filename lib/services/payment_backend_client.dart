import 'dart:convert';
import 'package:http/http.dart' as http;
import 'razorpay_service.dart' show RazorpayBackendConfig;

/// Thin client for a trusted payment backend's manual-payment endpoint.
///
/// When a trusted backend is deployed and configured via
/// `RAZORPAY_BACKEND_URL=...` in `.env`, cash/cheque payments, refunds,
/// and billing updates are recorded server-side.
///
/// When no backend is configured (the default after Functions removal), the
/// application falls back to direct authenticated RTDB writes in
/// [PaymentService].  This fallback requires permissive RTDB security rules
/// on the `payments` and `paymentHistory` nodes.
class PaymentBackendClient {
  static Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final base = RazorpayBackendConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse('$base/$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception(
            'Payment server did not respond. Please try again.',
          ),
        );
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'Payment server error (${response.statusCode}). Please try again.',
      );
    }
    if (response.statusCode != 200 ||
        decoded is! Map ||
        decoded['ok'] != true) {
      final message =
          decoded is Map && decoded['error'] != null
              ? decoded['error'].toString()
              : 'Payment server error (${response.statusCode}).';
      throw Exception(message);
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<String> recordManualPayment({
    required String idToken,
    required String patientId,
    required Map<String, dynamic> payment,
    required bool refund,
  }) async {
    final data = await _post('recordManualPayment', {
      'idToken': idToken,
      'patientId': patientId,
      'payment': payment,
      'refund': refund,
    });
    final id = data['id']?.toString();
    if (id == null) {
      throw Exception('Payment server did not return a transaction id.');
    }
    return id;
  }

  static Future<void> recalculateBilling({
    required String idToken,
    required String patientId,
  }) async {
    await _post('recalculateBilling', {
      'idToken': idToken,
      'patientId': patientId,
    });
  }

  static Future<void> amendManualPayment({
    required String idToken,
    required String patientId,
    required String paymentId,
    String? embeddedPaymentId,
    Map<String, dynamic>? changes,
    required bool voidPayment,
  }) async {
    await _post('amendManualPayment', {
      'idToken': idToken,
      'patientId': patientId,
      'paymentId': paymentId,
      'embeddedPaymentId': embeddedPaymentId,
      'changes': changes,
      'voidPayment': voidPayment,
    });
  }
}
