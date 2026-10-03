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

  /// Whether a trusted payment backend URL is configured.
  static bool get isPaymentBackendConfigured => razorpayBackendUrl.isNotEmpty;

  /// Whether the Firebase API key is configured.
  static bool get isApiKeyConfigured => firebaseApiKey.isNotEmpty;

  // ── Diagnostics ─────────────────────────────────────────────────────────────

  /// Safe diagnostic summary of the active configuration.
  ///
  /// The actual API key is NEVER exposed or printed.
  static Map<String, String> get safeSummary => {
    'Firebase project': firebaseProjectId.isEmpty ? 'NOT_CONFIGURED' : firebaseProjectId,
    'Database host': firebaseDatabaseUrl.isEmpty
        ? 'NOT_CONFIGURED'
        : (Uri.tryParse(firebaseDatabaseUrl)?.host ?? firebaseDatabaseUrl),
    'Auth domain': firebaseAuthDomain.isEmpty ? 'NOT_CONFIGURED' : firebaseAuthDomain,
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
  }
}
