import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/patient_model.dart';
import '../../../services/razorpay_service.dart';

// ── Pricing constants ─────────────────────────────────────────────────────────
const double _kBedRatePerDay = 500.0;
const double _kAttendantRatePerDay = 150.0;
const int _kDefaultDays = 7;

// ── Poll interval ─────────────────────────────────────────────────────────────
const Duration _kPollInterval = Duration(seconds: 5);

// ── Payment Methods ───────────────────────────────────────────────────────────
enum PaymentMethod { cash, check, online }

// ─────────────────────────────────────────────────────────────────────────────
// Public helper — returns PaymentModel if user confirmed/paid, null if cancelled.
// ─────────────────────────────────────────────────────────────────────────────
Future<PaymentModel?> showPatientPaymentDialog({
  required BuildContext context,
  required String patientName,
  required String contactNumber,
  required int bedsCount,
  required int attendantsCount,
  required String? roomIdentifier,
}) {
  return showDialog<PaymentModel?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PatientPaymentDialog(
      patientName: patientName,
      contactNumber: contactNumber,
      bedsCount: bedsCount,
      attendantsCount: attendantsCount,
      roomIdentifier: roomIdentifier,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
enum _PaymentStep { selectMethod, process, done }

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
  _PaymentStep _step = _PaymentStep.selectMethod;
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  
  // Forms
  final _receiptController = TextEditingController();
  final _checkNoController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _notesController = TextEditingController();

  // Online / Razorpay
  bool _isCreatingLink = false;
  RazorpayPaymentLink? _paymentLink;
  String? _error;
  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPolls = 72;

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

  @override
  void dispose() {
    _pollTimer?.cancel();
    _receiptController.dispose();
    _checkNoController.dispose();
    _bankNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Online Logic ──────────────────────────────────────────────────────────
  Future<void> _startOnlinePayment() async {
    setState(() {
      _isCreatingLink = true;
      _error = null;
      _step = _PaymentStep.process;
    });

    try {
      final link = await RazorpayService.createPaymentLink(
        amountInPaise: _amountInPaise,
        patientName: widget.patientName,
        contactNumber: widget.contactNumber,
        description:
            'Admission — ${widget.patientName} (Room ${widget.roomIdentifier ?? 'N/A'})',
        notes: {
          'beds': widget.bedsCount.toString(),
          'attendants': widget.attendantsCount.toString(),
          'room': widget.roomIdentifier ?? 'N/A',
        },
      );

      setState(() {
        _paymentLink = link;
      });

      _startPolling(link.id);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _step = _PaymentStep.selectMethod;
      });
    } finally {
      if (mounted) setState(() => _isCreatingLink = false);
    }
  }

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
        _onPaymentSuccess(
          transactionId: status.paymentId,
          methodName: 'Online (Razorpay - ${status.method ?? 'UPI'})',
        );
      }
    } catch (_) {}
  }

  void _onPaymentSuccess({String? transactionId, String? methodName}) {
    final payment = PaymentModel(
      id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
      amount: _grandTotal,
      method: methodName ?? _selectedMethod.name.toUpperCase(),
      date: DateTime.now(),
      receiptNumber: _receiptController.text.trim().isEmpty ? null : _receiptController.text.trim(),
      checkNumber: _checkNoController.text.trim().isEmpty ? null : _checkNoController.text.trim(),
      bankName: _bankNameController.text.trim().isEmpty ? null : _bankNameController.text.trim(),
      transactionId: transactionId,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    setState(() => _step = _PaymentStep.done);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop(payment);
    });
  }

  void _confirmManual() {
    if (_selectedMethod == PaymentMethod.online) {
      _onPaymentSuccess(transactionId: 'MANUAL_ONLINE', methodName: 'Online (QR Code)');
    } else if (_selectedMethod == PaymentMethod.cash) {
      if (_receiptController.text.trim().isEmpty) {
        setState(() => _error = 'Please enter receipt number');
        return;
      }
      _onPaymentSuccess(methodName: 'Cash');
    } else {
      if (_checkNoController.text.trim().isEmpty) {
        setState(() => _error = 'Please enter check number');
        return;
      }
      _onPaymentSuccess(methodName: 'Check');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(step: _step),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_step == _PaymentStep.selectMethod) {
      return _SelectMethodBody(
        patientName: widget.patientName,
        grandTotal: _grandTotal,
        fmt: _fmt,
        selectedMethod: _selectedMethod,
        error: _error,
        onMethodChanged: (m) => setState(() => _selectedMethod = m),
        onProceed: () {
          if (_selectedMethod == PaymentMethod.online) {
            _startOnlinePayment();
          } else {
            setState(() => _step = _PaymentStep.process);
          }
        },
        onCancel: () => Navigator.of(context).pop(null),
      );
    } else if (_step == _PaymentStep.process) {
      return _ProcessBody(
        method: _selectedMethod,
        patientName: widget.patientName,
        grandTotal: _grandTotal,
        fmt: _fmt,
        paymentLink: _paymentLink,
        pollCount: _pollCount,
        error: _error,
        isLoading: _isCreatingLink,
        receiptController: _receiptController,
        checkNoController: _checkNoController,
        bankNameController: _bankNameController,
        notesController: _notesController,
        onConfirm: _confirmManual,
        onBack: () => setState(() => _step = _PaymentStep.selectMethod),
      );
    } else {
      return _SuccessBody(
        fmt: _fmt,
        amount: _grandTotal,
        method: _selectedMethod,
      );
    }
  }
}

