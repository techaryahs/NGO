import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/service_locator.dart';
import '../../../utils/pricing_helper.dart';
import '../../../utils/upi_payment.dart';
import '../../../models/patient_model.dart';
import '../../../services/backend_api_service.dart';

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
  bool allowOfflineMethods = false,
  DateTime? checkoutAt,
}) {
  final attemptKey = UniqueKey();
  return showDialog<PaymentDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PatientPaymentDialog(
      key: attemptKey,
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
      allowOfflineMethods: allowOfflineMethods,
      checkoutAt: checkoutAt,
    ),
  );
}

class _PatientPaymentDialog extends StatefulWidget {
  final String patientName;
  final String? patientId;
  final double total;
  final double alreadyPaid;
  final bool showPayLater;
  final bool allowOfflineMethods;
  final DateTime? checkoutAt;
  const _PatientPaymentDialog({
    super.key,
    required this.patientName,
    required this.patientId,
    required this.total,
    required this.alreadyPaid,
    required this.showPayLater,
    required this.allowOfflineMethods,
    this.checkoutAt,
  });
  @override
  State<_PatientPaymentDialog> createState() => _PatientPaymentDialogState();
}

class _PatientPaymentDialogState extends State<_PatientPaymentDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController(text: '');
  final _receipt = TextEditingController(text: '');
  final _notes = TextEditingController();
  bool _submitting = false;
  // Keep retry metadata stable when a response is lost after server commit.
  DateTime _paymentDate = DateTime.now();
  final String _receiptId = 'receipt_${DateTime.now().microsecondsSinceEpoch}';
  String _method = 'ONLINE';
  String? _error;
  late double _total, _paid, _pending;
  String? _cycleId;
  bool _loadingBalance = false;
  bool _balanceReady = false;
  double? get _paying => double.tryParse(_amount.text.trim());
  @override
  void initState() {
    super.initState();
    _total = widget.total;
    _paid = widget.alreadyPaid;
    _pending = (_total - _paid).clamp(0, double.infinity);
    _amount.text = _pending.toStringAsFixed(2);
    _amount.addListener(_amountChanged);
    if (widget.patientId != null) {
      _loadBalance();
    } else {
      _balanceReady = true;
    }
  }

  Future<void> _loadBalance({bool preserveError = false}) async {
    setState(() {
      _loadingBalance = true;
      _balanceReady = false;
      if (!preserveError) _error = null;
    });
    try {
      final balance = await ServiceLocator().paymentService.collectionBalance(
        widget.patientId!,
        checkoutAt: widget.checkoutAt,
      );
      if (!mounted) return;
      setState(() {
        _total = balance.total;
        _paid = balance.paid;
        _pending = balance.due;
        _cycleId = balance.cycleId;
        _amount.text = _pending.toStringAsFixed(2);
        _balanceReady = true;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not load the current outstanding balance. Retry before collecting payment.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
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
    if (_submitting ||
        _loadingBalance ||
        !_balanceReady ||
        !_form.currentState!.validate()) {
      return;
    }
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
        id: _method == 'ONLINE'
            ? 'upi_${widget.patientId}_${_reference.text.trim().toUpperCase()}'
            : _receiptId,
        amount: double.parse(UpiPayment.formatAmount(_paying!)),
        method: _method,
        date: _paymentDate,
        cycleId: _cycleId,
        transactionId: _reference.text.trim().toUpperCase(),
        receiptNumber: _receipt.text.trim(),
        checkNumber: _method == 'check' ? _reference.text.trim() : null,
        notes: _notes.text.trim(),
        totalAmount: _total,
        paidAmount: _paid + _paying!,
        pendingAmount: (_pending - _paying!).clamp(0, double.infinity),
      );
      final id = await ServiceLocator().paymentService.recordPayment(
        patientId: widget.patientId!,
        patientName: widget.patientName,
        payment: payment,
        collectOutstanding: true,
        checkoutAt: widget.checkoutAt,
      );
      if (mounted) {
        Navigator.pop(context, PaymentDialogResult(recordedPaymentId: id));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Payment could not be recorded: $e');
      // A server rejection is definitive. A transport failure may follow COMMIT:
      // retain its amount/date/snapshot so retry can recover that same receipt.
      if (e is BackendApiException && e.statusCode == 409 && mounted) {
        await _loadBalance(preserveError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _paying;
    final validAmount =
        _balanceReady &&
        !_loadingBalance &&
        amount != null &&
        amount.isFinite &&
        amount >= 0.01 &&
        amount <= _pending;
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: Text(
          widget.allowOfflineMethods ? 'Record Payment' : 'Online UPI Payment',
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.patientName),
                  if (_loadingBalance) const LinearProgressIndicator(),
                  if (_balanceReady)
                    Text('Pending: ₹${_pending.toStringAsFixed(2)}'),
                  if (_balanceReady && validAmount)
                    Text(
                      'Remaining after payment: ₹${(_pending - amount).toStringAsFixed(2)}',
                    ),
                  if (widget.allowOfflineMethods) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ONLINE',
                          child: Text('UPI / Online'),
                        ),
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'check', child: Text('Cheque')),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() {
                              _method = value!;
                              _reference.clear();
                            }),
                    ),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              final selected = await showDatePicker(
                                context: context,
                                initialDate: _paymentDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (selected != null && mounted) {
                                setState(() => _paymentDate = selected);
                              }
                            },
                      child: Text(
                        'Payment date: ${_paymentDate.toIso8601String().split('T').first}',
                      ),
                    ),
                  ],
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
                      if (!validAmount) {
                        return 'Enter a positive amount within the pending balance.';
                      }
                      if (!RegExp(
                        r'^\d+(?:\.\d{1,2})?$',
                      ).hasMatch(value!.trim())) {
                        return 'Use at most two decimal places.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  if (validAmount && _method == 'ONLINE') ...[
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
                  if (_method == 'ONLINE')
                    const Text(
                      UpiPayment.payee,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (_method == 'ONLINE') const SelectableText(UpiPayment.vpa),
                  const SizedBox(height: 16),
                  if (_method == 'ONLINE')
                    const Text(
                      'Confirm receipt in the NGO account before entering the reference. '
                      'This app does not verify payment with the bank.',
                    ),
                  TextFormField(
                    controller: _reference,
                    autofillHints: null,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: _method == 'ONLINE'
                          ? 'UTR / UPI reference'
                          : 'Cheque / reference (optional)',
                    ),
                    validator: _method == 'ONLINE'
                        ? UpiPayment.validateReference
                        : null,
                  ),
                  TextFormField(
                    controller: _receipt,
                    autofillHints: null,
                    autocorrect: false,
                    enableSuggestions: false,
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
          if (!_balanceReady && !_loadingBalance && widget.patientId != null)
            TextButton(
              onPressed: _loadBalance,
              child: const Text('Retry balance'),
            ),
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
            onPressed: _submitting || _loadingBalance || !_balanceReady
                ? null
                : _confirm,
            child: Text(
              _submitting ? 'Recording…' : 'Confirm received payment',
            ),
          ),
        ],
      ),
    );
  }
}
