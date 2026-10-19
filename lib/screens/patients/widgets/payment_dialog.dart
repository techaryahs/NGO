import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/service_locator.dart';
import '../../../utils/pricing_helper.dart';
import '../../../utils/upi_payment.dart';
import '../../../models/patient_model.dart';

class PaymentDialogResult {
  final bool payLater;
  final String? recordedPaymentId;
  const PaymentDialogResult({this.payLater = false, this.recordedPaymentId});
}

Future<PaymentDialogResult?> showPatientPaymentDialog({
  required BuildContext context,
  required String patientName,
  required String contactNumber,
  required int bedsCount,
  required int attendantsCount,
  required String? roomIdentifier,
  double alreadyPaid = 0,
  bool showPayLater = false,
  double? totalBillOverride,
  String? patientId,
}) => showDialog<PaymentDialogResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PatientPaymentDialog(
    patientName: patientName,
    patientId: patientId,
    total:
        totalBillOverride ??
        PricingHelper.calculateAdvanceAmount(
          (roomIdentifier ?? '').toUpperCase().endsWith('A') ||
              (roomIdentifier ?? '').toUpperCase().endsWith('B'),
          attendantsCount,
          bedsCount: bedsCount,
        ),
    alreadyPaid: alreadyPaid,
    showPayLater: showPayLater,
  ),
);

class _PatientPaymentDialog extends StatefulWidget {
  final String patientName;
  final String? patientId;
  final double total;
  final double alreadyPaid;
  final bool showPayLater;
  const _PatientPaymentDialog({
    required this.patientName,
    required this.patientId,
    required this.total,
    required this.alreadyPaid,
    required this.showPayLater,
  });
  @override
  State<_PatientPaymentDialog> createState() => _PatientPaymentDialogState();
}

class _PatientPaymentDialogState extends State<_PatientPaymentDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _receipt = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;
  String? _error;
  double get _pending =>
      (widget.total - widget.alreadyPaid).clamp(0, double.infinity);
  double? get _paying => double.tryParse(_amount.text.trim());
  @override
  void initState() {
    super.initState();
    _amount.text = _pending.toStringAsFixed(2);
    _amount.addListener(_amountChanged);
  }

  void _amountChanged() => setState(() {});
  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _receipt.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting || !_form.currentState!.validate()) return;
    if (widget.patientId == null) {
      setState(() => _error = 'Save the admission before recording payment.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final payment = PaymentModel(
        id: 'upi_${widget.patientId}_${_reference.text.trim().toUpperCase()}',
        amount: double.parse(UpiPayment.formatAmount(_paying!)),
        method: 'ONLINE',
        date: DateTime.now(),
        transactionId: _reference.text.trim().toUpperCase(),
        receiptNumber: _receipt.text.trim(),
        notes: _notes.text.trim(),
        totalAmount: widget.total,
        paidAmount: widget.alreadyPaid + _paying!,
        pendingAmount: (_pending - _paying!).clamp(0, double.infinity),
      );
      final id = await ServiceLocator().paymentService.recordPayment(
        patientId: widget.patientId!,
        patientName: widget.patientName,
        payment: payment,
      );
      if (mounted)
        Navigator.pop(context, PaymentDialogResult(recordedPaymentId: id));
    } catch (e) {
      if (mounted) setState(() => _error = 'Payment could not be recorded: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _paying;
    final validAmount =
        amount != null &&
        amount.isFinite &&
        amount >= 0.01 &&
        amount <= _pending;
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: const Text('Online UPI Payment'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.patientName),
                  Text('Pending: ₹${_pending.toStringAsFixed(2)}'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amount,
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount to collect (₹)',
                    ),
                    validator: (value) {
                      if (!validAmount)
                        return 'Enter a positive amount within the pending balance.';
                      if (!RegExp(
                        r'^\d+(?:\.\d{1,2})?$',
                      ).hasMatch(value!.trim())) {
                        return 'Use at most two decimal places.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  if (validAmount) ...[
                    Text(
                      'Scan QR & Pay ₹${UpiPayment.formatAmount(amount)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    QrImageView(
                      data: UpiPayment.uri(
                        amount,
                        note: 'Stay payment - ${widget.patientName}',
                      ),
                      size: 240,
                      backgroundColor: Colors.white,
                    ),
                  ],
                  const Text(
                    UpiPayment.payee,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SelectableText(UpiPayment.vpa),
                  const SizedBox(height: 16),
                  const Text(
                    'Confirm receipt in the NGO account before entering the reference. '
                    'This app does not verify payment with the bank.',
                  ),
                  TextFormField(
                    controller: _reference,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'UTR / UPI reference',
                    ),
                    validator: UpiPayment.validateReference,
                  ),
                  TextFormField(
                    controller: _receipt,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Receipt number (optional)',
                    ),
                  ),
                  TextFormField(
                    controller: _notes,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (widget.showPayLater)
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => Navigator.pop(
                      context,
                      const PaymentDialogResult(payLater: true),
                    ),
              child: const Text('Pay Later'),
            ),
          FilledButton(
            onPressed: _submitting ? null : _confirm,
            child: Text(
              _submitting ? 'Recording…' : 'Confirm received payment',
            ),
          ),
        ],
      ),
    );
  }
}
