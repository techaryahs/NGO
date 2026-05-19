import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../utils/export_utility.dart';
import '../../../models/purchase_model.dart';
import '../../../models/expense_entry_model.dart';
import '../../../models/salary_model.dart';
import '../../../models/inventory_item_model.dart';
import '../../../models/vendor_model.dart';

/// Sub-tab to compile customized operations reports and export to Excel, CSV, and PDF
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _service = ServiceLocator().inventoryExpenseService;

  List<PurchaseModel> _purchases = [];
  List<ExpenseEntryModel> _expenses = [];
  List<SalaryModel> _salaries = [];
  List<InventoryItemModel> _items = [];
  List<VendorModel> _vendors = [];

  StreamSubscription? _purchasesSub;
  StreamSubscription? _expensesSub;
  StreamSubscription? _salariesSub;
  StreamSubscription? _itemsSub;
  StreamSubscription? _vendorsSub;

  bool _loading = true;

  // Filter values
  String _selectedReportType = "Monthly Expense Report";
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  String _selectedCategory = "All";
  String _selectedVendor = "All";
  String _selectedPaymentMethod = "All";
  String _selectedPaymentStatus = "All";

  // Generated Report Cache
  List<List<dynamic>> _generatedRows = [];
  List<String> _headers = [];
  double _totalSum = 0.0;

  final List<String> _reportTypes = [
    "Monthly Expense Report",
    "Yearly Expense Report",
    "Category-wise Report",
    "Vendor-wise Report",
    "Salary Report",
    "Payment Method Report",
    "Pending Payments Report",
    "Low Stock Report"
  ];

  final List<String> _categories = [
    "All", "Fruits", "Vegetables", "Groceries", "Drinking Water", "Water Tanker",
    "Laundry", "Cable TV", "Internet", "Canteen", "Housekeeping", "Cleaning Material",
    "Electricity", "Maintenance"
  ];

  final List<String> _paymentMethods = [
    "All", "Cash", "Cheque", "UPI", "NEFT / RTGS / IMPS", "Bank Transfer", "Credit Card", "Debit Card", "Other"
  ];

  @override
  void initState() {
    super.initState();
    _subscribeStreams();
  }

  void _subscribeStreams() {
    _purchasesSub = _service.getPurchasesStream().listen((data) {
      if (mounted) setState(() { _purchases = data; _checkLoading(); });
    });
    _expensesSub = _service.getExpenseEntriesStream().listen((data) {
      if (mounted) setState(() { _expenses = data; _checkLoading(); });
    });
    _salariesSub = _service.getSalariesStream().listen((data) {
      if (mounted) setState(() { _salaries = data; _checkLoading(); });
    });
    _itemsSub = _service.getInventoryItemsStream().listen((data) {
      if (mounted) setState(() { _items = data; _checkLoading(); });
    });
    _vendorsSub = _service.getVendorsStream().listen((data) {
      if (mounted) setState(() { _vendors = data; _checkLoading(); });
    });
  }

  void _checkLoading() {
    if (_purchasesSub != null && _expensesSub != null && _salariesSub != null && _itemsSub != null && _vendorsSub != null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _generateReport(); // Pre-generate initial report
        });
      }
    }
  }

  @override
  void dispose() {
    _purchasesSub?.cancel();
    _expensesSub?.cancel();
    _salariesSub?.cancel();
    _itemsSub?.cancel();
    _vendorsSub?.cancel();
    super.dispose();
  }

  /// Master function to compile report records in-memory based on selected filters
  void _generateReport() {
    final List<List<dynamic>> rows = [];
    double sum = 0.0;

    switch (_selectedReportType) {
      case "Monthly Expense Report":
      case "Yearly Expense Report":
      case "Category-wise Report":
      case "Vendor-wise Report":
      case "Payment Method Report":
      case "Pending Payments Report":
        _headers = ["Date", "Type", "Ref/Invoice No", "Category/Item", "Vendor/Employee", "Total Amount (₹)", "Method", "Status"];
        
        // 1. Process Purchases
        for (final p in _purchases) {
          if (!_checkDateFilter(p.purchaseDate)) continue;
          if (_selectedCategory != "All" && p.itemName != _selectedCategory) continue;
          if (_selectedVendor != "All" && p.vendorName != _selectedVendor) continue;
          if (_selectedPaymentMethod != "All" && p.paymentDetails.paymentMethod != _selectedPaymentMethod) continue;
          if (_selectedPaymentStatus != "All" && p.paymentDetails.paymentStatus != _selectedPaymentStatus) continue;

          rows.add([
            _formatDate(p.purchaseDate),
            "Purchase",
            p.invoiceNumber.isNotEmpty ? p.invoiceNumber : "—",
            p.itemName,
            p.vendorName,
            p.totalAmount.toStringAsFixed(2),
            p.paymentDetails.paymentMethod,
            p.paymentDetails.paymentStatus
          ]);
          sum += p.totalAmount;
        }

        // 2. Process Operational Expenses
        for (final e in _expenses) {
          if (!_checkDateFilter(e.expenseDate)) continue;
          if (_selectedCategory != "All" && e.category != _selectedCategory) continue;
          if (_selectedVendor != "All" && e.vendorName != _selectedVendor) continue;
          if (_selectedPaymentMethod != "All" && e.paymentDetails.paymentMethod != _selectedPaymentMethod) continue;
          if (_selectedPaymentStatus != "All" && e.paymentDetails.paymentStatus != _selectedPaymentStatus) continue;

          rows.add([
            _formatDate(e.expenseDate),
            "Operation",
            e.subcategory != null && e.subcategory!.isNotEmpty ? e.subcategory! : "—",
            e.category,
            e.vendorName != null && e.vendorName!.isNotEmpty ? e.vendorName! : "—",
            e.totalAmount.toStringAsFixed(2),
            e.paymentDetails.paymentMethod,
            e.paymentDetails.paymentStatus
          ]);
          sum += e.totalAmount;
        }
        break;

      case "Salary Report":
        _headers = ["Date", "Employee Name", "Role", "Salary Month", "Gross (₹)", "Deductions (₹)", "Net Paid (₹)", "Method", "Status"];
        
        for (final s in _salaries) {
          if (!_checkDateFilter(s.createdAt)) continue;
          if (_selectedPaymentMethod != "All" && s.paymentDetails.paymentMethod != _selectedPaymentMethod) continue;
          if (_selectedPaymentStatus != "All" && s.paymentDetails.paymentStatus != _selectedPaymentStatus) continue;

          rows.add([
            _formatDate(s.createdAt),
            s.employeeName,
            s.role,
            s.salaryMonth,
            s.grossSalary.toStringAsFixed(2),
            s.deductions.toStringAsFixed(2),
            s.netSalary.toStringAsFixed(2),
            s.paymentDetails.paymentMethod,
            s.paymentDetails.paymentStatus
          ]);
          sum += s.netSalary;
        }
        break;

      case "Low Stock Report":
        _headers = ["Item Name", "Category", "Unit", "Min Stock Level", "Current Stock", "Stock Deficit", "Status"];
        
        for (final item in _items) {
          if (!item.isLowStock) continue;
          if (_selectedCategory != "All" && item.category != _selectedCategory) continue;

          final deficit = (item.minStockLevel - item.currentStock).clamp(0.0, double.infinity);

          rows.add([
            item.name,
            item.category,
            item.unit,
            "${item.minStockLevel}",
            "${item.currentStock}",
            deficit.toStringAsFixed(2),
            "Low Stock Level"
          ]);
          sum += deficit;
        }
        break;
    }

    setState(() {
      _generatedRows = rows;
      _totalSum = sum;
    });
  }

  bool _checkDateFilter(DateTime date) {
    if (_selectedReportType == "Yearly Expense Report") {
      return date.year == DateTime.now().year;
    }
    // Standard Date Range checking
    return date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
           date.isBefore(_endDate.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11)));
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter Panel
          _buildFilterPanel(context),
          const SizedBox(height: 15),
          
          // Total Sum Indicator & Exports
          _buildUtilityHeader(context),
          const SizedBox(height: 10),

          // Generated Report Display
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFDF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _generatedRows.isEmpty
                    ? const Center(child: Text("No records match the active criteria", style: TextStyle(color: Color(0xFF639922))))
                    : ListView(
                        children: [
                          DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F9F0)),
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 48,
                            columns: _headers.map((h) {
                              return DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))));
                            }).toList(),
                            rows: _generatedRows.map((row) {
                              return DataRow(
                                cells: row.map((cell) {
                                  final valStr = cell?.toString() ?? '';
                                  if (valStr == 'Paid' || valStr == 'Cleared') {
                                    return DataCell(_buildCellBadge(valStr, const Color(0xFFE8F5E9), const Color(0xFF2E7D32)));
                                  } else if (valStr == 'Pending' || valStr == 'Low Stock Level' || valStr == 'Bounced') {
                                    return DataCell(_buildCellBadge(valStr, const Color(0xFFFFEBEE), const Color(0xFFC62828)));
                                  } else if (valStr == 'Partial') {
                                    return DataCell(_buildCellBadge(valStr, const Color(0xFFFFF8E1), const Color(0xFFF57F17)));
                                  }
                                  return DataCell(Text(valStr));
                                }).toList(),
                              );
                            }).toList(),
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

  Widget _buildCellBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFDF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Report Type selection
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _selectedReportType,
                  decoration: const InputDecoration(labelText: "Select Report Category *"),
                  items: _reportTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedReportType = val;
                        _generateReport();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 15),

              // Start date selector
              if (_selectedReportType != "Yearly Expense Report") ...[
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (selected != null) {
                        setState(() {
                          _startDate = selected;
                          _generateReport();
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: "Start Date"),
                      child: Text(_formatDate(_startDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 15),

                // End date selector
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (selected != null) {
                        setState(() {
                          _endDate = selected;
                          _generateReport();
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: "End Date"),
                      child: Text(_formatDate(_endDate)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          
          Row(
            children: [
              // Category filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(labelText: "Category Selection"),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategory = val;
                        _generateReport();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Vendor filter
              if (_selectedReportType != "SalaryReport" && _selectedReportType != "Low Stock Report") ...[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedVendor,
                    decoration: const InputDecoration(labelText: "Supplier Vendor"),
                    items: [
                      const DropdownMenuItem(value: "All", child: Text("All Vendors")),
                      ..._vendors.map((v) => DropdownMenuItem(value: v.name, child: Text(v.name)))
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedVendor = val;
                          _generateReport();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // Payment Method filter
              if (_selectedReportType != "Low Stock Report") ...[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedPaymentMethod,
                    decoration: const InputDecoration(labelText: "Settlement Method"),
                    items: _paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedPaymentMethod = val;
                          _generateReport();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),

                // Payment Status filter
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedPaymentStatus,
                    decoration: const InputDecoration(labelText: "Settlement Status"),
                    items: const [
                      DropdownMenuItem(value: "All", child: Text("All Statuses")),
                      DropdownMenuItem(value: "Paid", child: Text("Paid")),
                      DropdownMenuItem(value: "Pending", child: Text("Pending")),
                      DropdownMenuItem(value: "Partial", child: Text("Partial")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedPaymentStatus = val;
                          _generateReport();
                        });
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUtilityHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3DE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Total Spending Aggregation
          Text(
            _selectedReportType == "Low Stock Report"
                ? "Total Reorder Deficit Required: ${_totalSum.toStringAsFixed(1)} units"
                : "Total Compiled Expenses: ₹${_totalSum.toStringAsFixed(2)}",
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF27500A),
            ),
          ),
          
          // Action Buttons: Excel, CSV, PDF HTML
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _exportToExcel(context),
                icon: const Icon(Icons.table_view_rounded, size: 16, color: Color(0xFF3B6D11)),
                label: const Text("Excel", style: TextStyle(color: Color(0xFF27500A), fontSize: 12.5)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _exportToCSV(context),
                icon: const Icon(Icons.description_rounded, size: 16, color: Color(0xFF3B6D11)),
                label: const Text("CSV", style: TextStyle(color: Color(0xFF27500A), fontSize: 12.5)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _exportToPDF(context),
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text("Print / Save PDF"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B6D11),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _exportToCSV(BuildContext context) {
    if (_generatedRows.isEmpty) return;
    ExportUtility.exportToCSV(
      context: context,
      headers: _headers,
      rows: _generatedRows,
      defaultFileName: "${_selectedReportType.replaceAll(' ', '_')}_report",
    );
  }

  void _exportToExcel(BuildContext context) {
    if (_generatedRows.isEmpty) return;
    ExportUtility.exportToExcel(
      context: context,
      sheetName: "Report Data",
      headers: _headers,
      rows: _generatedRows,
      defaultFileName: "${_selectedReportType.replaceAll(' ', '_')}_report",
    );
  }

  void _exportToPDF(BuildContext context) {
    if (_generatedRows.isEmpty) return;
    final subtitle = _selectedReportType == "Yearly Expense Report"
        ? "Year: ${DateTime.now().year} | Filters: Category: $_selectedCategory, Vendor: $_selectedVendor"
        : "Date Range: ${_formatDate(_startDate)} to ${_formatDate(_endDate)} | Filters: Category: $_selectedCategory, Vendor: $_selectedVendor";

    ExportUtility.exportToPDF(
      context: context,
      reportTitle: _selectedReportType,
      subtitle: subtitle,
      headers: _headers,
      rows: _generatedRows,
      defaultFileName: "${_selectedReportType.replaceAll(' ', '_')}_report",
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }
}
