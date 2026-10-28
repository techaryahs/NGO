import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/patient_model.dart';
import '../../../services/service_locator.dart';
import '../../../utils/stay_billing.dart';

class BillingCorrectionDialog extends StatefulWidget {
  const BillingCorrectionDialog({super.key, required this.patient});
  final PatientModel patient;
  @override
  State<BillingCorrectionDialog> createState() =>
      _BillingCorrectionDialogState();
}

class _BillingCorrectionDialogState extends State<BillingCorrectionDialog> {
  final reason = TextEditingController(text: 'Billing correction');
  final selected = <String>{};
  List<Map<String, dynamic>>? days;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final snapshot = await ServiceLocator().backendApiService
          .financialSnapshot(widget.patient.id);
      final patient = PatientModel.fromMap(
        widget.patient.id,
        Map<String, dynamic>.from(snapshot['patient'] as Map),
      );
      final balance =
          patient.admissionBalances[StayBilling.currentCycle(patient)];
      if (balance is! Map || balance['reconciliationRequired'] == true) {
        throw StateError(
          'Resolve this admission’s financial review before correcting charges.',
        );
      }
      final rows = balance['dayCharges'];
      if (rows is! List) {
        throw StateError(
          'This admission does not have an editable daily bill.',
        );
      }
      if (mounted) {
        setState(
          () => days = rows
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> save() async {
    if (saving || days == null || selected.isEmpty) return;
    if (reason.text.trim().isEmpty) {
      setState(() => error = 'Enter a reason.');
      return;
    }
    final chosen = days!.where((d) => selected.contains(d['day'])).toList();
    final total = chosen.fold<double>(
      0,
      (sum, d) => sum + (d['amount'] as num).toDouble(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm billing correction'),
        content: Text(
          'Exclude ${chosen.length} date(s) totalling ₹${total.toStringAsFixed(2)}? Existing payments will remain recorded. Any refund due must be handled separately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ServiceLocator().backendApiService.correctBilling(
        widget.patient.id,
        reason: reason.text.trim(),
        dates: [
          for (final d in chosen)
            {'day': d['day'], 'stayId': d['stayId'], 'amount': d['amount']},
        ],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not save correction: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (days ?? [])
        .where((d) => selected.contains(d['day']))
        .fold<double>(0, (sum, d) => sum + (d['amount'] as num).toDouble());
    return AlertDialog(
      title: const Text('Billing Correction'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select the dates whose charges should be excluded.'),
            const SizedBox(height: 8),
            if (days == null && error == null)
              const Center(child: CircularProgressIndicator())
            else if (days != null)
              Flexible(
                child: SizedBox(
                  height: 300,
                  child: ListView(
                    children: [
                      for (final day in days!)
                        CheckboxListTile(
                          value: selected.contains(day['day']),
                          onChanged:
                              saving ||
                                  day['eligible'] != true ||
                                  day['excluded'] == true
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    selected.add(day['day'] as String);
                                  } else {
                                    selected.remove(day['day']);
                                  }
                                }),
                          title: Text(
                            DateFormat(
                              'dd MMM yyyy',
                            ).format(DateTime.parse(day['day'] as String)),
                          ),
                          subtitle: day['excluded'] == true
                              ? const Text('Already corrected')
                              : day['eligible'] != true
                              ? const Text('Not available for correction')
                              : null,
                          secondary: Text(
                            '₹${(day['amount'] as num).toStringAsFixed(2)}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Text('Selected total: ₹${total.toStringAsFixed(2)}'),
            TextField(
              controller: reason,
              enabled: !saving,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving || selected.isEmpty ? null : save,
          child: Text(saving ? 'Saving…' : 'Review correction'),
        ),
      ],
    );
  }
}
