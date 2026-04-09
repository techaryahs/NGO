import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';

class Sidebar extends StatelessWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onProfileTap;

  const Sidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    this.onProfileTap,
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
          const _SidebarBrand(),
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
          _SidebarFooter(onProfileTap: onProfileTap),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

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
  final NavItem item;
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
  final VoidCallback? onProfileTap;
  
  const _SidebarFooter({this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    final authService = ServiceLocator().authService;
    final user = authService.currentUser;
    
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onProfileTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: const Color(0xFF3B6D11),
                      child: Text(
                        user?.email.substring(0, 2).toUpperCase() ?? "AD",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEAF3DE),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.email.split('@')[0] ?? "Admin",
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            "Super admin",
                            style: TextStyle(fontSize: 11, color: Color(0xFF639922)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Logout"),
                    content: const Text("Are you sure you want to logout?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B6D11),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Logout"),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  await authService.signOut();
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE5E7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8B4B8), width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: Color(0xFFD32F2F),
                    ),
                    SizedBox(width: 8),
                    Text(
                      "Logout",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD32F2F),
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
}

class NavItem {
  final String label;
  final IconData icon;
  const NavItem(this.label, this.icon);
}
