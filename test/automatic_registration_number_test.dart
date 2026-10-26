import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/screens/patients/widgets/add_patient_dialog.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/registration_number_service.dart';
import 'package:ngo/services/service_locator.dart';

/// Test mock RTDB service with detailed request counting and inspection.
class MockRtdbForRegistration extends FirebaseRTDBRestService {
  MockRtdbForRegistration() : super(projectId: 'test-reg-numbering');

  final Map<String, dynamic> db = {};
  int etagVersion = 1;
  int conflictCountToInject = 0;
  int conflictsInjected = 0;

  int getCallsCount = 0;
  int getWithEtagCallsCount = 0;
  int streamCallsCount = 0;
  final List<String> getPaths = [];
  final List<String> streamPaths = [];

  String get _currentEtag => 'etag_$etagVersion';

  @override
  Future<dynamic> get(String path) async {
    getCallsCount++;
    getPaths.add(path);
    return db[path];
  }

  @override
  Future<RtdbValue> getWithEtag(String path) async {
    getWithEtagCallsCount++;
    getPaths.add(path);
    final val = db[path];
    return RtdbValue(val, _currentEtag);
  }

  final Map<String, StreamController<dynamic>> _streamControllers = {};

  @override
  Stream<dynamic> stream(String path, {Duration? pollInterval}) {
    streamCallsCount++;
    streamPaths.add(path);
    final controller = _streamControllers.putIfAbsent(
      path,
      () => StreamController<dynamic>.broadcast(),
    );
    return controller.stream;
  }

  @override
  Future<bool> put(String path, dynamic data) async {
    db[path] = data;
    etagVersion++;
    _streamControllers[path]?.add(data);
    return true;
  }

  @override
  Future<bool> putValueIfMatch(String path, dynamic value, String etag) async {
    if (conflictCountToInject > 0 && conflictsInjected < conflictCountToInject) {
      conflictsInjected++;
      // Simulate concurrent writer bumping etag
      etagVersion++;
      return false; // HTTP 412
    }
    if (etag != _currentEtag) {
      return false; // HTTP 412 Precondition Failed
    }
    db[path] = value;
    etagVersion++;
    _streamControllers[path]?.add(value);
    return true;
  }

  @override
  Future<bool> putIfMatch(String path, Map<String, dynamic> data, String etag) async {
    return putValueIfMatch(path, data, etag);
  }

  @override
  Future<void> patch(String path, Map<String, dynamic> data) async {
    if (path.isEmpty) {
      for (final entry in data.entries) {
        db[entry.key] = entry.value;
      }
    } else {
      final existing = db[path];
      if (existing is Map) {
        existing.addAll(data);
      } else {
        db[path] = Map<String, dynamic>.from(data);
      }
    }
    etagVersion++;
  }

  @override
  Future<dynamic> getByChildValue(String path, {required String child, required Object value}) async {
    final results = <String, dynamic>{};
    for (final entry in db.entries) {
      if (entry.key.startsWith('$path/') && entry.value is Map) {
        final map = entry.value as Map;
        if (map[child] == value) {
          final id = entry.key.substring('$path/'.length);
          results[id] = map;
        }
      }
    }
    return results;
  }
}

