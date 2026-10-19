import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/patient_model.dart';
import '../../../services/service_locator.dart';
import '../../../services/backend_api_service.dart';

Future<bool?> showRefundDialog(
  BuildContext context,
  PatientModel patient, {
  String? cycleId,
}) async {
  return await showDialog<bool>(
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
  final String _requestId = 'refund_${DateTime.now().microsecondsSinceEpoch}';
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
      if (cycle != null) {
        amount.text = (balances[cycle]['refundDue'] as num).toStringAsFixed(2);
      }
    } catch (e) {
      if (e is BackendApiException && e.serverMessage != null) {
        error = e.serverMessage;
      } else if (e is HttpException && e.message.isNotEmpty) {
        error = e.message;
      } else {
        error = e.toString();
      }
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
      if (value == null || !value.isFinite || value <= 0 || cycle == null) {
        throw ArgumentError('Enter a valid refund amount');
      }
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
        requestId: _requestId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund recorded successfully'),
            backgroundColor: Color(0xFF3B6D11),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (e is BackendApiException && e.serverMessage != null) {
          msg = e.serverMessage!;
        } else if (e is HttpException && e.message.isNotEmpty) {
          msg = e.message;
        } else if (e is ArgumentError && e.message != null) {
          msg = e.message.toString();
        } else if (e is StateError) {
          msg = e.message;
        }
        setState(() => error = msg);
      }
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
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
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
                                  overflow: TextOverflow.ellipsis,
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: amount,
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Refund amount',
                          prefixText: '₹ ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: method,
                        decoration: const InputDecoration(
                          labelText: 'Refund method',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'cash',
                            child: Text('Cash'),
                          ),
                          DropdownMenuItem(
                            value: 'online',
                            child: Text('UPI QR / Online'),
                          ),
                          DropdownMenuItem(
                            value: 'check',
                            child: Text('Cheque / Bank Transfer'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setState(() => method = value!),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: receipt,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Refund receipt number (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: transaction,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Transaction / reference number (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_rounded, size: 16),
                        onPressed: saving
                            ? null
                            : () async {
                                final selected = await showDatePicker(
                                  context: context,
                                  initialDate: date,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now(),
                                );
                                if (selected != null && mounted) {
                                  setState(() => date = selected);
                                }
                              },
                        label: Text(
                          'Refund date: ${DateFormat('dd MMM yyyy').format(date)}',
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFCDD2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
