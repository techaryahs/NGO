import 'firebase_rtdb_rest_service.dart';
import 'firebase_auth_rest_service.dart';

class AuthService {
  final FirebaseAuthRestService _auth;
  final FirebaseRTDBRestService _rtdb;

  AuthService({
    required FirebaseAuthRestService authService,
    required FirebaseRTDBRestService rtdbService,
  })  : _auth = authService,
        _rtdb = rtdbService;

  AuthUser? get currentUser => _auth.currentUser;
  Stream<AuthUser?> get authStateChanges => _auth.authStateChanges;

  // Sign up with email, password, and role
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role, // 'admin', 'staff', 'volunteer'
  }) async {
    try {
      final result = await _auth.signUp(
        email: email,
        password: password,
      );

      if (!result.success) {
        return {'success': false, 'message': result.message};
      }

      // Store user data with role in Realtime Database via REST API
      await _rtdb.put('users/${result.user!.uid}', {
        'uid': result.user!.uid,
        'email': email,
        'name': name,
        'phone': phone,
        'role': role,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      return {'success': true, 'user': result.user};
    } catch (e) {
      return {'success': false, 'message': 'An error occurred. Please try again.'};
    }
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signIn(
        email: email,
        password: password,
      );

      if (!result.success) {
        return {'success': false, 'message': result.message};
      }

      return {'success': true, 'user': result.user};
    } catch (e) {
      return {'success': false, 'message': 'An error occurred. Please try again.'};
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
      return {'success': false, 'message': 'An error occurred. Please try again.'};
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
      return {'success': false, 'message': 'An error occurred. Please try again.'};
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

      Map<String, dynamic> users =
      Map<String, dynamic>.from(data);

      users.forEach((uid, userData) {
        final user = Map<String, dynamic>.from(userData);

        if (user['role'] == 'admin') {
          admins.add({
            'uid': uid,
            ...user,
          });
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
  }
}
