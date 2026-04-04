import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int selectedIndex = 0;

  final List<_NavItem> navItems = const [
    _NavItem("Dashboard", Icons.grid_view_rounded),
    _NavItem("Patients", Icons.person_outline_rounded),
    _NavItem("Rooms", Icons.meeting_room_outlined),
    _NavItem("Stays", Icons.article_outlined),
    _NavItem("Attendance", Icons.calendar_today_outlined),
    _NavItem("Payments", Icons.payments_outlined),
    _NavItem("Reports", Icons.bar_chart_rounded),
    _NavItem("Settings", Icons.tune_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: Row(
        children: [
          _Sidebar(
            items: navItems,
            selectedIndex: selectedIndex,
            onSelect: (i) => setState(() => selectedIndex = i),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: navItems[selectedIndex].label),
                Expanded(
                  child: _PageContent(label: navItems[selectedIndex].label),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ──────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFFF4F9F0),
        border: Border(
          right: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          _SidebarBrand(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              itemCount: items.length,
              itemBuilder: (context, i) => _NavTile(
                item: items[i],
                isSelected: selectedIndex == i,
                onTap: () => onSelect(i),
              ),
            ),
          ),
          _SidebarFooter(),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3DE),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC0DD97), width: 1.5),
            ),
            child: const Icon(Icons.eco_rounded, color: Color(0xFF3B6D11), size: 18),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "NGO System",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B6D11),
                ),
              ),
              Text(
                "Patient Portal",
                style: TextStyle(fontSize: 11, color: Color(0xFF639922)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFD4EABD)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: const Color(0xFF3B6D11).withOpacity(isSelected ? 1.0 : 0.7),
                ),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: const Color(0xFF27500A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: const Color(0xFF3B6D11),
                  child: const Text(
                    "AD",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEAF3DE),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Admin",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    Text(
                      "Super admin",
                      style: TextStyle(fontSize: 11, color: Color(0xFF639922)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFDf7),
        border: Border(bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF27500A),
            ),
          ),
          Row(
            children: [
              // Notification bell
              Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3DE),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: Color(0xFF3B6D11),
                  size: 18,
                ),
              ),
              // Avatar
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF3B6D11),
                child: const Text(
                  "AD",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEAF3DE),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Page Content ─────────────────────────────────────────────────────────────

class _PageContent extends StatelessWidget {
  final String label;
  const _PageContent({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F7EA),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          "$label Page",
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

// ── Data model ───────────────────────────────────────────────────────────────

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}