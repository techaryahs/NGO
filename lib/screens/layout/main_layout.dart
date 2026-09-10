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
    final index = navItems.indexWhere((item) => item.label == "Settings");

    if (index != -1) {
      setState(() => selectedIndex = index);
    }
  }

  void _navigateToProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ProfilePage()));
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 900;
    void selectPage(int index) {
      setState(() => selectedIndex = index);
      if (isCompact) Navigator.of(context).pop();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      drawer: isCompact
          ? Drawer(
              child: SafeArea(
                child: Sidebar(
                  items: navItems,
                  selectedIndex: selectedIndex,
                  onSelect: selectPage,
                  onProfileTap: _navigateToProfile,
                ),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!isCompact)
            Sidebar(
              items: navItems,
              selectedIndex: selectedIndex,
              onSelect: selectPage,
              onProfileTap: _navigateToProfile,
            ),

          // MAIN CONTENT
          Expanded(
            child: Column(
              children: [
                // TOP BAR
                Builder(
                  builder: (topBarContext) => TopBar(
                    title: navItems[selectedIndex].label,
                    onProfileTap: _navigateToProfile,
                    onSettingsTap: _navigateToSettings,
                    onMenuTap: isCompact
                        ? () => Scaffold.of(topBarContext).openDrawer()
                        : null,
                  ),
                ),

                // PAGE CONTENT
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: constraints.maxWidth
                            .clamp(0.0, 1400.0)
                            .toDouble(),
                        height: constraints.maxHeight,
                        child: pages[selectedIndex],
                      ),
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
