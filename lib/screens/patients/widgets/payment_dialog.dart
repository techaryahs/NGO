import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/razorpay_service.dart';

// ── Pricing constants ─────────────────────────────────────────────────────────
const double _kBedRatePerDay = 500.0;
const double _kAttendantRatePerDay = 150.0;
const int _kDefaultDays = 7;

// ── Poll interval ─────────────────────────────────────────────────────────────
const Duration _kPollInterval = Duration(seconds: 5);

// ─────────────────────────────────────────────────────────────────────────────
// Public helper — returns true if user confirmed/paid, false if cancelled.
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> showPatientPaymentDialog({
  required BuildContext context,
  required String patientName,
  required String contactNumber,
  required int bedsCount,
  required int attendantsCount,
  required String? roomIdentifier,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PatientPaymentDialog(
      patientName: patientName,
      contactNumber: contactNumber,
      bedsCount: bedsCount,
      attendantsCount: attendantsCount,
      roomIdentifier: roomIdentifier,
    ),
  ).then((v) => v ?? false);
}

// ─────────────────────────────────────────────────────────────────────────────
enum _PaymentStep { invoice, waiting, done }

// ─────────────────────────────────────────────────────────────────────────────
class _PatientPaymentDialog extends StatefulWidget {
  final String patientName;
  final String contactNumber;
  final int bedsCount;
  final int attendantsCount;
  final String? roomIdentifier;

  const _PatientPaymentDialog({
    required this.patientName,
    required this.contactNumber,
    required this.bedsCount,
    required this.attendantsCount,
    required this.roomIdentifier,
  });

  @override
  State<_PatientPaymentDialog> createState() => _PatientPaymentDialogState();
}

class _PatientPaymentDialogState extends State<_PatientPaymentDialog> {
  _PaymentStep _step = _PaymentStep.invoice;
  bool _isCreatingLink = false;
  RazorpayPaymentLink? _paymentLink;
  RazorpayPaymentStatus? _paymentStatus;
  String? _error;

  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPolls = 72; // 72 × 5s = 6 minutes timeout

  // ── Amounts ────────────────────────────────────────────────────────────────
  double get _bedTotal => widget.bedsCount * _kBedRatePerDay * _kDefaultDays;
  double get _attendantTotal =>
      widget.attendantsCount * _kAttendantRatePerDay * _kDefaultDays;
  double get _grandTotal => _bedTotal + _attendantTotal;
  int get _amountInPaise => (_grandTotal * 100).round();

