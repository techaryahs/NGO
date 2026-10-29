import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/service_locator.dart';
import '../../models/patient_model.dart';
import 'package:intl/intl.dart';
import '../patients/widgets/payment_dialog.dart';
import '../patients/widgets/refund_dialog.dart';
import 'patient_financial_dialog.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final Stream<List<PatientModel>> _patientsStream;
  Stream<List<Map<String, dynamic>>>? _paymentsStream;
  final _searchController = TextEditingController();
  String _searchQuery = "";
  static const int _pageSize = 20;
  int _visibleBilling = _pageSize;
  int _visibleLedger = _pageSize;
  int _selectedTab = 0;
  int _billingFilterIndex = 0; // 0: All, 1: Due, 2: Refund Due

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _patientsStream = ServiceLocator().patientService.getPatientsStream();
    // Billing is recalculated when a patient is admitted, edited, or their
    // attendance changes. Avoid a full historical recalculation on every
    // visit to Payments because it can make the whole application sluggish.
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    final nextTab = _tabController.index;
    if (nextTab == _selectedTab) return;
    if (nextTab == 1) {
      _paymentsStream ??= ServiceLocator().paymentService
          .getAllPaymentsStream();
    }
    _searchController.clear();
    setState(() {
      _selectedTab = nextTab;
      _searchQuery = '';
      _visibleBilling = _pageSize;
      _visibleLedger = _pageSize;
    });
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() {
      _searchQuery = "";
      _visibleBilling = _pageSize;
      _visibleLedger = _pageSize;
    });
  }

  void _showQRDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Payment QR Code",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF27500A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Scan this code to make a payment",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFEAF3DE)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(
                  'assets/images/payment_qr.png',
                  width: 250,
                  height: 250,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.image_not_supported_outlined,
                    size: 100,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: const Color(0xFF3B6D11),
                  ),
                  child: const Text(
                    "Close",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecordRefundWorkflow(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _RefundPatientSelectionDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F7EA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    const Text(
                      "Payments Dashboard",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _showRecordRefundWorkflow(context),
                          icon: const Icon(
                            Icons.currency_exchange_rounded,
                            size: 18,
                          ),
                          label: const Text("Record Refund"),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF3E0),
                            foregroundColor: Colors.deepOrange.shade800,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showQRDialog(context),
                          icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                          label: const Text("Show QR Code"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B6D11),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF3B6D11),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF3B6D11),
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  tabs: const [
                    Tab(text: "Patient Billing"),
                    Tab(text: "Transaction Ledger"),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _buildPatientBillingTab(),
                _paymentsStream == null
                    ? const SizedBox.shrink()
                    : _buildLedgerTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Patient Billing Tab ───────────────────────────────────────────────────

  Widget _buildPatientBillingTab() {
    return StreamBuilder<List<PatientModel>>(
      stream: _patientsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _PaymentsError(
            message: 'Patient billing could not be loaded.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _PaymentsLoader(message: 'Loading patient billing...');
        }

        final allPatients = snapshot.data ?? [];
        final activePatients = allPatients.where((p) {
          final status = p.status.toLowerCase();
          return status == 'active' ||
              status == 'paid' ||
              status == 'discharged' ||
              p.effectiveDueAmount > 0 ||
              p.confirmedRefundDueAmount > 0;
        }).toList();

        final dueCount = activePatients
            .where((p) => p.effectiveDueAmount > 0)
            .length;
        final refundDueCount = activePatients
            .where((p) => p.confirmedRefundDueAmount > 0)
            .length;
        final totalDue = activePatients.fold<double>(
          0.0,
          (sum, p) => sum + p.effectiveDueAmount,
        );
        final totalCollected = allPatients.fold(
          0.0,
          (sum, p) => sum + p.accountNetPaid,
        );
        final totalRefundDue = allPatients.fold<double>(
          0.0,
          (sum, p) => sum + p.confirmedRefundDueAmount,
        );

        final filteredByChip = activePatients.where((p) {
          if (_billingFilterIndex == 1) return p.effectiveDueAmount > 0;
          if (_billingFilterIndex == 2) return p.confirmedRefundDueAmount > 0;
          return true;
        }).toList();

        final query = _searchQuery.trim().toLowerCase();
        final filtered = filteredByChip.where((p) {
          if (query.isEmpty) return true;
          final fields = [
            p.fullName,
            p.contactNumber,
            p.roomNumber ?? '',
            p.paymentStatus ?? '',
            p.registrationNumber ?? '',
            p.effectiveDueAmount.toString(),
            p.effectivePaidAmount.toString(),
          ].map((value) => value.toLowerCase());
          return fields.any((value) => value.contains(query));
        }).toList();
        final visiblePatients = filtered.take(_visibleBilling).toList();
        final hasMorePatients = visiblePatients.length < filtered.length;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SummaryCard(
                    title: "Total Outstanding Due",
                    value: totalDue,
                    color: const Color(0xFFD32F2F),
                    icon: Icons.warning_rounded,
                    onTap: () => setState(() => _billingFilterIndex = 1),
                  ),
                  const SizedBox(width: 16),
                  _SummaryCard(
                    title: "Net Collected",
                    value: totalCollected,
                    color: const Color(0xFF3B6D11),
                    icon: Icons.account_balance_wallet_rounded,
                    onTap: () => setState(() => _billingFilterIndex = 0),
                  ),
                  const SizedBox(width: 16),
                  _SummaryCard(
                    title: "Total Refund Due",
                    value: totalRefundDue,
                    color: Colors.deepOrange,
                    icon: Icons.currency_exchange_rounded,
                    onTap: () => setState(() => _billingFilterIndex = 2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text("All Patients (${activePatients.length})"),
                    selected: _billingFilterIndex == 0,
                    onSelected: (_) => setState(() => _billingFilterIndex = 0),
                  ),
                  ChoiceChip(
                    label: Text("Due Patients ($dueCount)"),
                    selected: _billingFilterIndex == 1,
                    onSelected: (_) => setState(() => _billingFilterIndex = 1),
                  ),
                  ChoiceChip(
                    label: Text("Refund Due ($refundDueCount)"),
                    selected: _billingFilterIndex == 2,
                    selectedColor: const Color(0xFFFFF3E0),
                    labelStyle: TextStyle(
                      color: _billingFilterIndex == 2
                          ? Colors.deepOrange
                          : Colors.black87,
                      fontWeight: _billingFilterIndex == 2
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _billingFilterIndex = 2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildFilters("Search patient billing..."),
              const SizedBox(height: 16),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          "No patients found.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount:
                            visiblePatients.length + (hasMorePatients ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == visiblePatients.length) {
                            return _LoadMorePaymentsButton(
                              remaining:
                                  filtered.length - visiblePatients.length,
                              onPressed: () =>
                                  setState(() => _visibleBilling += _pageSize),
                            );
                          }
                          return _PatientBillingTile(
                            patient: visiblePatients[index],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Ledger Tab ────────────────────────────────────────────────────────────

  Widget _buildLedgerTab() {
    _paymentsStream ??= ServiceLocator().paymentService.getAllPaymentsStream();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _paymentsStream!,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _PaymentsError(
            message: 'Transaction ledger could not be loaded.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _PaymentsLoader(
            message: 'Loading transaction ledger...',
          );
        }

        final payments = snapshot.data ?? [];
        final query = _searchQuery.trim().toLowerCase();
        final filtered = payments.where((p) {
          if (query.isEmpty) return true;
          final dateValue = p['date'];
          final dateText = dateValue is int
              ? DateFormat(
                  'dd MMM yyyy hh:mm a',
                ).format(DateTime.fromMillisecondsSinceEpoch(dateValue))
              : '';
          final fields = [
            p['patientName'],
            p['method'],
            p['receiptNumber'],
            p['transactionId'],
            p['checkNumber'],
            p['bankName'],
            p['notes'],
            p['amount'],
            dateText,
          ].map((value) => value?.toString().toLowerCase() ?? '');
          return fields.any((value) => value.contains(query));
        }).toList();
        final visiblePayments = filtered.take(_visibleLedger).toList();
        final hasMorePayments = visiblePayments.length < filtered.length;

        final total = payments.fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));
        final cash = payments
            .where((p) => p['method'].toString().toLowerCase().contains('cash'))
            .fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));
        final online = payments
            .where(
              (p) => p['method'].toString().toLowerCase().contains('online'),
            )
            .fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));
        final check = payments
            .where(
              (p) => p['method'].toString().toLowerCase().contains('check'),
            )
            .fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));
        final refunded = payments.fold(0.0, (sum, p) {
          final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          final isRefund =
              p['type']?.toString().toLowerCase() == 'refund' || amt < 0;
          return sum + (isRefund ? amt.abs() : 0.0);
        });

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _SummaryCard(
                      title: "Net Lifetime Collection",
                      value: total,
                      color: const Color(0xFF3B6D11),
                      icon: Icons.account_balance_wallet_rounded,
                      expand: false,
                    ),
                    const SizedBox(width: 12),
                    _SummaryCard(
                      title: "Cash",
                      value: cash,
                      color: Colors.orange,
                      icon: Icons.money_rounded,
                      expand: false,
                    ),
                    const SizedBox(width: 12),
                    _SummaryCard(
                      title: "Online",
                      value: online,
                      color: Colors.blue,
                      icon: Icons.qr_code_rounded,
                      expand: false,
                    ),
                    const SizedBox(width: 12),
                    _SummaryCard(
                      title: "Check",
                      value: check,
                      color: Colors.purple,
                      icon: Icons.account_balance_rounded,
                      expand: false,
                    ),
                    const SizedBox(width: 12),
                    _SummaryCard(
                      title: "Total Refunded",
                      value: refunded,
                      color: Colors.deepOrange,
                      icon: Icons.currency_exchange_rounded,
                      expand: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildFilters("Search ledger by name, receipt, or method..."),
              const SizedBox(height: 16),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          "No transactions found.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount:
                            visiblePayments.length + (hasMorePayments ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == visiblePayments.length) {
                            return _LoadMorePaymentsButton(
                              remaining:
                                  filtered.length - visiblePayments.length,
                              onPressed: () =>
                                  setState(() => _visibleLedger += _pageSize),
                            );
                          }
                          return _PaymentTile(payment: visiblePayments[index]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters(String hint) {
    return SizedBox(
      width: double.infinity,
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            _visibleBilling = _pageSize;
            _visibleLedger = _pageSize;
          });
        },
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: const Color(0xFF639922).withValues(alpha: 0.5),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF639922),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.clear_rounded),
                  color: const Color(0xFF639922),
                  onPressed: _clearSearch,
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFC0DD97)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFC0DD97)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF3B6D11), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _LoadMorePaymentsButton extends StatelessWidget {
  final int remaining;
  final VoidCallback onPressed;

  const _LoadMorePaymentsButton({
    required this.remaining,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final nextCount = remaining.clamp(0, _PaymentsScreenState._pageSize);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.expand_more_rounded),
          label: Text('Load $nextCount more ($remaining remaining)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF3B6D11),
            side: const BorderSide(color: Color(0xFF97C459)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _PaymentsLoader extends StatelessWidget {
  final String message;

  const _PaymentsLoader({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF3B6D11),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF639922),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsError extends StatelessWidget {
  final String message;

  const _PaymentsError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool expand;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    final card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fmt.format(value),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    final content = onTap == null
        ? card
        : InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: card,
          );

    return expand ? Expanded(child: content) : content;
  }
}

// ── Patient Billing Tile ────────────────────────────────────────────────────

class _PatientBillingTile extends StatefulWidget {
  final PatientModel patient;

  const _PatientBillingTile({required this.patient});

  @override
  State<_PatientBillingTile> createState() => _PatientBillingTileState();
}

class _PatientBillingTileState extends State<_PatientBillingTile> {
  bool _isProcessing = false;

  Widget _placementLabel(PatientModel patient) {
    const style = TextStyle(color: Colors.grey, fontSize: 12);
    final lobby = patient.lobby?.trim();
    if (lobby != null && lobby.isNotEmpty) {
      return Text('Lobby: $lobby', style: style);
    }
    final room = patient.roomNumber?.trim();
    if (room != null && room.isNotEmpty) {
      return Text('Room: $room', style: style);
    }

    return const Text('Room: Unassigned', style: style);
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
    final fmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    final configuredBill =
        patient.advanceBilledAmount + patient.attendanceCharges;
    final totalBill = configuredBill;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showPatientFinancialDialog(context, patient),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: patient.confirmedRefundDueAmount > 0
                ? Colors.deepOrange.withValues(alpha: 0.3)
                : const Color(0xFFC0DD97).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Avatar / Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: patient.confirmedRefundDueAmount > 0
                    ? const Color(0xFFFFF3E0)
                    : patient.isAdvancePeriod
                    ? const Color(0xFFE3F2FD)
                    : const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                patient.confirmedRefundDueAmount > 0
                    ? Icons.currency_exchange_rounded
                    : patient.isAdvancePeriod
                    ? Icons.hourglass_top_rounded
                    : Icons.calendar_month_rounded,
                color: patient.confirmedRefundDueAmount > 0
                    ? Colors.deepOrange
                    : patient.isAdvancePeriod
                    ? Colors.blue
                    : Colors.purple,
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          patient.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFF27500A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: patient.isAdvancePeriod
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          patient.isAdvancePeriod
                              ? 'Advance Mode'
                              : 'Attendance Mode',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: patient.isAdvancePeriod
                                ? Colors.blue
                                : Colors.purple,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _placementLabel(patient),
                      const SizedBox(width: 8),
                      const Text("•", style: TextStyle(color: Colors.grey)),
                      const SizedBox(width: 8),
                      Text(
                        "Present: ${patient.totalPresentDays} days",
                        style: const TextStyle(
                          color: Color(0xFF639922),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        "Bill: ${fmt.format(totalBill)}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text("•", style: TextStyle(color: Colors.grey)),
                      const SizedBox(width: 8),
                      Text(
                        "Paid: ${fmt.format(patient.effectivePaidAmount)}",
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
            // Actions / Due Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (patient.confirmedRefundDueAmount > 0) ...[
                  Text(
                    'Excess: ${fmt.format(patient.confirmedRefundDueAmount)}',
                    style: const TextStyle(
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF3E0),
                      foregroundColor: Colors.deepOrange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      minimumSize: const Size(80, 28),
                    ),
                    icon: const Icon(Icons.currency_exchange_rounded, size: 14),
                    label: const Text(
                      'Record Refund',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => showRefundDialog(context, patient),
                  ),
                  const SizedBox(height: 6),
                ],

                Text(
                  "Due: ${fmt.format(patient.effectiveDueAmount)}",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: patient.effectiveDueAmount > 0
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFF3B6D11),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(60, 32),
                        side: const BorderSide(color: Color(0xFF97C459)),
                      ),
                      icon: const Icon(
                        Icons.receipt_long_rounded,
                        size: 14,
                        color: Color(0xFF3B6D11),
                      ),
                      label: const Text(
                        "History",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF3B6D11),
                        ),
                      ),
                      onPressed: () =>
                          showPatientFinancialDialog(context, patient),
                    ),
                    if (patient.effectiveDueAmount > 0) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed:
                            _isProcessing ||
                                patient.financialReconciliation['required'] ==
                                    true
                            ? null
                            : () async {
                                setState(() => _isProcessing = true);
                                try {
                                  final result = await showPatientPaymentDialog(
                                    context: context,
                                    patientName: patient.fullName,
                                    contactNumber: patient.contactNumber,
                                    bedsCount: patient.bedIds?.length ?? 1,
                                    attendantsCount:
                                        patient.attendants?.length ?? 0,
                                    roomIdentifier: patient.roomNumber,
                                    alreadyPaid: patient.effectivePaidAmount,
                                    showPayLater: false,
                                    totalBillOverride:
                                        patient.advanceBilledAmount +
                                        patient.attendanceCharges,
                                    patientId: patient.id,
                                  );

                                  if (result?.recordedPaymentId != null &&
                                      context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Online payment recorded.',
                                        ),
                                        backgroundColor: Color(0xFF3B6D11),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isProcessing = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B6D11),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 0,
                          ),
                          minimumSize: const Size(80, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Pay Now",
                                style: TextStyle(fontSize: 12),
                              ),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF3B6D11),
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Cleared",
                              style: TextStyle(
                                color: Color(0xFF3B6D11),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ledger Tile ─────────────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final Map<String, dynamic> payment;

  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(payment['date'] ?? 0);
    final fmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    final method = payment['method']?.toString() ?? "CASH";
    final type = payment['type']?.toString().toLowerCase();
    final rawAmount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
    final isRefund = type == 'refund' || rawAmount < 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRefund
              ? Colors.deepOrange.withValues(alpha: 0.3)
              : const Color(0xFFC0DD97).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isRefund
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFF0F7EA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isRefund
                  ? Icons.currency_exchange_rounded
                  : method.toLowerCase().contains('online')
                  ? Icons.qr_code_rounded
                  : method.toLowerCase().contains('check')
                  ? Icons.account_balance_rounded
                  : Icons.money_rounded,
              color: isRefund ? Colors.deepOrange : const Color(0xFF3B6D11),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        payment['patientName'] ?? "Unknown Patient",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Color(0xFF27500A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isRefund) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.deepOrange.shade300),
                        ),
                        child: const Text(
                          'REFUND',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy, hh:mm a').format(date),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    const Text("•", style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    Text(
                      method,
                      style: TextStyle(
                        color: isRefund
                            ? Colors.deepOrange
                            : const Color(0xFF639922),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (payment['transactionId'] != null &&
                    payment['transactionId'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Txn Ref: ${payment['transactionId']}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isRefund
                    ? "- ${fmt.format(rawAmount.abs())}"
                    : fmt.format(rawAmount),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: isRefund ? Colors.deepOrange : const Color(0xFF3B6D11),
                ),
              ),
              if (payment['receiptNumber'] != null &&
                  payment['receiptNumber'].toString().trim().isNotEmpty)
                Text(
                  "Rec: ${payment['receiptNumber']}",
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Patient Selector for Record Refund ────────────────────────────────────────

class _RefundPatientSelectionDialog extends StatefulWidget {
  const _RefundPatientSelectionDialog();

  @override
  State<_RefundPatientSelectionDialog> createState() =>
      _RefundPatientSelectionDialogState();
}

class _RefundPatientSelectionDialogState
    extends State<_RefundPatientSelectionDialog> {
  String _search = '';
  bool _onlyRefundDue = true;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PatientModel>>(
      stream: ServiceLocator().patientService.getPatientsStream(),
      builder: (context, snapshot) {
        final patients = snapshot.data ?? [];
        return _buildDialog(context, patients);
      },
    );
  }

  Widget _buildDialog(BuildContext context, List<PatientModel> allPatients) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final filtered =
        allPatients.where((p) {
          if (_onlyRefundDue && p.confirmedRefundDueAmount <= 0) return false;
          if (_search.isEmpty) return true;
          final q = _search.toLowerCase();
          return p.fullName.toLowerCase().contains(q) ||
              (p.registrationNumber?.toLowerCase().contains(q) ?? false) ||
              (p.roomNumber?.toLowerCase().contains(q) ?? false) ||
              p.contactNumber.toLowerCase().contains(q);
        }).toList()..sort(
          (a, b) =>
              b.confirmedRefundDueAmount.compareTo(a.confirmedRefundDueAmount),
        );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        color: Colors.deepOrange,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Select Patient for Refund',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF27500A),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _search = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search patient by name, room, or registration...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF639922),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FDF7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFC0DD97)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFC0DD97)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF3B6D11),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilterChip(
                    label: Text(
                      'Patients with Refund Due (${allPatients.where((p) => p.confirmedRefundDueAmount > 0).length})',
                    ),
                    selected: _onlyRefundDue,
                    selectedColor: const Color(0xFFFFF3E0),
                    labelStyle: TextStyle(
                      color: _onlyRefundDue
                          ? Colors.deepOrange
                          : Colors.black87,
                      fontWeight: _onlyRefundDue
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    onSelected: (val) => setState(() => _onlyRefundDue = val),
                  ),
                  const SizedBox(width: 8),
                  if (_onlyRefundDue)
                    TextButton(
                      onPressed: () => setState(() => _onlyRefundDue = false),
                      child: const Text('Show all patients'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _onlyRefundDue
                              ? 'No patients currently have excess payments to refund.'
                              : 'No matching patients found.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final patient = filtered[i];
                          final hasRefund =
                              patient.confirmedRefundDueAmount > 0;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.pop(ctx);
                              showPatientFinancialDialog(context, patient);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: hasRefund
                                      ? Colors.deepOrange.withValues(alpha: 0.3)
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: hasRefund
                                        ? const Color(0xFFFFF3E0)
                                        : const Color(0xFFF0F7EA),
                                    child: Icon(
                                      hasRefund
                                          ? Icons.currency_exchange_rounded
                                          : Icons.person_outline_rounded,
                                      color: hasRefund
                                          ? Colors.deepOrange
                                          : const Color(0xFF3B6D11),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          patient.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF27500A),
                                          ),
                                        ),
                                        Text(
                                          'Room: ${patient.roomNumber ?? 'Unassigned'}${patient.registrationNumber != null ? ' · Reg: ${patient.registrationNumber}' : ''}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (hasRefund)
                                        Text(
                                          'Refund Due: ${currency.format(patient.confirmedRefundDueAmount)}',
                                          style: const TextStyle(
                                            color: Colors.deepOrange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        )
                                      else
                                        Text(
                                          'Due: ${currency.format(patient.effectiveDueAmount)}',
                                          style: TextStyle(
                                            color:
                                                patient.effectiveDueAmount > 0
                                                ? Colors.red
                                                : const Color(0xFF3B6D11),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Paid: ${currency.format(patient.effectivePaidAmount)}',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