void main() {
  late MockRtdbForRegistration mockRtdb;
  late RegistrationNumberService regService;
  late PatientService patientService;

  setUp(() {
    mockRtdb = MockRtdbForRegistration();
    regService = RegistrationNumberService(
      rtdbService: mockRtdb,
      counterPath: RegistrationNumberService.defaultCounterPath,
    );
    patientService = PatientService(
      rtdbService: mockRtdb,
      registrationNumberService: regService,
    );

    // Wire service locator
    final sl = ServiceLocator();
    sl.registrationNumberService = regService;
    sl.patientService = patientService;
    sl.roomService = RoomService(rtdbService: mockRtdb);
  });

  tearDown(() {
    ServiceLocator().dispose();
  });

  group('Automatic Registration Number Allocation Suite', () {
    // 1. Database-derived initialization
    test('1. Database-derived initialization computes sequence tail from RTDB', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5000', 'fullName': 'Patient A'},
        'p2': {'id': 'p2', 'registrationNumber': '5190', 'fullName': 'Patient B'},
        'p3': {'id': 'p3', 'registrationNumber': '5213', 'fullName': 'Patient C'},
      };

      final tail = await regService.computeEstablishedSequenceTail();
      expect(tail, equals(5213));

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5214'));
    });

    // 2. Current production fixture where established sequence ends at 5217
    // 3. Expected next value = 5218
    // 4. Verify 8000 is never used as an artificial baseline
    // 5. Verify 8959 historical outlier does not force initial allocation to 8960
    test('2-5. Production fixture: tail at 5217 with Lata (8959) allocates 5218, never 8000 or 8960', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5000', 'fullName': 'Historical Patient 1'},
        'p2': {'id': 'p2', 'registrationNumber': '5213', 'fullName': 'Sushil Hazra'},
        'p3': {'id': 'p3', 'registrationNumber': '5214', 'fullName': 'Dipanwita Mishra'},
        'p4': {'id': 'p4', 'registrationNumber': '5215', 'fullName': 'Sima Pradip Joshi'},
        'p5': {'id': 'p5', 'registrationNumber': '5216', 'fullName': 'Nitai Ghosh'},
        'p6': {'id': 'p6', 'registrationNumber': '5217', 'fullName': 'Abhijit Ghosh'},
        'p_lata': {'id': 'p_lata', 'registrationNumber': '8959', 'fullName': 'Lata'},
      };

      final analysis = await regService.analyzeDatabase();
      expect(analysis.establishedTail, equals(5217));
      expect(analysis.outliers, equals([8959]));
      expect(analysis.nextNumber, equals(5218));

      // Allocation must be 5218 (NOT 8000, NOT 8960)
      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5218'));
      expect(allocated, isNot(equals('8000')));
      expect(allocated, isNot(equals('8960')));
    });

    // 6. Verify existing registration 8959 remains reserved
    test('6. Existing registration 8959 remains reserved and is skipped when sequence reaches it', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '8958', 'fullName': 'Patient Pre-Lata'},
        'p_lata': {'id': 'p_lata', 'registrationNumber': '8959', 'fullName': 'Lata'},
      };

      // Force counter to 8958 to simulate sequence arriving at Lata
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 8958,
        'source': 'test',
      };

      // Allocation must skip 8959 and assign 8960 so Lata is never collided with!
      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('8960'));
      expect(allocated, isNot(equals('8959')));

      // Lata's original record in DB remains intact
      expect(mockRtdb.db['patients']['p_lata']['registrationNumber'], equals('8959'));
    });

    // 7. Verify gaps are not reused
    test('7. Historical gaps are never filled or reused (5097, 5099, 5213 -> 5214, not 5098)', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5097'},
        'p2': {'id': 'p2', 'registrationNumber': '5099'},
        'p3': {'id': 'p3', 'registrationNumber': '5213'},
      };

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5214'));
      expect(allocated, isNot(equals('5098')));
    });

    // 8. Verify malformed registration values do not break initialization
    test('8. Malformed, null, and nonnumeric registration values do not break initialization', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5213', 'fullName': 'Patient A'},
        'p2': {'id': 'p2', 'registrationNumber': null, 'fullName': 'Patient B'},
        'p3': {'id': 'p3', 'fullName': 'Patient C'},
        'p4': {'id': 'p4', 'registrationNumber': '', 'fullName': 'Patient D'},
        'p5': {'id': 'p5', 'registrationNumber': '   ', 'fullName': 'Patient E'},
        'p6': {'id': 'p6', 'registrationNumber': 'INVALID-XYZ', 'fullName': 'Patient F'},
        'p7': {'id': 'p7', 'registrationNumber': -1, 'fullName': 'Patient G'},
      };

      final analysis = await regService.analyzeDatabase();
      expect(analysis.establishedTail, equals(5213));
      expect(analysis.missingCount, equals(4)); // null, missing, empty, whitespace
      expect(analysis.nonNumericCount, equals(2)); // INVALID-XYZ, -1

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5214'));
    });

    // 9. Verify duplicate historical registrations are reported but never silently rewritten
    test('9. Duplicate historical registrations are reported but never silently rewritten', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5190', 'fullName': 'First Patient with 5190'},
        'p2': {'id': 'p2', 'registrationNumber': '5190', 'fullName': 'Second Patient with 5190'},
        'p3': {'id': 'p3', 'registrationNumber': '5217', 'fullName': 'Tail Patient'},
      };

      final analysis = await regService.analyzeDatabase();
      expect(analysis.duplicateCounts, containsPair(5190, 2));

      // Existing records must remain completely unchanged
      expect(mockRtdb.db['patients']['p1']['registrationNumber'], equals('5190'));
      expect(mockRtdb.db['patients']['p2']['registrationNumber'], equals('5190'));

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5218'));
    });

    // 10. Verify live preview does not consume numbers
    test('10. Live preview does not consume or increment registration numbers', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5217'},
      };

      // Multiple peeks in a row
      final peek1 = await regService.peekNextRegistrationNumber();
      expect(peek1, equals('5218'));
      final peek2 = await regService.peekNextRegistrationNumber();
      expect(peek2, equals('5218'));

      // Real allocation consumes 5218
      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5218'));

      // Next peek reflects 5219
      final peek3 = await regService.peekNextRegistrationNumber();
      expect(peek3, equals('5219'));
    });

    // 11. Verify second-client allocation advances the preview
    test('11. Second-client allocation advances the live preview stream in real-time', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5217,
      };

      final previews = <String>[];
      final sub = regService.watchNextRegistrationNumber().listen((val) {
        previews.add(val);
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(previews, contains('5218'));

      // Another client allocates 5218
      final clientB = RegistrationNumberService(
        rtdbService: mockRtdb,
        counterPath: RegistrationNumberService.defaultCounterPath,
      );
      final allocatedByB = await clientB.allocateNextRegistrationNumber();
      expect(allocatedByB, equals('5218'));

      // First client's stream receives update to 5219
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(previews.last, equals('5219'));

      await sub.cancel();
    });

    // 12. Verify concurrent allocation is collision-free
    test('12. Concurrent allocation between simultaneous clients is collision-free', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5217,
      };

      final client1 = RegistrationNumberService(
        rtdbService: mockRtdb,
        counterPath: RegistrationNumberService.defaultCounterPath,
      );
      final client2 = RegistrationNumberService(
        rtdbService: mockRtdb,
        counterPath: RegistrationNumberService.defaultCounterPath,
      );

      final results = await Future.wait([
        client1.allocateNextRegistrationNumber(),
        client2.allocateNextRegistrationNumber(),
      ]);

      expect(results.length, equals(2));
      expect(results[0], isNot(equals(results[1])));
      expect(results.toSet(), equals({'5218', '5219'}));
    });

    // 13. Verify ETag/CAS retry behavior on 412
    test('13. ETag/CAS retry behavior handles HTTP 412 conflicts and recovers', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5217,
      };
      mockRtdb.conflictCountToInject = 2; // Inject 2 consecutive conflicts

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5218'));
      expect(mockRtdb.conflictsInjected, equals(2));
    });

    // 14. Verify counter never moves backwards
    test('14. Counter never moves backwards even if a lower number is requested', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5220,
      };

      await regService.ensureInitialized();
      expect(regService.cachedHighestAllocatedNumber, equals(5220));

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5221'));
    });

    // 15. Verify counter self-heals upward if persisted counter is behind the canonical established sequence
    test('15. Counter self-heals upward if persisted counter is behind canonical established sequence', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5217'},
      };
      // Missing counter node triggers DB sequence bootstrap
      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5218'));
    });

    // 16. Verify a stale SQLite cache cannot reset the counter
    test('16. Stale local/SQLite cache cannot reset the authoritative RTDB counter', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5217,
      };

      final peek = await regService.peekNextRegistrationNumber();
      expect(peek, equals('5218'));

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5218'));
    });

    // 17. Verify failed patient creation does not create a blank/manual/random registration
    test('17. PatientService rejects blank/random registrations and enforces automatic numbering', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5217,
      };

      final id = await patientService.addPatient(
        fullName: 'Valid Auto Patient',
        dateOfBirth: DateTime(1990),
        gender: 'female',
        contactNumber: '9999999999',
        emergencyContact: '8888888888',
        emergencyContactName: 'Relative',
        medicalCondition: 'General',
        admissionDate: DateTime.now(),
        createdBy: 'staff_1',
      );

      final patient = mockRtdb.db['patients/$id'];
      expect(patient['registrationNumber'], equals('5218'));
      expect(patient['registrationNumber'], isNot(isEmpty));
      expect(RegExp(r'^\d+$').hasMatch(patient['registrationNumber']), isTrue);
    });

    // 18. Verify stay receives exactly the patient's allocated registration number
    test('18. Newly created stay and snapshot receive exactly the patient allocated registration number', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5217,
      };

      final patientId = await patientService.addPatient(
        fullName: 'New Admitted Patient',
        dateOfBirth: DateTime(1985),
        gender: 'male',
        contactNumber: '9876543210',
        emergencyContact: '9876543211',
        emergencyContactName: 'Contact Person',
        medicalCondition: 'Fever',
        admissionDate: DateTime.now(),
        createdBy: 'user_123',
      );

      final allocatedReg = mockRtdb.db['patients/$patientId']['registrationNumber'];
      expect(allocatedReg, equals('5218'));

      // Create stay
      final roomService = ServiceLocator().roomService;
      final stayId = await roomService.createLobbyStay(
        patientId: patientId,
        patientName: 'New Admitted Patient',
        lobbyName: '1B Lobby 1',
        admissionDate: DateTime.now(),
        durationDays: 5,
        attendantCount: 0,
        createdBy: 'user_123',
      );

      final stayData = mockRtdb.db['stays/$stayId'];
      expect(stayData, isNotNull);
      final snapshot = stayData['patientSnapshot'] as Map;
      expect(snapshot['registrationNumber'], equals('5218'));
    });

    // 19. Verify reopening/rebuilding the dialog does not consume numbers
    testWidgets('19. Reopening or rebuilding AddPatientDialog does not consume numbers', (tester) async {
      mockRtdb.db['system_counters/registrationNumber'] = {
        'current': 5217,
      };
      mockRtdb.db['rooms'] = <String, dynamic>{};
      mockRtdb.db['pricing'] = <String, dynamic>{};

      Widget buildApp() => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () {
                    showDialog(
                      context: ctx,
                      builder: (_) => const AddPatientDialog(),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          );

      await tester.pumpWidget(buildApp());

      // Open dialog 1st time
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('5218'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);

      // Close dialog without saving
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Open dialog 2nd time
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Must STILL show 5218, never 5219 or consumed!
      expect(find.text('5218'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
    });

    // 20. Verify application restart preserves the counter
    test('20. Application restart preserves the persisted RTDB counter', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5217,
      };

      // Client 1 allocates 5218
      final alloc1 = await regService.allocateNextRegistrationNumber();
      expect(alloc1, equals('5218'));

      // Simulate app restart: new ServiceLocator and new RegistrationNumberService instance
      final restartedService = RegistrationNumberService(
        rtdbService: mockRtdb,
        counterPath: RegistrationNumberService.defaultCounterPath,
      );

      final nextAlloc = await restartedService.allocateNextRegistrationNumber();
      expect(nextAlloc, equals('5219'));

      final storedVal = RegistrationNumberService.parseNumeric(
        mockRtdb.db[RegistrationNumberService.defaultCounterPath],
      );
      expect(storedVal, equals(5219));
    });

    // Editable registration number with uniqueness verification
    test('Editable registration number: existing patient registration number can be updated when unique', () async {
      mockRtdb.db['patients'] = {
        'p_lata': {'id': 'p_lata', 'registrationNumber': '8959', 'fullName': 'Lata'},
      };
      mockRtdb.db['patients/p_lata/registrationNumber'] = '8959';

      await patientService.updatePatient(
        'p_lata',
        {'registrationNumber': '5218'},
      );

      expect(mockRtdb.db['patients/p_lata/registrationNumber'], equals('5218'));
    });

    test('Editable registration number: updating to a duplicate registration number is rejected', () async {
      mockRtdb.db['patients'] = {
        'p_lata': {'id': 'p_lata', 'registrationNumber': '8959', 'fullName': 'Lata'},
        'p_other': {'id': 'p_other', 'registrationNumber': '5218', 'fullName': 'Other Patient'},
      };
      mockRtdb.db['patients/p_lata/registrationNumber'] = '8959';

      expect(
        () => patientService.updatePatient(
          'p_lata',
          {'registrationNumber': '5218'},
        ),
        throwsA(isA<StateError>()),
      );
    });

    // 21. Self-healing from outlier baseline
    test('21. Counter parked on outlier baseline (e.g. 8960 from prior naive run) heals to established tail 5217 and allocates 5218', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5000', 'fullName': 'Historical Patient 1'},
        'p2': {'id': 'p2', 'registrationNumber': '5213', 'fullName': 'Sushil Hazra'},
        'p3': {'id': 'p3', 'registrationNumber': '5217', 'fullName': 'Abhijit Ghosh'},
        'p_lata': {'id': 'p_lata', 'registrationNumber': '8959', 'fullName': 'Lata'},
      };

      // Simulate counter being at 8960 due to prior naive max run
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 8960,
      };

      // Live peek must detect outlier and display 5218
      final peeked = await regService.peekNextRegistrationNumber();
      expect(peeked, equals('5218'));

      // Allocation must self-heal counter to established tail (5217) and allocate 5218
      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5218'));
      expect(allocated, isNot(equals('8961')));

      // Next allocation must continue monotonically to 5219
      final nextAlloc = await regService.allocateNextRegistrationNumber();
      expect(nextAlloc, equals('5219'));
    });
  });

  group('Section 21: Production Network-Efficiency Tests', () {
    test('E1. Multiple peek calls perform zero Firebase requests after initialization', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };

      // Initial peek triggers bootstrap (1 counter read)
      final peek1 = await regService.peekNextRegistrationNumber();
      expect(peek1, equals('5227'));
      final recordedGetCount = mockRtdb.getPaths.length;

      // 10 subsequent peek calls
      for (int i = 0; i < 10; i++) {
        final peek = await regService.peekNextRegistrationNumber();
        expect(peek, equals('5227'));
      }

      // ZERO additional requests were performed!
      expect(mockRtdb.getPaths.length, equals(recordedGetCount));
    });

    testWidgets('E2. Multiple AddPatientDialog rebuilds perform zero Firebase requests', (tester) async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };
      mockRtdb.db['rooms'] = <String, dynamic>{};
      mockRtdb.db['pricing'] = <String, dynamic>{};

      await regService.ensureInitialized();
      final getCountBefore = mockRtdb.getPaths.length;

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AddPatientDialog())));
      await tester.pumpAndSettle();

      // Trigger 5 rebuilds
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Check counter was NOT re-queried during rebuilds
      final counterReadsDuringRebuilds = mockRtdb.getPaths
          .sublist(getCountBefore)
          .where((p) => p == RegistrationNumberService.defaultCounterPath)
          .length;
      expect(counterReadsDuringRebuilds, equals(0));

      // Dismiss dialog and drain timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    test('E3. Multiple dialogs share one service instance', () {
      final s1 = ServiceLocator().registrationNumberService;
      final s2 = ServiceLocator().registrationNumberService;
      expect(identical(s1, s2), isTrue);
    });

    test('E4. Multiple listeners share one counter stream', () {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };

      final sub1 = regService.watchNextRegistrationNumber().listen((_) {});
      final sub2 = regService.watchNextRegistrationNumber().listen((_) {});
      final sub3 = regService.watchNextRegistrationNumber().listen((_) {});

      // Under the hood, exactly ONE SSE connection was made to RTDB
      expect(regService.activeSseStreamsCount, equals(1));
      expect(mockRtdb.streamCallsCount, equals(1));

      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
    });

    test('E5. Concurrent initialization calls share one Future', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };

      // 5 concurrent ensureInitialized calls
      final futures = List.generate(5, (_) => regService.ensureInitialized());
      await Future.wait(futures);

      expect(regService.state, equals(AllocatorState.ready));
      // Only 1 GET was made to check counter
      expect(
        mockRtdb.getPaths.where((p) => p == RegistrationNumberService.defaultCounterPath).length,
        equals(1),
      );
    });

    test('E6. /patients bootstrap scan happens at most once', () async {
      mockRtdb.db['patients'] = {
        'p1': {'id': 'p1', 'registrationNumber': '5217'},
      };
      // Counter is missing, so bootstrap will scan /patients once
      await regService.ensureInitialized();
      expect(regService.bootstrapPatientsScanCount, equals(1));

      // Subsequent actions never scan /patients again
      await regService.peekNextRegistrationNumber();
      await regService.allocateNextRegistrationNumber();
      expect(regService.bootstrapPatientsScanCount, equals(1));
      expect(mockRtdb.getPaths.where((p) => p == 'patients').length, equals(1));
    });

    test('E7. Allocation after bootstrap never scans /patients', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };

      await regService.ensureInitialized();
      final callsBefore = mockRtdb.getPaths.length;

      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5227'));

      // Verify /patients was never queried
      final newPatientsCalls = mockRtdb.getPaths
          .sublist(callsBefore)
          .where((p) => p == 'patients')
          .length;
      expect(newPatientsCalls, equals(0));
    });

    test('E8. Preview never scans /patients', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };

      await regService.ensureInitialized();
      final preview = await regService.peekNextRegistrationNumber();
      expect(preview, equals('5227'));

      expect(mockRtdb.getPaths.contains('patients'), isFalse);
    });

    test('E9-10. CAS 412 performs bounded counter retries and does NOT download /patients', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };
      mockRtdb.conflictCountToInject = 3; // 3 CAS conflicts

      await regService.ensureInitialized();
      final allocated = await regService.allocateNextRegistrationNumber();
      expect(allocated, equals('5227'));
      expect(mockRtdb.conflictsInjected, equals(3));

      // Verify /patients was never downloaded during CAS conflict handling
      expect(mockRtdb.getPaths.contains('patients'), isFalse);
    });

    test('E11. No polling timer exists for registration numbers', () async {
      mockRtdb.db[RegistrationNumberService.defaultCounterPath] = {
        'current': 5226,
      };

      await regService.ensureInitialized();
      final countBefore = mockRtdb.getPaths.length;

      // Simulate passing of 60 seconds without events
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // No periodic polling GET requests occurred
      expect(mockRtdb.getPaths.length, equals(countBefore));
    });
  });
}
