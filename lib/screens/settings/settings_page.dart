import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F7EA),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Application Settings",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF27500A),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                _SettingsSection(
                  title: "General",
                  items: [
                    _SettingsItem(
                      icon: Icons.language_rounded,
                      title: "Language",
                      subtitle: "English",
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.notifications_outlined,
                      title: "Notifications",
                      subtitle: "Manage notification preferences",
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: "System",
                  items: [
                    _SettingsItem(
                      icon: Icons.security_rounded,
                      title: "Security",
                      subtitle: "Password and authentication",
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.backup_rounded,
                      title: "Backup & Restore",
                      subtitle: "Manage data backups",
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: "About",
                  items: [
                    _SettingsItem(
                      icon: Icons.info_outline_rounded,
                      title: "App Version",
                      subtitle: "1.0.0",
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.description_outlined,
                      title: "Terms & Privacy",
                      subtitle: "Legal information",
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsItem> items;

  const _SettingsSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF639922),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
          ),
          child: Column(
            children: items.map((item) {
              final isLast = item == items.last;
              return Column(
                children: [
                  item,
                  if (!isLast)
                    const Divider(
                      height: 1,
                      indent: 56,
                      color: Color(0xFFC0DD97),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3DE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: const Color(0xFF3B6D11)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF639922),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF639922),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
