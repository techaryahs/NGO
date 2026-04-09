import 'package:flutter/material.dart';
import '../../services/service_locator.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = ServiceLocator().authService;
    final user = authService.currentUser;
    final initials = user?.email.substring(0, 2).toUpperCase() ?? "AD";

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC0DD97), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B6D11).withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFF3B6D11),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEAF3DE),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // User Info
              _ProfileInfoRow(
                label: "Email",
                value: user?.email ?? "N/A",
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 12),
              _ProfileInfoRow(
                label: "User ID",
                value: user?.uid ?? "N/A",
                icon: Icons.fingerprint_rounded,
              ),
              const SizedBox(height: 12),
              _ProfileInfoRow(
                label: "Role",
                value: "Super Admin",
                icon: Icons.admin_panel_settings_outlined,
              ),
              
              const SizedBox(height: 24),
              
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Implement edit profile
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Edit profile coming soon")),
                        );
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text("Edit Profile"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF3B6D11),
                        side: const BorderSide(color: Color(0xFF3B6D11)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text("Close"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B6D11),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ProfileInfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF3B6D11)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF639922),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF27500A),
                    fontWeight: FontWeight.w600,
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
