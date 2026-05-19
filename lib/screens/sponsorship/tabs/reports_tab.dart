import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/sponsorship_model.dart';
import '../../inventory_expense/utils/export_utility.dart'; // Reuse the custom premium print/excel utility!

/// Tab to compile, review, filter, and export sponsorship bookings reports
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _service = ServiceLocator().sponsorshipService;

  List<SponsorshipModel> _allBookings = [];
  StreamSubscription? _subscription;
  bool _loading = true;

  // Filter criteria
  String _selectedReportType = "Monthly Sponsorship Report";
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  String _selectedSponsorQuery = "";

  // Compiled states cache
  List<List<dynamic>> _generatedRows = [];
  List<String> _headers = [];
  double _totalCollection = 0.0;

  final List<String> _reportTypes = [
    "Daily Sponsorship Report",
    "Monthly Sponsorship Report",
    "Yearly Sponsorship Report",
    "Sponsor-wise Report"
  ];

  final List<String> _months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ];

  @override
  void initState() {
    super.initState();
    _subscribeStream();
  }

  void _subscribeStream() {
    _subscription = _service.getSponsorshipsStream().listen((data) {
      if (mounted) {
        setState(() {
          _allBookings = data;
          _loading = false;
          _compileReport(); // Initial load generate
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Evaluates selections and compiles sponsorship rows
  void _compileReport() {
    final List<List<dynamic>> rows = [];
    double totalSum = 0.0;

    _headers = ["Date", "Sponsor Details", "Contact No", "Occasion", "Honoree Name", "Amount (₹)", "Payment", "Status"];

    for (final s in _allBookings) {
      bool include = false;

      switch (_selectedReportType) {
        case "Daily Sponsorship Report":
          include = s.sponsorshipDate.year == _selectedDate.year &&
                    s.sponsorshipDate.month == _selectedDate.month &&
                    s.sponsorshipDate.day == _selectedDate.day;
          break;

        case "Monthly Sponsorship Report":
          include = s.sponsorshipDate.year == _selectedDate.year &&
                    s.sponsorshipDate.month == _selectedDate.month;
          break;

        case "Yearly Sponsorship Report":
          include = s.sponsorshipDate.year == _selectedYear;
          break;

        case "Sponsor-wise Report":
          if (_selectedSponsorQuery.isEmpty) {
            include = true; // Show all if search is blank
          } else {
            include = s.sponsorName.toLowerCase().contains(_selectedSponsorQuery.toLowerCase());
          }
          break;
      }

      // Exclude Cancelled entries from reports calculation
      if (s.bookingStatus == 'Cancelled') {
        continue;
      }

      if (include) {
        rows.add([
          _formatDate(s.sponsorshipDate),
          "${s.sponsorPrefix} ${s.sponsorName}",
          s.sponsorMobile,
          s.occasion,
          s.honoreeName?.isNotEmpty ?? false ? s.honoreeName! : "—",
          s.amount.toStringAsFixed(2),
          s.paymentStatus,
          s.bookingStatus
        ]);
        totalSum += s.amount;
      }
    }

    setState(() {
      _generatedRows = rows;
      _totalCollection = totalSum;
    });
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
          // Dynamic Report Filter Panel
          _buildFilterPanel(),
          const SizedBox(height: 15),

          // Total aggregate collections and export triggers
          _buildActionHeader(),
          const SizedBox(height: 10),

          // Generated Grid Table Preview
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
                    ? const Center(child: Text("No records compiled for the selected parameters", style: TextStyle(color: Color(0xFF639922))))
                    : ListView(
                        children: [
                          DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F9F0)),
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 48,
                            columns: _headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))))).toList(),
                            rows: _generatedRows.map((row) {
                              return DataRow(
                                cells: row.map((cell) {
                                  final valStr = cell?.toString() ?? '';
                                  if (valStr == 'Paid' || valStr == 'Confirmed' || valStr == 'Completed') {
                                    return DataCell(_buildCellBadge(valStr, const Color(0xFFE8F5E9), const Color(0xFF2E7D32)));
                                  } else if (valStr == 'Pending' || valStr == 'Cancelled') {
                                    return DataCell(_buildCellBadge(valStr, const Color(0xFFFFEBEE), const Color(0xFFC62828)));
                                  } else if (valStr == 'Partial' || valStr == 'Booked') {
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildFilterPanel() {
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
                  decoration: const InputDecoration(labelText: "Select Report Type *"),
                  items: _reportTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedReportType = val;
                        _compileReport();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 20),

              // Conditional configurations: Daily selector
              if (_selectedReportType == "Daily Sponsorship Report") ...[
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (selected != null) {
                        setState(() {
                          _selectedDate = selected;
                          _compileReport();
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: "Choose Target Date"),
                      child: Text(_formatDate(_selectedDate)),
                    ),
                  ),
                ),
              ],

              // Conditional configurations: Monthly Selector
              if (_selectedReportType == "Monthly Sponsorship Report") ...[
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _selectedDate.month,
                    decoration: const InputDecoration(labelText: "Choose Month"),
                    items: List.generate(12, (index) {
                      return DropdownMenuItem(value: index + 1, child: Text(_months[index]));
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDate = DateTime(_selectedDate.year, val, 1);
                          _compileReport();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _selectedDate.year,
                    decoration: const InputDecoration(labelText: "Choose Year"),
                    items: List.generate(10, (index) {
                      final yr = DateTime.now().year - 5 + index;
                      return DropdownMenuItem(value: yr, child: Text("$yr"));
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDate = DateTime(val, _selectedDate.month, 1);
                          _compileReport();
                        });
                      }
                    },
                  ),
                ),
              ],

              // Conditional configurations: Yearly selector
              if (_selectedReportType == "Yearly Sponsorship Report") ...[
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: const InputDecoration(labelText: "Select Calendar Year"),
                    items: List.generate(10, (index) {
                      final yr = DateTime.now().year - 5 + index;
                      return DropdownMenuItem(value: yr, child: Text("$yr"));
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedYear = val;
                          _compileReport();
                        });
                      }
                    },
                  ),
                ),
              ],

              // Conditional configurations: Sponsor-wise search
              if (_selectedReportType == "Sponsor-wise Report") ...[
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: "Sponsor Name query",
                      hintText: "Enter part of sponsor name...",
                    ),
                    onChanged: (val) {
                      setState(() {
                        _selectedSponsorQuery = val;
                        _compileReport();
                      });
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

  Widget _buildActionHeader() {
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
          // Aggregate Sum
          Text(
            "Compiled Total Sponsored Collections: ₹${_totalCollection.toStringAsFixed(2)}",
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF27500A),
            ),
          ),
          
          // Action Buttons: Excel, CSV, PDF
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
      sheetName: "Sponsorships",
      headers: _headers,
      rows: _generatedRows,
      defaultFileName: "${_selectedReportType.replaceAll(' ', '_')}_report",
    );
  }

  void _exportToPDF(BuildContext context) {
    if (_generatedRows.isEmpty) return;
    String subtitle = "";

    switch (_selectedReportType) {
      case "Daily Sponsorship Report":
        subtitle = "Date: ${_formatDate(_selectedDate)}";
        break;
      case "Monthly Sponsorship Report":
        subtitle = "Month: ${_months[_selectedDate.month - 1]} ${_selectedDate.year}";
        break;
      case "Yearly Sponsorship Report":
        subtitle = "Year: $_selectedYear";
        break;
      case "Sponsor-wise Report":
        subtitle = _selectedSponsorQuery.isNotEmpty ? "Sponsor contains: '$_selectedSponsorQuery'" : "All Sponsor Dossier";
        break;
    }

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
