import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/screens/rooms/widgets/room_card.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/photo_migration_service.dart';
import 'package:ngo/services/photo_rtdb_service.dart';
import 'package:ngo/services/room_service.dart';

Uint8List testImage({
  int width = 80,
  int height = 80,
  int r = 40,
  int g = 160,
  int b = 40,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgba8(r, g, b, 255));
  return Uint8List.fromList(img.encodeJpg(image));
}

class TestMemoryDb extends FirebaseRTDBRestService {
  TestMemoryDb() : super(projectId: 'test');
  final records = <String, dynamic>{};
  final reads = <String, int>{};

  @override
  Stream<dynamic> stream(String path, {Duration? pollInterval}) {
    reads[path] = (reads[path] ?? 0) + 1;
    return Stream.value(records[path]);
  }

  @override
  Future<dynamic> get(String path) async {
    reads[path] = (reads[path] ?? 0) + 1;
    return records[path];
  }

  @override
  Future<void> put(String path, Map<String, dynamic> data) async {
    records[path] = data;
  }

  @override
  Future<void> delete(String path) async {
    records.remove(path);
  }

  @override
  Future<dynamic> getByChildValue(
    String path, {
    required String child,
    required Object value,
  }) async {
    final collection = records[path];
    if (collection is! Map) return null;
    return {
      for (final entry in collection.entries)
        if (entry.value is Map && entry.value[child] == value)
          entry.key.toString(): entry.value,
    };
  }

  @override
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    for (final update in updates.entries) {
      final parts = update.key.split('/');
      if (parts.length < 3) continue;
      final collection = records[parts[0]];
      if (collection is! Map) continue;
      final record = collection[parts[1]];
      if (record is! Map) continue;
      dynamic target = record;
      for (final part in parts.skip(2).take(parts.length - 3)) {
        target = target is List
            ? target[int.parse(part)]
            : (target as Map).putIfAbsent(part, () => <String, dynamic>{});
      }
      if (update.value == null) {
        (target as Map).remove(parts.last);
      } else {
        (target as Map)[parts.last] = update.value;
      }
    }
  }
}

class ControlledSseClient extends http.BaseClient {
  ControlledSseClient({this.statusCode = 200});

