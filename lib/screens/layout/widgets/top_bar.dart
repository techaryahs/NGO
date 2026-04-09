import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';

class TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;
  
  const TopBar({
    super.key,
    required this.title,
    required this.onProfileTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final authService = ServiceLocator().authService;
    final user = authService.currentUser;
    final initials = user?.email.substring(0, 2).toUpperCase() ?? "AD";

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
              PopupMenuButton<String>(
                offset: const Offset(0, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFC0DD97), width: 1),
                ),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF3B6D11),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEAF3DE),
                    ),
                  ),
                ),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.email ?? "admin@ngo.org",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "Super Admin",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF639922),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Color(0xFFC0DD97)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'profile',
                    child: Row(
                      children: const [
                        Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF3B6D11)),
                        SizedBox(width: 12),
                        Text(
                          "Profile",
                          style: TextStyle(fontSize: 13, color: Color(0xFF27500A)),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: const [
                        Icon(Icons.settings_outlined, size: 18, color: Color(0xFF3B6D11)),
                        SizedBox(width: 12),
                        Text(
                          "Settings",
                          style: TextStyle(fontSize: 13, color: Color(0xFF27500A)),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: const [
                        Icon(Icons.logout_rounded, size: 18, color: Color(0xFFD32F2F)),
                        SizedBox(width: 12),
                        Text(
                          "Logout",
                          style: TextStyle(fontSize: 13, color: Color(0xFFD32F2F), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'logout') {
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
                  } else if (value == 'profile') {
                    onProfileTap();
                  } else if (value == 'settings') {
                    onSettingsTap();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
