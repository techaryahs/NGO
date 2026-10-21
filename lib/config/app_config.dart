import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized application configuration.
///
/// All runtime configuration flows through this single class.
/// Values are loaded from the root `.env` file via `flutter_dotenv`.
///
/// **Architecture & Security Contract**
///
/// - The root `.env` file is the ONLY runtime configuration source.
/// - The application must not depend on `--dart-define` or command-line args.
/// - No individual service or screen may access `dotenv` directly.
/// - Privileged server secrets (service accounts, Razorpay secret keys) must
///   NEVER be placed in `.env` or in Flutter client code.
class AppConfig {
  AppConfig._();

  // ── Firebase Configuration ──────────────────────────────────────────────────

  /// Firebase project ID read from `.env`.
  static String get firebaseProjectId =>
      dotenv.isInitialized ? (dotenv.env['FIREBASE_PROJECT_ID']?.trim() ?? '') : '';

  /// Firebase Realtime Database URL read from `.env`.
  ///
  /// This is the authoritative source for the database URL. Individual
  /// services must obtain the URL exclusively through AppConfig / ServiceLocator.
  static String get firebaseDatabaseUrl =>
      dotenv.isInitialized ? (dotenv.env['FIREBASE_DATABASE_URL']?.trim() ?? '') : '';

  /// Firebase client API key read from `.env`.
  static String get firebaseApiKey =>
      dotenv.isInitialized ? (dotenv.env['FIREBASE_API_KEY']?.trim() ?? '') : '';

  /// Firebase Authentication domain read from `.env`.
  static String get firebaseAuthDomain =>
      dotenv.isInitialized ? (dotenv.env['FIREBASE_AUTH_DOMAIN']?.trim() ?? '') : '';

  // ── Payment Backend Configuration (Optional) ──────────────────────────────

  /// Trusted payment backend URL read from `.env`.
  ///
  /// When empty (the default), online Razorpay payment links are disabled.
  static String get razorpayBackendUrl =>
      dotenv.isInitialized ? (dotenv.env['RAZORPAY_BACKEND_URL']?.trim() ?? '') : '';

  /// Authoritative backend API URL (e.g. http://localhost:8080/api).
  static String get backendApiUrl {
    final configured = dotenv.isInitialized
        ? dotenv.env['BACKEND_API_URL']?.trim()
        : null;
    return configured == null || configured.isEmpty
        ? 'http://localhost:8080/api'
        : configured;
  }

  /// Whether to route data access to PostgreSQL backend API instead of Firebase RTDB.
  static bool get usePostgresBackend => dotenv.isInitialized
      ? (dotenv.env['USE_POSTGRES_BACKEND']?.trim().toLowerCase() == 'true')
      : false;

  /// Active environment name (e.g. 'production', 'development', 'testing').
  static String get environment => dotenv.isInitialized
      ? (dotenv.env['ENVIRONMENT']?.trim().toLowerCase() ??
          (kReleaseMode ? 'production' : 'development'))
      : 'development';

  /// Whether the application is running in production mode.
  static bool get isProduction => environment == 'production';

