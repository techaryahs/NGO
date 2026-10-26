import 'package:flutter/foundation.dart';
import '../cache/persistent_cache.dart';
import 'firebase_rtdb_rest_service.dart';
import 'firebase_auth_rest_service.dart';
import 'backend_api_service.dart';
import 'service_locator.dart';

class AuthService {
  final FirebaseAuthRestService _auth;
  final FirebaseRTDBRestService? _rtdb;
  final BackendApiService? _backendApi;
  final PersistentCache? _persistentCache;

  AuthService({
    required FirebaseAuthRestService authService,
    FirebaseRTDBRestService? rtdbService,
    BackendApiService? backendApiService,
    PersistentCache? persistentCache,
  }) : _auth = authService,
       _rtdb = rtdbService,
       _backendApi =
           backendApiService ??
           (rtdbService == null ? _tryLocatorBackendApi() : null),
       _persistentCache = persistentCache;

  static BackendApiService? _tryLocatorBackendApi() {
    try {
      return ServiceLocator().backendApiService;
    } catch (_) {
      return null;
    }
  }

  bool get isPostgres => _backendApi != null || _rtdb == null;

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

  final Map<String, Future<Map<String, dynamic>>> _inFlightSignIn = {};
  final Map<String, Future<Map<String, dynamic>>> _inFlightSignUp = {};
  final Map<String, Future<String?>> _inFlightRoleLookups = {};

  // New accounts are unprivileged. Staff/admin roles are assigned by a
  // trusted operator through the Firebase Admin SDK.
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) {
    final key = email.trim().toLowerCase();
    final existing = _inFlightSignUp[key];
    if (existing != null) return existing;
    final future = _performSignUp(
      email: email,
      password: password,
      name: name,
      phone: phone,
    );
    _inFlightSignUp[key] = future;
    return future.whenComplete(() => _inFlightSignUp.remove(key));
  }

  Future<Map<String, dynamic>> _performSignUp({
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
        final profileData = {
          'uid': result.user!.uid,
          'email': email,
          'name': name,
          'phone': phone,
          'role': 'volunteer',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };
        final backendApi = _backendApi;
        if (backendApi != null) {
          await backendApi.put('users/${result.user!.uid}', profileData);
        } else {
          await _safeRtdb.put('users/${result.user!.uid}', profileData);
        }
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
  }) {
    final key = email.trim().toLowerCase();
    final existing = _inFlightSignIn[key];
    if (existing != null) return existing;
    final future = _performSignIn(email: email, password: password);
    _inFlightSignIn[key] = future;
    return future.whenComplete(() => _inFlightSignIn.remove(key));
  }

  Future<Map<String, dynamic>> _performSignIn({
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

  // Get user role from Realtime Database / Backend API
  Future<String?> getUserRole(String uid) {
    final existing = _inFlightRoleLookups[uid];
    if (existing != null) return existing;
    final future = _fetchUserRole(uid);
    _inFlightRoleLookups[uid] = future;
    return future.whenComplete(() => _inFlightRoleLookups.remove(uid));
  }

  Future<String?> _fetchUserRole(String uid) async {
    // Restored currentUser can be read before the cache-aware auth stream
    // finishes. Bind this account before BackendApiService captures its
    // generation; otherwise a successful profile response becomes obsolete.
    final user = currentUser;
    if (user != null && user.uid == uid) {
      await _persistentCache?.activateAccount(user.uid);
    }
    final backendApi = _backendApi;
    final dynamic data;
    if (backendApi != null) {
      data = await backendApi.get('users/$uid');
    } else {
      data = await _safeRtdb.get('users/$uid');
    }
    if (data != null && data is Map) {
      final userData = Map<String, dynamic>.from(data);
      return userData['role'] as String?;
    }
    // A missing profile is distinct from a failed request. Let transport and
    // authentication errors reach the retry UI instead of caching volunteer.
    return null;
  }

  // Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final backendApi = _backendApi;
      final dynamic data;
      if (backendApi != null) {
        data = await backendApi.get('users/$uid');
      } else {
        data = await _safeRtdb.get('users/$uid');
      }
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
      final backendApi = _backendApi;
      final dynamic data;
      if (backendApi != null) {
        data = await backendApi.get('users');
      } else {
        data = await _safeRtdb.get('users');
      }

      if (data == null || data is! Map) {
        return [];
      }

      List<Map<String, dynamic>> admins = [];

      Map<String, dynamic> users = Map<String, dynamic>.from(data);

      users.forEach((uid, userData) {
        if (userData is Map) {
          final user = Map<String, dynamic>.from(userData);
          if (user['role'] == 'admin') {
            admins.add({'uid': uid, ...user});
          }
        }
      });

      return admins;
    } catch (e) {
      debugPrint("Error fetching admins: $e");
      return [];
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _persistentCache?.deactivateAccount();
  }
}
