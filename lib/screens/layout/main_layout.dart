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

  final List<NavItem> navItems = const [
    NavItem("Dashboard", Icons.grid_view_rounded),
    NavItem("Patients", Icons.person_outline_rounded),
    NavItem("Rooms", Icons.meeting_room_outlined),
    NavItem("Stays", Icons.article_outlined),
    NavItem("Attendance", Icons.calendar_today_outlined),
    NavItem("Payments", Icons.payments_outlined),
    NavItem("Reports", Icons.bar_chart_rounded),
    NavItem("Settings", Icons.tune_rounded),
  ];

  final List<Widget> pages = const [
    DashboardScreen(),
    PatientsScreen(),
    RoomsPage(),
    _PlaceholderPage(title: "Stays"),
    Attendance(),
    _PlaceholderPage(title: "Payments"),
    _PlaceholderPage(title: "Reports"),
    SettingsPage(),
  ];

  void _navigateToSettings() {
    setState(() => selectedIndex = 7);
  }

  void _navigateToProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ProfilePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: Row(
        children: [
          Sidebar(
            items: navItems,
            selectedIndex: selectedIndex,
            onSelect: (i) => setState(() => selectedIndex = i),
            onProfileTap: _navigateToProfile,
          ),
          Expanded(
            child: Column(
              children: [
                TopBar(
                  title: navItems[selectedIndex].label,
                  onProfileTap: _navigateToProfile,
                  onSettingsTap: _navigateToSettings,
                ),
                Expanded(
                  child: pages[selectedIndex],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  final String title;
  
  const _PlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F7EA),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          "$title Page",
          style: const TextStyle(
            fontSize: 20,
            color: Color(0xFF639922),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