  final int statusCode;
  final StreamController<List<int>> events =
      StreamController<List<int>>.broadcast();
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return http.StreamedResponse(
      events.stream,
      statusCode,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void addEvent(String type, String path, dynamic data) {
    events.add(
      utf8.encode(
        'event: $type\ndata: ${json.encode({'path': path, 'data': data})}\n\n',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FIX #9 — Database Rules Index Verification', () {
    test(
      'database.rules.json contains expectedDischargeDate in stays.indexOn',
      () {
        final file = File('database.rules.json');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'database.rules.json must exist',
        );
        final content = file.readAsStringSync();
        final rules = json.decode(content) as Map<String, dynamic>;
        final staysRules = rules['rules']['stays'] as Map<String, dynamic>;
        final indexOn = (staysRules['.indexOn'] as List).cast<String>();

        expect(
          indexOn,
          contains('expectedDischargeDate'),
          reason: 'stays node must index expectedDischargeDate',
        );
        expect(indexOn, contains('roomId'));
        expect(indexOn, contains('patientId'));
        expect(indexOn, contains('status'));
      },
    );

    test('legacy photo fields allow deletion but not insertion or change', () {
      final rules =
          json.decode(File('database.rules.json').readAsStringSync())
              as Map<String, dynamic>;
      final root = rules['rules'] as Map<String, dynamic>;
      final validations = <String>[
        root['patients']['\$patientId']['photoDataUrl']['.validate'],
        root['patients']['\$patientId']['attendants']['\$index']['photoDataUrl']['.validate'],
        root['stays']['\$stayId']['patientSnapshot']['photoDataUrl']['.validate'],
        root['stays']['\$stayId']['patientSnapshot']['attendants']['\$index']['photoDataUrl']['.validate'],
      ];
      for (final validation in validations) {
        expect(validation, contains('!newData.exists()'));
        expect(validation, contains('newData.val() == data.val()'));
        expect(validation, contains('data.exists()'));
      }
    });
  });

  group('SSE and bounded-query regression protection', () {
    test(
      'SSE initialization and child PATCH perform no REST collection GET',
      () async {
        var restRequests = 0;
        final sse = ControlledSseClient();
        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          databaseUrl: 'https://example.test',
          getAuthToken: () async => 'token',
          httpClient: MockClient((_) async {
            restRequests++;
            return http.Response('{}', 200);
          }),
          sseClientFactory: () => sse,
        );
        final values = <dynamic>[];
        final subscription = rtdb
            .stream('patients', pollInterval: const Duration(milliseconds: 10))
            .listen(values.add);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(sse.request?.url.path, '/patients.json');
        sse.addEvent('put', '/', {
          'p1': {'id': 'p1', 'status': 'active', 'fullName': 'Before'},
        });
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          restRequests,
          0,
          reason: 'SSE initial snapshot replaces REST initialization',
        );

        sse.addEvent('patch', '/p1', {'fullName': 'After'});
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(values.last['p1']['fullName'], 'After');
        expect(
          restRequests,
          0,
          reason: 'Child SSE mutation must not invalidate collection',
        );

        await subscription.cancel();
        await sse.events.close();
        rtdb.dispose();
      },
    );

    test(
      'filtered SSE maintains membership without periodic REST polling',
      () async {
        var restRequests = 0;
        final sse = ControlledSseClient();
        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          databaseUrl: 'https://example.test',
          getAuthToken: () async => 'token',
          httpClient: MockClient((_) async {
            restRequests++;
            return http.Response('{}', 200);
          }),
          sseClientFactory: () => sse,
        );
        final values = <dynamic>[];
        final subscription = rtdb
            .queryStream(
              'stays',
              orderBy: 'status',
              equalTo: 'active',
              pollInterval: const Duration(milliseconds: 10),
            )
            .listen(values.add);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          sse.request?.url.queryParameters['orderBy'],
          json.encode('status'),
        );
        expect(
          sse.request?.url.queryParameters['equalTo'],
          json.encode('active'),
        );
        sse.addEvent('put', '/', {
          's1': {'id': 's1', 'status': 'active'},
        });
        await Future<void>.delayed(const Duration(milliseconds: 25));
        sse.addEvent('put', '/s1', null);
        sse.addEvent('put', '/s2', {'id': 's2', 'status': 'active'});
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(values.last, contains('s2'));
        expect(values.last, isNot(contains('s1')));
        expect(
          restRequests,
          0,
          reason: 'Filtered resources must not run timer GET loops',
        );

        await subscription.cancel();
        await sse.events.close();
        rtdb.dispose();
      },
    );

    test(
      'filtered SSE failure performs one controlled REST reconciliation',
      () async {
        var restRequests = 0;
        final sse = ControlledSseClient(statusCode: 503);
        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          databaseUrl: 'https://example.test',
          getAuthToken: () async => 'token',
          httpClient: MockClient((_) async {
            restRequests++;
            return http.Response('{}', 200);
          }),
          sseClientFactory: () => sse,
        );
        final subscription = rtdb
            .queryStream(
              'stays',
              orderBy: 'status',
              equalTo: 'active',
              pollInterval: const Duration(milliseconds: 10),
            )
            .listen((_) {});

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          restRequests,
          1,
          reason: 'SSE fallback is bounded, not periodic polling',
        );

        await subscription.cancel();
        await sse.events.close();
        rtdb.dispose();
      },
    );

    test(
      'expectedDischargeDate query is automatically bounded and indexed',
      () async {
        http.Request? captured;
        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          databaseUrl: 'https://example.test',
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response('{}', 200);
          }),
        );

        await rtdb.query('stays', orderBy: 'expectedDischargeDate');

        final params = captured!.url.queryParameters;
        expect(params['orderBy'], json.encode('expectedDischargeDate'));
        expect(params, contains('startAt'));
        expect(params, contains('endAt'));
        expect(params['limitToFirst'], '200');
        rtdb.dispose();
      },
    );
  });

  group('FIX #3 & #8 — RTDB Local Cache Updates Without Collection Refetch', () {
    test(
      'single PUT /patients/p1 updates collection stream without GET /patients',
      () async {
        var collectionGetCount = 0;
        final serverDb = <String, dynamic>{
          'patients': {
            'p1': {
              'id': 'p1',
              'fullName': 'Alice Original',
              'status': 'active',
              'searchKey': 'alice',
              'dateOfBirth': 0,
              'age': 30,
              'gender': 'female',
              'contactNumber': '123',
              'emergencyContact': '456',
              'emergencyContactName': 'Bob',
              'medicalCondition': 'none',
              'admissionDate': 0,
              'createdAt': 0,
              'updatedAt': 0,
              'createdBy': 'admin',
            },
          },
        };

        final client = MockClient((request) async {
          final path = request.url.path
              .replaceAll('.json', '')
              .replaceFirst('/', '');
          if (request.method == 'GET') {
            if (path == 'patients') {
              collectionGetCount++;
              return http.Response(json.encode(serverDb['patients']), 200);
            }
            return http.Response(json.encode(serverDb[path]), 200);
          }
          if (request.method == 'PUT') {
            final data = json.decode(request.body);
            serverDb[path] = data;
            return http.Response(json.encode(data), 200);
          }
          return http.Response('{}', 200);
        });

        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          httpClient: client,
        );

        final streamValues = <dynamic>[];
        final sub = rtdb
            .stream('patients', pollInterval: const Duration(hours: 1))
            .listen((val) {
              streamValues.add(val);
            });

        // Allow the 150ms initial refresh timer to complete
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          collectionGetCount,
          equals(1),
          reason: 'Initial load should fetch collection',
        );
        expect(streamValues.isNotEmpty, isTrue);
        expect(streamValues.last['p1']['fullName'], equals('Alice Original'));

        // Now perform a PUT on a single patient
        final updatedPatient = {
          'id': 'p1',
          'fullName': 'Alice Updated',
          'status': 'active',
          'searchKey': 'alice',
        };
        await rtdb.put('patients/p1', updatedPatient);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Verify NO collection GET was triggered
        expect(
          collectionGetCount,
          equals(1),
          reason: 'Single record PUT must not trigger full collection GET',
        );
        expect(
          streamValues.last['p1']['fullName'],
          equals('Alice Updated'),
          reason: 'Stream should receive merged local update immediately',
        );

        await sub.cancel();
      },
    );

    test(
      'single PATCH /patients/p1 merges fields without GET /patients',
      () async {
        var collectionGetCount = 0;
        final serverDb = <String, dynamic>{
          'patients': {
            'p1': {
              'id': 'p1',
              'fullName': 'Alice Original',
              'status': 'active',
              'currentDueAmount': 100,
            },
          },
        };

        final client = MockClient((request) async {
          final path = request.url.path
              .replaceAll('.json', '')
              .replaceFirst('/', '');
          if (request.method == 'GET') {
            if (path == 'patients') {
              collectionGetCount++;
              return http.Response(json.encode(serverDb['patients']), 200);
            }
            return http.Response(json.encode(serverDb[path]), 200);
          }
          if (request.method == 'PATCH') {
            return http.Response('{}', 200);
          }
          return http.Response('{}', 200);
        });

        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          httpClient: client,
        );

        final streamValues = <dynamic>[];
        final sub = rtdb
            .stream('patients', pollInterval: const Duration(hours: 1))
            .listen((val) {
              streamValues.add(val);
            });

        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(collectionGetCount, equals(1));

        // PATCH a field on p1
        await rtdb.patch('patients/p1', {'currentDueAmount': 250});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          collectionGetCount,
          equals(1),
          reason: 'PATCH /patients/p1 must not trigger full collection GET',
        );
        expect(
          streamValues.last['p1']['fullName'],
          equals('Alice Original'),
          reason: 'Unchanged fields must be preserved',
        );
        expect(
          streamValues.last['p1']['currentDueAmount'],
          equals(250),
          reason: 'Changed field must be updated in collection cache',
        );

        await sub.cancel();
      },
    );

    test(
      'multi-path root PATCH (e.g. attendance billing updates) merges field without GET /patients',
      () async {
        var collectionGetCount = 0;
        final serverDb = <String, dynamic>{
          'patients': {
            'p1': {
              'id': 'p1',
              'fullName': 'Bob Original',
              'totalPaidAmount': 500,
            },
          },
        };

        final client = MockClient((request) async {
          final path = request.url.path
              .replaceAll('.json', '')
              .replaceFirst('/', '');
          if (request.method == 'GET') {
            if (path == 'patients') {
              collectionGetCount++;
              return http.Response(json.encode(serverDb['patients']), 200);
            }
            return http.Response(json.encode(serverDb[path]), 200);
          }
          if (request.method == 'PATCH') {
            return http.Response('{}', 200);
          }
          return http.Response('{}', 200);
        });

        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          httpClient: client,
        );

        final streamValues = <dynamic>[];
        final sub = rtdb
            .stream('patients', pollInterval: const Duration(hours: 1))
            .listen((val) {
              streamValues.add(val);
            });

        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(collectionGetCount, equals(1));

        // Multi-path root patch: simulates paymentService.recalculatePatientAttendanceAndBilling
        await rtdb.patch('', {
          'patients/p1/totalPaidAmount': 700,
          'patients/p1/currentDueAmount': 0,
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          collectionGetCount,
          equals(1),
          reason: 'Root multi-path patch must not trigger collection GET',
        );
        expect(streamValues.last['p1']['totalPaidAmount'], equals(700));
        expect(streamValues.last['p1']['currentDueAmount'], equals(0));

        await sub.cancel();
      },
    );

    test(
      'DELETE /patients/p1 removes record from collection stream without GET /patients',
      () async {
        var collectionGetCount = 0;
        final serverDb = <String, dynamic>{
          'patients': {
            'p1': {'id': 'p1', 'fullName': 'To Delete'},
            'p2': {'id': 'p2', 'fullName': 'Keep Me'},
          },
        };

        final client = MockClient((request) async {
          final path = request.url.path
              .replaceAll('.json', '')
              .replaceFirst('/', '');
          if (request.method == 'GET') {
            if (path == 'patients') {
              collectionGetCount++;
              return http.Response(json.encode(serverDb['patients']), 200);
            }
            return http.Response(json.encode(serverDb[path]), 200);
          }
          if (request.method == 'DELETE') {
            return http.Response('{}', 200);
          }
          return http.Response('{}', 200);
        });

        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          httpClient: client,
        );

        final streamValues = <dynamic>[];
        final sub = rtdb
            .stream('patients', pollInterval: const Duration(hours: 1))
            .listen((val) {
              streamValues.add(val);
            });

        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(collectionGetCount, equals(1));

        await rtdb.delete('patients/p1');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          collectionGetCount,
          equals(1),
          reason: 'DELETE must not trigger full collection GET',
        );
        expect(
          streamValues.last.containsKey('p1'),
          isFalse,
          reason: 'p1 must be removed from cached collection',
        );
        expect(
          streamValues.last.containsKey('p2'),
          isTrue,
          reason: 'p2 must remain',
        );

        await sub.cancel();
      },
    );
  });

  group('FIX #4 — Room Service Targeted /stays Reads', () {
    test(
      'updateRoomStatus uses getByChildValue(stays, roomId) and never calls get(stays)',
      () async {
        final getPaths = <String>[];
        final filteredQueries = <String>[];

        final client = MockClient((request) async {
          final path = request.url.path
              .replaceAll('.json', '')
              .replaceFirst('/', '');
          if (request.url.queryParameters.containsKey('orderBy')) {
            filteredQueries.add('$path?${request.url.query}');
            return http.Response('{}', 200);
          }
          getPaths.add(path);
          if (path == 'rooms/room1') {
            return http.Response(
              json.encode({
                'id': 'room1',
                'roomNumber': '101',
                'floor': 1,
                'roomType': 'general',
                'status': 'available',
                'createdAt': 0,
                'updatedAt': 0,
                'beds': {},
              }),
              200,
            );
          }
          if (path == 'stays') {
            fail('updateRoomStatus MUST NOT perform full get(stays)');
          }
          return http.Response('{}', 200);
        });

        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          httpClient: client,
        );
        final roomService = RoomService(rtdbService: rtdb);

        await roomService.updateRoomStatus('room1');

        expect(
          getPaths,
          isNot(contains('stays')),
          reason: 'updateRoomStatus must never download full stays collection',
        );
        expect(
          filteredQueries.any(
            (q) =>
                q.contains('stays') &&
                q.contains('roomId') &&
                q.contains('room1'),
          ),
          isTrue,
          reason: 'updateRoomStatus must use targeted roomId query',
        );
      },
    );

    test(
      'deleteRoom uses getByChildValue(stays, roomId) and never calls get(stays)',
      () async {
        final getPaths = <String>[];
        final filteredQueries = <String>[];

        final client = MockClient((request) async {
          final path = request.url.path
              .replaceAll('.json', '')
              .replaceFirst('/', '');
          if (request.url.queryParameters.containsKey('orderBy')) {
            filteredQueries.add('$path?${request.url.query}');
            return http.Response('{}', 200);
          }
          getPaths.add(path);
          if (path == 'rooms/room1') {
            return http.Response(
              json.encode({
                'id': 'room1',
                'roomNumber': '101',
                'floor': 1,
                'roomType': 'general',
                'status': 'available',
                'createdAt': 0,
                'updatedAt': 0,
                'beds': {},
              }),
              200,
            );
          }
          if (path == 'stays') {
            fail('deleteRoom MUST NOT perform full get(stays)');
          }
          return http.Response('{}', 200);
        });

        final rtdb = FirebaseRTDBRestService(
          projectId: 'test',
          httpClient: client,
        );
        final roomService = RoomService(rtdbService: rtdb);

        await roomService.deleteRoom('room1');

        expect(
          getPaths,
          isNot(contains('stays')),
          reason: 'deleteRoom must never download full stays collection',
        );
        expect(
          filteredQueries.any(
            (q) =>
                q.contains('stays') &&
                q.contains('roomId') &&
                q.contains('room1'),
          ),
          isTrue,
          reason: 'deleteRoom must use targeted roomId query',
        );
      },
    );
  });

  group('FIX #5 — RoomCard Patient Stream Removal', () {
    testWidgets(
      'RoomCard renders directly from room data without subscribing to patient stream',
      (tester) async {
        final room = RoomModel(
          id: 'r1',
          roomNumber: '101',
          roomIdentifier: '101',
          floor: 1,
          roomType: 'general',
          status: 'available',
          currentAttendants: 0,
          maxAttendants: 2,
          beds: [
            BedModel.create(roomId: 'r1', bedLabel: '1'),
            BedModel.create(roomId: 'r1', bedLabel: '2'),
          ],
          totalBeds: 2,
          occupiedBeds: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          lastUpdated: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RoomCard(room: room)),
          ),
        );

        expect(find.text('Room 101'), findsOneWidget);
        expect(find.text('Available'), findsOneWidget);
        expect(find.text('Occupied: 0/2'), findsOneWidget);
      },
    );
  });

  group('FIX #1 — Photo Migration Historical Stays Semantics', () {
    test(
      'distinct historical stay photo is preserved in dedicated record instead of overwritten',
      () async {
        final legacyBase64Patient =
            'data:image/jpeg;base64,${base64Encode(testImage(r: 40, g: 160, b: 40))}';
        final legacyBase64Historical =
            'data:image/jpeg;base64,${base64Encode(testImage(r: 200, g: 50, b: 50))}';

        final db = TestMemoryDb();
        db.records['patients'] = {
          'p1': {
            'fullName': 'Patient With Stay Photo',
            'photoDataUrl': legacyBase64Patient,
          },
        };
        db.records['stays'] = {
          'stay_100': {
            'id': 'stay_100',
            'patientId': 'p1',
            'status': 'completed',
            'patientSnapshot': {
              'registrationNumber': 'REG-001',
              'photoDataUrl':
                  legacyBase64Historical, // Different historical photo!
            },
          },
        };

        final photoService = PhotoRtdbService(rtdb: db);
        final migrationService = PhotoMigrationService(
          rtdb: db,
          photos: photoService,
        );

        final report = await migrationService.migrate();
        expect(
          report.failed,
          0,
          reason: 'Migration should have 0 failures: ${report.errors}',
        );
        expect(report.allDone, isTrue);

        // Verify that patient photo was uploaded to patientPhotos/p1/patient
        final patientPhotoPath = PhotoRtdbService.patientPath('p1');
        expect(db.records[patientPhotoPath], isNotNull);

        // CRITICAL CHECK: Verify that the historical stay photo was NOT overwritten with patient photo,
        // but migrated to dedicated record patientPhotos/p1/attendants/stay_stay_100_patient!
        final stayPhotoPath = PhotoRtdbService.attendantPath(
          'p1',
          'stay_stay_100_patient',
        );
        expect(
          db.records[stayPhotoPath],
          isNotNull,
          reason: 'Historical stay photo must be migrated to dedicated record',
        );

        // Verify that stay's photoRef points to the dedicated historical stay photo
        final staySnapshot =
            (db.records['stays']['stay_100']['patientSnapshot'] as Map);
        expect(staySnapshot['photoRef'], equals(stayPhotoPath));
        expect(
          staySnapshot['photoDataUrl'],
          isNull,
          reason:
              'Legacy photoDataUrl must be removed only after verified upload',
        );
      },
    );
  });
}