  String _fmt(double v) {
    if (v >= 1000) {
      return '₹${v.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'),
            (m) => '${m[1]},',
          )}';
    }
    return '₹${v.toStringAsFixed(0)}';
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Open Razorpay ──────────────────────────────────────────────────────────
  Future<void> _openRazorpay() async {
    setState(() {
      _isCreatingLink = true;
      _error = null;
    });

    try {
      final link = await RazorpayService.createAndOpen(
        amountInPaise: _amountInPaise,
        patientName: widget.patientName,
        contactNumber: widget.contactNumber,
        description:
            'Patient Admission — ${widget.patientName} (Room ${widget.roomIdentifier ?? 'N/A'})',
        notes: {
          'beds': widget.bedsCount.toString(),
          'attendants': widget.attendantsCount.toString(),
          'room': widget.roomIdentifier ?? 'N/A',
        },
      );

      setState(() {
        _paymentLink = link;
        _step = _PaymentStep.waiting;
      });

      _startPolling(link.id);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCreatingLink = false);
    }
  }

  // ── Polling ────────────────────────────────────────────────────────────────
  void _startPolling(String linkId) {
    _pollCount = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kPollInterval, (_) => _poll(linkId));
  }

  Future<void> _poll(String linkId) async {
    _pollCount++;
    if (_pollCount > _maxPolls) {
      _pollTimer?.cancel();
      return;
    }

    try {
      final status = await RazorpayService.getPaymentLinkStatus(linkId);
      if (!mounted) return;

      if (status.isPaid) {
        _pollTimer?.cancel();
        setState(() {
          _paymentStatus = status;
          _step = _PaymentStep.done;
        });

        // Auto-close after 3 seconds showing the receipt
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    } catch (_) {
      // Silently ignore poll errors — keep trying
    }
  }

  // ── Manual confirm (fallback if auto-poll misses) ──────────────────────────
  void _confirmManually() {
    _pollTimer?.cancel();
    setState(() => _step = _PaymentStep.done);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  // ── Reopen link ────────────────────────────────────────────────────────────
  Future<void> _reopenLink() async {
    if (_paymentLink == null) return;
    try {
      await RazorpayService.openInBrowser(_paymentLink!.url);
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(step: _step),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _step == _PaymentStep.invoice
                    ? _InvoiceBody(
                        key: const ValueKey('invoice'),
                        patientName: widget.patientName,
                        bedsCount: widget.bedsCount,
                        attendantsCount: widget.attendantsCount,
                        bedTotal: _bedTotal,
                        attendantTotal: _attendantTotal,
                        grandTotal: _grandTotal,
                        fmt: _fmt,
                        error: _error,
                        isLoading: _isCreatingLink,
                        onPay: _openRazorpay,
                        onSkip: () => Navigator.of(context).pop(true),
                        onCancel: () => Navigator.of(context).pop(false),
                      )
                    : _step == _PaymentStep.waiting
                        ? _WaitingBody(
                            key: const ValueKey('waiting'),
                            paymentLink: _paymentLink!,
                            grandTotal: _grandTotal,
                            fmt: _fmt,
                            pollCount: _pollCount,
                            onReopen: _reopenLink,
                            onConfirmManually: _confirmManually,
                            onCancel: () {
                              _pollTimer?.cancel();
                              Navigator.of(context).pop(false);
                            },
                          )
                        : _ReceiptBody(
                            key: const ValueKey('done'),
                            patientName: widget.patientName,
                            grandTotal: _grandTotal,
                            fmt: _fmt,
                            status: _paymentStatus,
                            roomIdentifier: widget.roomIdentifier,
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final _PaymentStep step;
  const _Header({required this.step});

  @override
  Widget build(BuildContext context) {
    final isDone = step == _PaymentStep.done;
    final icon = isDone ? Icons.check_circle_rounded : Icons.payment_rounded;
    final title = isDone ? 'Payment Successful' : 'Patient Payment';
    final sub = step == _PaymentStep.invoice
        ? 'Review the fee breakdown before proceeding'
        : step == _PaymentStep.waiting
            ? 'Waiting for payment — browser has opened'
            : 'Payment confirmed — saving patient record…';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: isDone ? const Color(0xFF3B6D11) : const Color(0xFFF4F9F0),
        border: Border(
          bottom: BorderSide(
            color: isDone ? Colors.transparent : const Color(0xFFC0DD97),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDone
                  ? Colors.white.withValues(alpha: 0.25)
                  : const Color(0xFFEAF3DE),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDone ? Colors.white30 : const Color(0xFFC0DD97),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: isDone ? Colors.white : const Color(0xFF3B6D11),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDone ? Colors.white : const Color(0xFF27500A),
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDone
                        ? Colors.white70
                        : const Color(0xFF639922),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice step
// ─────────────────────────────────────────────────────────────────────────────
class _InvoiceBody extends StatelessWidget {
  final String patientName;
  final int bedsCount;
  final int attendantsCount;
  final double bedTotal;
  final double attendantTotal;
  final double grandTotal;
  final String Function(double) fmt;
  final String? error;
  final bool isLoading;
  final VoidCallback onPay;
  final VoidCallback onSkip;
  final VoidCallback onCancel;

  const _InvoiceBody({
    super.key,
    required this.patientName,
    required this.bedsCount,
    required this.attendantsCount,
    required this.bedTotal,
    required this.attendantTotal,
    required this.grandTotal,
    required this.fmt,
    required this.error,
    required this.isLoading,
    required this.onPay,
    required this.onSkip,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient badge
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3DE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC0DD97)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 16, color: Color(0xFF3B6D11)),
                const SizedBox(width: 8),
                Text(
                  patientName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF27500A)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Breakdown
          _SectionLabel('Fee breakdown'),
          const SizedBox(height: 10),
          _LineItem(
            icon: Icons.bed_outlined,
            label:
                'Beds ($bedsCount × ₹${_kBedRatePerDay.toInt()}/day × $_kDefaultDays days)',
            amount: fmt(bedTotal),
          ),
          const SizedBox(height: 8),
          _LineItem(
            icon: Icons.person_outline_rounded,
            label:
                'Attendants ($attendantsCount × ₹${_kAttendantRatePerDay.toInt()}/day × $_kDefaultDays days)',
            amount: fmt(attendantTotal),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Color(0xFFC0DD97), thickness: 0.8),
          ),

          // Total row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Amount',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF27500A))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B6D11),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  fmt(grandTotal),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '* 7-day estimate at standard rates. Actual may vary.',
            style: TextStyle(fontSize: 10, color: Color(0xFF97C459)),
          ),

          // Error box
          if (error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCC02)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Color(0xFF856404)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(error!,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF856404))),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Buttons
          Row(
            children: [
              TextButton(
                onPressed: isLoading ? null : onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF639922),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFC0DD97)),
                  ),
                ),
                child:
                    const Text('Cancel', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: isLoading ? null : onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF888888),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                child: const Text('Skip payment',
                    style: TextStyle(
                        fontSize: 12,
                        decoration: TextDecoration.underline)),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: isLoading ? null : onPay,
                icon: isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white)))
                    : const Icon(Icons.open_in_browser_rounded, size: 16),
                label: Text(
                    isLoading ? 'Creating link…' : 'Pay with Razorpay',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B6D11),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waiting step — with live polling indicator
