import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/sponsorship_model.dart';
import 'bookings_tab.dart'; // Reuse the BookingFormModal

/// Interactive Monthly Calendar View representing scheduled sponsorships
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  final _service = ServiceLocator().sponsorshipService;

  List<SponsorshipModel> _sponsorships = [];
  StreamSubscription? _subscription;
  bool _loading = true;

  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  final List<String> _weekDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
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
          _sponsorships = data;
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

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
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
          // Calendar Controller Header (Month/Year selections)
          _buildCalendarHeader(),
          const SizedBox(height: 15),

          // Days of the Week Columns
          _buildWeekDayColumns(),
          const SizedBox(height: 5),

          // Monthly Calendar Grid
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFDF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildCalendarGrid(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3DE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 15,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month_rounded, color: Color(0xFF3B6D11)),
              const SizedBox(width: 10),
              Text(
                "${_months[_currentMonth.month - 1]} ${_currentMonth.year}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF27500A),
                ),
              ),
            ],
          ),
          
          // Action Buttons: Previous/Next Month & Quick Guide
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              const Text(
                "💡 Double-click any empty date to quickly book!",
                style: TextStyle(fontSize: 12, color: Color(0xFF639922), fontStyle: FontStyle.italic),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF3B6D11)),
                onPressed: _previousMonth,
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
                  });
                },
                child: const Text("Today", style: TextStyle(color: Color(0xFF27500A), fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF3B6D11)),
                onPressed: _nextMonth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekDayColumns() {
    return Row(
      children: _weekDays.map((day) {
        return Expanded(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              day,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: Color(0xFF3B6D11),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarGrid() {
    // 1. Calculate dates layout parameters
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    
    final daysInMonth = lastDayOfMonth.day;
    final startWeekday = firstDayOfMonth.weekday % 7; // Convert Sun=0, Mon=1, ..., Sat=6

    final totalGridCells = daysInMonth + startWeekday;
    final rowsCount = (totalGridCells / 7).ceil();

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.45,
      ),
      itemCount: rowsCount * 7,
      itemBuilder: (context, index) {
        final dayIndex = index - startWeekday + 1;
        
        // Blank cells before month start or after month end
        if (index < startWeekday || dayIndex > daysInMonth) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAFDF7).withOpacity(0.4),
              border: Border.all(color: const Color(0xFFE6F3D6), width: 0.25),
            ),
          );
        }

        // Date of this cell
        final date = DateTime(_currentMonth.year, _currentMonth.month, dayIndex);
        
        // Fetch sponsorships matching this date
        final bookings = _sponsorships.where((s) =>
          s.sponsorshipDate.year == date.year &&
          s.sponsorshipDate.month == date.month &&
          s.sponsorshipDate.day == date.day &&
          s.bookingStatus != 'Cancelled'
        ).toList();

        final isToday = date.year == DateTime.now().year &&
                        date.month == DateTime.now().month &&
                        date.day == DateTime.now().day;

        return InkWell(
          onTap: () {
            if (bookings.isNotEmpty) {
              _showBookingsSummaryModal(date, bookings);
            }
          },
          onDoubleTap: () => _quickBookDate(date),
          child: Container(
            decoration: BoxDecoration(
              color: isToday ? const Color(0xFFEAF3DE) : Colors.transparent,
              border: Border.all(color: const Color(0xFFC0DD97), width: 0.35),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Day number indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: isToday
                          ? const BoxDecoration(color: Color(0xFF3B6D11), shape: BoxShape.circle)
                          : null,
                      child: Text(
                        "$dayIndex",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? Colors.white : const Color(0xFF27500A),
                        ),
                      ),
                    ),
                    if (bookings.isNotEmpty)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Color(0xFF3B6D11), shape: BoxShape.circle),
                      )
                  ],
                ),
                const SizedBox(height: 4),

                // Bookings snippet display inside cell
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: bookings.map((b) => _buildGridBookingBadge(b)).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridBookingBadge(SponsorshipModel b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFC8E6C9), width: 0.5),
      ),
      child: Text(
        "${b.sponsorPrefix} ${b.sponsorName} - ${b.occasion}",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
      ),
    );
  }

  void _quickBookDate(DateTime date) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BookingFormModal(
        existing: null,
        allSponsorships: _sponsorships,
        onSave: (model) async {
          // Pre-fill date when invoking
          final customized = model.copyWith(sponsorshipDate: date);
          await _service.addSponsorship(customized);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Sponsorship successfully booked!"),
                backgroundColor: Color(0xFF3B6D11),
              ),
            );
          }
        },
      ),
    );
  }

  void _showBookingsSummaryModal(DateTime date, List<SponsorshipModel> bookings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.checklist_rounded, color: Color(0xFF3B6D11)),
            const SizedBox(width: 10),
            Text(
              "Sponsorships on ${date.day}/${date.month}/${date.year}",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: bookings.length,
            itemBuilder: (context, index) {
              final b = bookings[index];
              return Card(
                color: const Color(0xFFFAFDF7),
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${b.sponsorPrefix} ${b.sponsorName}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF27500A)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "₹${b.amount}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2E7D32)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text("Occasion: ${b.occasion}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      if (b.honoreeName?.isNotEmpty ?? false)
                        Text("Honoree: ${b.honoreeName}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      Text("Contact: ${b.sponsorMobile}", style: const TextStyle(fontSize: 13, color: Colors.black54)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Status: ${b.bookingStatus}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3B6D11))),
                          Text("Payment: ${b.paymentStatus}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _quickBookDate(date);
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text("Book Additional"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
