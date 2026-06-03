import 'package:flutter/material.dart';
import 'package:ngo/screens/attendance/attendance.dart';

import '../patients/patients_screen.dart';
import '../rooms/rooms_page.dart';
import '../profile/profile_page.dart';
import '../settings/settings_page.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory_expense/inventory_expense_screen.dart';
import '../sponsorship/sponsorship_screen.dart';
import '../payments/payments_screen.dart';

import 'widgets/sidebar.dart';
import 'widgets/top_bar.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int selectedIndex = 0;

  // UPDATED SIDEBAR ITEMS
  final List<NavItem> navItems = const [
    NavItem("Dashboard", Icons.grid_view_rounded),
    NavItem("Patients", Icons.person_outline_rounded),
    NavItem("Rooms", Icons.meeting_room_outlined),
    NavItem("Attendance", Icons.calendar_today_outlined),
    NavItem("Payments", Icons.payments_outlined),
    NavItem("Inventory & Expense", Icons.inventory_2_outlined),
    NavItem("Sponsorship", Icons.volunteer_activism_outlined),
    NavItem("Settings", Icons.tune_rounded),
  ];

  // UPDATED PAGES
  final List<Widget> pages = const [
    DashboardScreen(),
    PatientsScreen(),
    RoomsPage(),
    Attendance(),
    PaymentsScreen(),
    InventoryExpenseScreen(),
    SponsorshipScreen(),
    SettingsPage(),
  ];

  void _navigateToSettings() {
    final index = navItems.indexWhere(
          (item) => item.label == "Settings",
    );

    if (index != -1) {
      setState(() => selectedIndex = index);
    }
  }

  void _navigateToProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ProfilePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),

      body: Row(
        children: [

          // SIDEBAR
          Sidebar(
            items: navItems,
            selectedIndex: selectedIndex,
            onSelect: (i) {
              setState(() {
                selectedIndex = i;
              });
            },
            onProfileTap: _navigateToProfile,
          ),

          // MAIN CONTENT
          Expanded(
            child: Column(
              children: [

                // TOP BAR
                TopBar(
                  title: navItems[selectedIndex].label,
                  onProfileTap: _navigateToProfile,
                  onSettingsTap: _navigateToSettings,
                ),

                // PAGE CONTENT
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 1400,
                        minWidth: 1000,
                      ),
                      child: pages[selectedIndex],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}