// ─────────────────────────────────────────────────────────────────────────────
class _WaitingBody extends StatelessWidget {
  final RazorpayPaymentLink paymentLink;
  final double grandTotal;
  final String Function(double) fmt;
  final int pollCount;
  final VoidCallback onReopen;
  final VoidCallback onConfirmManually;
  final VoidCallback onCancel;

  const _WaitingBody({
    super.key,
    required this.paymentLink,
    required this.grandTotal,
    required this.fmt,
    required this.pollCount,
    required this.onReopen,
    required this.onConfirmManually,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Animated waiting card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F9F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC0DD97)),
            ),
            child: Column(
              children: [
                // Pulsing icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3DE),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF3B6D11), width: 2),
                  ),
                  child: const Icon(Icons.open_in_new_rounded,
                      color: Color(0xFF3B6D11), size: 28),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Waiting for payment…',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF27500A)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Complete the Razorpay checkout in your browser.\nThis screen will update automatically when payment is done.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: Color(0xFF639922)),
                ),
                const SizedBox(height: 14),

                // Live polling indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B6D11).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF3B6D11)),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Auto-checking every 5s (check #$pollCount)',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF3B6D11),
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onReopen,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Reopen payment link'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF3B6D11),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF639922),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFC0DD97)),
                  ),
                ),
                child:
                    const Text('Cancel', style: TextStyle(fontSize: 13)),
              ),
              const Spacer(),
              // Manual confirm fallback
              TextButton(
                onPressed: onConfirmManually,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF888888),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                child: const Text(
                  'I paid manually →',
                  style: TextStyle(
                      fontSize: 12,
                      decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt step — shown after payment is auto-detected or manually confirmed
// ─────────────────────────────────────────────────────────────────────────────
class _ReceiptBody extends StatelessWidget {
  final String patientName;
  final double grandTotal;
  final String Function(double) fmt;
  final RazorpayPaymentStatus? status;
  final String? roomIdentifier;

  const _ReceiptBody({
    super.key,
    required this.patientName,
    required this.grandTotal,
    required this.fmt,
    required this.status,
    required this.roomIdentifier,
  });

  String _methodLabel(String? m) {
    switch (m?.toLowerCase()) {
      case 'upi':
        return 'UPI';
      case 'card':
        return 'Card';
      case 'netbanking':
        return 'Net Banking';
      case 'wallet':
        return 'Wallet';
      case 'emi':
        return 'EMI';
      default:
        return m ?? 'Online';
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final now = dt.toLocal();
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '${now.day} ${months[now.month - 1]} ${now.year}  $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final paymentId = status?.paymentId;
    final isAutoDetected = status != null && paymentId != null;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Success icon
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFF3B6D11),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 14),
          Text(
            fmt(grandTotal),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF27500A),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Payment received successfully',
            style: TextStyle(fontSize: 13, color: Color(0xFF639922)),
          ),
          const SizedBox(height: 24),

          // Receipt card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F9F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC0DD97)),
            ),
            child: Column(
              children: [
                // Receipt header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF3DE),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          size: 15, color: Color(0xFF3B6D11)),
                      const SizedBox(width: 6),
                      const Text(
                        'PAYMENT RECEIPT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3B6D11),
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      if (isAutoDetected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B6D11),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'AUTO-VERIFIED',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),

                // Receipt rows
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _ReceiptRow('Patient', patientName),
                      _ReceiptRow('Room', roomIdentifier ?? '—'),
                      _ReceiptRow('Method',
                          _methodLabel(status?.method)),
                      _ReceiptRow('Date',
                          _formatDate(status?.paidAt ?? DateTime.now())),
                      _ReceiptRow('Amount', fmt(grandTotal), bold: true),
                      if (paymentId != null) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                              color: Color(0xFFC0DD97), thickness: 0.8),
                        ),
                        _PaymentIdRow(paymentId),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'Patient record is being saved. This dialog will close automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF97C459)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt row widgets
// ─────────────────────────────────────────────────────────────────────────────
class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _ReceiptRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF888888)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF27500A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentIdRow extends StatelessWidget {
  final String paymentId;
  const _PaymentIdRow(this.paymentId);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 90,
          child: Text('Payment ID',
              style:
                  TextStyle(fontSize: 12, color: Color(0xFF888888))),
        ),
        Expanded(
          child: Text(
            paymentId,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3B6D11),
              fontFamily: 'monospace',
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: paymentId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment ID copied'),
                backgroundColor: Color(0xFF3B6D11),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: const Icon(Icons.copy_rounded,
              size: 14, color: Color(0xFF639922)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF639922),
        letterSpacing: 0.6,
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  const _LineItem(
      {required this.icon, required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF639922)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: Color(0xFF27500A)))),
        Text(amount,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A))),
      ],
    );
  }
}
