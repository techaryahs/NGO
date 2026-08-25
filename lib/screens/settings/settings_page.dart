import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/service_locator.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Notification states
  bool pendingPaymentAlerts = true;
  bool patientStayExpiryAlert = true;
  bool lowInventoryAlerts = true;

  // Security states
  bool autoLogoutSession = false;

  // Backup states
  bool autoDailyBackup = true;
  String lastBackupTime = "No backup yet";

  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => isLoading = true);
    final settingsService = ServiceLocator().settingsService;
    final settings = await settingsService.getSettings();

    if (settings.isNotEmpty) {
      if (settings['notifications'] != null) {
        pendingPaymentAlerts =
            settings['notifications']['pendingPayment'] ?? true;
        patientStayExpiryAlert =
            settings['notifications']['stayExpiry'] ?? true;
        lowInventoryAlerts = settings['notifications']['lowInventory'] ?? true;
      }
      if (settings['security'] != null) {
        autoLogoutSession = settings['security']['autoLogout'] ?? false;
      }
      if (settings['backup'] != null) {
        autoDailyBackup = settings['backup']['autoDailyBackup'] ?? true;
        lastBackupTime = settings['backup']['lastBackup'] ?? "No backup yet";
      }
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.red.shade800
            : const Color(0xFF3B6D11),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _updateNotification(
    String key,
    bool value,
    void Function() localUpdate,
  ) async {
    setState(() => isSaving = true);
    final success = await ServiceLocator().settingsService
        .updateNotificationSetting(key, value);
    setState(() => isSaving = false);

    if (success) {
      localUpdate();
      _showSnackBar("Notification setting updated");
    } else {
      _showSnackBar("Failed to update setting", isError: true);
    }
  }

  Future<void> _updateSecurity(
    String key,
    bool value,
    void Function() localUpdate,
  ) async {
    setState(() => isSaving = true);
    final success = await ServiceLocator().settingsService
        .updateSecuritySetting(key, value);
    setState(() => isSaving = false);

    if (success) {
      localUpdate();
      _showSnackBar("Security setting updated");
    } else {
      _showSnackBar("Failed to update setting", isError: true);
    }
  }

  Future<void> _updateBackup(bool value) async {
    setState(() => isSaving = true);
    final success = await ServiceLocator().settingsService
        .updateAutoBackupSetting(value);
    setState(() => isSaving = false);

    if (success) {
      setState(() => autoDailyBackup = value);
      _showSnackBar("Backup setting updated");
    } else {
      _showSnackBar("Failed to update setting", isError: true);
    }
  }

  Future<void> _triggerManualBackup() async {
    setState(() => isSaving = true);
    final result = await ServiceLocator().settingsService.triggerManualBackup();
    setState(() => isSaving = false);

    if (result['success']) {
      setState(() => lastBackupTime = result['timestamp']);
      _showSnackBar("Backup completed successfully");
    } else {
      _showSnackBar(result['message'], isError: true);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isProcessing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Change Password",
                style: TextStyle(color: Color(0xFF27500A)),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPasswordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Current Password",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: newPasswordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "New Password",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (v) => v!.length < 6
                          ? "Must be at least 6 characters"
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isProcessing = true);

                            final authService = ServiceLocator().authService;
                            // 1. Reauthenticate
                            final reauthResult = await authService
                                .reauthenticate(
                                  password: currentPasswordCtrl.text,
                                );

                            if (reauthResult['success']) {
                              // 2. Change Password
                              final changeResult = await authService
                                  .changePassword(
                                    newPassword: newPasswordCtrl.text,
                                  );
                              if (changeResult['success']) {
                                Navigator.pop(context);
                                _showSnackBar("Password changed successfully!");
                              } else {
                                setDialogState(() => isProcessing = false);
                                _showSnackBar(
                                  changeResult['message'],
                                  isError: true,
                                );
                              }
                            } else {
                              setDialogState(() => isProcessing = false);
                              _showSnackBar(
                                reauthResult['message'],
                                isError: true,
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF639922),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Update",
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          "About the NGO Management System",
          style: TextStyle(
            color: Color(0xFF27500A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Text('''
NGO PATIENT MANAGEMENT SYSTEM

Supporting compassionate care through organized patient services.

This platform helps the NGO manage patients, attendants, room and lobby allocations, attendance, payments, sponsorships, inventory, and operational expenses in one secure place.

MISSION
To support patients and their families with transparent, efficient, and well-coordinated care services.

VISION
To make every patient record, stay, payment, and support activity accurate, accessible, and connected across the NGO.

WHAT THIS SYSTEM MANAGES
• Patient registration and profiles
• Room, bed, and lobby allocations
• Admissions, discharges, and stay history
• Patient and attendant attendance
• Billing, payments, and pending amounts
• Sponsorships and social-support activities
• Inventory, purchases, salaries, and expenses
• Reports and operational records

OUR COMMITMENT
• Respect patient privacy and dignity
• Maintain accurate and consistent records
• Improve transparency in financial and operational activities
• Help staff coordinate care efficiently
• Support informed decisions through reliable information

Together, we work toward better care, stronger support, and meaningful social impact.
            ''', style: TextStyle(height: 1.5, fontSize: 14)),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF639922)),
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPlaceholder(String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Color(0xFF27500A))),
        content: const Text("This feature is currently a placeholder."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Close",
              style: TextStyle(color: Color(0xFF639922)),
            ),
          ),
        ],
      ),
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          "Terms & Conditions",
          style: TextStyle(
            color: Color(0xFF27500A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Text('''
TERMS AND CONDITIONS

1. ACCEPTANCE OF TERMS
By accessing this NGO Patient Management System, users agree to follow these terms and all policies established by the NGO administration.

2. USE OF SYSTEM
This platform is intended solely for authorized NGO staff to manage patient records, attendants, room and lobby allocations, attendance, billing, sponsorships, inventory, and related operations. It must not be used for unauthorized or unlawful purposes.

3. DATA PRIVACY
Patient, attendant, payment, identity, and health-related information is confidential. Users must access it only when required for their assigned responsibilities and must not disclose, copy, export, or share it with unauthorized persons.

4. USER RESPONSIBILITY
Users are responsible for protecting their login credentials, using only their own account, signing out from shared devices, and promptly reporting suspected unauthorized access to the NGO administration.

5. ACCURACY OF INFORMATION
Users must ensure that patient details, admission and exit dates, placements, attendance, payments, and other records are accurate and updated promptly. Incorrect information must be corrected through the authorized editing process without concealing historical activity.

6. BILLING & PAYMENTS
Billing estimates and pending amounts are calculated using configured rates, placement details, attendants, and attendance records. Authorized staff must verify entries before collecting payment. Questions or disputes must be reported to the NGO administration for review and correction.

7. SYSTEM AVAILABILITY
The system may occasionally be unavailable due to maintenance, connectivity, power failure, or technical issues. Staff should follow the NGO's approved temporary record-keeping procedure during an outage and update the system when service is restored.

8. OPERATIONAL RESPONSIBILITY
Users must review information before relying on it for operational or financial decisions. The NGO administration is responsible for access control, rate configuration, record verification, backups, and correction of errors. Users may be held accountable for intentional misuse or unauthorized disclosure.

9. MEDICAL AND EMERGENCY USE
This system supports administrative record keeping and does not replace professional medical judgment, emergency procedures, or advice from qualified healthcare providers.

10. ACCOUNT SUSPENSION
The NGO administration may restrict or suspend access when an account is misused, security is at risk, or a user is no longer authorized.

11. CHANGES TO TERMS
The NGO administration may update these terms when operational, legal, privacy, or security requirements change. Users should review the latest version made available in the system.

12. QUESTIONS AND REPORTING
Questions, incorrect records, privacy concerns, or suspected misuse should be reported directly to the authorized NGO administrator.

Last updated: August 2026
            ''', style: TextStyle(height: 1.5, fontSize: 14)),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF639922),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        children: List.generate(
          3,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 100, height: 16, color: Colors.white),
                const SizedBox(height: 8),
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: isSaving,
      child: Container(
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
              child: isLoading
                  ? _buildShimmer()
                  : ListView(
                      children: [
                        _SettingsSection(
                          title: "Notifications",
                          items: [
                            _SettingsSwitchItem(
                              icon: Icons.payment_outlined,
                              title: "Pending Payment Alerts",
                              subtitle: "Notify when payments are pending",
                              value: pendingPaymentAlerts,
                              onChanged: (val) {
                                _updateNotification('pendingPayment', val, () {
                                  setState(() => pendingPaymentAlerts = val);
                                });
                              },
                            ),
                            _SettingsSwitchItem(
                              icon: Icons.timer_outlined,
                              title: "Patient Stay Expiry Alert",
                              subtitle: "10 days before 2 months complete",
                              value: patientStayExpiryAlert,
                              onChanged: (val) {
                                _updateNotification('stayExpiry', val, () {
                                  setState(() => patientStayExpiryAlert = val);
                                });
                              },
                            ),
                            _SettingsSwitchItem(
                              icon: Icons.inventory_2_outlined,
                              title: "Low Inventory Alerts",
                              subtitle: "Notify when supplies are low",
                              value: lowInventoryAlerts,
                              onChanged: (val) {
                                _updateNotification('lowInventory', val, () {
                                  setState(() => lowInventoryAlerts = val);
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: "Security",
                          items: [
                            _SettingsItem(
                              icon: Icons.password_rounded,
                              title: "Change Password",
                              subtitle: "Update your account password",
                              onTap: _showChangePasswordDialog,
                            ),
                            _SettingsItem(
                              icon: Icons.history_rounded,
                              title: "Login Activity",
                              subtitle: "View recent login attempts",
                              onTap: () => _showPlaceholder("Login Activity"),
                            ),
                            _SettingsSwitchItem(
                              icon: Icons.logout_rounded,
                              title: "Auto Logout Session",
                              subtitle: "Logout after 30 mins of inactivity",
                              value: autoLogoutSession,
                              onChanged: (val) {
                                _updateSecurity('autoLogout', val, () {
                                  setState(() => autoLogoutSession = val);
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsSection(
                          title: "Backup & Restore",
                          items: [
                            _SettingsItem(
                              icon: Icons.cloud_upload_outlined,
                              title: "Manual Backup",
                              subtitle: "Last Backup: $lastBackupTime",
                              onTap: _triggerManualBackup,
                            ),
                            _SettingsSwitchItem(
                              icon: Icons.autorenew_rounded,
                              title: "Auto Daily Backup",
                              subtitle: "Backup data automatically every day",
                              value: autoDailyBackup,
                              onChanged: _updateBackup,
                            ),
                            _SettingsItem(
                              icon: Icons.restore_rounded,
                              title: "Restore Database",
                              subtitle: "Restore from a previous backup",
                              onTap: () => _showPlaceholder("Restore Database"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _SettingsSection(
                          title: "About",
                          items: [
                            _SettingsItem(
                              icon: Icons.business_rounded,
                              title: "About This Platform",
                              subtitle: "NGO Management System details",
                              onTap: _showAboutDialog,
                            ),
                            _SettingsItem(
                              icon: Icons.description_outlined,
                              title: "Terms & Conditions",
                              subtitle: "Usage terms and policies",
                              onTap: _showTermsDialog,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const _SettingsSection({required this.title, required this.items});

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
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF639922).withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final int index = entry.key;
              final Widget item = entry.value;
              final isLast = index == items.length - 1;
              return Column(
                children: [
                  item,
                  if (!isLast)
                    const Divider(
                      height: 1,
                      indent: 56,
                      color: Color(0xFFEAF3DE),
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
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: const Color(0xFFF0F7EA),
        splashColor: const Color(0xFFEAF3DE),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF639922),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing ??
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

class _SettingsSwitchItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: const Color(0xFF3B6D11),
        inactiveTrackColor: const Color(0xFFEAF3DE),
        inactiveThumbColor: const Color(0xFF8BBF4A),
      ),
    );
  }
}
