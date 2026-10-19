import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'firebase_rtdb_rest_service.dart';
import 'backend_api_service.dart';

class SettingsService {
  final FirebaseRTDBRestService? _rtdb;
  final BackendApiService? _backendApi;

  SettingsService([this._rtdb, this._backendApi]);

  bool get isPostgres => _backendApi != null;

  FirebaseRTDBRestService get _safeRtdb {
    final rtdb = _rtdb;
    if (rtdb == null) {
      throw StateError(
        'Firebase RTDB is disabled when USE_POSTGRES_BACKEND=true. '
        'All database operations must route through BackendApiService.',
      );
    }
    return rtdb;
  }

  // Fetch all settings
  Future<Map<String, dynamic>> getSettings() async {
    final backendApi = _backendApi;
    if (backendApi != null) {
      try {
        final notifications =
            await backendApi.getSettingsCategory('notifications');
        final security = await backendApi.getSettingsCategory('security');
        final backup = await backendApi.getSettingsCategory('backup');
        return {
          'notifications': notifications,
          'security': security,
          'backup': backup,
        };
      } catch (e) {
        debugPrint("Error fetching settings: $e");
        return {};
      }
    }
    try {
      final data = await _safeRtdb.get('settings');
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return {};
    } catch (e) {
      debugPrint("Error fetching settings: $e");
      return {};
    }
  }

  // Update a specific notification setting
  Future<bool> updateNotificationSetting(String key, bool value) async {
    final backendApi = _backendApi;
    if (backendApi != null) {
      try {
        await backendApi.updateSettingsKey('notifications', key, value);
        return true;
      } catch (e) {
        debugPrint("Error updating notification setting $key: $e");
        return false;
      }
    }
    try {
      await _safeRtdb.patch('settings/notifications', {key: value});
      return true;
    } catch (e) {
      debugPrint("Error updating notification setting $key: $e");
      return false;
    }
  }

  // Update a specific security setting
  Future<bool> updateSecuritySetting(String key, bool value) async {
    final backendApi = _backendApi;
    if (backendApi != null) {
      try {
        await backendApi.updateSettingsKey('security', key, value);
        return true;
      } catch (e) {
        debugPrint("Error updating security setting $key: $e");
        return false;
      }
    }
    try {
      await _safeRtdb.patch('settings/security', {key: value});
      return true;
    } catch (e) {
      debugPrint("Error updating security setting $key: $e");
      return false;
    }
  }

  /// Whether client-side payment writes are locked. When locked, only the
  /// trusted payment backend (Cloud Functions) can write payment records.
  Future<bool?> getPaymentWritesLocked() async {
    final backendApi = _backendApi;
    if (backendApi != null) {
      try {
        final val = await backendApi.getSettingsKey(
          'security',
          'paymentWritesLocked',
        );
        if (val is bool) return val;
        if (val is Map && val.containsKey('paymentWritesLocked')) {
          return val['paymentWritesLocked'] == true;
        }
        return false;
      } catch (e) {
        debugPrint("Error reading payment lock: $e");
        return null;
      }
    }
    try {
      final data = await _safeRtdb.get('admin_settings/security');
      if (data is Map) {
        return data['paymentWritesLocked'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Error reading payment lock: $e");
      return null;
    }
  }

  Future<bool> updatePaymentWritesLocked(bool value) async {
    final backendApi = _backendApi;
    if (backendApi != null) {
      try {
        await backendApi.updateSettingsKey(
          'security',
          'paymentWritesLocked',
          value,
        );
        return true;
      } catch (e) {
        debugPrint("Error updating payment lock: $e");
        return false;
      }
    }
    try {
      await _safeRtdb.patch('admin_settings/security', {
        'paymentWritesLocked': value,
      });
      return true;
    } catch (e) {
      debugPrint("Error updating payment lock: $e");
      return false;
    }
  }

  // Update auto backup setting
  Future<bool> updateAutoBackupSetting(bool value) async {
    final backendApi = _backendApi;
    if (backendApi != null) {
      try {
        await backendApi.updateSettingsKey(
          'backup',
          'autoDailyBackup',
          value,
        );
        return true;
      } catch (e) {
        debugPrint("Error updating auto backup: $e");
        return false;
      }
    }
    try {
      await _safeRtdb.patch('settings/backup', {'autoDailyBackup': value});
      return true;
    } catch (e) {
      debugPrint("Error updating auto backup: $e");
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

      final backendApi = _backendApi;
      if (backendApi != null) {
        await backendApi.updateSettingsKey(
          'backup',
          'lastBackup',
          formattedDate,
        );
      } else {
        await _safeRtdb.patch('settings/backup', {'lastBackup': formattedDate});
      }
      return {'success': true, 'timestamp': formattedDate};
    } catch (e) {
      debugPrint("Error triggering manual backup: $e");
      return {'success': false, 'message': 'Failed to run backup.'};
    }
  }
}
