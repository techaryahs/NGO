import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/service_locator.dart';
import '../../../models/sponsorship_model.dart';

/// Tab to view, edit, search, and record advance sponsorship bookings
class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  final _service = ServiceLocator().sponsorshipService;

  List<SponsorshipModel> _allSponsorships = [];
  List<SponsorshipModel> _filteredSponsorships = [];
  StreamSubscription? _subscription;
  bool _loading = true;

  // Filters
  String _searchQuery = "";
  DateTime? _filterDate;
  String _filterOccasion = "All";
  String _filterStatus = "All";

  // Pagination & Sorting
  int _currentPage = 0;
  final int _rowsPerPage = 8;
  bool _sortAscending = true;
  int _sortColumnIndex = 0;

  // Dropdowns lists
  final List<String> _prefixes = ["Shri", "Shrimati", "Late", "Dr.", "Mr.", "Mrs."];
  final List<String> _occasions = ["Birthday", "Anniversary", "Punyatithi", "Memorial", "Festival", "Other"];
  final List<String> _paymentMethods = ["Cash", "Cheque", "UPI", "Bank Transfer", "Online"];
  final List<String> _paymentStatuses = ["Paid", "Pending", "Partial"];
  final List<String> _bookingStatuses = ["Booked", "Confirmed", "Completed", "Cancelled"];

  @override
  void initState() {
    super.initState();
    _subscribeStream();
  }

  void _subscribeStream() {
    _subscription = _service.getSponsorshipsStream().listen((data) {
      if (mounted) {
        setState(() {
          _allSponsorships = data;
          _applyFilters();
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _applyFilters() {
    List<SponsorshipModel> temp = List.from(_allSponsorships);

    // Text search (Sponsor name or Honoree)
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      temp = temp.where((s) =>
        s.sponsorName.toLowerCase().contains(q) ||
        (s.honoreeName?.toLowerCase().contains(q) ?? false) ||
        s.sponsorMobile.contains(q)
      ).toList();
    }

    // Date filter
    if (_filterDate != null) {
      temp = temp.where((s) =>
        s.sponsorshipDate.year == _filterDate!.year &&
        s.sponsorshipDate.month == _filterDate!.month &&
        s.sponsorshipDate.day == _filterDate!.day
      ).toList();
    }

    // Occasion filter
    if (_filterOccasion != "All") {
      temp = temp.where((s) => s.occasion == _filterOccasion).toList();
    }

    // Status filter
    if (_filterStatus != "All") {
      temp = temp.where((s) => s.bookingStatus == _filterStatus).toList();
    }

    // Re-apply sorting
    _sortData(temp);

    setState(() {
      _filteredSponsorships = temp;
      _currentPage = 0; // Reset pagination on filter
    });
  }

  void _sortData(List<SponsorshipModel> list) {
    list.sort((a, b) {
      dynamic valA, valB;
      switch (_sortColumnIndex) {
        case 0: // Date
          valA = a.sponsorshipDate;
          valB = b.sponsorshipDate;
          break;
        case 1: // Sponsor Name
          valA = a.sponsorName.toLowerCase();
          valB = b.sponsorName.toLowerCase();
          break;
        case 2: // Occasion
          valA = a.occasion;
          valB = b.occasion;
          break;
        case 3: // Honoree
          valA = a.honoreeName?.toLowerCase() ?? '';
          valB = b.honoreeName?.toLowerCase() ?? '';
          break;
        case 4: // Amount
          valA = a.amount;
          valB = b.amount;
          break;
        case 5: // Payment Status
          valA = a.paymentStatus;
          valB = b.paymentStatus;
          break;
        case 6: // Booking Status
          valA = a.bookingStatus;
          valB = b.bookingStatus;
          break;
        default:
          return 0;
      }
      return _sortAscending
          ? Comparable.compare(valA, valB)
          : Comparable.compare(valB, valA);
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _sortData(_filteredSponsorships);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11)));
    }

    // Paginated sublist computation
    final totalRows = _filteredSponsorships.length;
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalRows);
    final pageRows = _filteredSponsorships.isNotEmpty
        ? _filteredSponsorships.sublist(startIndex, endIndex)
        : <SponsorshipModel>[];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter & Search Controls Bar
          _buildFilterBar(),
          const SizedBox(height: 15),

          // Main data Grid table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFDF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    Expanded(
                      child: totalRows == 0
                          ? const Center(child: Text("No sponsorship bookings recorded", style: TextStyle(color: Color(0xFF639922))))
                          : SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F9F0)),
                                  sortColumnIndex: _sortColumnIndex,
                                  sortAscending: _sortAscending,
                                  dataRowMinHeight: 52,
                                  dataRowMaxHeight: 52,
                                  columns: [
                                    DataColumn(
                                      label: const Text("Date", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                      onSort: _onSort,
                                    ),
                                    DataColumn(
                                      label: const Text("Sponsor Name", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                      onSort: _onSort,
                                    ),
                                    DataColumn(
                                      label: const Text("Occasion", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                      onSort: _onSort,
                                    ),
                                    DataColumn(
                                      label: const Text("Honoree Name", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                      onSort: _onSort,
                                    ),
                                    DataColumn(
                                      label: const Text("Amount (₹)", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                      onSort: _onSort,
                                    ),
                                    DataColumn(
                                      label: const Text("Payment Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                      onSort: _onSort,
                                    ),
                                    DataColumn(
                                      label: const Text("Booking Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                      onSort: _onSort,
                                    ),
                                    const DataColumn(
                                      label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A))),
                                    ),
                                  ],
                                  rows: pageRows.map((s) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(_formatDate(s.sponsorshipDate))),
                                        DataCell(Text("${s.sponsorPrefix} ${s.sponsorName}")),
                                        DataCell(Text(s.occasion)),
                                        DataCell(Text(s.honoreeName?.isNotEmpty ?? false ? s.honoreeName! : "—")),
                                        DataCell(Text("₹${s.amount.toStringAsFixed(1)}")),
                                        DataCell(_buildPaymentStatusBadge(s.paymentStatus)),
                                        DataCell(_buildBookingStatusBadge(s.bookingStatus)),
                                        DataCell(
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, color: Color(0xFF3B6D11), size: 20),
                                                onPressed: () => _openBookingDialog(s),
                                                tooltip: "Edit Booking",
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                                onPressed: () => _confirmDelete(s),
                                                tooltip: "Delete Record",
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                    ),
                    
                    // Pagination controllers
                    if (totalRows > 0) _buildPaginationFooter(totalRows, startIndex, endIndex),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusBadge(String status) {
    Color bg = const Color(0xFFFFEBEE);
    Color fg = const Color(0xFFC62828);
    if (status == 'Paid') {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    } else if (status == 'Partial') {
      bg = const Color(0xFFFFF8E1);
      fg = const Color(0xFFF57F17);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(status, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildBookingStatusBadge(String status) {
    Color bg = const Color(0xFFE0F2F1);
    Color fg = const Color(0xFF00796B);
    
    if (status == 'Confirmed') {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    } else if (status == 'Completed') {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF1565C0);
    } else if (status == 'Cancelled') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(status, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFDF7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Wrap(
        spacing: 15,
        runSpacing: 15,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search Input
          SizedBox(
            width: 300,
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Search by Sponsor, Honoree, or Mobile...",
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: Color(0xFF639922)),
                contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _applyFilters();
                });
              },
            ),
          ),

          // Date Picker filter
          SizedBox(
            width: 200,
            child: InkWell(
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _filterDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                setState(() {
                  _filterDate = selected;
                  _applyFilters();
                });
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Date Filter",
                  contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_filterDate == null ? "Select Date" : _formatDate(_filterDate!)),
                    if (_filterDate != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _filterDate = null;
                            _applyFilters();
                          });
                        },
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      )
                  ],
                ),
              ),
            ),
          ),

          // Occasion Selector
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              value: _filterOccasion,
              decoration: const InputDecoration(
                labelText: "Occasion Filter",
                contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              ),
              items: ["All", ..._occasions].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filterOccasion = val;
                    _applyFilters();
                  });
                }
              },
            ),
          ),

          // Status Selector
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              value: _filterStatus,
              decoration: const InputDecoration(
                labelText: "Status Filter",
                contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              ),
              items: ["All", ..._bookingStatuses].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filterStatus = val;
                    _applyFilters();
                  });
                }
              },
            ),
          ),

          // Add Booking Button
          ElevatedButton.icon(
            onPressed: () => _openBookingDialog(null),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("Book Sponsorship"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B6D11),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter(int totalRows, int startIndex, int endIndex) {
    final maxPages = (totalRows / _rowsPerPage).ceil();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F9F0),
        border: Border(top: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Showing ${startIndex + 1} to $endIndex of $totalRows bookings",
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF27500A)),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
              ),
              Text(
                "Page ${_currentPage + 1} of $maxPages",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF27500A)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _currentPage < maxPages - 1 ? () => setState(() => _currentPage++) : null,
              ),
            ],
          )
        ],
      ),
    );
  }

  // --- CRUD dialog ---
  void _openBookingDialog(SponsorshipModel? existing) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BookingFormModal(
        existing: existing,
        allSponsorships: _allSponsorships,
        onSave: (model) async {
          if (existing == null) {
            await _service.addSponsorship(model);
          } else {
            await _service.updateSponsorship(existing.id, model);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(existing == null ? "Sponsorship successfully booked!" : "Sponsorship successfully updated!"),
                backgroundColor: const Color(0xFF3B6D11),
              ),
            );
          }
        },
      ),
    );
  }

  void _confirmDelete(SponsorshipModel model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Sponsorship Record?"),
        content: Text("Are you absolutely sure you want to delete the booking for ${model.sponsorPrefix} ${model.sponsorName} scheduled on ${_formatDate(model.sponsorshipDate)}? This action is permanent."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _service.deleteSponsorship(model.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Sponsorship booking deleted!"),
                    backgroundColor: Color(0xFFD32F2F),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }
}

/// Modal Form component for Creating & Editing Sponsorship bookings
class BookingFormModal extends StatefulWidget {
  final SponsorshipModel? existing;
  final List<SponsorshipModel> allSponsorships;
  final Function(SponsorshipModel) onSave;

  const BookingFormModal({
    super.key,
    this.existing,
    required this.allSponsorships,
    required this.onSave,
  });

  @override
  State<BookingFormModal> createState() => _BookingFormModalState();
}

class _BookingFormModalState extends State<BookingFormModal> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _selectedDate;
  late String _sponsorPrefix;
  final _sponsorNameCtrl = TextEditingController();
  final _sponsorMobileCtrl = TextEditingController();
  
  late String _referencePrefix;
  final _referenceNameCtrl = TextEditingController();
  final _referenceMobileCtrl = TextEditingController();

  late String _occasion;
  final _honoreeNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  late String _paymentMethod;
  late String _paymentStatus;
  final _transactionRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late String _bookingStatus;

  // Conflict state indicator
  SponsorshipModel? _conflictSponsorship;

  @override
  void initState() {
    super.initState();
    final model = widget.existing;

    _selectedDate = model?.sponsorshipDate ?? DateTime.now().add(const Duration(days: 1)); // Default tomorrow
    _sponsorPrefix = model?.sponsorPrefix ?? "Shri";
    _sponsorNameCtrl.text = model?.sponsorName ?? "";
    _sponsorMobileCtrl.text = model?.sponsorMobile ?? "";
    _referencePrefix = model?.referencePrefix ?? "Shri";
    _referenceNameCtrl.text = model?.referenceName ?? "";
    _referenceMobileCtrl.text = model?.referenceMobile ?? "";
    _occasion = model?.occasion ?? "Birthday";
    _honoreeNameCtrl.text = model?.honoreeName ?? "";
    _amountCtrl.text = model?.amount.toString() ?? "";
    _paymentMethod = model?.paymentMethod ?? "Cash";
    _paymentStatus = model?.paymentStatus ?? "Pending";
    _transactionRefCtrl.text = model?.transactionRef ?? "";
    _notesCtrl.text = model?.notes ?? "";
    _bookingStatus = model?.bookingStatus ?? "Booked";

    _checkForConflicts();
  }

  @override
  void dispose() {
    _sponsorNameCtrl.dispose();
    _sponsorMobileCtrl.dispose();
    _referenceNameCtrl.dispose();
    _referenceMobileCtrl.dispose();
    _honoreeNameCtrl.dispose();
    _amountCtrl.dispose();
    _transactionRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Scans state to check if a sponsorship is already booked for this date
  void _checkForConflicts() {
    final conflict = widget.allSponsorships.firstWhere(
      (s) =>
          s.id != widget.existing?.id &&
          s.sponsorshipDate.year == _selectedDate.year &&
          s.sponsorshipDate.month == _selectedDate.month &&
          s.sponsorshipDate.day == _selectedDate.day &&
          s.bookingStatus != 'Cancelled',
      orElse: () => SponsorshipModel(
        id: '',
        sponsorshipDate: DateTime.now(),
        sponsorPrefix: '',
        sponsorName: '',
        sponsorMobile: '',
        referencePrefix: '',
        referenceName: '',
        referenceMobile: '',
        occasion: '',
        amount: 0,
        paymentMethod: '',
        paymentStatus: '',
        transactionRef: '',
        notes: '',
        bookingStatus: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: '',
        updatedBy: '',
      ),
    );

    setState(() {
      _conflictSponsorship = conflict.id.isNotEmpty ? conflict : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existing == null ? "New Sponsorship Booking" : "Edit Sponsorship Booking";

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.card_giftcard_rounded, color: Color(0xFF3B6D11)),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(color: Color(0xFF27500A), fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 800,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Real-time duplicate booking Warning Banner
                if (_conflictSponsorship != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFFECB5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "⚠️ DUPLICATE BOOKING ALERT: This date has already been booked by ${_conflictSponsorship!.sponsorPrefix} ${_conflictSponsorship!.sponsorName} for ${_conflictSponsorship!.occasion}.\nProceeding will list this as an alternative scheduling entry.",
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF856404), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Row 1: Date & Statuses
                Row(
                  children: [
                    // Date picker field
                    Expanded(
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
                              _checkForConflicts();
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: "Sponsorship Date *"),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}"),
                              const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF3B6D11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),

                    // Booking Status
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _bookingStatus,
                        decoration: const InputDecoration(labelText: "Booking Status *"),
                        items: ["Booked", "Confirmed", "Completed", "Cancelled"]
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) => setState(() => _bookingStatus = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Sponsor Details Header
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text("1. Sponsor Information", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B6D11))),
                ),
                const Divider(),
                Row(
                  children: [
                    // Sponsor Prefix
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _sponsorPrefix,
                        decoration: const InputDecoration(labelText: "Prefix *"),
                        items: ["Shri", "Shrimati", "Late", "Dr.", "Mr.", "Mrs."]
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (val) => setState(() => _sponsorPrefix = val!),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Sponsor Name
                    Expanded(
                      flex: 5,
                      child: TextFormField(
                        controller: _sponsorNameCtrl,
                        decoration: const InputDecoration(labelText: "Sponsor Name *"),
                        validator: (v) => v!.isEmpty ? "Enter Sponsor Name" : null,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Sponsor Mobile
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _sponsorMobileCtrl,
                        decoration: const InputDecoration(labelText: "Mobile Number *"),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) => v!.length < 10 ? "Enter valid 10-digit number" : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Reference Details Header
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text("2. Reference / Guardian details", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B6D11))),
                ),
                const Divider(),
                Row(
                  children: [
                    // Reference Prefix
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _referencePrefix,
                        decoration: const InputDecoration(labelText: "Prefix *"),
                        items: ["Shri", "Shrimati", "Late", "Dr.", "Mr.", "Mrs."]
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (val) => setState(() => _referencePrefix = val!),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Reference Name
                    Expanded(
                      flex: 5,
                      child: TextFormField(
                        controller: _referenceNameCtrl,
                        decoration: const InputDecoration(labelText: "Reference Name *"),
                        validator: (v) => v!.isEmpty ? "Enter Reference Name" : null,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Reference Mobile
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _referenceMobileCtrl,
                        decoration: const InputDecoration(labelText: "Mobile Number *"),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) => v!.length < 10 ? "Enter valid 10-digit number" : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Occasion Details Header
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text("3. Occasion & Honoree Details", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B6D11))),
                ),
                const Divider(),
                Row(
                  children: [
                    // Occasion / Reason selection
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _occasion,
                        decoration: const InputDecoration(labelText: "Occasion / Reason *"),
                        items: ["Birthday", "Anniversary", "Punyatithi", "Memorial", "Festival", "Other"]
                            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                            .toList(),
                        onChanged: (val) => setState(() => _occasion = val!),
                      ),
                    ),
                    const SizedBox(width: 15),

                    // Honoree Name
                    Expanded(
                      child: TextFormField(
                        controller: _honoreeNameCtrl,
                        decoration: const InputDecoration(labelText: "Honoree Name (Optional)"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Financial Details Header
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text("4. Payouts & Accounting", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B6D11))),
                ),
                const Divider(),
                Row(
                  children: [
                    // Sponsorship Amount
                    Expanded(
                      child: TextFormField(
                        controller: _amountCtrl,
                        decoration: const InputDecoration(labelText: "Sponsorship Amount *", prefixText: "₹ "),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                        validator: (v) => v!.isEmpty ? "Enter Sponsorship Amount" : null,
                      ),
                    ),
                    const SizedBox(width: 15),

                    // Payment Method
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _paymentMethod,
                        decoration: const InputDecoration(labelText: "Payment Method *"),
                        items: ["Cash", "Cheque", "UPI", "Bank Transfer", "Online"]
                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (val) => setState(() => _paymentMethod = val!),
                      ),
                    ),
                    const SizedBox(width: 15),

                    // Payment Status
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _paymentStatus,
                        decoration: const InputDecoration(labelText: "Payment Status *"),
                        items: ["Paid", "Pending", "Partial"]
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) => setState(() => _paymentStatus = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Transaction Ref & Notes
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _transactionRefCtrl,
                        decoration: const InputDecoration(labelText: "Transaction Ref (UTR/Cheque No/Voucher ID)"),
                      ),
                    ),
                    const SizedBox(width: 15),

                    Expanded(
                      child: TextFormField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(labelText: "Additional Notes"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              final newModel = SponsorshipModel(
                id: widget.existing?.id ?? '',
                sponsorshipDate: _selectedDate,
                sponsorPrefix: _sponsorPrefix,
                sponsorName: _sponsorNameCtrl.text,
                sponsorMobile: _sponsorMobileCtrl.text,
                referencePrefix: _referencePrefix,
                referenceName: _referenceNameCtrl.text,
                referenceMobile: _referenceMobileCtrl.text,
                occasion: _occasion,
                honoreeName: _honoreeNameCtrl.text.isNotEmpty ? _honoreeNameCtrl.text : null,
                amount: double.parse(_amountCtrl.text),
                paymentMethod: _paymentMethod,
                paymentStatus: _paymentStatus,
                transactionRef: _transactionRefCtrl.text,
                notes: _notesCtrl.text,
                bookingStatus: _bookingStatus,
                createdAt: widget.existing?.createdAt ?? DateTime.now(),
                updatedAt: DateTime.now(),
                createdBy: widget.existing?.createdBy ?? "Admin",
                updatedBy: "Admin",
              );

              Navigator.pop(context);
              widget.onSave(newModel);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white),
          child: const Text("Save Booking"),
        ),
      ],
    );
  }
}
