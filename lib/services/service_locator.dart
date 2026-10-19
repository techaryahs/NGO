import 'dart:async';

import '../cache/persistent_cache.dart';
import 'firebase_rtdb_rest_service.dart';
import 'firebase_auth_rest_service.dart';
import 'auth_service.dart';
import 'patient_service.dart';
import 'room_service.dart';
import 'inventory_expense_service.dart';
import 'sponsorship_service.dart';
import 'payment_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'photo_rtdb_service.dart';
import 'photo_migration_service.dart';
import 'registration_number_service.dart';
import 'backend_api_service.dart';
import '../config/app_config.dart';

export 'room_service.dart'; // Ensure extension methods are visible everywhere ServiceLocator is used

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
  BackendApiService? _backendApiService;
  AuthService? _authService;
  PatientService? _patientService;
  RoomService? _roomService;
  InventoryExpenseService? _inventoryExpenseService;
  SponsorshipService? _sponsorshipService;
  PaymentService? _paymentService;
  NotificationService? _notificationService;
  SettingsService? _settingsService;
  PhotoRtdbService? _photoRtdbService;
  PhotoMigrationService? _photoMigrationService;
  RegistrationNumberService? _registrationNumberService;
  PersistentCache? _persistentCache;

  bool get isInitialized => _authRestService != null;
  bool get isPostgresMode => _rtdbService == null && _backendApiService != null;

  /// Initialize services with Firebase project configuration
  void initialize({
    required String projectId,
    required String apiKey,
    String? databaseUrl,
  }) {
    if (isInitialized) {
      if (isPostgresMode == AppConfig.usePostgresBackend) {
        return;
      }
      dispose();
    }
    _persistentCache = PersistentCache.open();
    _persistentCache?.dataSource = AppConfig.usePostgresBackend
        ? 'postgres:${AppConfig.backendApiUrl}'
        : 'rtdb:${AppConfig.firebaseDatabaseUrl}';

    // Initialize auth service first
    _authRestService = FirebaseAuthRestService(apiKey: apiKey);

    // Initialize backend API service
    _backendApiService = BackendApiService(
      baseUrl: AppConfig.backendApiUrl,
      getAuthToken: () async => await _authRestService?.getIdToken(),
      persistentCache: _persistentCache,
    );

    if (AppConfig.usePostgresBackend) {
      _rtdbService = null;
      _photoRtdbService = PhotoRtdbService(
        backendApi: _backendApiService,
        persistentCache: _persistentCache,
      );
      _registrationNumberService = RegistrationNumberService(
        backendApiService: _backendApiService,
      );
      _patientService = PatientService(
        backendApiService: _backendApiService,
        photos: _photoRtdbService,
        registrationNumberService: _registrationNumberService,
      );
      _roomService = RoomService(backendApiService: _backendApiService);
      _paymentService = PaymentService(null, _backendApiService);
      _settingsService = SettingsService(null, _backendApiService);
      _notificationService = NotificationService(
        patientService: _patientService!,
      );
      _authService = AuthService(
        authService: _authRestService!,
        backendApiService: _backendApiService,
        persistentCache: _persistentCache,
      );
      _photoMigrationService = PhotoMigrationService(
        backendApi: _backendApiService,
        photos: _photoRtdbService!,
      );
      _inventoryExpenseService = InventoryExpenseService(
        backendApiService: _backendApiService,
      );
      _sponsorshipService = SponsorshipService(
        backendApiService: _backendApiService,
      );
    } else {
      // Initialize RTDB service with auth token callback
      _rtdbService = FirebaseRTDBRestService(
        projectId: projectId,
        databaseUrl: databaseUrl,
        getAuthToken: () async {
          final token = await _authRestService?.getIdToken();
          return token;
        },
        persistentCache: _persistentCache,
      );

      // Initialize other services
      _authService = AuthService(
        authService: _authRestService!,
        rtdbService: _rtdbService!,
        persistentCache: _persistentCache,
      );
      _patientService = PatientService(rtdbService: _rtdbService!);
      _roomService = RoomService(rtdbService: _rtdbService!);
      _inventoryExpenseService = InventoryExpenseService(
        rtdbService: _rtdbService!,
      );
      _sponsorshipService = SponsorshipService(rtdbService: _rtdbService!);
      _paymentService = PaymentService(_rtdbService!);
      _notificationService = NotificationService(
        patientService: _patientService!,
      );
      _settingsService = SettingsService(_rtdbService!);
      _photoRtdbService = PhotoRtdbService(
        rtdb: _rtdbService!,
        persistentCache: _persistentCache,
      );
      _photoMigrationService = PhotoMigrationService(
        rtdb: _rtdbService!,
        photos: _photoRtdbService!,
      );
      _registrationNumberService = RegistrationNumberService(
        rtdbService: _rtdbService!,
      );
    }
  }

  /// Get Auth REST service instance
  FirebaseAuthRestService get authRestService {
    if (_authRestService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _authRestService!;
  }

  /// Get RTDB REST service instance
  FirebaseRTDBRestService get rtdbService {
    if (AppConfig.usePostgresBackend) {
      throw StateError(
        'Firebase RTDB is disabled when USE_POSTGRES_BACKEND=true. '
        'All database operations must route through BackendApiService.',
      );
    }
    if (_rtdbService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _rtdbService!;
  }

  /// Get Auth service instance
  AuthService get authService {
    if (_authService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _authService!;
  }

  /// Get Patient service instance
  PatientService get patientService {
    if (_patientService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _patientService!;
  }

  set patientService(PatientService? service) => _patientService = service;

  /// Get Room service instance
  RoomService get roomService {
    if (_roomService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _roomService!;
  }

  set roomService(RoomService? service) => _roomService = service;

  /// Get Inventory & Expense service instance
  InventoryExpenseService get inventoryExpenseService {
    if (_inventoryExpenseService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _inventoryExpenseService!;
  }

  set inventoryExpenseService(InventoryExpenseService? service) =>
      _inventoryExpenseService = service;

  /// Get Sponsorship service instance
  SponsorshipService get sponsorshipService {
    if (_sponsorshipService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _sponsorshipService!;
  }

  set sponsorshipService(SponsorshipService? service) =>
      _sponsorshipService = service;

  /// Get Payment service instance
  PaymentService get paymentService {
    if (_paymentService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _paymentService!;
  }

  set paymentService(PaymentService? service) => _paymentService = service;

  /// Get Notification service instance
  NotificationService get notificationService {
    if (_notificationService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _notificationService!;
  }

  /// Get Settings service instance
  SettingsService get settingsService {
    if (_settingsService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _settingsService!;
  }

  /// Get the shared RTDB photo service instance
  PhotoRtdbService get photoRtdbService {
    if (_photoRtdbService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _photoRtdbService!;
  }

  /// Get Photo migration service instance
  PhotoMigrationService get photoMigrationService {
    if (_photoMigrationService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _photoMigrationService!;
  }

  /// Get Registration Number service instance
  RegistrationNumberService get registrationNumberService {
    if (_registrationNumberService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _registrationNumberService!;
  }

  set registrationNumberService(RegistrationNumberService? service) =>
      _registrationNumberService = service;

  PersistentCache get persistentCache {
    if (_persistentCache == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _persistentCache!;
  }

  /// Get Backend API service instance
  BackendApiService get backendApiService {
    if (_backendApiService == null) {
      throw Exception(
        'ServiceLocator not initialized. Call initialize() first.',
      );
    }
    return _backendApiService!;
  }

  set backendApiService(BackendApiService? service) =>
      _backendApiService = service;

  /// Whether Backend API service is configured and ready
  bool get isBackendApiConfigured =>
      AppConfig.usePostgresBackend && _backendApiService != null;

  /// Refreshes all active data streams in whichever backend mode is active.
  void retryAllStreams() {
    if (AppConfig.usePostgresBackend) {
      _backendApiService?.retryAll();
    } else {
      _rtdbService?.retryAll();
    }
  }

  /// Opens and validates the disposable local cache before the UI starts.
  Future<void> initializePersistentCache() => persistentCache.initialize();

  /// Dispose all services
  void dispose() {
    _paymentService?.disposeScheduler();
    _authRestService?.dispose();
    _rtdbService?.dispose();
    _backendApiService?.dispose();
    _backendApiService = null;
    _authRestService = null;
    _rtdbService = null;
    _authService = null;
    _patientService = null;
    _roomService = null;
    _inventoryExpenseService = null;
    _sponsorshipService = null;
    _paymentService = null;
    _notificationService = null;
    _settingsService = null;
    _photoRtdbService = null;
    _photoMigrationService = null;
    _registrationNumberService?.dispose();
    _registrationNumberService = null;
    final cache = _persistentCache;
    _persistentCache = null;
    if (cache != null) unawaited(cache.close());
  }
}