class _Header extends StatelessWidget {
  final _PaymentStep step;
  const _Header({required this.step});

  @override
  Widget build(BuildContext context) {
    final isDone = step == _PaymentStep.done;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDone ? const Color(0xFF3B6D11) : const Color(0xFFF8FBF4),
        border: Border(bottom: BorderSide(color: isDone ? Colors.transparent : const Color(0xFFEAF3DE))),
      ),
      child: Row(
        children: [
          Icon(isDone ? Icons.check_circle_rounded : Icons.payments_rounded, color: isDone ? Colors.white : const Color(0xFF3B6D11), size: 28),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isDone ? 'Payment Confirmed' : 'Payment Collection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDone ? Colors.white : const Color(0xFF27500A))),
              Text(isDone ? 'The transaction has been recorded' : 'Select a payment method to proceed', style: TextStyle(fontSize: 12, color: isDone ? Colors.white70 : const Color(0xFF639922))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectMethodBody extends StatelessWidget {
  final String patientName;
  final double grandTotal;
  final String Function(double) fmt;
  final PaymentMethod selectedMethod;
  final String? error;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final VoidCallback onProceed;
  final VoidCallback onCancel;

  const _SelectMethodBody({required this.patientName, required this.grandTotal, required this.fmt, required this.selectedMethod, this.error, required this.onMethodChanged, required this.onProceed, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoTile(label: 'Patient', value: patientName, icon: Icons.person_outline),
          const SizedBox(height: 12),
          _InfoTile(label: 'Total Amount', value: fmt(grandTotal), icon: Icons.currency_rupee, isBold: true),
          const SizedBox(height: 24),
          const Text('SELECT PAYMENT METHOD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF639922), letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: [
              _MethodCard(method: PaymentMethod.cash, selected: selectedMethod == PaymentMethod.cash, label: 'Cash', icon: Icons.money_rounded, onTap: () => onMethodChanged(PaymentMethod.cash)),
              const SizedBox(width: 12),
              _MethodCard(method: PaymentMethod.check, selected: selectedMethod == PaymentMethod.check, label: 'Check', icon: Icons.account_balance_wallet_rounded, onTap: () => onMethodChanged(PaymentMethod.check)),
              const SizedBox(width: 12),
              _MethodCard(method: PaymentMethod.online, selected: selectedMethod == PaymentMethod.online, label: 'Online / QR', icon: Icons.qr_code_rounded, onTap: () => onMethodChanged(PaymentMethod.online)),
            ],
          ),
          if (error != null) ...[const SizedBox(height: 16), Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12))],
          const SizedBox(height: 32),
          Row(
            children: [
              TextButton(onPressed: onCancel, child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              const Spacer(),
              ElevatedButton(onPressed: onProceed, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Continue →', style: TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProcessBody extends StatelessWidget {
  final PaymentMethod method;
  final String patientName;
  final double grandTotal;
  final String Function(double) fmt;
  final RazorpayPaymentLink? paymentLink;
  final int pollCount;
  final String? error;
  final bool isLoading;
  final TextEditingController receiptController;
  final TextEditingController checkNoController;
  final TextEditingController bankNameController;
  final TextEditingController notesController;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  const _ProcessBody({required this.method, required this.patientName, required this.grandTotal, required this.fmt, this.paymentLink, required this.pollCount, this.error, required this.isLoading, required this.receiptController, required this.checkNoController, required this.bankNameController, required this.notesController, required this.onConfirm, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (method == PaymentMethod.online) ...[
            if (isLoading) const Center(child: CircularProgressIndicator())
            else ...[
              const Text('Scan QR Code to Pay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFEAF3DE)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(
                  'assets/images/payment_qr.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 200,
                      height: 200,
                      color: Colors.grey[100],
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'payment_qr.png not found\nin assets/images/',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Text('OR use the link below', style: TextStyle(fontSize: 12, color: Colors.grey)),
              if (paymentLink != null) TextButton(onPressed: () => RazorpayService.openInBrowser(paymentLink!.url), child: const Text('Open Razorpay Checkout')),
              Text('Checking payment status... (#$pollCount)', style: const TextStyle(fontSize: 10, color: Color(0xFF639922))),
            ],
          ] else if (method == PaymentMethod.cash) ...[
            _TextField(label: 'Receipt Number', controller: receiptController, icon: Icons.receipt_long_rounded),
          ] else ...[
            _TextField(label: 'Check Number', controller: checkNoController, icon: Icons.pin_rounded),
            const SizedBox(height: 12),
            _TextField(label: 'Bank Name', controller: bankNameController, icon: Icons.account_balance_rounded),
          ],
          const SizedBox(height: 12),
          _TextField(label: 'Notes (Optional)', controller: notesController, icon: Icons.notes_rounded, maxLines: 2),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(onPressed: onBack, child: const Text('← Back')),
              const Spacer(),
              ElevatedButton(onPressed: onConfirm, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(method == PaymentMethod.online ? 'Confirm Manually' : 'Save Payment')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuccessBody extends StatelessWidget {
  final String Function(double) fmt;
  final double amount;
  final PaymentMethod method;

  const _SuccessBody({required this.fmt, required this.amount, required this.method});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF3B6D11), size: 80),
          const SizedBox(height: 24),
          Text(fmt(amount), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF27500A))),
          const Text('Payment Recorded Successfully', style: TextStyle(color: Color(0xFF639922), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isBold;

  const _InfoTile({required this.label, required this.value, required this.icon, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FBF4), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF3B6D11)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF639922))),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.w700 : FontWeight.w600, color: const Color(0xFF27500A))),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _MethodCard({required this.method, required this.selected, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(color: selected ? const Color(0xFF3B6D11) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? const Color(0xFF3B6D11) : const Color(0xFFEAF3DE), width: 2)),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : const Color(0xFF3B6D11), size: 28),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xFF27500A), fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final int maxLines;

  const _TextField({required this.label, required this.controller, required this.icon, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF3B6D11)),
        filled: true,
        fillColor: const Color(0xFFF8FBF4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3B6D11))),
      ),
    );
  }
}
