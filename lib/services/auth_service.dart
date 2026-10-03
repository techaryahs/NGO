import 'package:flutter/foundation.dart';
import '../cache/persistent_cache.dart';
import 'firebase_rtdb_rest_service.dart';
import 'firebase_auth_rest_service.dart';

class AuthService {
  final FirebaseAuthRestService _auth;
  final FirebaseRTDBRestService _rtdb;
  final PersistentCache? _persistentCache;

  AuthService({
    required FirebaseAuthRestService authService,
    required FirebaseRTDBRestService rtdbService,
    PersistentCache? persistentCache,
  }) : _auth = authService,
       _rtdb = rtdbService,
       _persistentCache = persistentCache;

  AuthUser? get currentUser => _auth.currentUser;
  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges.asyncMap((user) async {
        if (user == null) {
          _persistentCache?.deactivateAccount();
        } else {
          await _persistentCache?.activateAccount(user.uid);
        }
        return user;
      });

  // New accounts are unprivileged. Staff/admin roles are assigned by a
  // trusted operator through the Firebase Admin SDK.
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    debugPrint(
      '[AUTH FLOW] STEP 1 AUTH REQUEST START: target=Identity Toolkit signUp, email=$email',
    );
    try {
      final result = await _auth.signUp(
        email: email,
        password: password,
        broadcastState: false,
      );

      if (!result.success) {
        debugPrint(
          '[AUTH FLOW] STEP 1 AUTH REQUEST FAILED: HTTP ${result.statusCode}, code=${result.errorCode}, msg=${result.message}',
        );
        return {
          'success': false,
          'message':
              result.message ?? 'Authentication failed. Please try again.',
          'statusCode': result.statusCode,
          'errorCode': result.errorCode,
        };
      }

      debugPrint(
        '[AUTH FLOW] STEP 2 AUTH RESPONSE RECEIVED: HTTP ${result.statusCode}',
      );
      debugPrint(
        '[AUTH FLOW] STEP 3 USER UID RECEIVED: uid=${result.user!.uid}',
      );

      // Store an unprivileged profile; the RTDB rules enforce this value.
      debugPrint(
        '[AUTH FLOW] STEP 4 PROFILE WRITE START: path=users/${result.user!.uid}',
      );
      try {
        await _rtdb.put('users/${result.user!.uid}', {
          'uid': result.user!.uid,
          'email': email,
          'name': name,
          'phone': phone,
          'role': 'volunteer',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
        debugPrint(
          '[AUTH FLOW] STEP 5 PROFILE WRITE COMPLETE: path=users/${result.user!.uid}',
        );
      } catch (dbError) {
        debugPrint('[AUTH FLOW] STEP 4 PROFILE WRITE FAILED: $dbError');
        // Sign out if profile initialization fails so user is not stuck in broken state
        await _auth.signOut();
        return {
          'success': false,
          'message':
              'Account created in Auth, but profile write failed: $dbError',
          'profileError': true,
        };
      }

      // Safely notify listeners now that users/$uid profile exists in RTDB
      await _persistentCache?.activateAccount(result.user!.uid);
      debugPrint('[AUTH FLOW] STEP 6 AUTH STATE UPDATE');
      _auth.notifyAuthStateChanged();

      debugPrint('[AUTH FLOW] STEP 7 ROUTING');
      return {'success': true, 'user': result.user};
    } catch (e) {
      debugPrint('[AUTH FLOW] UNEXPECTED EXCEPTION: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred during signup: $e',
      };
    }
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signIn(email: email, password: password);

      if (!result.success) {
        return {'success': false, 'message': result.message};
      }

      await _persistentCache?.activateAccount(result.user!.uid);
      return {'success': true, 'user': result.user};
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
      };
    }
  }

  // Reauthenticate user
  Future<Map<String, dynamic>> reauthenticate({
    required String password,
  }) async {
    try {
      final result = await _auth.reauthenticate(password: password);

      if (!result.success) {
        return {'success': false, 'message': result.message};
      }

      return {'success': true, 'user': result.user};
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
      };
    }
  }

  // Change Password
  Future<Map<String, dynamic>> changePassword({
    required String newPassword,
  }) async {
    try {
      final result = await _auth.changePassword(newPassword: newPassword);

      if (!result.success) {
        return {'success': false, 'message': result.message};
      }

      return {'success': true, 'user': result.user};
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> sendPasswordResetEmail({
    required String email,
  }) async {
    try {
      final result = await _auth.sendPasswordResetEmail(email: email);

      if (!result.success) {
        return {'success': false, 'message': result.message};
      }

      return {'success': true, 'message': result.message};
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
      };
    }
  }

  // Get user role from Realtime Database
  Future<String?> getUserRole(String uid) async {
    try {
      final data = await _rtdb.get('users/$uid');
      if (data != null && data is Map) {
        final userData = Map<String, dynamic>.from(data);
        return userData['role'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final data = await _rtdb.get('users/$uid');
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllAdmins() async {
    try {
      final data = await _rtdb.get('users');

      if (data == null || data is! Map) {
        return [];
      }

      List<Map<String, dynamic>> admins = [];

      Map<String, dynamic> users = Map<String, dynamic>.from(data);

      users.forEach((uid, userData) {
        final user = Map<String, dynamic>.from(userData);

        if (user['role'] == 'admin') {
          admins.add({'uid': uid, ...user});
        }
      });

      return admins;
    } catch (e) {
      print("Error fetching admins: $e");
      return [];
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _persistentCache?.deactivateAccount();
  }
}
