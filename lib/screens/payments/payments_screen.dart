import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../models/patient_model.dart';
import 'package:intl/intl.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _rtdb = ServiceLocator().rtdbService;
  bool _isLoading = true;
  List<Map<String, dynamic>> _payments = [];
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ServiceLocator().paymentService.getAllPaymentsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final payments = snapshot.data ?? [];
        return Container(
          color: const Color(0xFFF0F7EA),
          padding: const EdgeInsets.all(24),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSummarySection(payments),
              const SizedBox(height: 24),
              _buildFilters(),
              const SizedBox(height: 16),
              Expanded(
                child: _buildPaymentsList(payments),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildSummarySection(List<Map<String, dynamic>> payments) {
    final total = payments.fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));
    final cash = payments.where((p) => p['method'].toString().toLowerCase().contains('cash')).fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));
    final online = payments.where((p) => p['method'].toString().toLowerCase().contains('online')).fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));
    final check = payments.where((p) => p['method'].toString().toLowerCase().contains('check')).fold(0.0, (sum, p) => sum + (p['amount'] ?? 0));

    return Row(
      children: [
        _SummaryCard(title: "Total Collection", value: total, color: const Color(0xFF3B6D11), icon: Icons.account_balance_wallet_rounded),
        const SizedBox(width: 16),
        _SummaryCard(title: "Cash", value: cash, color: Colors.orange, icon: Icons.money_rounded),
        const SizedBox(width: 16),
        _SummaryCard(title: "Online", value: online, color: Colors.blue, icon: Icons.qr_code_rounded),
        const SizedBox(width: 16),
        _SummaryCard(title: "Check", value: check, color: Colors.purple, icon: Icons.account_balance_rounded),
      ],
    );
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
                  child: const Text("Close", style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97).withValues(alpha: 0.5)),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: const InputDecoration(
          hintText: "Search by patient name, receipt or method...",
          border: InputBorder.none,
          icon: Icon(Icons.search, color: Color(0xFF3B6D11)),
        ),
      ),
    );
  }

  Widget _buildPaymentsList(List<Map<String, dynamic>> allPayments) {
    final filtered = allPayments.where((p) {
      if (_searchQuery.isEmpty) return true;
      final name = p['patientName']?.toString().toLowerCase() ?? "";
      final method = p['method']?.toString().toLowerCase() ?? "";
      final receipt = p['receiptNumber']?.toString().toLowerCase() ?? "";
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || method.contains(query) || receipt.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_searchQuery.isEmpty ? "No payments recorded yet" : "No payments match your search", 
                style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final payment = filtered[index];
        return _PaymentTile(payment: payment);
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final IconData icon;

  const _SummaryCard({required this.title, required this.value, required this.color, required this.icon});

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
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(fmt.format(value), style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

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
        border: Border.all(color: const Color(0xFFC0DD97).withValues(alpha: 0.3)),
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
              method.toLowerCase().contains('online') ? Icons.qr_code_rounded : 
              method.toLowerCase().contains('check') ? Icons.account_balance_rounded : 
              Icons.money_rounded,
              color: const Color(0xFF3B6D11),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment['patientName'] ?? "Unknown Patient", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF27500A))),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(DateFormat('dd MMM yyyy, hh:mm a').format(date), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(width: 8),
                    const Text("•", style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    Text(method, style: const TextStyle(color: Color(0xFF639922), fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt.format(payment['amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF3B6D11))),
              if (payment['receiptNumber'] != null)
                Text("Rec: ${payment['receiptNumber']}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
