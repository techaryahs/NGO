import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/config/app_config.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    ServiceLocator().dispose();
    dotenv.loadFromString(isOptional: true, envString: '');
  });

  test('PostgreSQL feature flag is disabled unless explicitly true', () {
    for (final value in ['', 'false', '1', 'enabled']) {
      dotenv.loadFromString(
        isOptional: true,
        envString: 'USE_POSTGRES_BACKEND=$value',
      );
      expect(AppConfig.usePostgresBackend, isFalse);
    }
    dotenv.loadFromString(
      isOptional: true,
      envString: 'USE_POSTGRES_BACKEND=TRUE',
    );
    expect(AppConfig.usePostgresBackend, isTrue);
  });

  test('backend URL defaults for missing and blank configuration', () {
    dotenv.loadFromString(isOptional: true, envString: '');
    expect(AppConfig.backendApiUrl, 'http://localhost:8080/api');
    dotenv.loadFromString(isOptional: true, envString: 'BACKEND_API_URL=   ');
    expect(AppConfig.backendApiUrl, 'http://localhost:8080/api');
    dotenv.loadFromString(
      isOptional: true,
      envString: 'BACKEND_API_URL=https://backend.example/api',
    );
    expect(AppConfig.backendApiUrl, 'https://backend.example/api');
  });

  test('enabled mode initializes domain services with Postgres and fails closed on RTDB', () async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      isOptional: true,
      envString: 'USE_POSTGRES_BACKEND=true',
    );
    final locator = ServiceLocator();
    locator.initialize(projectId: 'synthetic', apiKey: 'synthetic');
    expect(locator.isBackendApiConfigured, isTrue);
    expect(locator.patientService.isPostgres, isTrue);
    expect(locator.roomService.isPostgres, isTrue);
    expect(locator.paymentService.isPostgres, isTrue);
    expect(locator.settingsService.isPostgres, isTrue);
    expect(locator.photoRtdbService.isPostgres, isTrue);
    expect(locator.registrationNumberService.isPostgres, isTrue);
    expect(
      () => locator.rtdbService,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'diagnostic',
          contains('Firebase RTDB is disabled when USE_POSTGRES_BACKEND=true'),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    locator.dispose();
  });

  test(
    'disabled mode keeps Firebase domain services and disposes the client',
    () async {
      SharedPreferences.setMockInitialValues({});
      dotenv.loadFromString(
        isOptional: true,
        envString: 'USE_POSTGRES_BACKEND=false',
      );
      final locator = ServiceLocator();
      locator.initialize(projectId: 'synthetic', apiKey: 'synthetic');
      expect(locator.rtdbService.projectId, 'synthetic');
      expect(locator.patientService, isNotNull);
      expect(locator.registrationNumberService, isNotNull);
      expect(locator.isBackendApiConfigured, isFalse);
      // Auth restoration is asynchronous; let it finish before disposal.
      await Future<void>.delayed(Duration.zero);
      locator.dispose();
      expect(() => locator.backendApiService, throwsException);
      expect(() => locator.rtdbService, throwsException);
    },
  );
}
