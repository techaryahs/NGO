import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/patient_model.dart';
import '../../models/stay_model.dart';
import '../../services/service_locator.dart';
import '../patients/widgets/refund_dialog.dart';

Future<void> showPatientFinancialDialog(
  BuildContext context,
  PatientModel patient,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => PatientFinancialDialog(initialPatient: patient),
  );
}

class PatientFinancialDialog extends StatefulWidget {
  final PatientModel initialPatient;
  const PatientFinancialDialog({super.key, required this.initialPatient});

  @override
  State<PatientFinancialDialog> createState() => _PatientFinancialDialogState();
}

class _PatientFinancialDialogState extends State<PatientFinancialDialog> {
  late PatientModel _patient;
  Map<String, dynamic> _balances = {};
  List<StayModel> _stays = [];
  List<Map<String, dynamic>> _ledger = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _patient = widget.initialPatient;
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final paymentService = ServiceLocator().paymentService;
      final billing = await paymentService.billingUpdates(_patient.id);
      final stayRows = billing['financialSnapshot/stays'];
      final stays = stayRows is List
          ? [
              for (final row in stayRows)
                StayModel.fromMap(
                  row['id'].toString(),
                  Map<String, dynamic>.from(row as Map),
                ),
            ]
          : await paymentService.loadStays(_patient.id);

      final dynamic rawBalances =
          (billing['patients/${_patient.id}/admissionBalances'] as Map?) ?? {};
      final balancesMap = Map<String, dynamic>.from(rawBalances);

      // Fetch fresh patient data to get updated balances and payments
      PatientModel freshPatient = _patient;
      try {
        final projected = billing['patients/${_patient.id}/id'];
        final p = projected != null
            ? PatientModel.fromMap(_patient.id, {
                for (final entry in billing.entries.where(
                  (entry) => entry.key.startsWith('patients/${_patient.id}/'),
                ))
                  entry.key.split('/').last: entry.value,
              })
            : await ServiceLocator().patientService.getPatient(_patient.id);
        if (p != null) freshPatient = p;
      } catch (_) {}

      // Collect patient transactions
      final List<Map<String, dynamic>> txList = [];
      if (freshPatient.payments != null) {
        for (final p in freshPatient.payments!) {
          txList.add(p.toMap());
        }
      }

      // Sort descending by date
      txList.sort((a, b) {
        final da = (a['date'] as num?)?.toInt() ?? 0;
        final db = (b['date'] as num?)?.toInt() ?? 0;
        return db.compareTo(da);
      });

