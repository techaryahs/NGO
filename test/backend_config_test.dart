import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/config/app_config.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    ServiceLocator().dispose();
    dotenv.loadFromString(isOptional: true, envString: '');
  });

  test('PostgreSQL backend is always enabled as the sole application data store', () {
    for (final value in ['', 'false', '0', 'TRUE', 'true']) {
      dotenv.loadFromString(
        isOptional: true,
        envString: 'USE_POSTGRES_BACKEND=$value',
      );
      expect(AppConfig.usePostgresBackend, isTrue);
    }
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
    'ServiceLocator never falls back to Firebase RTDB even if USE_POSTGRES_BACKEND=false is set in .env',
    () async {
      SharedPreferences.setMockInitialValues({});
      dotenv.loadFromString(
        isOptional: true,
        envString: 'USE_POSTGRES_BACKEND=false',
      );
      final locator = ServiceLocator();
      locator.initialize(projectId: 'synthetic', apiKey: 'synthetic');
      expect(locator.isBackendApiConfigured, isTrue);
      expect(locator.patientService.isPostgres, isTrue);
      expect(locator.registrationNumberService.isPostgres, isTrue);
      expect(() => locator.rtdbService, throwsA(isA<StateError>()));
      // Auth restoration is asynchronous; let it finish before disposal.
      await Future<void>.delayed(Duration.zero);
      locator.dispose();
      expect(() => locator.backendApiService, throwsException);
      expect(() => locator.rtdbService, throwsA(isA<StateError>()));
    },
  );

  test('VPS connectivity endpoint is parsed and recognized as non-localhost', () {
    dotenv.loadFromString(
      isOptional: true,
      envString: '''
ENVIRONMENT=testing
USE_POSTGRES_BACKEND=true
BACKEND_API_URL=http://46.202.167.86:8808/api
''',
    );
    expect(AppConfig.backendApiUrl, 'http://46.202.167.86:8808/api');
    expect(AppConfig.usePostgresBackend, isTrue);
    expect(AppConfig.environment, 'testing');
    expect(AppConfig.isProduction, isFalse);
    expect(AppConfig.isLocalhostUrl(AppConfig.backendApiUrl), isFalse);
  });

  test('production configuration does not silently use localhost', () {
    const validFirebaseBase = '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=synthetic-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
ENVIRONMENT=production
USE_POSTGRES_BACKEND=true
''';

    for (final localUrl in [
      'http://localhost:8080/api',
      'http://127.0.0.1:8808/api',
      'http://0.0.0.0:8080/api',
      'https://localhost:8080/api',
      'https://127.0.0.1:8808/api',
    ]) {
      dotenv.loadFromString(
        isOptional: true,
        envString: '$validFirebaseBase\nBACKEND_API_URL=$localUrl',
      );
      expect(
        () => AppConfig.validate(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'diagnostic',
            contains('BACKEND_API_URL cannot target localhost/loopback'),
          ),
        ),
      );
    }
  });

  test('production configuration requires HTTPS', () {
    dotenv.loadFromString(
      isOptional: true,
      envString: '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=synthetic-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
ENVIRONMENT=production
USE_POSTGRES_BACKEND=true
BACKEND_API_URL=http://46.202.167.86:8808/api
''',
    );
    expect(
      () => AppConfig.validate(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'diagnostic',
          contains('BACKEND_API_URL must use HTTPS'),
        ),
      ),
    );

    // Valid HTTPS production endpoint passes validation
    dotenv.loadFromString(
      isOptional: true,
      envString: '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=synthetic-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
ENVIRONMENT=production
USE_POSTGRES_BACKEND=true
BACKEND_API_URL=https://ngo.aryahs.org/api
''',
    );
    expect(() => AppConfig.validate(), returnsNormally);
  });

  test('client configuration strictly rejects PostgreSQL database credentials', () {
    dotenv.loadFromString(
      isOptional: true,
      envString: '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=synthetic-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
POSTGRES_PASSWORD=leak_secret_db_pass
USE_POSTGRES_BACKEND=true
BACKEND_API_URL=http://46.202.167.86:8808/api
''',
    );
    expect(
      () => AppConfig.validate(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'diagnostic',
          contains('Security violation: POSTGRES_PASSWORD must not be stored in client .env assets'),
        ),
      ),
    );
  });

  test('testing environment allows HTTP to VPS for controlled connectivity verification', () {
    dotenv.loadFromString(
      isOptional: true,
      envString: '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=synthetic-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
ENVIRONMENT=testing
USE_POSTGRES_BACKEND=true
BACKEND_API_URL=http://46.202.167.86:8808/api
''',
    );
    expect(() => AppConfig.validate(), returnsNormally);
  });

  test('authentication tokens are attached correctly to BackendApiService requests', () async {
    String? capturedAuthHeader;
    final client = MockClient((request) async {
      capturedAuthHeader = request.headers['Authorization'];
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    });

    final backendApi = BackendApiService(
      baseUrl: 'http://46.202.167.86:8808/api',
      getAuthToken: () async => 'test-firebase-jwt-token-12345',
      client: client,
    );

    final result = await backendApi.get('health');
    expect(capturedAuthHeader, 'Bearer test-firebase-jwt-token-12345');
    expect(result, isNotNull);
    backendApi.dispose();
  });

  test('failed remote requests fail closed and never fall back to Firebase RTDB', () async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      isOptional: true,
      envString: '''
FIREBASE_PROJECT_ID=ngo-management-system-new-as
FIREBASE_DATABASE_URL=https://ngo-management-system-new-as-default-rtdb.asia-southeast1.firebasedatabase.app
FIREBASE_API_KEY=synthetic-key
FIREBASE_AUTH_DOMAIN=ngo-management-system-new-as.firebaseapp.com
ENVIRONMENT=testing
USE_POSTGRES_BACKEND=true
BACKEND_API_URL=http://46.202.167.86:8808/api
''',
    );

    final client = MockClient((request) async {
      return http.Response(jsonEncode({'error': 'Internal server error'}), 500);
    });

    final backendApi = BackendApiService(
      baseUrl: AppConfig.backendApiUrl,
      getAuthToken: () async => 'token',
      client: client,
    );

    expect(
      () => backendApi.get('patients'),
      throwsA(isA<BackendApiException>()),
    );

    final locator = ServiceLocator();
    locator.initialize(projectId: 'synthetic', apiKey: 'synthetic');

    // Guaranteed fail-closed: RTDB cannot be accessed as a fallback write/read authority
    expect(
      () => locator.rtdbService,
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'diagnostic',
        contains('Firebase RTDB is disabled when USE_POSTGRES_BACKEND=true'),
      )),
    );

    await Future<void>.delayed(Duration.zero);
    locator.dispose();
    backendApi.dispose();
  });

  test('cache invalidates server entity data on data source switch while preserving profiles', () async {
    final db = CacheDatabase(NativeDatabase.memory());
    final cache = PersistentCache(db);
    await cache.initialize();

    // 1. Initial connection to local database
    cache.dataSource = 'postgres:http://127.0.0.1:8808/api';
    await cache.activateAccount('staff_user_1');

    // Seed local patient data and user profile
    await cache.replaceSnapshot('patients', {
      'patient_old': {
        'id': 'patient_old',
        'fullName': 'Old Local Patient',
        'status': 'active',
        'admissionDate': '2026-09-01T10:00:00.000Z',
      },
    });
    await cache.applyServerMutation({
      'users/staff_user_1': {'id': 'staff_user_1', 'role': 'admin', 'name': 'Staff One'},
    }, isPatch: false);

    expect(await cache.read('patients/patient_old'), isNotNull);
    expect(await cache.read('users/staff_user_1'), isNotNull);

    // 2. Switch data source to VPS
    cache.deactivateAccount();
    cache.dataSource = 'postgres:http://46.202.167.86:8808/api';
    await cache.activateAccount('staff_user_1');

    // Stale local patient entity was purged to prevent mixing datasets
    expect(await cache.read('patients/patient_old'), isNull);
    // User profile/auth state is preserved across data source transitions
    final profile = await cache.read('users/staff_user_1');
    expect(profile, isNotNull);
    expect((profile as Map)['role'], 'admin');

    await cache.close();
  });

  test('reconciled advance payments, payment history, registration numbers, and room occupancy route via PostgreSQL API', () async {
    final requestedUrls = <String>[];
    final admissionMs = 1787196600000;
    const upiId = 'upi_78872293db2bf1ea37273e07deb48e11a2950085cf84010e367fcd5af0fbf996';

    final client = MockClient((request) async {
      requestedUrls.add('${request.method} ${request.url.path}');
      expect(request.url.host, isNot(contains('firebasedatabase.app')));
      if (request.url.path == '/api/patients/-P01po5yZfRSwP3UDFLN') {
        return http.Response(
          jsonEncode({
            'id': '-P01po5yZfRSwP3UDFLN',
            'fullName': 'Taraknath Pal',
            'registrationNumber': '5132',
            'dateOfBirth': DateTime(1965, 1, 1).millisecondsSinceEpoch,
            'age': 61,
            'gender': 'Male',
            'contactNumber': '9876543210',
            'emergencyContact': '9876543211',
            'emergencyContactName': 'Kin',
            'medicalCondition': 'Treatment',
            'admissionDate': admissionMs,
            'status': 'discharged',
            'totalPaidAmount': 25900.0,
            'currentDueAmount': 0.0,
            'advanceBilledAmount': 25900.0,
            'payments': [
              {
                'id': upiId,
                'patientId': '-P01po5yZfRSwP3UDFLN',
                'cycleId': '$admissionMs',
                'amount': 10000.0,
                'method': 'UPI',
                'type': 'Advance Payment',
                'transactionId': '449581259384',
                'receiptNumber': '6966',
                'date': admissionMs,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/api/payments') {
        return http.Response(
          jsonEncode({
            upiId: {
              'id': upiId,
              'patientId': '-P01po5yZfRSwP3UDFLN',
              'cycleId': '$admissionMs',
              'amount': 10000.0,
              'method': 'UPI',
              'type': 'Advance Payment',
              'transactionId': '449581259384',
              'receiptNumber': '6966',
              'date': admissionMs,
            },
          }),
          200,
        );
      }
      if (request.url.path == '/api/rooms') {
        return http.Response(
          jsonEncode({
            'r_2c': {
              'id': 'r_2c',
              'roomNumber': '2C',
              'roomIdentifier': '2C',
              'floor': 2,
              'roomType': 'general',
              'totalBeds': 6,
              'occupiedBeds': 2,
              'status': 'partially_occupied',
              'beds': [
                {
                  'id': 'r_2c_3',
                  'bedLabel': '3',
                  'status': 'occupied',
                  'currentPatientId': 'p_1792653066208754_a70a4b731afc0975e593ce40',
                },
                {
                  'id': 'r_2c_5',
                  'bedLabel': '5',
                  'status': 'occupied',
                  'currentPatientId': 'p_1792581651923638_6b674d3190bc6d8df34ddebd',
                },
              ],
            },
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    final backendApi = BackendApiService(
      baseUrl: 'http://46.202.167.86:8808/api',
      getAuthToken: () async => 'firebase-jwt-token',
      client: client,
    );
    ServiceLocator().backendApiService = backendApi;

    final patient = await ServiceLocator().backendApiService.get('patients/-P01po5yZfRSwP3UDFLN') as Map;
    expect(patient['registrationNumber'], '5132');
    expect(patient['totalPaidAmount'], 25900.0);
    expect((patient['payments'] as List).single['id'], upiId);
    expect((patient['payments'] as List).single['amount'], 10000.0);

    final rooms = await ServiceLocator().backendApiService.get('rooms') as Map;
    expect((rooms['r_2c'] as Map)['occupiedBeds'], 2);

    expect(requestedUrls, contains('GET /api/patients/-P01po5yZfRSwP3UDFLN'));
    expect(requestedUrls, contains('GET /api/rooms'));
    backendApi.dispose();
  });
}
