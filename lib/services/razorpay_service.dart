import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// RazorpayBackendConfig — trusted backend endpoint.
///
/// The Razorpay key secret NEVER exists in this application.  Payment link
/// creation, payment verification, and webhook processing require a
/// **separate trusted backend** that holds the Razorpay secret key.
///
/// Configure the endpoint in the root `.env` file:
///   RAZORPAY_BACKEND_URL=https://...
///
/// When the backend is not configured (the default), online payments are
/// disabled and the UI asks staff to collect cash/cheque instead.
///
/// **Note:** The previous Firebase Cloud Functions backend (`functions/`) has
/// been removed from this repository.  A replacement trusted backend must be
/// deployed independently before online Razorpay payments can be re-enabled.
/// ─────────────────────────────────────────────────────────────────────────────
class RazorpayBackendConfig {
  static String get baseUrl => AppConfig.razorpayBackendUrl;
  static bool get isConfigured => AppConfig.isPaymentBackendConfigured;
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Model returned after creating a Payment Link.
/// ─────────────────────────────────────────────────────────────────────────────
class RazorpayPaymentLink {
  /// Razorpay internal ID, e.g. "plink_xxxxxxxxxxxx"
  final String id;

  /// Short URL to open in browser.
  final String url;

  const RazorpayPaymentLink({required this.id, required this.url});
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Model returned when polling a Payment Link for status.
/// ─────────────────────────────────────────────────────────────────────────────
class RazorpayPaymentStatus {
  /// "created" | "partially_paid" | "paid" | "cancelled" | "expired"
  final String status;

  /// Razorpay payment ID, e.g. "pay_xxxxxxxxxxxx" (only when paid)
  final String? paymentId;

  /// Payment method: "upi", "card", "netbanking", "wallet", etc.
  final String? method;

  /// When the payment was completed (only when paid).
  final DateTime? paidAt;

  /// Amount actually paid in paise.
  final int? amountPaid;

  const RazorpayPaymentStatus({
    required this.status,
    this.paymentId,
    this.method,
    this.paidAt,
    this.amountPaid,
  });

  bool get isPaid => status == 'paid';
}

/// ─────────────────────────────────────────────────────────────────────────────
/// RazorpayService — thin client for a trusted payment backend.
///
/// This client only ever talks to a trusted backend endpoint.  It has no
/// access to the Razorpay secret key and cannot fabricate a payment:
///   - the backend computes the amount from the database balance
///   - the backend verifies payments with the Razorpay API
///   - the backend verifies webhook signatures server-side
///   - the backend writes the payment ledger idempotently
///
/// Online Razorpay features are **disabled** unless a trusted backend URL
/// is provided in `.env` via `RAZORPAY_BACKEND_URL=https://...`.
/// ─────────────────────────────────────────────────────────────────────────────
class RazorpayService {
  static Never _backendMissing() {
    throw Exception(
      'Online payments are not configured on this installation. '
      'Please collect cash or cheque and contact the administrator.',
    );
  }

  static Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
  };

  static Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    if (!RazorpayBackendConfig.isConfigured) _backendMissing();
    final base = RazorpayBackendConfig.baseUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final response = await http
        .post(
          Uri.parse('$base/$endpoint'),
          headers: _jsonHeaders,
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
    if (response.statusCode != 200 || decoded is! Map || decoded['ok'] != true) {
      final message =
          decoded is Map && decoded['error'] != null
              ? decoded['error'].toString()
              : 'Payment server error (${response.statusCode}).';
      throw Exception(message);
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Creates a Razorpay Payment Link through the trusted backend.
  ///
  /// [amountInPaise] is only a request — the backend recomputes the
  /// outstanding balance and rejects amounts that exceed it.
  static Future<RazorpayPaymentLink> createPaymentLink({
    required String idToken,
    required String patientId,
    required int amountInPaise,
    required String patientName,
    required String contactNumber,
    required String description,
    Map<String, String>? notes,
  }) async {
    final data = await _post('createPaymentLink', {
      'idToken': idToken,
      'patientId': patientId,
      'amountInPaise': amountInPaise,
      'description': description,
      'patientName': patientName,
      'contactNumber': contactNumber,
      if (notes != null) 'notes': notes,
    });
    final linkId = data['linkId']?.toString();
    final url = data['url']?.toString();
    if (linkId == null || url == null) {
      throw Exception('Payment server returned an invalid link.');
    }
    return RazorpayPaymentLink(id: linkId, url: url);
  }

  /// Polls a payment link through the trusted backend.
  ///
  /// When the backend confirms payment it records the transaction in the
  /// ledger server-side, so the client never writes a payment for online
  /// transactions itself.
  static Future<RazorpayPaymentStatus> getPaymentLinkStatus({
    required String idToken,
    required String linkId,
  }) async {
    try {
      final data = await _post('checkPaymentLink', {
        'idToken': idToken,
        'linkId': linkId,
      });
      final status = data['status']?.toString() ?? 'created';
      return RazorpayPaymentStatus(
        status: status,
        paymentId: data['paymentId']?.toString(),
        method: data['method']?.toString(),
        paidAt: data['paidAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(data['paidAt'] as int)
            : null,
        amountPaid: data['amountPaid'] is int ? data['amountPaid'] as int : null,
      );
    } catch (_) {
      // Don't throw — keep polling so a temporary backend failure does not
      // lose an in-flight payment.
      return const RazorpayPaymentStatus(status: 'created');
    }
  }

  /// Opens the given [url] in the system default browser.
  static Future<void> openInBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception(
        'Could not open browser. Please open this link manually:\n$url',
      );
    }
  }

  /// Convenience method — creates the payment link and immediately opens it.
  static Future<RazorpayPaymentLink> createAndOpen({
    required String idToken,
    required String patientId,
    required int amountInPaise,
    required String patientName,
    required String contactNumber,
    required String description,
    Map<String, String>? notes,
  }) async {
    final link = await createPaymentLink(
      idToken: idToken,
      patientId: patientId,
      amountInPaise: amountInPaise,
      patientName: patientName,
      contactNumber: contactNumber,
      description: description,
      notes: notes,
    );
    await openInBrowser(link.url);
    return link;
  }
}
