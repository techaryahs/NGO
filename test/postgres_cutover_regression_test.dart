import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/services/auth_service.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/firebase_auth_rest_service.dart';
import 'package:ngo/services/inventory_expense_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/photo_migration_service.dart';
import 'package:ngo/services/photo_rtdb_service.dart';
import 'package:ngo/services/registration_number_service.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/services/sponsorship_service.dart';
import 'package:ngo/services/stay_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthRestService extends FirebaseAuthRestService {
  _FakeAuthRestService() : super(apiKey: 'fake-api-key');

  int signInCalls = 0;
  int signUpCalls = 0;
  Duration delay = const Duration(milliseconds: 40);

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    await Future<void>.delayed(delay);
    final user = AuthUser(uid: 'uid_${email.hashCode.abs()}', email: email);
    return AuthResult(success: true, user: user, statusCode: 200);
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    bool broadcastState = true,
  }) async {
    signUpCalls++;
    await Future<void>.delayed(delay);
    final user = AuthUser(uid: 'uid_${email.hashCode.abs()}', email: email);
    return AuthResult(success: true, user: user, statusCode: 200);
  }
}

Future<void> _validateRegistrationWithBackend(
  Map<String, dynamic> payload,
) async {
  // Import only the real request validator. No server, database connection,
  // application configuration, or live records participate in this contract.
  final process = await Process.start('node', [
    '--import',
    'tsx',
    '--input-type=module',
    '-e',
    r'''
import { readFileSync } from 'node:fs';
import { validateDomainRequest } from './src/validation.ts';
try {
  await validateDomainRequest({
    method: 'POST',
    routeOptions: { url: '/api/patients/register' },
    body: JSON.parse(readFileSync(0, 'utf8')),
  });
  console.log('Actual backend registration schema accepted Flutter JSON');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
''',
  ], workingDirectory: Directory('backend').absolute.path);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(jsonEncode(payload));
  await process.stdin.close();
  expect(await process.exitCode, 0, reason: await errors);
  expect(await output, contains('schema accepted Flutter JSON'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistentCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = PersistentCache(CacheDatabase(NativeDatabase.memory()));
    await cache.initialize();
    await cache.activateAccount('test-cutover-account');
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

  group('1. Atomic Patient Registration & 71-char Stay IDs', () {
    test(
      'buildRegistrationStaysPayload + addPatient calls POST /api/patients/register atomically',
      () async {
        Map<String, dynamic>? capturedRegisterBody;
        final postedPaths = <String>[];
        final backend = createMockBackend((request) async {
          if (request.method == 'POST') postedPaths.add(request.url.path);
          if (request.url.path == '/api/settings/pricing' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'generalRoomBedPrice': 200,
                'privateRoomBasePrice': 700,
                'privateRoomIncludedAttendants': 1,
                'privateRoomExtraAttendantFee': 200,
              }),
              200,
            );
          }
          if (request.url.path == '/api/patients/register' &&
              request.method == 'POST') {
            capturedRegisterBody =
                jsonDecode(request.body) as Map<String, dynamic>;
            await _validateRegistrationWithBackend(capturedRegisterBody!);
            return http.Response(
              jsonEncode({
                'patient': Map<String, dynamic>.from(capturedRegisterBody!)
                  ..remove('stays')
                  ..remove('initialAttendance'),
                'stays': capturedRegisterBody!['stays'],
              }),
              201,
            );
          }
          return http.Response(
            'Unexpected ${request.method} ${request.url.path}',
            500,
          );
        });

        final roomService = RoomService(backendApiService: backend);
        final patientService = PatientService(
          backendApiService: backend,
          roomService: roomService,
          registrationNumberService: RegistrationNumberService(
            backendApiService: backend,
          ),
        );

        const patientId = 'p_1792317035249089_7491219db8037bcf66f1cc8b';
        const bedId = 'r_1792316250516360_1/2';
        final room = RoomModel(
          id: 'r_1792316250516360',
          roomNumber: '1A',
          roomIdentifier: '1A',
          floor: 1,
          roomType: 'general',
          totalBeds: 2,
          occupiedBeds: 0,
          status: 'available',
          beds: [BedModel(id: bedId, bedLabel: '1/2', status: 'available')],
          createdAt: DateTime(2026, 10, 18),
          updatedAt: DateTime(2026, 10, 18),
        );

        final staysPayload = await roomService.buildRegistrationStaysPayload(
          patientId: patientId,
          patientName: 'Atomic Patient',
          admissionDate: DateTime(2026, 10, 18),
          durationDays: 5,
          attendantCount: 2,
          attendantLabels: const ['Spouse', 'Sibling.QA'],
          createdBy: 'admin_1',
          room: room,
          bedIds: const [bedId],
        );

        expect(staysPayload, hasLength(1));
        final generatedStayId = staysPayload.first['id'] as String;
        expect(generatedStayId, 'stay_${patientId}_$bedId');
        expect(generatedStayId.length, greaterThan(64));

        final returnedId = await patientService.addPatient(
          id: patientId,
          fullName: 'Atomic Patient',
          dateOfBirth: DateTime(1985, 5, 10),
          gender: 'male',
          contactNumber: '9876543210',
          emergencyContact: '9876543211',
          emergencyContactName: 'Spouse',
          medicalCondition: 'Observation',
          admissionDate: DateTime(2026, 10, 18),
          exitDate: DateTime(2026, 10, 20),
          roomId: room.id,
          roomNumber: room.roomIdentifier,
          floor: 1,
          bedIds: const [bedId],
          bedLabels: const ['1/2'],
          createdBy: 'admin_1',
          registrationNumber: '105',
          attendants: [
            AttendantModel(
              name: 'Spouse',
              relation: 'Wife',
              mobileNumber: '9876543211',
              isEmergencyContact: true,
            ),
            AttendantModel(name: 'Sibling.QA', relation: 'Sibling'),
          ],
          initialStays: staysPayload,
        );

        expect(returnedId, patientId);
        expect(capturedRegisterBody, isNotNull);
        expect(capturedRegisterBody!['id'], patientId);
        expect(capturedRegisterBody!['fullName'], 'Atomic Patient');
        expect(capturedRegisterBody!.containsKey('patient'), isFalse);
        expect(
          (capturedRegisterBody!['stays'] as List).first['id'],
          generatedStayId,
        );
        expect(capturedRegisterBody!.containsKey('initialAttendance'), isFalse);
        expect(postedPaths, ['/api/patients/register']);
      },
    );

    test(
      'addPatient converts HTTP 409 from /api/patients/register into BedConflictException',
      () async {
        final backend = createMockBackend((request) async {
          if (request.url.path == '/api/patients/register') {
            return http.Response(
              jsonEncode({
                'error': 'Conflict',
                'message': 'Bed 1/2 is already occupied',
              }),
              409,
            );
          }
          return http.Response('{}', 200);
        });

        final roomService = RoomService(backendApiService: backend);
        final patientService = PatientService(
          backendApiService: backend,
          roomService: roomService,
        );

        expect(
          () => patientService.addPatient(
            id: 'p_conflict_1',
            fullName: 'Conflict Patient',
            dateOfBirth: DateTime(1990, 1, 1),
            gender: 'female',
            contactNumber: '9999999999',
            emergencyContact: '',
            emergencyContactName: '',
            medicalCondition: 'Checkup',
            admissionDate: DateTime(2026, 10, 18),
            createdBy: 'admin_1',
            registrationNumber: '106',
            initialStays: [
              {
                'id': 'stay_p_conflict_1_bed_1',
                'patientId': 'p_conflict_1',
                'patientName': 'Conflict Patient',
                'roomId': 'r_1',
                'roomNumber': '1A',
                'roomType': 'general',
                'bedId': 'bed_1',
                'bedLabel': '1/2',
                'admissionDate': DateTime(2026, 10, 18).millisecondsSinceEpoch,
                'durationDays': 5,
              },
            ],
          ),
          throwsA(isA<BedConflictException>()),
        );
      },
    );
  });

  group(
    '2 & 3. ServiceLocator Initialization & Complete RTDB Retirement in PostgreSQL Mode',
    () {
      test(
        'ServiceLocator initializes all services in PostgreSQL mode and blocks rtdbService access',
        () async {
          dotenv.loadFromString(
            envString:
                'USE_POSTGRES_BACKEND=true\nBACKEND_BASE_URL=https://backend.example/api\nFIREBASE_WEB_API_KEY=fake-key\n',
          );
          ServiceLocator().initialize(
            projectId: 'test-project',
            apiKey: 'fake-key',
          );

          expect(ServiceLocator().isInitialized, isTrue);
          // Calling initialize() again is idempotent and does not fail
          ServiceLocator().initialize(
            projectId: 'test-project',
            apiKey: 'fake-key',
          );

          expect(ServiceLocator().authService.isPostgres, isTrue);
          expect(ServiceLocator().patientService.isPostgres, isTrue);
          expect(ServiceLocator().roomService.isPostgres, isTrue);
          expect(ServiceLocator().registrationNumberService.isPostgres, isTrue);
          expect(ServiceLocator().paymentService.isPostgres, isTrue);
          expect(ServiceLocator().settingsService.isPostgres, isTrue);
          expect(ServiceLocator().photoRtdbService.isPostgres, isTrue);
          expect(ServiceLocator().inventoryExpenseService.isPostgres, isTrue);
          expect(ServiceLocator().sponsorshipService.isPostgres, isTrue);
          expect(ServiceLocator().photoMigrationService, isNotNull);
          expect(ServiceLocator().notificationService, isNotNull);
          expect(ServiceLocator().backendApiService, isNotNull);

          // StayHistoryService.fromLocator routes to PostgreSQL backendApi
          final stayHistory = StayHistoryService.fromLocator();
          expect(stayHistory.backendApi, isNotNull);
          expect(stayHistory.db, isNull);

          // retryAllStreams succeeds without touching rtdbService
          ServiceLocator().retryAllStreams();

          // Accessing rtdbService in PostgreSQL mode must throw StateError
          expect(
            () => ServiceLocator().rtdbService,
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains(
                  'Firebase RTDB is disabled when USE_POSTGRES_BACKEND=true',
                ),
              ),
            ),
          );
        },
      );

      test(
        'InventoryExpenseService, SponsorshipService, PhotoMigrationService, and StayHistoryService route through BackendApiService',
        () async {
          final requestedPaths = <String>[];
          final backend = createMockBackend((request) async {
            requestedPaths.add('${request.method} ${request.url.path}');
            if (request.method == 'GET' &&
                request.url.path.startsWith('/api/erp/')) {
              return http.Response(
                jsonEncode([
                  {
                    'id': 'rec_1',
                    'name': 'Bandages',
                    'category': 'Medical',
                    'current_stock': 10,
                    'unit': 'boxes',
                    'min_stock_level': 2,
                    'amount': 500,
                    'total_amount': 500,
                    'sponsor_name': 'Donor A',
                    'sponsorship_date': DateTime(
                      2026,
                      10,
                      18,
                    ).toIso8601String(),
                    'created_at': DateTime(2026, 10, 18).toIso8601String(),
                    'updated_at': DateTime(2026, 10, 18).toIso8601String(),
                  },
                ]),
                200,
              );
            }
            if (request.method == 'POST' &&
                request.url.path.startsWith('/api/erp/')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({'id': body['id'] ?? 'generated_1', ...body}),
                201,
              );
            }
            if (request.method == 'PUT' || request.method == 'DELETE') {
              return http.Response(jsonEncode({'ok': true}), 200);
            }
            if (request.url.path == '/api/patients') {
              return http.Response(jsonEncode({}), 200);
            }
            if (request.url.path == '/api/attendance') {
              return http.Response(
                jsonEncode({
                  '2026-10-18': {
                    'p_1': {'status': 'Present', 'date': '2026-10-18'},
                  },
                }),
                200,
              );
            }
            return http.Response('{}', 200);
          });

          final invService = InventoryExpenseService(
            backendApiService: backend,
          );
          final items = await invService.getInventoryItemsStream().first;
          expect(items, hasLength(1));
          expect(items.first.name, 'Bandages');
          expect(items.first.currentStock, 10);

          await invService.addInventoryItem(
            name: 'Gloves',
            category: 'Medical',
            unit: 'packs',
            minStockLevel: 1,
            currentStock: 5,
            createdBy: 'admin_1',
          );

          final sponService = SponsorshipService(backendApiService: backend);
          final sponsorships = await sponService.getSponsorshipsStream().first;
          expect(sponsorships, hasLength(1));
          expect(sponsorships.first.sponsorName, 'Donor A');

          final photoMigration = PhotoMigrationService(
            backendApi: backend,
            photos: PhotoRtdbService(backendApi: backend),
          );
          final report = await photoMigration.migrate();
          expect(report.scannedPatients, 0);

          final patientService = PatientService(backendApiService: backend);
          final attendanceRange = await patientService
              .getAttendanceRangeForProfile(
                kind: 'attendance',
                startKey: '2026-10-18',
                endKey: '2026-10-18',
              );
          expect(attendanceRange, isA<Map>());

          expect(requestedPaths, contains('GET /api/erp/inventory'));
          expect(requestedPaths, contains('POST /api/erp/inventory'));
          expect(requestedPaths, contains('GET /api/erp/sponsorships'));
          expect(requestedPaths, contains('GET /api/patients'));
          expect(requestedPaths, contains('GET /api/attendance'));
        },
      );

      test(
        'Static codebase scan confirms no UI screen or widget accesses ServiceLocator().rtdbService directly',
        () {
          final uiDirs = [Directory('lib/screens'), Directory('lib/widgets')];
          final violations = <String>[];

          for (final dir in uiDirs) {
            if (!dir.existsSync()) continue;
            for (final entity in dir.listSync(recursive: true)) {
              if (entity is! File || !entity.path.endsWith('.dart')) continue;
              final normalizedPath = entity.path.replaceAll('\\', '/');
              // attendance_service.dart is a dual-mode service class living under lib/screens/attendance/
              if (normalizedPath.endsWith(
                'lib/screens/attendance/attendance_service.dart',
              )) {
                continue;
              }
              final lines = entity.readAsLinesSync();
              for (var i = 0; i < lines.length; i++) {
                final line = lines[i];
                if (line.contains('rtdbService')) {
                  violations.add('$normalizedPath:${i + 1}: ${line.trim()}');
                }
              }
            }
          }

          expect(
            violations,
            isEmpty,
            reason:
                'UI screens and widgets must not call ServiceLocator().rtdbService directly:\n${violations.join('\n')}',
          );
        },
      );
    },
  );

  group('4. Authentication Request Deduplication', () {
    test(
      'AuthService deduplicates concurrent in-flight signIn and getUserRole calls',
      () async {
        final fakeAuthRest = _FakeAuthRestService();
        int roleApiCalls = 0;
        final backend = createMockBackend((request) async {
          if (request.url.path.startsWith('/api/users/')) {
            roleApiCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return http.Response(
              jsonEncode({'uid': 'u_1', 'role': 'admin'}),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        final authService = AuthService(
          authService: fakeAuthRest,
          backendApiService: backend,
          persistentCache: cache,
        );

        // Fire two concurrent signIn requests for the same email
        final signInResults = await Future.wait([
          authService.signIn(email: 'admin@ngo.org', password: 'secret'),
          authService.signIn(email: 'admin@ngo.org', password: 'secret'),
        ]);

        expect(signInResults[0]['success'], isTrue);
        expect(signInResults[1]['success'], isTrue);
        expect(fakeAuthRest.signInCalls, 1);

        // Fire three concurrent getUserRole requests for the same uid
        final roleResults = await Future.wait([
          authService.getUserRole('u_1'),
          authService.getUserRole('u_1'),
          authService.getUserRole('u_1'),
        ]);

        expect(roleResults, everyElement('admin'));
        expect(roleApiCalls, 1);
      },
    );
  });

  group('5. Attendance Sync, Payment, and Discharge Lifecycle in PostgreSQL Mode', () {
    test(
      'legacy automatic sync does not read, create or overwrite attendance',
      () async {
        final postedDates = <String>[];
        final backend = createMockBackend((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/attendance') {
            expect(request.url.queryParameters['startDate'], '2026-10-18');
            expect(request.url.queryParameters['endDate'], '2026-10-20');
            return http.Response(
              jsonEncode({
                '2026-10-18': {
                  'p_1': {
                    'patientId': 'p_1',
                    'status': 'Present',
                    'source': 'automatic_registration_period',
                    'cycleId': 'cycle_1',
                  },
                },
                '2026-10-19': {
                  'p_1': {
                    'patientId': 'p_1',
                    'status': 'Absent',
                    'source': 'manual',
                  },
                },
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/attendance/bulk') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            postedDates.add(body['date'].toString());
            return http.Response(
              jsonEncode({'success': true, 'count': 1}),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        final patientService = PatientService(backendApiService: backend);
        await patientService.syncAutomaticPatientAttendance(
          patientId: 'p_1',
          patientName: 'Patient One',
          start: DateTime(2026, 10, 18),
          end: DateTime(2026, 10, 20),
          cycleId: 'cycle_1',
        );

        // 2026-10-18 is already synced for cycle_1, 2026-10-19 is manual Absent;
        // only 2026-10-20 should be posted.
        expect(postedDates, isEmpty);
      },
    );

    test(
      'Payment recording, billing recalculation, discharge readiness, and discharge route cleanly via PostgreSQL API',
      () async {
        final admissionMs = DateTime(2026, 10, 18, 8, 0).millisecondsSinceEpoch;
        final exitMs = DateTime(2026, 10, 19, 8, 0).millisecondsSinceEpoch;
        final cycleId = admissionMs.toString();

        Map<String, dynamic> patientRow = {
          'id': 'p_discharge_1',
          'fullName': 'Discharge Test Patient',
          'registrationNumber': '701',
          'dateOfBirth': DateTime(1985, 5, 10).millisecondsSinceEpoch,
          'age': 41,
          'gender': 'Male',
          'contactNumber': '9876543210',
          'emergencyContact': '9876543211',
          'emergencyContactName': 'Relative',
          'medicalCondition': 'Observation',
          'admissionDate': admissionMs,
          'registrationDate': admissionMs,
          'exitDate': exitMs,
          'status': 'active',
          'roomId': 'r_101',
          'roomNumber': '101',
          'floor': 1,
          'bedIds': ['r_101_bed_1'],
          'bedLabels': ['Bed 1'],
          'payments': <Map<String, dynamic>>[],
          'admissionBalances': <String, dynamic>{},
        };

        Map<String, dynamic> stayRow = {
          'id': 'stay_p_discharge_1_r_101_bed_1',
          'patientId': 'p_discharge_1',
          'patientName': 'Discharge Test Patient',
          'roomId': 'r_101',
          'roomNumber': '101',
          'floor': 1,
          'roomType': 'General',
          'bedId': 'r_101_bed_1',
          'bedLabel': 'Bed 1',
          'admissionDate': admissionMs,
          'expectedDischargeDate': exitMs,
          'durationDays': 1,
          'attendantCount': 0,
          'status': 'active',
          'createdBy': 'admin_1',
        };

        final attendanceByDate = <String, Map<String, dynamic>>{
          '2026-10-18': {
            'p_discharge_1': {
              'patientId': 'p_discharge_1',
              'status': 'Present',
              'source': 'automatic_registration_period',
              'cycleId': admissionMs.toString(),
            },
          },
        };

        int patientPatchCalls = 0;
        int stayCompleteCalls = 0;
        final readinessRequests = <http.Request>[];

        final backend = createMockBackend((request) async {
          readinessRequests.add(request);
          final path = request.url.path;
          if (path.endsWith('/financials') ||
              path.endsWith('/recalculate-billing')) {
            final paid = (patientRow['payments'] as List).fold<double>(
              0,
              (n, p) => n + (p['amount'] as num).toDouble(),
            );
            patientRow.addAll({
              'advanceBilledAmount': 200.0,
              'totalPaidAmount': paid,
              'currentDueAmount': 200.0 - paid,
              'refundDueAmount': 0.0,
              'totalRefundDueAmount': 0.0,
            });
            return http.Response(
              jsonEncode({
                'patient': patientRow,
                'stays': [stayRow],
              }),
              200,
            );
          }
          if (path.endsWith('/discharge')) {
            patientPatchCalls++;
            stayCompleteCalls++;
            patientRow = {...patientRow, 'status': 'discharged'};
            stayRow = {...stayRow, 'status': 'completed'};
            return http.Response(
              jsonEncode({
                'patient': patientRow,
                'stays': [stayRow],
              }),
              200,
            );
          }

          if (request.method == 'GET' &&
              path == '/api/patients/p_discharge_1') {
            return http.Response(jsonEncode(patientRow), 200);
          }
          if ((request.method == 'PATCH' || request.method == 'PUT') &&
              path == '/api/patients/p_discharge_1') {
            patientPatchCalls++;
            final patch = jsonDecode(request.body) as Map<String, dynamic>;
            patientRow = {...patientRow, ...patch};
            return http.Response(jsonEncode(patientRow), 200);
          }
          if (request.method == 'GET' && path == '/api/stays') {
            return http.Response(
              jsonEncode({stayRow['id'] as String: stayRow}),
              200,
            );
          }
          if ((request.method == 'PUT' || request.method == 'PATCH') &&
              path == '/api/stays/${stayRow['id']}') {
            final patch = jsonDecode(request.body) as Map<String, dynamic>;
            if (patch['status'] == 'completed') {
              stayCompleteCalls++;
            }
            stayRow = {...stayRow, ...patch};
            return http.Response(jsonEncode(stayRow), 200);
          }
          if (request.method == 'GET' && path == '/api/settings/pricing') {
            return http.Response(
              jsonEncode({
                'generalRoomBedPrice': 200,
                'privateRoomBasePrice': 700,
              }),
              200,
            );
          }
          if (request.method == 'GET' && path == '/api/attendance') {
            final kind = request.url.queryParameters['kind'] ?? 'attendance';
            if (kind == 'attendance') {
              return http.Response(jsonEncode(attendanceByDate), 200);
            }
            return http.Response(jsonEncode({}), 200);
          }
          if (request.method == 'POST' && path == '/api/payments') {
            final pay = jsonDecode(request.body) as Map<String, dynamic>;
            final list = List<Map<String, dynamic>>.from(
              patientRow['payments'] as List,
            )..add(pay);
            patientRow['payments'] = list;
            return http.Response(jsonEncode(pay), 201);
          }
          return http.Response('{}', 200);
        });

        final roomService = RoomService(backendApiService: backend);
        final paymentService = PaymentService(null, backend);
        final patientService = PatientService(
          backendApiService: backend,
          roomService: roomService,
          paymentService: paymentService,
        );

        // 1. Check initial discharge readiness (unpaid ₹200 -> ready: false)
        final initialReadiness = await patientService.getDischargeReadiness(
          'p_discharge_1',
          patientOverride: PatientModel.fromMap('p_discharge_1', {
            ...patientRow,
            'exitDate': exitMs + const Duration(days: 1).inMilliseconds,
          }),
        );
        expect(initialReadiness['ready'], isFalse);
        expect(initialReadiness['pending'], 200.0);
        expect(patientPatchCalls, 0);
        expect(readinessRequests, hasLength(1));
        expect(readinessRequests.single.method, 'GET');
        expect(readinessRequests.single.url.path, endsWith('/financials'));
        expect(
          readinessRequests.single.url.queryParameters['checkoutAt'],
          isNotNull,
        );
        expect(patientRow['exitDate'], exitMs);

        // 2. Record ₹200 payment
        await paymentService.recordPayment(
          patientId: 'p_discharge_1',
          patientName: 'Discharge Test Patient',
          payment: PaymentModel(
            id: 'pay_discharge_1',
            amount: 200.0,
            date: DateTime(2026, 10, 18, 10, 0),
            method: 'Cash',
            cycleId: cycleId,
          ),
        );

        // 3. Discharge patient
        await patientService.dischargePatient('p_discharge_1');

        expect(stayCompleteCalls, 1);
        expect(stayRow['status'], 'completed');
        expect(patientRow['status'], 'discharged');
        expect(patientPatchCalls, greaterThan(0));
      },
    );

    test(
      'Instruments client-side ServiceLocator initialization, SQLite PersistentCache, and model decoding latency',
      () async {
        dotenv.loadFromString(
          isOptional: true,
          envString:
              'USE_POSTGRES_BACKEND=true\nBACKEND_BASE_URL=http://127.0.0.1:3000/api',
        );
        final swInit = Stopwatch()..start();
        ServiceLocator().dispose();
        ServiceLocator().initialize(
          projectId: 'ngo-local-dev',
          apiKey: 'fake-api-key',
        );
        swInit.stop();

        // Build a 35-day attendance dataset (10 patients per day)
        final fullAttendanceTree = <String, dynamic>{};
        for (var d = 1; d <= 35; d++) {
          final dateKey = '2026-01-${d.toString().padLeft(2, '0')}';
          final daily = <String, dynamic>{};
          for (var p = 1; p <= 10; p++) {
            daily['p_$p'] = {
              'patientId': 'p_$p',
              'status': 'Present',
              'date': dateKey,
              'source': 'automatic_registration_period',
            };
          }
          fullAttendanceTree[dateKey] = daily;
        }

        // Measure BEFORE SQLite cache write: replacing entire 'attendance/daily' 35-day tree on a 5-day range read
        final swSqliteFullWrite = Stopwatch()..start();
        await cache.replaceSnapshot('attendance/daily', fullAttendanceTree);
        swSqliteFullWrite.stop();

        // Measure AFTER SQLite cache write: per-date snapshot update for a 5-day window
        final swSqliteBoundedWrite = Stopwatch()..start();
        for (var d = 1; d <= 5; d++) {
          final dateKey = '2026-01-${d.toString().padLeft(2, '0')}';
          await cache.replaceSnapshot(
            'attendance/daily/$dateKey',
            fullAttendanceTree[dateKey],
          );
        }
        swSqliteBoundedWrite.stop();

        // Measure SQLite cache read + PatientModel / RoomModel decoding for 25 patients & 10 rooms
        final patientsPayload = <String, dynamic>{};
        for (var i = 1; i <= 25; i++) {
          patientsPayload['p_$i'] = {
            'id': 'p_$i',
            'fullName': 'Patient $i',
            'registrationNumber': '$i',
            'dateOfBirth': DateTime(1980, 1, 1).millisecondsSinceEpoch,
            'age': 46,
            'gender': 'Female',
            'contactNumber': '9876543210',
            'emergencyContact': '9876543211',
            'emergencyContactName': 'Kin $i',
            'medicalCondition': 'Observation',
            'admissionDate': DateTime(2026, 10, 1).millisecondsSinceEpoch,
            'status': 'active',
          };
        }
        final swPatientsCacheWrite = Stopwatch()..start();
        await cache.replaceSnapshot('patients', patientsPayload);
        swPatientsCacheWrite.stop();

        final swPatientsCacheRead = Stopwatch()..start();
        final cachedPatients = await cache.read('patients') as Map;
        swPatientsCacheRead.stop();

        final swPatientsDecode = Stopwatch()..start();
        final decodedPatients = cachedPatients.entries
            .map((e) => PatientModel.fromMap(e.key.toString(), e.value as Map))
            .toList();
        swPatientsDecode.stop();
        expect(decodedPatients, hasLength(25));

        // ignore: avoid_print
        print(
          jsonEncode({
            'benchmark': 'FLUTTER_CLIENT_SQLITE_DECODE_US',
            'serviceLocatorInitUs': swInit.elapsedMicroseconds,
            'sqliteFullAttendanceReplaceUs':
                swSqliteFullWrite.elapsedMicroseconds,
            'sqliteBounded5DayAttendanceWriteUs':
                swSqliteBoundedWrite.elapsedMicroseconds,
            'sqlitePatients25WriteUs': swPatientsCacheWrite.elapsedMicroseconds,
            'sqlitePatients25ReadUs': swPatientsCacheRead.elapsedMicroseconds,
            'decodePatients25ModelsUs': swPatientsDecode.elapsedMicroseconds,
          }),
        );
      },
    );
  });
}
