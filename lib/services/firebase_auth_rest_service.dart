import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase Authentication REST API Service
///
/// Implements Firebase Auth using REST API instead of native SDK.
/// Works on ALL platforms including Windows desktop.
class FirebaseAuthRestService {
  final String apiKey;

  // Auth endpoints
  static const String _signUpUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp';
  static const String _signInUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
  static const String _refreshTokenUrl =
      'https://securetoken.googleapis.com/v1/token';
  static const String _getUserDataUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup';
  static const String _updateAccountUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:update';
  static const String _sendOobCodeUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode';

  // Storage keys
  static const String _keyIdToken = 'firebase_id_token';
  static const String _keyRefreshToken = 'firebase_refresh_token';
  static const String _keyUserId = 'firebase_user_id';
  static const String _keyEmail = 'firebase_email';
  static const String _keyExpiresAt = 'firebase_expires_at';

  // Current user data
  String? _idToken;
  String? _refreshToken;
  String? _userId;
  String? _email;
  DateTime? _expiresAt;

  // Stream controller for auth state changes
  final _authStateController = StreamController<AuthUser?>.broadcast();

  // Current auth state (cached)
  AuthUser? _currentAuthState;

  FirebaseAuthRestService({required this.apiKey}) {
    // Don't emit here, let _loadStoredAuth handle it
    _loadStoredAuth();
  }

  /// Get current user
  AuthUser? get currentUser {
    if (_userId != null && _email != null && _isTokenValid()) {
      return AuthUser(uid: _userId!, email: _email!);
    }
    return null;
  }

  /// Stream of auth state changes - returns cached state immediately
  Stream<AuthUser?> get authStateChanges {
    return Stream.value(_currentAuthState).asyncExpand((initial) async* {
      yield initial;
      yield* _authStateController.stream;
    });
  }

  /// Get current ID token (for authenticated requests)
  Future<String?> getIdToken() async {
    if (_idToken != null && _isTokenValid()) {
      return _idToken;
    }

    // Try to refresh token
    if (_refreshToken != null) {
      await _refreshIdToken();
      return _idToken;
    }

    return null;
  }

