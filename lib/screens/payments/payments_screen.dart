import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../models/patient_model.dart';
import 'package:intl/intl.dart';
import '../patients/widgets/payment_dialog.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final Stream<List<PatientModel>> _patientsStream;
  late final Stream<List<Map<String, dynamic>>> _paymentsStream;
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _patientsStream = ServiceLocator().patientService.getPatientsStream();
    _paymentsStream = ServiceLocator().paymentService.getAllPaymentsStream();
    // Trigger auto-calculation of attendance billing on dashboard load
    ServiceLocator().paymentService.recalculateAllActivePatientsBilling();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      _clearSearch();
    }
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _searchQuery = "");
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Payments Dashboard",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF27500A),
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
            child: TabBarView(
              controller: _tabController,
              children: [_buildPatientBillingTab(), _buildLedgerTab()],
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allPatients = snapshot.data ?? [];
        final activePatients = allPatients
            .where((p) => p.status == 'active' || p.status == 'Paid')
            .toList();

        final query = _searchQuery.trim().toLowerCase();
        final filtered = activePatients.where((p) {
          if (query.isEmpty) return true;
          final fields = [
            p.fullName,
            p.contactNumber,
            p.roomNumber ?? '',
            p.paymentStatus ?? '',
            p.registrationNumber ?? '',
            p.currentDueAmount?.toString() ?? '',
            p.totalPaidAmount?.toString() ?? '',
          ].map((value) => value.toLowerCase());
          return fields.any((value) => value.contains(query));
        }).toList();

        final totalDue = activePatients.fold<double>(
          0.0,
          (sum, p) => sum + (p.currentDueAmount ?? 0.0),
        );
        final totalCollected = activePatients.fold(
          0.0,
          (sum, p) => sum + (p.totalPaidAmount ?? 0),
        );

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
                  ),
                  const SizedBox(width: 16),
                  _SummaryCard(
                    title: "Total Collected (Active)",
                    value: totalCollected,
                    color: const Color(0xFF3B6D11),
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildFilters("Search active patients..."),
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
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _PatientBillingTile(patient: filtered[index]);
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _paymentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
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

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SummaryCard(
                    title: "Lifetime Collection",
                    value: total,
                    color: const Color(0xFF3B6D11),
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  const SizedBox(width: 16),
                  _SummaryCard(
                    title: "Cash",
                    value: cash,
                    color: Colors.orange,
                    icon: Icons.money_rounded,
                  ),
                  const SizedBox(width: 16),
                  _SummaryCard(
                    title: "Online",
                    value: online,
                    color: Colors.blue,
                    icon: Icons.qr_code_rounded,
                  ),
                  const SizedBox(width: 16),
                  _SummaryCard(
                    title: "Check",
                    value: check,
                    color: Colors.purple,
                    icon: Icons.account_balance_rounded,
                  ),
                ],
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
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _PaymentTile(payment: filtered[index]);
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
          setState(() => _searchQuery = value);
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

class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    return Expanded(
      child: Container(
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
      ),
    );
  }
}

// ── Patient Billing Tile ────────────────────────────────────────────────────

class _PatientBillingTile extends StatelessWidget {
  final PatientModel patient;

  const _PatientBillingTile({required this.patient});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    final totalBill = patient.advanceBilledAmount + patient.attendanceCharges;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC0DD97).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Avatar / Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: patient.isAdvancePeriod
                  ? const Color(0xFFE3F2FD)
                  : const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              patient.isAdvancePeriod
                  ? Icons.hourglass_top_rounded
                  : Icons.calendar_month_rounded,
              color: patient.isAdvancePeriod ? Colors.blue : Colors.purple,
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
                    Text(
                      "Room: ${patient.roomNumber ?? 'Unassigned'}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
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
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    const Text("•", style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    Text(
                      "Paid: ${fmt.format(patient.totalPaidAmount ?? 0)}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
              Text(
                "Due: ${fmt.format(patient.currentDueAmount)}",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: (patient.currentDueAmount ?? 0.0) > 0
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF3B6D11),
                ),
              ),
              const SizedBox(height: 8),
              if ((patient.currentDueAmount ?? 0.0) > 0)
                ElevatedButton(
                  onPressed: () async {
                    final result = await showPatientPaymentDialog(
                      context: context,
                      patientName: patient.fullName,
                      contactNumber: patient.contactNumber,
                      bedsCount: patient.bedIds?.length ?? 1,
                      attendantsCount: patient.attendants?.length ?? 0,
                      roomIdentifier: patient.roomNumber,
                      alreadyPaid: patient.totalPaidAmount ?? 0.0,
                      showPayLater: false,
                      totalBillOverride:
                          patient.advanceBilledAmount +
                          patient.attendanceCharges,
                    );

                    if (result != null && result.payment != null) {
                      await ServiceLocator().patientService.recordPayment(
                        patient.id,
                        result.payment!,
                      );
                      await ServiceLocator().patientService
                          .updatePatient(patient.id, {
                            'paymentPending':
                                result.payment!.paymentStatus == "Pending",
                            'paymentStatus': result.payment!.paymentStatus,
                            'status': result.payment!.paymentStatus == "Paid"
                                ? 'Paid'
                                : 'active',
                            'totalPaidAmount': result.payment!.paidAmount,
                            'currentDueAmount': result.payment!.pendingAmount,
                          });

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Payment successfully recorded!'),
                            backgroundColor: Color(0xFF3B6D11),
                          ),
                        );
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
                  child: const Text("Pay Now", style: TextStyle(fontSize: 12)),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC0DD97).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7EA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              method.toLowerCase().contains('online')
                  ? Icons.qr_code_rounded
                  : method.toLowerCase().contains('check')
                  ? Icons.account_balance_rounded
                  : Icons.money_rounded,
              color: const Color(0xFF3B6D11),
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
                      style: const TextStyle(
                        color: Color(0xFF639922),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmt.format(payment['amount'] ?? 0),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF3B6D11),
                ),
              ),
              if (payment['receiptNumber'] != null)
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