  /// Whether the given URL targets localhost or a loopback address.
  static bool isLocalhostUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host == '[::1]';
  }

  /// Whether a trusted payment backend URL is configured.
  static bool get isPaymentBackendConfigured => razorpayBackendUrl.isNotEmpty;

  /// Whether the Firebase API key is configured.
  static bool get isApiKeyConfigured => firebaseApiKey.isNotEmpty;

  // ── Diagnostics ─────────────────────────────────────────────────────────────

  /// Safe diagnostic summary of the active configuration.
  ///
  /// The actual API key is NEVER exposed or printed.
  static Map<String, String> get safeSummary => {
    'Environment': environment,
    'Firebase project': firebaseProjectId.isEmpty ? 'NOT_CONFIGURED' : firebaseProjectId,
    'Database host': firebaseDatabaseUrl.isEmpty
        ? 'NOT_CONFIGURED'
        : (Uri.tryParse(firebaseDatabaseUrl)?.host ?? firebaseDatabaseUrl),
    'Auth domain': firebaseAuthDomain.isEmpty ? 'NOT_CONFIGURED' : firebaseAuthDomain,
    'Backend mode': usePostgresBackend ? 'PostgreSQL ($backendApiUrl)' : 'Firebase RTDB',
    'API key configured': isApiKeyConfigured ? 'yes' : 'no',
    'Payment backend configured': isPaymentBackendConfigured ? 'yes' : 'no',
  };

  // ── Initialization & Validation ─────────────────────────────────────────────

  /// Initializes and validates application configuration.
  static void initialize() {
    validate();
  }

  /// Validates that `.env` is loaded and all required configuration values
  /// are present and targeting the authoritative new Firebase project.
  ///
  /// Throws [StateError] with actionable diagnostic messages if validation fails.
  static void validate() {
    if (!dotenv.isInitialized) {
      throw StateError(
        'AppConfig error: .env has not been loaded.\n'
        'Ensure dotenv.load(fileName: ".env") is called before AppConfig.validate().',
      );
    }

    final missing = <String>[];
    if (firebaseProjectId.isEmpty) missing.add('FIREBASE_PROJECT_ID');
    if (firebaseDatabaseUrl.isEmpty) missing.add('FIREBASE_DATABASE_URL');
    if (firebaseApiKey.isEmpty) missing.add('FIREBASE_API_KEY');
    if (firebaseAuthDomain.isEmpty) missing.add('FIREBASE_AUTH_DOMAIN');

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required configuration in .env: ${missing.join(', ')}.\n'
        'Ensure the root .env file exists and contains all required keys.\n'
        'Refer to .env.example for template values.',
      );
    }

    // Guard against targeting legacy Firebase environments
    if (firebaseProjectId == 'ngo-management-system-d8c06' ||
        firebaseProjectId == 'ngov-org' ||
        firebaseProjectId != 'ngo-management-system-new-as') {
      throw StateError(
        'Invalid FIREBASE_PROJECT_ID: "$firebaseProjectId".\n'
        'The application must target the new project: "ngo-management-system-new-as".',
      );
    }

    if (firebaseDatabaseUrl.contains('d8c06') ||
        firebaseDatabaseUrl.contains('ngov-org') ||
        !firebaseDatabaseUrl.contains('ngo-management-system-new-as')) {
      throw StateError(
        'Invalid FIREBASE_DATABASE_URL: "$firebaseDatabaseUrl".\n'
        'The application must target the new database URL for "ngo-management-system-new-as".',
      );
    }

    // Guard against storing PostgreSQL credentials in client .env assets
    final forbiddenDbKeys = [
      'POSTGRES_PASSWORD',
      'POSTGRES_USER',
      'POSTGRES_DB',
    ];
    final leaked = forbiddenDbKeys.where(
      (k) => dotenv.env.containsKey(k) && (dotenv.env[k]?.trim().isNotEmpty ?? false),
    );
    if (leaked.isNotEmpty) {
      throw StateError(
        'Security violation: ${leaked.join(', ')} must not be stored in client .env assets.\n'
        'The Flutter desktop application communicates via the REST API (BackendApiService),\n'
        'not direct database connections.',
      );
    }

    // Production guardrails for backend API configuration
    if (usePostgresBackend && isProduction) {
      if (isLocalhostUrl(backendApiUrl)) {
        throw StateError(
          'Production configuration error: BACKEND_API_URL cannot target localhost/loopback ("$backendApiUrl").\n'
          'Configure a production remote API endpoint.',
        );
      }
      final uri = Uri.tryParse(backendApiUrl);
      if (uri?.scheme != 'https') {
        throw StateError(
          'Production configuration error: BACKEND_API_URL must use HTTPS ("$backendApiUrl").\n'
          'Transmitting patient and financial records over unencrypted HTTP is not permitted in production.',
        );
      }
    }
  }
}
