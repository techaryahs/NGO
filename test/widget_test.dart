import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ngo/config/app_config.dart';
import 'package:ngo/services/service_locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validEnv = '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=test-sample-client-api-key-12345
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
RAZORPAY_BACKEND_URL=
''';

  group('AppConfig & .env architecture tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      dotenv.clean();
      ServiceLocator().dispose();
    });

    test('.env must be loaded before AppConfig validation', () {
      dotenv.clean();
      expect(dotenv.isInitialized, isFalse);
      expect(
        () => AppConfig.validate(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Ensure dotenv.load(fileName: ".env") is called'),
        )),
      );
    });

    test('required values are read correctly from .env', () {
      dotenv.loadFromString(envString: validEnv);

      expect(AppConfig.firebaseProjectId, 'ngo-management-system-new-as');
      expect(
        AppConfig.firebaseDatabaseUrl,
        'https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
      expect(AppConfig.firebaseApiKey, 'test-sample-client-api-key-12345');
      expect(
        AppConfig.firebaseAuthDomain,
        'ngo-management-system-new-as.firebaseapp.com',
      );
      expect(AppConfig.razorpayBackendUrl, isEmpty);
      expect(AppConfig.isPaymentBackendConfigured, isFalse);
      expect(AppConfig.isApiKeyConfigured, isTrue);

      // Validation passes with complete valid env
      expect(() => AppConfig.validate(), returnsNormally);
    });

    test('optional RAZORPAY_BACKEND_URL is parsed correctly', () {
      const envWithBackend = '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=test-sample-client-api-key-12345
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
RAZORPAY_BACKEND_URL=https://payment.example.com
''';
      dotenv.loadFromString(envString: envWithBackend);
      expect(AppConfig.razorpayBackendUrl, 'https://payment.example.com');
      expect(AppConfig.isPaymentBackendConfigured, isTrue);
    });

    test('missing FIREBASE_API_KEY fails validation', () {
      const missingApiKeyEnv = '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
''';
      dotenv.loadFromString(envString: missingApiKeyEnv);
      expect(
        () => AppConfig.validate(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('FIREBASE_API_KEY'),
        )),
      );
    });

    test('missing required keys fails validation with descriptive error', () {
      const incompleteEnv = '''
FIREBASE_API_KEY=test-key
''';
      dotenv.loadFromString(envString: incompleteEnv);
      expect(
        () => AppConfig.validate(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('FIREBASE_PROJECT_ID'),
            contains('FIREBASE_DATABASE_URL'),
            contains('FIREBASE_AUTH_DOMAIN'),
          ),
        )),
      );
    });

    test('wrong or legacy Firebase project ID is rejected', () {
      const legacyProjectEnv = '''
FIREBASE_PROJECT_ID=ngo-management-system-d8c06
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=test-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
''';
      dotenv.loadFromString(envString: legacyProjectEnv);
      expect(
        () => AppConfig.validate(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Invalid FIREBASE_PROJECT_ID'),
        )),
      );

      const ngovProjectEnv = '''
FIREBASE_PROJECT_ID=ngov-org
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=test-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
''';
      dotenv.loadFromString(envString: ngovProjectEnv);
      expect(
        () => AppConfig.validate(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Invalid FIREBASE_PROJECT_ID'),
        )),
      );
    });

    test('legacy RTDB database URL is rejected', () {
      const legacyUrlEnv = '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-d8c06-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=test-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
''';
      dotenv.loadFromString(envString: legacyUrlEnv);
      expect(
        () => AppConfig.validate(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Invalid FIREBASE_DATABASE_URL'),
        )),
      );
    });

    test('RTDB service and Auth service receive configuration from AppConfig', () {
      dotenv.loadFromString(envString: validEnv);
      AppConfig.validate();

      final locator = ServiceLocator();
      locator.initialize(
        projectId: AppConfig.firebaseProjectId,
        apiKey: AppConfig.firebaseApiKey,
        databaseUrl: AppConfig.firebaseDatabaseUrl,
      );

      expect(locator.rtdbService.projectId, 'ngo-management-system-new-as');
      expect(
        locator.rtdbService.databaseUrl,
        'https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
      expect(locator.authRestService.apiKey, 'test-sample-client-api-key-12345');
    });

    test('safeSummary never leaks the actual API key string', () {
      dotenv.loadFromString(envString: validEnv);
      final summary = AppConfig.safeSummary;

      expect(summary['Firebase project'], 'ngo-management-system-new-as');
      expect(
        summary['Database host'],
        'ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
      expect(summary['API key configured'], 'yes');
      // Ensure the actual secret key is NOT present in any value
      for (final value in summary.values) {
        expect(value, isNot(contains('test-sample-client-api-key-12345')));
      }
    });

    test('no service directly accesses dotenv', () {
      final servicesDir = Directory('lib/services');
      expect(servicesDir.existsSync(), isTrue);

      final files = servicesDir.listSync(recursive: true).whereType<File>();
      for (final file in files) {
        if (!file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        expect(
          content.contains('dotenv'),
          isFalse,
          reason: '${file.path} should not directly access dotenv',
        );
      }
    });

    test('no application code uses String.fromEnvironment for Firebase config', () {
      final libDir = Directory('lib');
      final files = libDir.listSync(recursive: true).whereType<File>();

      for (final file in files) {
        if (!file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        expect(
          content.contains('fromEnvironment'),
          isFalse,
          reason: '${file.path} should not use String.fromEnvironment',
        );
      }
    });
  });
}
