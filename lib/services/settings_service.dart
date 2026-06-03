import 'dart:async';
import 'package:intl/intl.dart';
import 'firebase_rtdb_rest_service.dart';

class SettingsService {
  final FirebaseRTDBRestService _rtdb;

  SettingsService(this._rtdb);

  // Fetch all settings
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final data = await _rtdb.get('settings');
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return {};
    } catch (e) {
      print("Error fetching settings: $e");
      return {};
    }
  }

  // Update a specific notification setting
  Future<bool> updateNotificationSetting(String key, bool value) async {
    try {
      await _rtdb.patch('settings/notifications', {key: value});
      return true;
    } catch (e) {
      print("Error updating notification setting $key: $e");
      return false;
    }
  }

  // Update a specific security setting
  Future<bool> updateSecuritySetting(String key, bool value) async {
    try {
      await _rtdb.patch('settings/security', {key: value});
      return true;
    } catch (e) {
      print("Error updating security setting $key: $e");
      return false;
    }
  }

  // Update auto backup setting
  Future<bool> updateAutoBackupSetting(bool value) async {
    try {
      await _rtdb.patch('settings/backup', {'autoDailyBackup': value});
      return true;
    } catch (e) {
      print("Error updating auto backup: $e");
      return false;
    }
  }

  // Trigger manual backup and record timestamp
  Future<Map<String, dynamic>> triggerManualBackup() async {
    try {
      final now = DateTime.now();
      // Format: Today at 10:30 AM
      final formattedTime = DateFormat('jm').format(now);
      final formattedDate = "Today at $formattedTime";
      
      await _rtdb.patch('settings/backup', {'lastBackup': formattedDate});
      return {'success': true, 'timestamp': formattedDate};
    } catch (e) {
      print("Error triggering manual backup: $e");
      return {'success': false, 'message': 'Failed to run backup.'};
    }
  }
}
