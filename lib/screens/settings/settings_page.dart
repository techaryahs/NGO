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
        pendingPaymentAlerts = settings['notifications']['pendingPayment'] ?? true;
        patientStayExpiryAlert = settings['notifications']['stayExpiry'] ?? true;
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
        backgroundColor: isError ? Colors.red.shade800 : const Color(0xFF3B6D11),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _updateNotification(String key, bool value, void Function() localUpdate) async {
    setState(() => isSaving = true);
    final success = await ServiceLocator().settingsService.updateNotificationSetting(key, value);
    setState(() => isSaving = false);
    
    if (success) {
      localUpdate();
      _showSnackBar("Notification setting updated");
    } else {
      _showSnackBar("Failed to update setting", isError: true);
    }
  }

  Future<void> _updateSecurity(String key, bool value, void Function() localUpdate) async {
    setState(() => isSaving = true);
    final success = await ServiceLocator().settingsService.updateSecuritySetting(key, value);
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
    final success = await ServiceLocator().settingsService.updateAutoBackupSetting(value);
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text("Change Password", style: TextStyle(color: Color(0xFF27500A))),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: newPasswordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "New Password",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      validator: (v) => v!.length < 6 ? "Must be at least 6 characters" : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isProcessing = true);
                            
                            final authService = ServiceLocator().authService;
                            // 1. Reauthenticate
                            final reauthResult = await authService.reauthenticate(password: currentPasswordCtrl.text);
                            
                            if (reauthResult['success']) {
                              // 2. Change Password
                              final changeResult = await authService.changePassword(newPassword: newPasswordCtrl.text);
                              if (changeResult['success']) {
                                Navigator.pop(context);
                                _showSnackBar("Password changed successfully!");
                              } else {
                                setDialogState(() => isProcessing = false);
                                _showSnackBar(changeResult['message'], isError: true);
                              }
                            } else {
                              setDialogState(() => isProcessing = false);
                              _showSnackBar(reauthResult['message'], isError: true);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF639922),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isProcessing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Update", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
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
            child: const Text("Close", style: TextStyle(color: Color(0xFF639922))),
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
        children: List.generate(3, (index) => Padding(
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
        )),
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
