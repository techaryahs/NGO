import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/patient_model.dart';
import '../../../services/service_locator.dart';

Future<void> showRefundDialog(
  BuildContext context,
  PatientModel patient, {
  String? cycleId,
}) async {
  await showDialog<bool>(
    context: context,
    builder: (_) => RefundDialog(patient: patient, cycleId: cycleId),
  );
}

class RefundDialog extends StatefulWidget {
  final PatientModel patient;
  final String? cycleId;
  const RefundDialog({super.key, required this.patient, this.cycleId});
  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  final amount = TextEditingController(),
      receipt = TextEditingController(),
      transaction = TextEditingController();
  Map<String, dynamic> balances = {};
  String? cycle, error;
  String method = 'cash';
  DateTime date = DateTime.now();
  bool loading = true, saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final updates = await ServiceLocator().paymentService.billingUpdates(
        widget.patient.id,
      );
      balances =
          Map<String, dynamic>.from(
            updates['patients/${widget.patient.id}/admissionBalances'] as Map,
          )..removeWhere(
            (_, value) => value is! Map || (value['refundDue'] as num) <= 0.005,
          );
      cycle = balances.containsKey(widget.cycleId)
          ? widget.cycleId
          : balances.keys.firstOrNull;
      if (cycle != null)
        amount.text = (balances[cycle]['refundDue'] as num).toStringAsFixed(2);
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    amount.dispose();
    receipt.dispose();
    transaction.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final value = double.tryParse(amount.text);
      if (value == null || !value.isFinite || value <= 0 || cycle == null)
        throw ArgumentError('Enter a valid refund amount');
      setState(() {
        saving = true;
        error = null;
      });
      await ServiceLocator().paymentService.recordRefund(
        patientId: widget.patient.id,
        cycleId: cycle!,
        amount: value,
        date: date,
        method: method,
        receiptNumber: receipt.text,
        transactionId: transaction.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Record refund paid'),
      content: SizedBox(
        width: 440,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Record money already returned to the patient. This updates the balance and adds a refund to the transaction ledger.',
                    ),
                    if (balances.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No excess payment is available to refund.',
                        ),
                      ),
                    if (balances.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: cycle,
                        decoration: const InputDecoration(
                          labelText: 'Admission',
                        ),
                        items: balances.keys
                            .map(
                              (id) => DropdownMenuItem(
                                value: id,
                                child: Text(
                                  '${DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0))} · ₹${(balances[id]['refundDue'] as num).toStringAsFixed(2)} excess',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (value) => setState(() {
                                cycle = value;
                                amount.text =
                                    (balances[cycle]['refundDue'] as num)
                                        .toStringAsFixed(2);
                              }),
                      ),
                      TextField(
                        controller: amount,
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Refund amount',
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: method,
                        decoration: const InputDecoration(
                          labelText: 'Refund method',
                        ),
                        items: ['cash', 'online', 'check']
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (value) => setState(() => method = value!),
                      ),
                      TextField(
                        controller: receipt,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Refund receipt number',
                        ),
                      ),
                      TextField(
                        controller: transaction,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Transaction / cheque number',
                        ),
                      ),
                      TextButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final selected = await showDatePicker(
                                  context: context,
                                  initialDate: date,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now(),
                                );
                                if (selected != null && mounted)
                                  setState(() => date = selected);
                              },
                        child: Text(
                          'Refund date: ${DateFormat('dd MMM yyyy').format(date)}',
                        ),
                      ),
                    ],
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving || loading || cycle == null ? null : _save,
          child: Text(saving ? 'Recording…' : 'Record refund paid'),
        ),
      ],
    ),
  );
}