      if (mounted) {
        setState(() {
          _patient = freshPatient;
          _stays = stays;
          _balances = balancesMap;
          _ledger = txList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _recordRefund({String? cycleId}) async {
    final success = await showRefundDialog(context, _patient, cycleId: cycleId);
    if (success == true && mounted) {
      await _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final totalBilled =
        _patient.advanceBilledAmount + _patient.attendanceCharges;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7EA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFF3B6D11),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _patient.fullName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (_patient.registrationNumber != null &&
                                _patient.registrationNumber!.isNotEmpty) ...[
                              Text(
                                'Reg: ${_patient.registrationNumber}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Text(
                              _patient.roomNumber != null &&
                                      _patient.roomNumber!.isNotEmpty
                                  ? 'Room ${_patient.roomNumber}'
                                  : 'Room: Unassigned',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Phone: ${_patient.contactNumber}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Overview Cards
              Row(
                children: [
                  _MetricCard(
                    title: 'Total Billed',
                    value: currency.format(totalBilled),
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(width: 12),
                  _MetricCard(
                    title: 'Net Paid',
                    value: currency.format(_patient.effectivePaidAmount),
                    color: const Color(0xFF3B6D11),
                  ),
                  const SizedBox(width: 12),
                  _MetricCard(
                    title: 'Outstanding Due',
                    value: currency.format(_patient.effectiveDueAmount),
                    color: _patient.effectiveDueAmount > 0
                        ? const Color(0xFFD32F2F)
                        : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  _MetricCard(
                    title: 'Refund Due (Excess)',
                    value: currency.format(_patient.confirmedRefundDueAmount),
                    color: _patient.confirmedRefundDueAmount > 0
                        ? Colors.deepOrange
                        : Colors.grey,
                    subtitle: _patient.totalRefundedAmount > 0
                        ? 'Refunded: ${currency.format(_patient.totalRefundedAmount)}'
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_patient.confirmedRefundDueAmount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFCC80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.deepOrange,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Payment exceeded by ${currency.format(_patient.confirmedRefundDueAmount)}. Record the refund once cash/UPI is returned to patient.',
                          style: const TextStyle(
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _recordRefund(),
                        icon: const Icon(
                          Icons.currency_exchange_rounded,
                          size: 16,
                        ),
                        label: const Text('Record Refund'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Content: Cycles & Transactions
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            const TabBar(
                              labelColor: Color(0xFF3B6D11),
                              indicatorColor: Color(0xFF3B6D11),
                              tabs: [
                                Tab(text: 'Admission Cycles'),
                                Tab(text: 'Transaction History'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _buildCyclesTab(currency),
                                  _buildTransactionsTab(currency),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  if (_patient.confirmedRefundDueAmount > 0) ...[
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3B6D11),
                      ),
                      onPressed: () => _recordRefund(),
                      icon: const Icon(
                        Icons.currency_exchange_rounded,
                        size: 16,
                      ),
                      label: const Text('Record Refund'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCyclesTab(NumberFormat currency) {
    if (_balances.isEmpty) {
      return const Center(
        child: Text(
          'No admission cycles found.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final cycleEntries = _balances.entries.toList()
      ..sort((a, b) {
        final ta = int.tryParse(a.key) ?? 0;
        final tb = int.tryParse(b.key) ?? 0;
        return tb.compareTo(ta);
      });

    return ListView.separated(
      itemCount: cycleEntries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = cycleEntries[index];
        final cycleKey = entry.key;
        final data = entry.value is Map
            ? entry.value as Map
            : <String, dynamic>{};

        final cycleMs = int.tryParse(cycleKey) ?? 0;
        final cycleDate = DateTime.fromMillisecondsSinceEpoch(cycleMs);
        final dateLabel = DateFormat('dd MMM yyyy').format(cycleDate);

        final total = (data['total'] as num?)?.toDouble() ?? 0.0;
        final paid = (data['paid'] as num?)?.toDouble() ?? 0.0;
        final refunded = (data['refunded'] as num?)?.toDouble() ?? 0.0;
        final due = (data['due'] as num?)?.toDouble() ?? 0.0;
        final uncertain = data['reconciliationRequired'] == true;
        final refundDue = uncertain
            ? 0.0
            : (data['refundDue'] as num?)?.toDouble() ?? 0.0;
        final status = data['status']?.toString() ?? '';

        final matchingStay = _stays
            .where((s) => s.cycleId == cycleKey)
            .firstOrNull;
        final roomNumber = matchingStay?.roomNumber;
        final roomText = roomNumber != null && roomNumber.isNotEmpty
            ? 'Room $roomNumber'
            : null;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: refundDue > 0
                  ? Colors.deepOrange.withValues(alpha: 0.4)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Admission: $dateLabel',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        if (roomText != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '($roomText)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (refundDue > 0
                                        ? Colors.deepOrange
                                        : due > 0
                                        ? Colors.red
                                        : Colors.green)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.isNotEmpty
                                ? status
                                : (refundDue > 0 ? 'Excess' : 'Paid'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: refundDue > 0
                                  ? Colors.deepOrange
                                  : due > 0
                                  ? Colors.red
                                  : const Color(0xFF3B6D11),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    if (data['checkoutAdjustment'] is Map)
                      Text(
                        'After 9 AM checkout adjustment (${data['checkoutAdjustment']['day']}, billable day ${data['checkoutAdjustment']['billableDay']}): ${currency.format(data['checkoutAdjustment']['amount'] ?? 0)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    Wrap(
                      spacing: 12,
                      children: [
                        Text(
                          'Billed: ${currency.format(total)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          'Paid: ${currency.format(paid)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        if (refunded > 0)
                          Text(
                            'Refunded: ${currency.format(refunded)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.deepOrange,
                            ),
                          ),
                        Text(
                          'Due: ${currency.format(due)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: due > 0 ? Colors.red : Colors.grey,
                            fontWeight: due > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (refundDue > 0)
                          Text(
                            'Excess / Refund Due: ${currency.format(refundDue)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (refundDue > 0)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF3E0),
                    foregroundColor: Colors.deepOrange,
                  ),
                  onPressed: () => _recordRefund(cycleId: cycleKey),
                  child: const Text('Refund Cycle'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionsTab(NumberFormat currency) {
    if (_ledger.isEmpty) {
      return const Center(
        child: Text(
          'No transaction records found.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      itemCount: _ledger.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final tx = _ledger[index];
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final type = tx['type']?.toString().toLowerCase();
        final isRefund = type == 'refund' || amount < 0;
        final dateMs = (tx['date'] as num?)?.toInt() ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
        final method = tx['method']?.toString().toUpperCase() ?? 'CASH';
        final receipt = tx['receiptNumber']?.toString().trim();
        final txnId = tx['transactionId']?.toString().trim();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isRefund
                  ? Colors.deepOrange.withValues(alpha: 0.3)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isRefund
                      ? const Color(0xFFFFF3E0)
                      : const Color(0xFFF0F7EA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isRefund
                      ? Icons.currency_exchange_rounded
                      : method.contains('ONLINE')
                      ? Icons.qr_code_rounded
                      : Icons.money_rounded,
                  color: isRefund ? Colors.deepOrange : const Color(0xFF3B6D11),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isRefund) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.deepOrange.shade300,
                              ),
                            ),
                            child: const Text(
                              'REFUND',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          method,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isRefund
                                ? Colors.deepOrange
                                : const Color(0xFF27500A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd MMM yyyy, hh:mm a').format(date),
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                    if (receipt != null && receipt.isNotEmpty)
                      Text(
                        'Receipt: $receipt',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    if (txnId != null && txnId.isNotEmpty)
                      Text(
                        'Txn Ref: $txnId',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                isRefund
                    ? '- ${currency.format(amount.abs())}'
                    : currency.format(amount),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: isRefund ? Colors.deepOrange : const Color(0xFF3B6D11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final String? subtitle;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
