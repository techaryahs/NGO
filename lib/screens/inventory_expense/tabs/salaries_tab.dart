import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/salary_model.dart';
import '../../../models/payment_details_model.dart';

/// Sub-tab to record and review employee payroll disburshments
class SalariesTab extends StatefulWidget {
  const SalariesTab({super.key});

  @override
  State<SalariesTab> createState() => _SalariesTabState();
}

class _SalariesTabState extends State<SalariesTab> {
  final _service = ServiceLocator().inventoryExpenseService;
  final _searchController = TextEditingController();

  List<SalaryModel> _salaries = [];
  StreamSubscription? _subscription;
  bool _loading = true;
  String _searchQuery = "";
  String _roleFilter = "All";

  final List<String> _roles = ["All", "Security Guard", "Staff", "Housekeeping", "Gardening", "Other"];

  @override
  void initState() {
    super.initState();
    _subscription = _service.getSalariesStream().listen((data) {
      if (mounted) {
        setState(() {
          _salaries = data;
          _loading = false;
        });
      }
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11)));
    }

    final filteredSalaries = _salaries.where((s) {
      final matchesSearch = s.employeeName.toLowerCase().contains(_searchQuery) ||
                            s.salaryMonth.toLowerCase().contains(_searchQuery);
      final matchesRole = _roleFilter == "All" || s.role == _roleFilter;
      return matchesSearch && matchesRole;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter Bar
          _buildFilterBar(context),
          const SizedBox(height: 15),
          
          // Salaries Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFDF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: filteredSalaries.isEmpty
                    ? const Center(child: Text("No payroll entries recorded", style: TextStyle(color: Color(0xFF639922))))
                    : ListView(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F9F0)),
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 48,
                              columns: const [
                                DataColumn(label: Text("Employee Name", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Role", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Salary Month", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Gross (₹)", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Deductions (₹)", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Net Disbursed (₹)", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Method", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              ],
                              rows: filteredSalaries.map((salary) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(salary.employeeName, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    DataCell(Text(salary.role)),
                                    DataCell(Text(salary.salaryMonth)),
                                    DataCell(Text("₹${salary.grossSalary.toStringAsFixed(0)}")),
                                    DataCell(Text("₹${salary.deductions.toStringAsFixed(0)}")),
                                    DataCell(Text("₹${salary.netSalary.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataCell(Text(salary.paymentDetails.paymentMethod)),
                                    DataCell(_buildStatusBadge(salary.paymentDetails.paymentStatus)),
                                    DataCell(_buildActionButtons(salary)),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFDF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Row(
        children: [
          // Search box
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search employee name or month (e.g. May 2026)...",
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF639922), size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                fillColor: const Color(0xFFF4F9F0),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3B6D11), width: 1.0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          
          // Role filter dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _roleFilter,
              decoration: const InputDecoration(
                labelText: "Role Filter",
                labelStyle: TextStyle(color: Color(0xFF3B6D11), fontSize: 12),
                contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              ),
              items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _roleFilter = val);
              },
            ),
          ),
          const Spacer(),

          // Add Button
          ElevatedButton.icon(
            onPressed: () => _showFormDialog(context),
            icon: const Icon(Icons.currency_exchange_rounded, size: 18),
            label: const Text("Disburse Salary"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B6D11),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFFFF8E1);
    Color fg = const Color(0xFFF57F17);
    Color border = const Color(0xFFFFB300);

    if (status == 'Paid') {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      border = const Color(0xFF81C784);
    } else if (status == 'Pending') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      border = const Color(0xFFE57373);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildActionButtons(SalaryModel salary) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.visibility_outlined, color: Color(0xFF3B6D11), size: 18),
          tooltip: "View Details",
          onPressed: () => _viewSalaryDetails(salary),
        ),
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: Color(0xFF639922), size: 18),
          tooltip: "Edit Record",
          onPressed: () => _showFormDialog(context, salary: salary),
        ),
        IconButton(
          icon: const Icon(Icons.delete_rounded, color: Color(0xFFC62828), size: 18),
          tooltip: "Delete Record",
          onPressed: () => _confirmDelete(salary),
        ),
      ],
    );
  }

  void _confirmDelete(SalaryModel salary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Salary Entry"),
        content: Text("Are you sure you want to permanently delete payroll for '${salary.employeeName}' (${salary.salaryMonth})?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.deleteSalary(salary.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Salary record successfully deleted'), backgroundColor: Color(0xFF3B6D11)),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC62828), foregroundColor: Colors.white),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _viewSalaryDetails(SalaryModel salary) {
    final pd = salary.paymentDetails;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.badge_rounded, color: Color(0xFF3B6D11)),
            SizedBox(width: 10),
            Text("Salary Payout Details"),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow("Employee Name", salary.employeeName),
                _buildDetailRow("Role", salary.role),
                _buildDetailRow("Salary Month", salary.salaryMonth),
                _buildDetailRow("Gross Salary", "₹${salary.grossSalary.toStringAsFixed(2)}"),
                _buildDetailRow("Total Deductions", "₹${salary.deductions.toStringAsFixed(2)}"),
                _buildDetailRow("Net Disbursed Amount", "₹${salary.netSalary.toStringAsFixed(2)}"),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFFC0DD97)),
                ),
                const Text("Payment Information", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A), fontSize: 13.5)),
                const SizedBox(height: 8),
                
                _buildDetailRow("Payment Method", pd.paymentMethod),
                _buildDetailRow("Payment Status", pd.paymentStatus),
                if (pd.paymentDate != null) _buildDetailRow("Disbursement Date", _formatDate(pd.paymentDate!)),
                if (pd.bankName != null && pd.bankName!.isNotEmpty) _buildDetailRow("Bank Name", pd.bankName!),
                if (pd.transactionId != null && pd.transactionId!.isNotEmpty) _buildDetailRow("UTR / Transaction ID", pd.transactionId!),
                if (pd.cashVoucherNumber != null && pd.cashVoucherNumber!.isNotEmpty) _buildDetailRow("Cash Voucher No", pd.cashVoucherNumber!),
                if (pd.receivedBy != null && pd.receivedBy!.isNotEmpty) _buildDetailRow("Cash Received By", pd.receivedBy!),
                if (pd.chequeNumber != null && pd.chequeNumber!.isNotEmpty) _buildDetailRow("Cheque Number", pd.chequeNumber!),
                if (pd.chequeDate != null) _buildDetailRow("Cheque Date", _formatDate(pd.chequeDate!)),
                if (pd.chequeClearanceStatus != null && pd.chequeClearanceStatus!.isNotEmpty) _buildDetailRow("Clearance Status", pd.chequeClearanceStatus!),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF639922), fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  void _showFormDialog(BuildContext context, {SalaryModel? salary}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: salary?.employeeName ?? "");
    final grossCtrl = TextEditingController(text: salary?.grossSalary.toString() ?? "");
    final dedCtrl = TextEditingController(text: salary?.deductions.toString() ?? "0.0");
    final netCtrl = TextEditingController(text: salary?.netSalary.toString() ?? "0.0");

    final bankCtrl = TextEditingController(text: salary?.paymentDetails.bankName ?? "");
    final transactionCtrl = TextEditingController(text: salary?.paymentDetails.transactionId ?? "");
    final voucherCtrl = TextEditingController(text: salary?.paymentDetails.cashVoucherNumber ?? "");
    final receivedByCtrl = TextEditingController(text: salary?.paymentDetails.receivedBy ?? "");
    final chequeNumCtrl = TextEditingController(text: salary?.paymentDetails.chequeNumber ?? "");

    DateTime paymentDate = salary?.paymentDetails.paymentDate ?? DateTime.now();
    DateTime? chequeDate = salary?.paymentDetails.chequeDate;

    String selectedRole = salary?.role ?? "Staff";
    
    // Manage salary month selection
    final now = DateTime.now();
    final List<String> monthsList = [];
    for (int i = 0; i < 12; i++) {
      final target = DateTime(now.year, now.month - i, 1);
      monthsList.add(_getMonthName(target.month) + " ${target.year}");
    }
    String selectedMonth = salary?.salaryMonth ?? monthsList.first;

    String paymentMethod = salary?.paymentDetails.paymentMethod ?? "Bank Transfer";
    String paymentStatus = salary?.paymentDetails.paymentStatus ?? "Paid";
    String chequeStatus = salary?.paymentDetails.chequeClearanceStatus ?? "Cleared";

    void recalculateNet() {
      final gross = double.tryParse(grossCtrl.text.trim()) ?? 0.0;
      final ded = double.tryParse(dedCtrl.text.trim()) ?? 0.0;
      netCtrl.text = (gross - ded).toStringAsFixed(2);
    }

    grossCtrl.addListener(recalculateNet);
    dedCtrl.addListener(recalculateNet);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(salary == null ? "Disburse Employee Salary" : "Edit Payroll Entry"),
              content: SizedBox(
                width: 580,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic Details
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(labelText: "Employee Full Name *"),
                                validator: (val) => val == null || val.isEmpty ? "Enter employee name" : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedRole,
                                decoration: const InputDecoration(labelText: "Employee Role *"),
                                items: _roles
                                    .where((r) => r != "All")
                                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedRole = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedMonth,
                                decoration: const InputDecoration(labelText: "Salary Month *"),
                                items: monthsList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedMonth = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final selected = await showDatePicker(
                                    context: context,
                                    initialDate: paymentDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (selected != null) {
                                    setDialogState(() => paymentDate = selected);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(labelText: "Disbursement Date"),
                                  child: Text(_formatDate(paymentDate)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Financial Calculations
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: grossCtrl,
                                decoration: const InputDecoration(labelText: "Gross Salary (₹) *"),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (val) => val == null || double.tryParse(val) == null ? "Enter valid amount" : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: dedCtrl,
                                decoration: const InputDecoration(labelText: "Deductions / Tax (₹)"),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (val) => val == null || double.tryParse(val) == null ? "Enter valid amount" : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: netCtrl,
                                decoration: const InputDecoration(labelText: "Net Payout (₹)"),
                                readOnly: true,
                              ),
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(color: Color(0xFFC0DD97)),
                        ),
                        
                        const Text("Payment Channels", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A), fontSize: 13)),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: paymentMethod,
                                decoration: const InputDecoration(labelText: "Payment Method"),
                                items: ["Cash", "Cheque", "UPI", "NEFT / RTGS / IMPS", "Bank Transfer", "Credit Card", "Debit Card", "Other"]
                                    .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => paymentMethod = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: paymentStatus,
                                decoration: const InputDecoration(labelText: "Payment Status"),
                                items: ["Paid", "Pending", "Partial"]
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => paymentStatus = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Conditional forms based on payment method
                        if (paymentMethod == "Cheque") ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: chequeNumCtrl,
                                  decoration: const InputDecoration(labelText: "Cheque Number"),
                                  validator: (val) => val == null || val.isEmpty ? "Enter cheque no" : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final selected = await showDatePicker(
                                      context: context,
                                      initialDate: chequeDate ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2030),
                                    );
                                    if (selected != null) {
                                      setDialogState(() => chequeDate = selected);
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(labelText: "Cheque Date"),
                                    child: Text(chequeDate != null ? _formatDate(chequeDate!) : "Select Date"),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: chequeStatus,
                            decoration: const InputDecoration(labelText: "Cheque Clearance Status"),
                            items: ["Pending", "Cleared", "Bounced"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => chequeStatus = val);
                              }
                            },
                          ),
                        ] else if (paymentMethod == "Cash") ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: voucherCtrl,
                                  decoration: const InputDecoration(labelText: "Cash Voucher Number"),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: receivedByCtrl,
                                  decoration: const InputDecoration(labelText: "Received By"),
                                ),
                              ),
                            ],
                          ),
                        ] else if (paymentMethod == "UPI" || paymentMethod.contains("Bank") || paymentMethod.contains("NEFT")) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: bankCtrl,
                                  decoration: const InputDecoration(labelText: "Bank Name"),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: transactionCtrl,
                                  decoration: const InputDecoration(labelText: "UTR / Transaction ID"),
                                  validator: (val) => val == null || val.isEmpty ? "Enter transaction id" : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final double gross = double.parse(grossCtrl.text.trim());
                      final double ded = double.parse(dedCtrl.text.trim());
                      final double net = gross - ded;

                      final paymentDetails = PaymentDetailsModel(
                        paymentMethod: paymentMethod,
                        paymentStatus: paymentStatus,
                        paymentDate: paymentDate,
                        bankName: bankCtrl.text.trim(),
                        transactionId: transactionCtrl.text.trim(),
                        cashVoucherNumber: voucherCtrl.text.trim(),
                        receivedBy: receivedByCtrl.text.trim(),
                        chequeNumber: chequeNumCtrl.text.trim(),
                        chequeDate: chequeDate,
                        chequeClearanceStatus: chequeStatus,
                      );

                      final now = DateTime.now();

                      final newSalary = SalaryModel(
                        id: salary?.id ?? "",
                        employeeName: nameCtrl.text.trim(),
                        role: selectedRole,
                        salaryMonth: selectedMonth,
                        grossSalary: gross,
                        deductions: ded,
                        netSalary: net,
                        paymentDetails: paymentDetails,
                        createdBy: "Admin",
                        updatedBy: "Admin",
                        createdAt: salary?.createdAt ?? now,
                        updatedAt: now,
                      );

                      if (salary == null) {
                        await _service.addSalary(newSalary);
                      } else {
                        await _service.updateSalary(salary.id, newSalary);
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(salary == null ? 'Salary payout recorded successfully.' : 'Salary details updated successfully.'),
                            backgroundColor: const Color(0xFF3B6D11),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white),
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }

  String _getMonthName(int month) {
    const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
    if (month >= 1 && month <= 12) return months[month - 1];
    return "";
  }
}
