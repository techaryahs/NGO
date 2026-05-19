import 'package:flutter/material.dart';
import 'tabs/bookings_tab.dart';
import 'tabs/calendar_tab.dart';
import 'tabs/reports_tab.dart';

/// Container Screen for the Sponsorship Management Module
class SponsorshipScreen extends StatefulWidget {
  const SponsorshipScreen({super.key});

  @override
  State<SponsorshipScreen> createState() => _SponsorshipScreenState();
}

class _SponsorshipScreenState extends State<SponsorshipScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F7EA),
        body: Column(
          children: [
            // Master navigation bar with secondary green healthcare accents
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFAFDF7),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                ),
              ),
              alignment: Alignment.centerLeft,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: Color(0xFF3B6D11),
                labelColor: Color(0xFF3B6D11),
                unselectedLabelColor: Color(0xFF639922),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorWeight: 3.0,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  fontFamily: 'Segoe UI',
                ),
                unselectedLabelStyle: TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 13.5,
                ),
                tabs: [
                  Tab(text: "Sponsorship Bookings"),
                  Tab(text: "Sponsorship Calendar"),
                  Tab(text: "Reports & Exports"),
                ],
              ),
            ),
            
            // Expanded content section
            const Expanded(
              child: TabBarView(
                children: [
                  BookingsTab(),
                  CalendarTab(),
                  ReportsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
