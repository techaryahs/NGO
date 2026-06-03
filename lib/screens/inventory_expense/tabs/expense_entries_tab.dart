import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/expense_entry_model.dart';
import '../../../models/vendor_model.dart';
import '../../../models/payment_details_model.dart';

/// Sub-tab to record and review facility operations & utility bills expenses
class ExpenseEntriesTab extends StatefulWidget {
  const ExpenseEntriesTab({super.key});

  @override
  State<ExpenseEntriesTab> createState() => _ExpenseEntriesTabState();
}

class _ExpenseEntriesTabState extends State<ExpenseEntriesTab> {
  final _service = ServiceLocator().inventoryExpenseService;
  final _searchController = TextEditingController();

  List<ExpenseEntryModel> _expenses = [];
  List<VendorModel> _vendors = [];

  StreamSubscription? _expensesSub;
  StreamSubscription? _vendorsSub;

  bool _loading = true;
  String _searchQuery = "";
  String _categoryFilter = "All";

  final List<String> _categories = [
    "All", "Fruits", "Vegetables", "Groceries", "Drinking Water", "Water Tanker",
    "Laundry", "Cable TV", "Internet", "Canteen", "Housekeeping", "Cleaning Material",
    "Electricity", "Maintenance"
  ];

  @override
  void initState() {
    super.initState();
    _subscribeStreams();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  void _subscribeStreams() {
    _expensesSub = _service.getExpenseEntriesStream().listen((data) {
      if (mounted) setState(() { _expenses = data; _checkLoading(); });
    });
    _vendorsSub = _service.getVendorsStream().listen((data) {
      if (mounted) setState(() { _vendors = data; _checkLoading(); });
    });
  }

  void _checkLoading() {
    if (_expensesSub != null && _vendorsSub != null) {
      setState(() { _loading = false; });
    }
  }

  @override
  void dispose() {
    _expensesSub?.cancel();
    _vendorsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11)));
    }

    final filteredExpenses = _expenses.where((e) {
      final matchesSearch = e.description.toLowerCase().contains(_searchQuery) ||
                            (e.subcategory != null && e.subcategory!.toLowerCase().contains(_searchQuery)) ||
                            (e.vendorName != null && e.vendorName!.toLowerCase().contains(_searchQuery));
      final matchesCategory = _categoryFilter == "All" || e.category == _categoryFilter;
      return matchesSearch && matchesCategory;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter Bar
          _buildFilterBar(context),
          const SizedBox(height: 15),
          
          // Expense Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFDF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: filteredExpenses.isEmpty
                    ? const Center(child: Text("No operational expenses recorded", style: TextStyle(color: Color(0xFF639922))))
                    : ListView(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F9F0)),
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 48,
                              columns: const [
                                DataColumn(label: Text("Date", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Category", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Subcategory", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Description", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Amount", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Method", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              ],
                              rows: filteredExpenses.map((expense) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(_formatDate(expense.expenseDate))),
                                    DataCell(Text(expense.category)),
                                    DataCell(Text(expense.subcategory != null && expense.subcategory!.isNotEmpty ? expense.subcategory! : "—")),
                                    DataCell(Text(expense.description, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    DataCell(Text("₹${expense.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataCell(Text(expense.paymentDetails.paymentMethod)),
                                    DataCell(_buildStatusBadge(expense.paymentDetails.paymentStatus)),
                                    DataCell(_buildActionButtons(expense)),
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
                hintText: "Search description, subcategory, or vendor...",
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
          
          // Category filter dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _categoryFilter,
              decoration: const InputDecoration(
                labelText: "Category Filter",
                labelStyle: TextStyle(color: Color(0xFF3B6D11), fontSize: 12),
                contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              ),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _categoryFilter = val);
              },
            ),
          ),
          const Spacer(),

          // Add Button
          ElevatedButton.icon(
            onPressed: () => _showFormDialog(context),
            icon: const Icon(Icons.post_add_rounded, size: 18),
            label: const Text("Record Expense"),
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

  Widget _buildActionButtons(ExpenseEntryModel expense) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.visibility_outlined, color: Color(0xFF3B6D11), size: 18),
          tooltip: "View Details",
          onPressed: () => _viewExpenseDetails(expense),
        ),
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: Color(0xFF639922), size: 18),
          tooltip: "Edit Record",
          onPressed: () => _showFormDialog(context, expense: expense),
        ),
        IconButton(
          icon: const Icon(Icons.delete_rounded, color: Color(0xFFC62828), size: 18),
          tooltip: "Delete Record",
          onPressed: () => _confirmDelete(expense),
        ),
      ],
    );
  }

  void _confirmDelete(ExpenseEntryModel expense) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Expense Record"),
        content: Text("Are you sure you want to permanently delete this operational expense for '${expense.category}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.deleteExpenseEntry(expense.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Expense successfully deleted'), backgroundColor: Color(0xFF3B6D11)),
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

  void _viewExpenseDetails(ExpenseEntryModel expense) {
    final pd = expense.paymentDetails;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.payment_rounded, color: Color(0xFF3B6D11)),
            SizedBox(width: 10),
            Text("Operational Expense Details"),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow("Expense Date", _formatDate(expense.expenseDate)),
                _buildDetailRow("Category", expense.category),
                _buildDetailRow("Subcategory", expense.subcategory != null && expense.subcategory!.isNotEmpty ? expense.subcategory! : "—"),
                _buildDetailRow("Description", expense.description),
                _buildDetailRow("Linked Vendor", expense.vendorName != null && expense.vendorName!.isNotEmpty ? expense.vendorName! : "No Registered Vendor Linked"),
                _buildDetailRow("Total Paid Amount", "₹${expense.totalAmount.toStringAsFixed(2)}"),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFFC0DD97)),
                ),
                const Text("Payment Information", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A), fontSize: 13.5)),
                const SizedBox(height: 8),
                
                _buildDetailRow("Payment Method", pd.paymentMethod),
                _buildDetailRow("Payment Status", pd.paymentStatus),
                if (pd.paymentDate != null) _buildDetailRow("Payment Date", _formatDate(pd.paymentDate!)),
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

  void _showFormDialog(BuildContext context, {ExpenseEntryModel? expense}) {
    final formKey = GlobalKey<FormState>();
    
    final descCtrl = TextEditingController(text: expense?.description ?? "");
    final subcatCtrl = TextEditingController(text: expense?.subcategory ?? "");
    final amountCtrl = TextEditingController(text: expense?.totalAmount.toString() ?? "");
    
    final bankCtrl = TextEditingController(text: expense?.paymentDetails.bankName ?? "");
    final transactionCtrl = TextEditingController(text: expense?.paymentDetails.transactionId ?? "");
    final voucherCtrl = TextEditingController(text: expense?.paymentDetails.cashVoucherNumber ?? "");
    final receivedByCtrl = TextEditingController(text: expense?.paymentDetails.receivedBy ?? "");
    final chequeNumCtrl = TextEditingController(text: expense?.paymentDetails.chequeNumber ?? "");

    DateTime expenseDate = expense?.expenseDate ?? DateTime.now();
    DateTime? chequeDate = expense?.paymentDetails.chequeDate;

    String selectedCategory = expense?.category ?? _categories.where((c) => c != "All").first;
    
    // Optional vendor linkage
    VendorModel? selectedVendor = _vendors.isNotEmpty 
        ? _vendors.firstWhere((v) => v.id == expense?.vendorId, orElse: () => _vendors.first)
        : null;
    bool enableVendor = expense?.vendorId != null;

    String paymentMethod = expense?.paymentDetails.paymentMethod ?? "Cash";
    String paymentStatus = expense?.paymentDetails.paymentStatus ?? "Paid";
    String chequeStatus = expense?.paymentDetails.chequeClearanceStatus ?? "Pending";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(expense == null ? "Record Operational Expense" : "Edit Expense Details"),
              content: SizedBox(
                width: 580,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date & Category selection
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final selected = await showDatePicker(
                                    context: context,
                                    initialDate: expenseDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (selected != null) {
                                    setDialogState(() => expenseDate = selected);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(labelText: "Expense Date"),
                                  child: Text(_formatDate(expenseDate)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedCategory,
                                decoration: const InputDecoration(labelText: "Expense Category *"),
                                items: _categories
                                    .where((c) => c != "All")
                                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedCategory = val);
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
                              child: TextFormField(
                                controller: subcatCtrl,
                                decoration: const InputDecoration(labelText: "Subcategory / Label (Optional)"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: amountCtrl,
                                decoration: const InputDecoration(labelText: "Total Bill Amount (₹) *"),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (val) => val == null || double.tryParse(val) == null ? "Enter valid bill amount" : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Vendor Link Switch
                        Row(
                          children: [
                            const Text("Link Registered Vendor", style: TextStyle(fontSize: 12, color: Color(0xFF27500A), fontWeight: FontWeight.w600)),
                            const SizedBox(width: 10),
                            Switch(
                              value: enableVendor,
                              activeColor: const Color(0xFF3B6D11),
                              onChanged: (val) {
                                if (_vendors.isEmpty && val) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('No registered vendors found!'), backgroundColor: Color(0xFFC62828)),
                                  );
                                  return;
                                }
                                setDialogState(() {
                                  enableVendor = val;
                                  if (val && selectedVendor == null && _vendors.isNotEmpty) {
                                    selectedVendor = _vendors.first;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        
                        if (enableVendor && selectedVendor != null) ...[
                          const SizedBox(height: 5),
                          DropdownButtonFormField<VendorModel>(
                            value: selectedVendor,
                            decoration: const InputDecoration(labelText: "Select Supplier Vendor"),
                            items: _vendors.map((v) => DropdownMenuItem(value: v, child: Text(v.name))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => selectedVendor = val);
                              }
                            },
                          ),
                        ],
                        
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: descCtrl,
                          decoration: const InputDecoration(labelText: "Payment Description / Notes *"),
                          maxLines: 2,
                          validator: (val) => val == null || val.isEmpty ? "Enter expense description" : null,
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(color: Color(0xFFC0DD97)),
                        ),
                        
                        const Text("Payment Settlement", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A), fontSize: 13)),
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
                      final double total = double.parse(amountCtrl.text.trim());

                      final paymentDetails = PaymentDetailsModel(
                        paymentMethod: paymentMethod,
                        paymentStatus: paymentStatus,
                        paymentDate: expenseDate,
                        bankName: bankCtrl.text.trim(),
                        transactionId: transactionCtrl.text.trim(),
                        cashVoucherNumber: voucherCtrl.text.trim(),
                        receivedBy: receivedByCtrl.text.trim(),
                        chequeNumber: chequeNumCtrl.text.trim(),
                        chequeDate: chequeDate,
                        chequeClearanceStatus: chequeStatus,
                      );

                      final now = DateTime.now();

                      final newEntry = ExpenseEntryModel(
                        id: expense?.id ?? "",
                        expenseDate: expenseDate,
                        category: selectedCategory,
                        subcategory: subcatCtrl.text.trim(),
                        description: descCtrl.text.trim(),
                        vendorId: enableVendor && selectedVendor != null ? selectedVendor!.id : null,
                        vendorName: enableVendor && selectedVendor != null ? selectedVendor!.name : null,
                        totalAmount: total,
                        paymentDetails: paymentDetails,
                        createdBy: "Admin",
                        updatedBy: "Admin",
                        createdAt: expense?.createdAt ?? now,
                        updatedAt: now,
                      );

                      if (expense == null) {
                        await _service.addExpenseEntry(newEntry);
                      } else {
                        await _service.updateExpenseEntry(expense.id, newEntry);
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(expense == null ? 'Expense successfully recorded.' : 'Expense successfully updated.'),
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
}
