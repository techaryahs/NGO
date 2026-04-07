import 'firebase_rtdb_rest_service.dart';
import 'firebase_auth_rest_service.dart';
import 'auth_service.dart';
import 'patient_service.dart';
import 'room_service.dart';

/// Service Locator for dependency injection
/// 
/// Provides singleton instances of services throughout the app.
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Singleton instances
  FirebaseAuthRestService? _authRestService;
  FirebaseRTDBRestService? _rtdbService;
  AuthService? _authService;
  PatientService? _patientService;
  RoomService? _roomService;

  /// Initialize services with Firebase project configuration
  void initialize({
    required String projectId,
    required String apiKey,
    String? databaseUrl,
  }) {
    // Initialize auth service first
    _authRestService = FirebaseAuthRestService(apiKey: apiKey);
    
    // Initialize RTDB service with auth token callback
    _rtdbService = FirebaseRTDBRestService(
      projectId: projectId,
      databaseUrl: databaseUrl,
      getAuthToken: () async {
        final token = await _authRestService?.getIdToken();
        return token;
      },
    );
    
    // Initialize other services
    _authService = AuthService(
      authService: _authRestService!,
      rtdbService: _rtdbService!,
    );
    _patientService = PatientService(rtdbService: _rtdbService!);
    _roomService = RoomService(rtdbService: _rtdbService!);
  }

  /// Get Auth REST service instance
  FirebaseAuthRestService get authRestService {
    if (_authRestService == null) {
      throw Exception('ServiceLocator not initialized. Call initialize() first.');
    }
    return _authRestService!;
  }

  /// Get RTDB REST service instance
  FirebaseRTDBRestService get rtdbService {
    if (_rtdbService == null) {
      throw Exception('ServiceLocator not initialized. Call initialize() first.');
    }
    return _rtdbService!;
  }

  /// Get Auth service instance
  AuthService get authService {
    if (_authService == null) {
      throw Exception('ServiceLocator not initialized. Call initialize() first.');
    }
    return _authService!;
  }

  /// Get Patient service instance
  PatientService get patientService {
    if (_patientService == null) {
      throw Exception('ServiceLocator not initialized. Call initialize() first.');
    }
    return _patientService!;
  }

  /// Get Room service instance
  RoomService get roomService {
    if (_roomService == null) {
      throw Exception('ServiceLocator not initialized. Call initialize() first.');
    }
    return _roomService!;
  }

  /// Dispose all services
  void dispose() {
    _authRestService?.dispose();
    _rtdbService?.dispose();
    _authRestService = null;
    _rtdbService = null;
    _authService = null;
    _patientService = null;
    _roomService = null;
  }
}