  // ===========================================================================
  // SIGN UP
  // ===========================================================================

  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final url = '$_signUpUrl?key=$apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthData(
          idToken: data['idToken'],
          refreshToken: data['refreshToken'],
          userId: data['localId'],
          email: data['email'],
          expiresIn: int.parse(data['expiresIn']),
        );

        _currentAuthState = currentUser;
        _authStateController.add(currentUser);

        return AuthResult(success: true, user: currentUser);
      } else {
        final error = json.decode(response.body);
        return AuthResult(
          success: false,
          message: _parseErrorMessage(error['error']['message']),
        );
      }
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'An error occurred. Please try again.',
      );
    }
  }

  // ===========================================================================
  // SIGN IN
  // ===========================================================================

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final url = '$_signInUrl?key=$apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthData(
          idToken: data['idToken'],
          refreshToken: data['refreshToken'],
          userId: data['localId'],
          email: data['email'],
          expiresIn: int.parse(data['expiresIn']),
        );

        _currentAuthState = currentUser;
        _authStateController.add(currentUser);

        return AuthResult(success: true, user: currentUser);
      } else {
        final error = json.decode(response.body);
        return AuthResult(
          success: false,
          message: _parseErrorMessage(error['error']['message']),
        );
      }
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'An error occurred. Please try again.',
      );
    }
  }

  // ===========================================================================
  // PASSWORD MANAGEMENT
  // ===========================================================================

  Future<AuthResult> reauthenticate({required String password}) async {
    if (_email == null) {
      return AuthResult(success: false, message: 'No user signed in.');
    }
    return signIn(email: _email!, password: password);
  }

  Future<AuthResult> changePassword({required String newPassword}) async {
    try {
      final token = await getIdToken();
      if (token == null) {
        return AuthResult(
          success: false,
          message: 'User is not authenticated.',
        );
      }

      final url = '$_updateAccountUrl?key=$apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'idToken': token,
          'password': newPassword,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthData(
          idToken: data['idToken'],
          refreshToken: data['refreshToken'],
          userId: data['localId'],
          email: data['email'],
          expiresIn: int.parse(data['expiresIn']),
        );
        return AuthResult(success: true, user: currentUser);
      } else {
        final error = json.decode(response.body);
        return AuthResult(
          success: false,
          message: _parseErrorMessage(error['error']['message']),
        );
      }
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'An error occurred. Please try again.',
      );
    }
  }

  Future<AuthResult> sendPasswordResetEmail({required String email}) async {
    try {
      final url = '$_sendOobCodeUrl?key=$apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'requestType': 'PASSWORD_RESET', 'email': email}),
      );

      if (response.statusCode == 200) {
        return AuthResult(success: true, message: 'Password reset email sent.');
      } else {
        final error = json.decode(response.body);
        return AuthResult(
          success: false,
          message: _parseErrorMessage(error['error']['message']),
        );
      }
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'An error occurred. Please try again.',
      );
    }
  }

  // ===========================================================================
  // SIGN OUT
  // ===========================================================================

  Future<void> signOut() async {
    _idToken = null;
    _refreshToken = null;
    _userId = null;
    _email = null;
    _expiresAt = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIdToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyExpiresAt);

    _currentAuthState = null;
    _authStateController.add(null);
  }

  // ===========================================================================
  // PRIVATE METHODS
  // ===========================================================================

  Future<void> _saveAuthData({
    required String idToken,
    required String refreshToken,
    required String userId,
    required String email,
    required int expiresIn,
  }) async {
    _idToken = idToken;
    _refreshToken = refreshToken;
    _userId = userId;
    _email = email;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyIdToken, idToken);
    await prefs.setString(_keyRefreshToken, refreshToken);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyExpiresAt, _expiresAt!.toIso8601String());
  }

  Future<void> _loadStoredAuth() async {
    final prefs = await SharedPreferences.getInstance();

    _idToken = prefs.getString(_keyIdToken);
    _refreshToken = prefs.getString(_keyRefreshToken);
    _userId = prefs.getString(_keyUserId);
    _email = prefs.getString(_keyEmail);

    final expiresAtStr = prefs.getString(_keyExpiresAt);
    if (expiresAtStr != null) {
      _expiresAt = DateTime.parse(expiresAtStr);
    }

    // Emit initial auth state
    if (_isTokenValid()) {
      _currentAuthState = currentUser;
      _authStateController.add(currentUser);
    } else if (_refreshToken != null) {
      // Try to refresh token
      await _refreshIdToken();
      _currentAuthState = currentUser;
      _authStateController.add(currentUser);
    } else {
      _currentAuthState = null;
      _authStateController.add(null);
    }
  }

  bool _isTokenValid() {
    if (_expiresAt == null) return false;
    return DateTime.now().isBefore(_expiresAt!);
  }

  Future<void> _refreshIdToken() async {
    if (_refreshToken == null) return;

    try {
      final url = '$_refreshTokenUrl?key=$apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthData(
          idToken: data['id_token'],
          refreshToken: data['refresh_token'],
          userId: data['user_id'],
          email: _email!,
          expiresIn: int.parse(data['expires_in']),
        );
      }
    } catch (e) {
      // Token refresh failed, sign out
      await signOut();
    }
  }

  String _parseErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'EMAIL_EXISTS':
        return 'This email is already registered.';
      case 'INVALID_EMAIL':
        return 'Invalid email address.';
      case 'WEAK_PASSWORD':
        return 'Password should be at least 6 characters.';
      case 'EMAIL_NOT_FOUND':
        return 'No user found with this email.';
      case 'INVALID_PASSWORD':
        return 'Incorrect password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  void dispose() {
    _authStateController.close();
  }
}

// ===========================================================================
// DATA MODELS
// ===========================================================================

class AuthUser {
  final String uid;
  final String email;

  AuthUser({required this.uid, required this.email});
}

class AuthResult {
  final bool success;
  final AuthUser? user;
  final String? message;

  AuthResult({required this.success, this.user, this.message});
}
