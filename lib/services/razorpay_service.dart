import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// RazorpayConfig — store your keys here.
///
/// ⚠️  IMPORTANT: Never commit your key_secret to version control.
///     In production, fetch it from a secure backend instead.
/// ─────────────────────────────────────────────────────────────────────────────
class RazorpayConfig {
  static const String keyId = 'rzp_live_RseCm2t4lFlfMC';
  static const String keySecret = 'AFZDA4Niu4341bFSTBVYlQr4';
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
/// RazorpayService — creates links, polls status, opens browser.
/// ─────────────────────────────────────────────────────────────────────────────
class RazorpayService {
  static const String _baseUrl = 'https://api.razorpay.com/v1';

  // ── Shared auth header ────────────────────────────────────────────────────
  static Map<String, String> get _authHeaders {
    final credentials = base64Encode(
      utf8.encode('${RazorpayConfig.keyId}:${RazorpayConfig.keySecret}'),
    );
    return {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/json',
    };
  }

  /// Creates a Razorpay Payment Link and returns a [RazorpayPaymentLink].
  ///
  /// [amountInPaise] — amount in paise (₹1 = 100 paise)
  static Future<RazorpayPaymentLink> createPaymentLink({
    required int amountInPaise,
    required String patientName,
    required String contactNumber,
    required String description,
    Map<String, String>? notes,
  }) async {
    final body = jsonEncode({
      'amount': amountInPaise,
      'currency': 'INR',
      'description': description,
      'customer': {
        'name': patientName,
        'contact': contactNumber.startsWith('+') ? contactNumber : '+91$contactNumber',
      },
      'notify': {'sms': true},
      'reminder_enable': false,
      'notes': {
        'patient': patientName,
        ...?notes,
      },
    });

    final response = await http.post(
      Uri.parse('$_baseUrl/payment_links/'),
      headers: _authHeaders,
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final id = data['id'] as String?;
      final url = data['short_url'] as String?;
      if (id == null || url == null) {
        throw Exception('Invalid response from Razorpay');
      }
      return RazorpayPaymentLink(id: id, url: url);
    } else {
      final error = jsonDecode(response.body);
      debugPrint('Razorpay error: ${response.body}');
      throw Exception(
        error['error']?['description'] ?? 'Failed to create payment link',
      );
    }
  }

  /// Polls a payment link by [linkId] and returns its current [RazorpayPaymentStatus].
  ///
  /// Call this repeatedly (e.g. every 5 seconds) to detect when payment is complete.
  static Future<RazorpayPaymentStatus> getPaymentLinkStatus(String linkId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/payment_links/$linkId'),
      headers: _authHeaders,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'created';

      // Extract payment details if paid
      String? paymentId;
      String? method;
      DateTime? paidAt;
      int? amountPaid;

      final payments = data['payments'];
      if (payments != null && payments is List && payments.isNotEmpty) {
        final lastPayment = payments.last as Map<String, dynamic>;
        paymentId = lastPayment['payment_id'] as String?;
        method = lastPayment['method'] as String?;
        amountPaid = lastPayment['amount'] as int?;
        final paidAtRaw = lastPayment['paid_at'];
        if (paidAtRaw != null) {
          paidAt = DateTime.fromMillisecondsSinceEpoch(
            (paidAtRaw as int) * 1000,
          );
        }
      }

      return RazorpayPaymentStatus(
        status: status,
        paymentId: paymentId,
        method: method,
        paidAt: paidAt,
        amountPaid: amountPaid,
      );
    } else {
      debugPrint('Razorpay poll error: ${response.body}');
      // Don't throw — just return a "created" status so polling continues.
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
    required int amountInPaise,
    required String patientName,
    required String contactNumber,
    required String description,
    Map<String, String>? notes,
  }) async {
    final link = await createPaymentLink(
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
