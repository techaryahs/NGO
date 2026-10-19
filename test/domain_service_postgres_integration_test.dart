import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/photo_rtdb_service.dart';
import 'package:ngo/services/registration_number_service.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistentCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = PersistentCache(CacheDatabase(NativeDatabase.memory()));
    await cache.initialize();
    await cache.activateAccount('test-account-pg');
  });

  tearDown(() async {
    await cache.close();
    ServiceLocator().dispose();
    dotenv.loadFromString(isOptional: true, envString: '');
  });

  BackendApiService createMockBackend(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final service = BackendApiService(
      baseUrl: 'https://backend.example/api',
      persistentCache: cache,
      client: MockClient(handler),
      getAuthToken: () async => 'mock-firebase-token',
    );
    addTearDown(service.dispose);
    return service;
  }

  Uint8List createSmallPng() {
    final image = img.Image(width: 10, height: 10);
    img.fill(image, color: img.ColorRgba8(255, 0, 0, 255));
    return Uint8List.fromList(img.encodePng(image));
  }

  group('PatientService with PostgreSQL Backend', () {
    test('getPatientsStream maps backend map response to Patient objects', () async {
      final backend = createMockBackend((request) async {
        if (request.url.path == '/api/patients') {
          return http.Response(
            json.encode({
              'p_1': {
                'id': 'p_1',
                'fullName': 'Alice Wonderland',
                'registrationNumber': '101',
                'admissionDate': DateTime.now().toIso8601String(),
                'status': 'active',
                'dateOfBirth': '1990-01-01',
                'gender': 'Female',
                'contactNumber': '1234567890',
                'emergencyContact': '9876543210',
                'emergencyContactName': 'Bob',
                'medicalCondition': 'Stable',
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final patientService = PatientService(backendApiService: backend);
      expect(patientService.isPostgres, isTrue);

      final patients = await patientService
          .getPatientsStream()
          .firstWhere((list) => list.isNotEmpty);
      expect(patients.length, 1);
      expect(patients.first.id, 'p_1');
      expect(patients.first.fullName, 'Alice Wonderland');
      expect(patients.first.registrationNumber, '101');
    });

    test('getPatient reads single patient from /api/patients/:id', () async {
      final backend = createMockBackend((request) async {
        if (request.url.path == '/api/patients/p_1') {
          return http.Response(
            json.encode({
              'id': 'p_1',
              'fullName': 'Alice Wonderland',
              'registrationNumber': '101',
              'admissionDate': DateTime.now().toIso8601String(),
              'status': 'active',
              'dateOfBirth': '1990-01-01',
              'gender': 'Female',
              'contactNumber': '1234567890',
              'emergencyContact': '9876543210',
              'emergencyContactName': 'Bob',
              'medicalCondition': 'Stable',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final patientService = PatientService(backendApiService: backend);
      final patient = await patientService.getPatient('p_1');
      expect(patient, isNotNull);
      expect(patient!.fullName, 'Alice Wonderland');
      expect(patient.registrationNumber, '101');
    });

    test('deletePatient calls DELETE on /api/patients/:id', () async {
      var deleted = false;
      final backend = createMockBackend((request) async {
        if (request.method == 'DELETE' && request.url.path == '/api/patients/p_1') {
          deleted = true;
          return http.Response(json.encode({'success': true}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final patientService = PatientService(backendApiService: backend);
      await patientService.deletePatient('p_1');
      expect(deleted, isTrue);
    });
  });

  group('RoomService with PostgreSQL Backend', () {
    test('streamRooms combines backend rooms and stays', () async {
      final backend = createMockBackend((request) async {
        if (request.url.path == '/api/rooms') {
          return http.Response(
            json.encode({
              'r_101': {
                'id': 'r_101',
                'roomNumber': '101',
                'roomIdentifier': '101',
                'floor': 1,
                'roomType': 'General',
                'status': 'available',
                'maxAttendants': 4,
                'currentAttendants': 0,
                'totalBeds': 2,
                'occupiedBeds': 0,
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/stays') {
          return http.Response(json.encode({}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final roomService = RoomService(backendApiService: backend);
      expect(roomService.isPostgres, isTrue);

      final rooms = await roomService
          .streamRooms()
          .firstWhere((list) => list.isNotEmpty);
      expect(rooms.length, 1);
      expect(rooms.first.id, 'r_101');
      expect(rooms.first.roomNumber, '101');
    });

    test('getPricing and updatePricing read and write settings/pricing', () async {
      var pricingData = <String, dynamic>{
        'generalRoomBedPrice': 200,
        'privateRoomBasePrice': 700,
      };

      final backend = createMockBackend((request) async {
        if (request.method == 'GET' && request.url.path == '/api/settings/pricing') {
          return http.Response(json.encode(pricingData), 200);
        }
        if (request.method == 'PUT' && request.url.path == '/api/settings/pricing') {
          pricingData = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(json.encode(pricingData), 200);
        }
        return http.Response('Not Found', 404);
      });

      final roomService = RoomService(backendApiService: backend);
      final pricing = await roomService.getPricing();
      expect(pricing, isNotNull);

      await roomService.updatePricing({
        'generalRoomBedPrice': 250,
        'privateRoomBasePrice': 750,
      });
      expect(pricingData['generalRoomBedPrice'], 250);
    });

    test('createStay and completeStay call /api/stays routes', () async {
      var stayCreated = false;
      var stayCompleted = false;

      final backend = createMockBackend((request) async {
        if (request.method == 'POST' && request.url.path == '/api/stays') {
          stayCreated = true;
          return http.Response(
            json.encode({
              'id': 'stay_123',
              'patientId': 'p_1',
              'roomId': 'r_101',
              'roomNumber': '101',
              'floor': 1,
              'status': 'active',
            }),
            201,
          );
        }
        if (request.method == 'PUT' && request.url.path == '/api/stays/stay_123') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          if (body['status'] == 'completed') {
            stayCompleted = true;
          }
          return http.Response(json.encode({'id': 'stay_123', ...body}), 200);
        }
        if (request.method == 'GET' && request.url.path == '/api/patients/p_1') {
          return http.Response(
            json.encode({
              'id': 'p_1',
              'fullName': 'Alice Wonderland',
              'admissionDate': DateTime.now().toIso8601String(),
              'dateOfBirth': '1990-01-01',
              'gender': 'Female',
              'contactNumber': '1234567890',
              'emergencyContact': '9876543210',
              'emergencyContactName': 'Bob',
              'medicalCondition': 'Stable',
            }),
            200,
          );
        }
        if (request.method == 'GET' && request.url.path == '/api/settings/pricing') {
          return http.Response(
            json.encode({'generalRoomBedPrice': 200, 'privateRoomBasePrice': 700}),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final roomService = RoomService(backendApiService: backend);
      final stayId = await roomService.createStay(
        patientId: 'p_1',
        patientName: 'Alice Wonderland',
        roomId: 'r_101',
        roomNumber: '101',
        roomType: 'General',
        admissionDate: DateTime.now(),
        durationDays: 5,
        attendantCount: 0,
        createdBy: 'admin_test',
      );

      expect(stayCreated, isTrue);
      expect(stayId, 'stay_123');

      await roomService.completeStay(
        'stay_123',
        completedAt: DateTime.now(),
      );
      expect(stayCompleted, isTrue);
    });
  });

  group('PaymentService with PostgreSQL Backend', () {
    test('loadStays queries /api/stays by patientId', () async {
      final backend = createMockBackend((request) async {
        if (request.url.path == '/api/stays' &&
            request.url.queryParameters['patientId'] == 'p_1') {
          return http.Response(
            json.encode({
              'stay_1': {
                'id': 'stay_1',
                'patientId': 'p_1',
                'patientName': 'Alice Wonderland',
                'roomNumber': '101',
                'roomType': 'General',
                'admissionDate': DateTime.now().toIso8601String(),
                'status': 'active',
                'startDate': '2026-10-01',
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final paymentService = PaymentService(null, backend);
      expect(paymentService.isPostgres, isTrue);

      final stays = await paymentService.loadStays('p_1');
      expect(stays.length, 1);
      expect(stays.first.id, 'stay_1');
    });
  });

  group('RegistrationNumberService with PostgreSQL Backend', () {
    test('allocateNextRegistrationNumber calls /api/counters/registrationNumber/next', () async {
      var nextCalled = false;
      final backend = createMockBackend((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/counters/registrationNumber') {
          return http.Response(
            json.encode({'name': 'registrationNumber', 'currentValue': 100}),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/counters/registrationNumber/next') {
          nextCalled = true;
          return http.Response(
            json.encode({'name': 'registrationNumber', 'allocatedValue': 101}),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final regService = RegistrationNumberService(backendApiService: backend);
      expect(regService.isPostgres, isTrue);

      final allocated = await regService.allocateNextRegistrationNumber(
        idempotencyKey: 'adm_123',
      );
      expect(nextCalled, isTrue);
      expect(allocated, '101');

      // Idempotency check: repeat call returns cached value without second POST
      nextCalled = false;
      final cached = await regService.allocateNextRegistrationNumber(
        idempotencyKey: 'adm_123',
      );
      expect(nextCalled, isFalse);
      expect(cached, '101');
    });
  });

  group('SettingsService with PostgreSQL Backend', () {
    test('reads and updates settings categories and keys', () async {
      final db = <String, Map<String, dynamic>>{
        'notifications': {'dailySummary': true},
        'security': {'paymentWritesLocked': false},
        'backup': {'autoDailyBackup': true, 'lastBackup': 'Never'},
      };

      final backend = createMockBackend((request) async {
        const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};
        if (request.method == 'GET' && request.url.path.startsWith('/api/settings/')) {
          final segments = request.url.path.replaceFirst('/api/settings/', '').split('/');
          final cat = segments[0];
          if (segments.length == 1) {
            return http.Response(json.encode(db[cat] ?? {}), 200, headers: jsonHeaders);
          } else {
            final key = segments[1];
            return http.Response(json.encode(db[cat]?[key]), 200, headers: jsonHeaders);
          }
        }
        if (request.method == 'PUT' && request.url.path.startsWith('/api/settings/')) {
          final segments = request.url.path.replaceFirst('/api/settings/', '').split('/');
          final cat = segments[0];
          final key = segments[1];
          final value = json.decode(request.body);
          db.putIfAbsent(cat, () => {})[key] = value;
          return http.Response(json.encode(value), 200, headers: jsonHeaders);
        }
        return http.Response('Not Found', 404);
      });

      final settings = SettingsService(null, backend);
      expect(settings.isPostgres, isTrue);

      final all = await settings.getSettings();
      expect(all['notifications']['dailySummary'], isTrue);
      expect(all['security']['paymentWritesLocked'], isFalse);

      final lockInitial = await settings.getPaymentWritesLocked();
      expect(lockInitial, isFalse);

      final lockUpdate = await settings.updatePaymentWritesLocked(true);
      expect(lockUpdate, isTrue);
      expect(db['security']?['paymentWritesLocked'], isTrue);

      final updatedLock = await settings.getPaymentWritesLocked();
      expect(updatedLock, isTrue);

      final backupResult = await settings.triggerManualBackup();
      expect(backupResult['success'], isTrue);
      expect(db['backup']?['lastBackup'], isNotNull);
    });
  });

  group('PhotoRtdbService with PostgreSQL Backend', () {
    test('upload, download, and delete photos via BackendApiService', () async {
      final storage = <String, Map<String, dynamic>>{};
      final backend = createMockBackend((request) async {
        final path = request.url.path;
        String normalizePhotoRef(String raw) {
          var r = raw.replaceFirst('/api/photos/', '');
          while (r.startsWith('photos/')) {
            r = r.replaceFirst('photos/', '');
          }
          return r.startsWith('patientPhotos/') ? r : 'patientPhotos/$r';
        }
        if (request.method == 'PUT' && path.startsWith('/api/photos/')) {
          final ref = normalizePhotoRef(path);
          final body = json.decode(request.body) as Map<String, dynamic>;
          storage[ref] = {
            'data': body['data'],
            'contentType': body['contentType'],
            'version': body['version'],
          };
          return http.Response(json.encode(storage[ref]), 200);
        }
        if (request.method == 'GET' && path.startsWith('/api/photos/')) {
          final ref = normalizePhotoRef(path);
          if (storage.containsKey(ref)) {
            return http.Response(json.encode(storage[ref]), 200);
          }
          return http.Response('Not Found', 404);
        }
        if (request.method == 'DELETE' && path.startsWith('/api/photos/')) {
          final ref = normalizePhotoRef(path);
          storage.remove(ref);
          return http.Response(json.encode({'success': true}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final photoService = PhotoRtdbService(backendApi: backend, persistentCache: cache);
      expect(photoService.isPostgres, isTrue);

      final photoPath = PhotoRtdbService.patientPath('patient_999');
      final pngBytes = createSmallPng();

      final uploadedRef = await photoService.uploadPhoto(
        photoPath: photoPath,
        bytes: pngBytes,
      );
      expect(uploadedRef, photoPath);

      final exists = await photoService.photoExists(photoPath);
      expect(exists, isTrue);

      final downloaded = await photoService.downloadPhoto(photoPath);
      expect(downloaded, isNotNull);
      expect(downloaded!.isNotEmpty, isTrue);

      await photoService.deletePhoto(photoPath);
      final existsAfterDelete = await photoService.photoExists(photoPath);
      expect(existsAfterDelete, isFalse);
    });
  });

  group('ServiceLocator Fail-Closed Safety Guarantees', () {
    test('USE_POSTGRES_BACKEND=true prevents RTDB access with StateError', () async {
      dotenv.loadFromString(
        isOptional: true,
        envString: 'USE_POSTGRES_BACKEND=true',
      );
      final locator = ServiceLocator();
      locator.initialize(projectId: 'mock-proj', apiKey: 'mock-key');

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
    });
  });
}
