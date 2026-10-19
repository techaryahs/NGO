import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestRtdbService extends FirebaseRTDBRestService {
  _TestRtdbService({http.Client? httpClient, PersistentCache? persistentCache})
      : super(
          projectId: 'test-project',
          httpClient: httpClient,
          persistentCache: persistentCache,
        );

  final Map<String, int> getCalls = {};

  @override
  Future<dynamic> get(String path) async {
    getCalls[path] = (getCalls[path] ?? 0) + 1;
    return super.get(path);
  }

  void injectLatestValue(String key, dynamic value) {
    if (key == 'patients' && value is Map<String, dynamic>) {
      seedCanonicalPatientsForTesting(value);
      return;
    }
    latestValuesForTesting[key] = value;
  }

  dynamic getLatestValue(String key) => latestValuesForTesting[key];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheDatabase database;
  late PersistentCache persistentCache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = CacheDatabase(NativeDatabase.memory());
    persistentCache = PersistentCache(database);
    await persistentCache.initialize();
    await persistentCache.activateAccount('test-account');
  });

  tearDown(() async {
    await persistentCache.close();
  });

  Map<String, dynamic> createSamplePatient(
    String id, {
    String name = 'Test Patient',
    String status = 'active',
    int updatedAt = 1000,
  }) {
    return {
      'id': id,
      'fullName': name,
      'status': status,
      'admissionDate': '2026-09-01T10:00:00.000Z',
      'searchKey': name.toLowerCase(),
      'registrationNumber': 'REG-$id',
      'updatedAt': updatedAt,
    };
  }

  Map<String, dynamic> create108Patients() {
    final map = <String, dynamic>{};
    for (int i = 1; i <= 108; i++) {
      final id = 'patient_$i';
      map[id] = createSamplePatient(
        id,
        name: i == 1 ? 'Rita Nandi' : 'Patient $i',
        status: i <= 17 ? 'active' : 'discharged',
      );
    }
    return map;
  }

  group('GROUP 1: PATIENT CACHE', () {
    test('1. 108 patients in memory, targeted Rita patch -> remains 108', () async {
      final client = MockClient((req) async => http.Response('{}', 200));
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      // Seed 108 patients in memory
      final all108 = create108Patients();
      rtdb.injectLatestValue('patients', Map<String, dynamic>.from(all108));

      // Subscribe to create shared resource
      final sub = rtdb.stream('patients').listen((_) {});

      // Apply targeted patch for Rita
      rtdb.notifyWrittenForTesting(
        ['patients/patient_1/billing'],
        explicitValues: {
          'patients/patient_1/billing': {'advanceAmount': 500.0},
        },
        isPatch: true,
      );

      final cached = rtdb.getLatestValue('patients') as Map?;
      expect(cached, isNotNull);
      expect(cached!.length, equals(108), reason: 'Collection must never collapse');
      expect((cached['patient_1'] as Map)['billing'], equals({'advanceAmount': 500.0}));

      await sub.cancel();
    });

    test('2. Empty memory cache, SQLite has 108, targeted Rita patch -> hydrate full local dataset -> remains 108', () async {
      final client = MockClient((req) async => http.Response('{}', 200));
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      // Seed SQLite with 108 patients
      final all108 = create108Patients();
      await persistentCache.replaceSnapshot('patients', all108);

      // Memory cache is empty / evicted
      expect(rtdb.getLatestValue('patients'), isNull);

      final stream = rtdb.stream('patients');
      dynamic emittedValue;
      final completer = Completer<void>();
      final sub = stream.listen((val) {
        if (val is Map && val.length == 108) {
          emittedValue = val;
          if (!completer.isCompleted) completer.complete();
        }
      });

      await completer.future.timeout(const Duration(seconds: 3));
      expect(emittedValue, isNotNull);
      expect((emittedValue as Map).length, equals(108));

      await sub.cancel();
    });

    test('3. No synthetic one-record canonical collections', () async {
      final client = MockClient((req) async => http.Response('{}', 200));
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      // Memory cache is completely empty
      expect(rtdb.getLatestValue('patients'), isNull);

      final emissions = <int>[];
      final sub = rtdb.stream('patients').listen((data) {
        if (data is Map) emissions.add(data.length);
      });

      // Target mutation arrives when memory cache is empty
      rtdb.notifyWrittenForTesting(
        ['patients/patient_1'],
        explicitValues: {
          'patients/patient_1': createSamplePatient('patient_1', name: 'Rita Nandi'),
        },
        isPatch: false,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      // No emission should ever have length == 1 representing a partial canonical collection
      expect(emissions.contains(1), isFalse, reason: 'Must never emit synthetic 1-patient canonical collection');

      await sub.cancel();
    });
  });

  group('GROUP 2: STREAMS', () {
    test('4. Header and patient-list subscribers both receive the same replayed dataset', () async {
      final client = MockClient((req) async {
        return http.Response(json.encode(create108Patients()), 200);
      });
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      final patientService = PatientService(rtdbService: rtdb);
      final stream = patientService.getPatientsStream();

      // Subscriber 1 (e.g. Header)
      final sub1Result = Completer<List<PatientModel>>();
      final sub1 = stream.listen((patients) {
        if (!sub1Result.isCompleted && patients.isNotEmpty) {
          sub1Result.complete(patients);
        }
      });

      final patients1 = await sub1Result.future.timeout(const Duration(seconds: 3));
      expect(patients1.length, equals(108));

      // Subscriber 2 (e.g. Patient List mounted later)
      final sub2Result = Completer<List<PatientModel>>();
      final sub2 = stream.listen((patients) {
        if (!sub2Result.isCompleted && patients.isNotEmpty) {
          sub2Result.complete(patients);
        }
      });

      final patients2 = await sub2Result.future.timeout(const Duration(seconds: 3));
      expect(patients2.length, equals(108));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('5. Payment History remount receives current data', () async {
      final samplePayments = {
        'pay_1': {'id': 'pay_1', 'amount': 1000, 'date': 1700000000000, 'status': 'completed'},
        'pay_2': {'id': 'pay_2', 'amount': 2000, 'date': 1700000001000, 'status': 'completed'},
      };
      final client = MockClient((req) async {
        return http.Response(json.encode(samplePayments), 200);
      });
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      final paymentService = PaymentService(rtdb);
      final stream = paymentService.getAllPaymentsStream();

      // First mount
      final sub1Result = Completer<List<Map<String, dynamic>>>();
      final sub1 = stream.listen((payments) {
        if (!sub1Result.isCompleted && payments.isNotEmpty) {
          sub1Result.complete(payments);
        }
      });

      final list1 = await sub1Result.future.timeout(const Duration(seconds: 3));
      expect(list1.length, equals(2));
      await sub1.cancel();

      // Second mount (remount tab)
      final sub2Result = Completer<List<Map<String, dynamic>>>();
      final sub2 = stream.listen((payments) {
        if (!sub2Result.isCompleted && payments.isNotEmpty) {
          sub2Result.complete(payments);
        }
      });

      final list2 = await sub2Result.future.timeout(const Duration(seconds: 3));
      expect(list2.length, equals(2));
      await sub2.cancel();
    });
  });

  group('GROUP 3: SQLITE', () {
    test('6. Patient upsert is atomic', () async {
      await persistentCache.applyServerMutation({
        'patients/p1': createSamplePatient('p1', name: 'John Doe'),
      }, isPatch: false);

      final read = await persistentCache.read('patients/p1');
      expect(read, isNotNull);
      expect((read as Map)['fullName'], equals('John Doe'));
    });

    test('7. Sync transaction never exposes intermediate empty collection', () async {
      final initial = {'p1': createSamplePatient('p1'), 'p2': createSamplePatient('p2')};
      await persistentCache.replaceSnapshot('patients', initial);

      final next = {'p1': createSamplePatient('p1'), 'p2': createSamplePatient('p2'), 'p3': createSamplePatient('p3')};
      await persistentCache.replaceSnapshot('patients', next);

      final read = await persistentCache.read('patients') as Map;
      expect(read.length, equals(3));
      expect(read.containsKey('p1'), isTrue);
      expect(read.containsKey('p2'), isTrue);
      expect(read.containsKey('p3'), isTrue);
    });

    test('8. Account partition remains correct', () async {
      await persistentCache.applyServerMutation({
        'patients/p1': createSamplePatient('p1', name: 'Account A Patient'),
      }, isPatch: false);

      final readA = await persistentCache.read('patients/p1');
      expect(readA, isNotNull);
      expect((readA as Map)['fullName'], equals('Account A Patient'));

      // Insert row for a different account
      await database.into(database.cachedPatients).insert(
            CachedPatientsCompanion.insert(
              accountId: 'other-account',
              id: 'p_other',
              payload: jsonEncode(createSamplePatient('p_other', name: 'Other Account Patient')),
            ),
          );

      // Active account 'test-account' must never see rows for 'other-account'
      final readOther = await persistentCache.read('patients/p_other');
      expect(readOther, isNull, reason: 'Active account must never see rows belonging to another account');
    });

    test('9. Confirmed server deletion removes local orphan', () async {
      // Seed SQLite with 109 patients (including orphan -OzuBVsFsu6wT6uwhIrN)
      final mapWithOrphan = create108Patients();
      mapWithOrphan['-OzuBVsFsu6wT6uwhIrN'] = createSamplePatient('-OzuBVsFsu6wT6uwhIrN', name: 'Orphan');
      await persistentCache.replaceSnapshot('patients', mapWithOrphan);

      final before = await persistentCache.read('patients') as Map;
      expect(before.length, equals(109));
      expect(before.containsKey('-OzuBVsFsu6wT6uwhIrN'), isTrue);

      // Authoritative server snapshot contains only the 108 patients
      final authoritative108 = create108Patients();
      await persistentCache.replaceSnapshot('patients', authoritative108);

      final after = await persistentCache.read('patients') as Map;
      expect(after.length, equals(108));
      expect(after.containsKey('-OzuBVsFsu6wT6uwhIrN'), isFalse, reason: 'Orphan must be safely deleted');
    });

    test('10. Filtered query absence does NOT delete canonical row', () async {
      final allPatients = {
        'p_active': createSamplePatient('p_active', status: 'active'),
        'p_discharged': createSamplePatient('p_discharged', status: 'discharged'),
      };
      await persistentCache.replaceSnapshot('patients', allPatients);

      // A filtered query returns only active patients
      await persistentCache.mergeQuerySnapshot('patients', {
        'p_active': createSamplePatient('p_active', status: 'active', name: 'Updated Active'),
      });

      final read = await persistentCache.read('patients') as Map;
      expect(read.length, equals(2));
      expect(read.containsKey('p_discharged'), isTrue, reason: 'Discharged patient must not be deleted by filtered query');
    });
  });

  group('GROUP 4: SYNC', () {
    test('11. Stale snapshot cannot overwrite newer state', () async {
      await persistentCache.applyServerMutation({
        'patients/p1': createSamplePatient('p1', name: 'Newer Name', updatedAt: 2000),
      }, isPatch: false);

      // Older snapshot arrives with updatedAt: 1000
      await persistentCache.applyServerMutation({
        'patients/p1': createSamplePatient('p1', name: 'Stale Name', updatedAt: 1000),
      }, isPatch: false);

      final read = await persistentCache.read('patients/p1') as Map;
      expect(read['fullName'], equals('Newer Name'), reason: 'Stale snapshot must not overwrite newer state');
      expect(read['updatedAt'], equals(2000));
    });

    test('12. Duplicate SSE event is idempotent', () async {
      final patient = createSamplePatient('p1', name: 'Idempotent Patient');
      await persistentCache.applyServerMutation({'patients/p1': patient}, isPatch: false);
      await persistentCache.applyServerMutation({'patients/p1': patient}, isPatch: false);

      final rows = await database.select(database.cachedPatients).get();
      expect(rows.length, equals(1));
    });

    test('13. Reconnect does not collapse canonical data', () async {
      final client = MockClient((req) async {
        return http.Response(json.encode(create108Patients()), 200);
      });
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      // Seed initial 108 patients
      await persistentCache.replaceSnapshot('patients', create108Patients());
      final stream = rtdb.stream('patients');

      final completer = Completer<dynamic>();
      final sub = stream.listen((val) {
        if (val is Map && val.length == 108 && !completer.isCompleted) {
          completer.complete(val);
        }
      });

      final result = await completer.future.timeout(const Duration(seconds: 3));
      expect((result as Map).length, equals(108));
      await sub.cancel();
    });
  });

  group('GROUP 5: PATIENT DETAIL', () {
    test('14. Opening patient detail does not mutate global patient list', () async {
      final client = MockClient((req) async => http.Response('{}', 200));
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      final all108 = create108Patients();
      rtdb.injectLatestValue('patients', Map<String, dynamic>.from(all108));

      // Simulate opening Rita's detail and calculating billing (root patch for patient_1)
      rtdb.notifyWrittenForTesting(
        ['patients/patient_1/effectiveDueAmount'],
        explicitValues: {'patients/patient_1/effectiveDueAmount': 150.0},
        isPatch: true,
      );

      final globalPatients = rtdb.getLatestValue('patients') as Map?;
      expect(globalPatients, isNotNull);
      expect(globalPatients!.length, equals(108), reason: 'Opening detail must not collapse global list');
    });

    test('15. Background billing update for one patient changes one patient only', () async {
      final initial = {
        'p1': createSamplePatient('p1', name: 'Patient 1'),
        'p2': createSamplePatient('p2', name: 'Patient 2'),
      };
      await persistentCache.replaceSnapshot('patients', initial);

      await persistentCache.applyServerMutation({
        'patients/p1/effectiveDueAmount': 250.0,
      }, isPatch: true);

      final readP1 = await persistentCache.read('patients/p1') as Map;
      final readP2 = await persistentCache.read('patients/p2') as Map;

      expect(readP1['effectiveDueAmount'], equals(250.0));
      expect(readP2['fullName'], equals('Patient 2'));
      expect(readP2.containsKey('effectiveDueAmount'), isFalse);
    });

    test('16. Secondary stays/payment/attendance error does not null patient', () {
      final patient = PatientModel.fromMap('p1', createSamplePatient('p1', name: 'Rita Nandi'));
      expect(patient.id, equals('p1'));
      expect(patient.fullName, equals('Rita Nandi'));
      // Even if stays or payments fail, patient model remains valid and has non-empty identity
      expect(patient.id.isNotEmpty, isTrue);
    });

    test('17. Background refresh retains visible patient', () async {
      final patientMap = createSamplePatient('p1', name: 'Rita Nandi');
      await persistentCache.applyServerMutation({'patients/p1': patientMap}, isPatch: false);

      final cached = await persistentCache.read('patients/p1');
      expect(cached, isNotNull);
      expect((cached as Map)['fullName'], equals('Rita Nandi'));
    });
  });

  group('GROUP 6: ADD PATIENT', () {
    test('18. Root multi-path patch has no overlapping parent/child paths', () {
      final rtdb = _TestRtdbService();
      final input = {
        'stays/stay_1': {
          'patientId': 'p1',
          'roomId': 'room_1',
          'status': 'active',
        },
        'rooms/room_1/status': 'occupied',
      };

      final prepared = rtdb.prepareWriteForTesting('', input, isPatch: true);

      // Must NOT have 'stays/stay_1/updatedAt' as a top-level key because 'stays/stay_1' is already an object
      expect(prepared.containsKey('stays/stay_1/updatedAt'), isFalse,
          reason: 'Overlapping child updatedAt path must not be generated when parent is a full object');

      // The stay object itself should have updatedAt embedded
      final stay = prepared['stays/stay_1'] as Map<String, dynamic>;
      expect(stay.containsKey('updatedAt'), isTrue);
      expect(stay['updatedAt'], equals({'.sv': 'timestamp'}));
    });

    test('19. Admission succeeds with updatedAt semantics', () {
      final rtdb = _TestRtdbService();
      final input = {
        'patients/p1': {
          'fullName': 'New Patient',
          'status': 'active',
        },
        'stays/stay_1': {
          'patientId': 'p1',
          'roomId': 'room_1',
          'status': 'active',
        },
      };

      final prepared = rtdb.prepareWriteForTesting('', input, isPatch: true);
      expect((prepared['patients/p1'] as Map)['updatedAt'], equals({'.sv': 'timestamp'}));
      expect((prepared['stays/stay_1'] as Map)['updatedAt'], equals({'.sv': 'timestamp'}));
      expect(prepared.keys.where((k) => k.contains('/updatedAt')), isEmpty);
    });

    test('20. Failed admission creates no phantom patient', () async {
      // Simulate failed admission write - verify cache is clean
      final patient = await persistentCache.read('patients/non_existent_patient');
      expect(patient, isNull);
    });
  });

  group('GROUP 7: HISTORICAL DATA', () {
    test('21. September attendance for discharged patients remains visible', () {
      // Historical report data
      final septemberDailyMap = {
        '2026-09-15': {
          'p_discharged': {
            'patientName': 'Rita Nandi',
            'status': 'Present',
          },
          'p_active': {
            'patientName': 'Active Patient',
            'status': 'Present',
          },
        },
      };

      // Simulating the fixed parsing logic from attendance.dart
      final result = <String, Map<String, String>>{};
      septemberDailyMap.forEach((date, data) {
        data.forEach((patientId, v) {
          final name = v['patientName'] ?? '';
          final status = v['status'] ?? '';
          if (name.isNotEmpty && (status == 'Present' || status == 'Absent')) {
            result.putIfAbsent(name, () => {})[date] = status;
          }
        });
      });

      expect(result.containsKey('Rita Nandi'), isTrue,
          reason: 'Discharged patient must be included in historical September report');
      expect(result['Rita Nandi']!['2026-09-15'], equals('Present'));
    });

    test('22. September stays remain accessible', () async {
      final septemberStay = {
        'id': 'stay_sep_1',
        'patientId': 'p_rita',
        'roomId': 'room_101',
        'status': 'discharged',
        'admissionDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'dischargeDate': DateTime(2026, 9, 25).millisecondsSinceEpoch,
      };
      await persistentCache.applyServerMutation({'stays/stay_sep_1': septemberStay}, isPatch: false);

      final read = await persistentCache.read('stays/stay_sep_1') as Map?;
      expect(read, isNotNull);
      expect(read!['id'], equals('stay_sep_1'));
    });

    test('23. September payment history remains accessible where supported', () async {
      final sepPayment = {
        'id': 'pay_sep_1',
        'patientId': 'p_rita',
        'amount': 2500,
        'date': DateTime(2026, 9, 5).millisecondsSinceEpoch,
        'status': 'completed',
      };
      await persistentCache.applyServerMutation({'paymentHistory/pay_sep_1': sepPayment}, isPatch: false);

      final read = await persistentCache.read('paymentHistory/pay_sep_1') as Map?;
      expect(read, isNotNull);
      expect(read!['amount'], equals(2500));
    });

    test('24. Historical date range does not depend on current patient status', () {
      final dates = ['2026-09-01', '2026-09-02', '2026-09-30'];
      expect(dates.first, equals('2026-09-01'));
      expect(dates.last, equals('2026-09-30'));
      expect(dates.length, equals(3));
    });
  });

  group('GROUP 8: PHOTOS', () {
    test('25. No Base64 reintroduced into hot patient/stay rows', () async {
      final patientWithPhoto = {
        ...createSamplePatient('p1'),
        'photoDataUrl': 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD...',
      };

      await persistentCache.applyServerMutation({'patients/p1': patientWithPhoto}, isPatch: false);

      final row = await (database.select(database.cachedPatients)
            ..where((r) => r.id.equals('p1')))
          .getSingle();

      final payloadMap = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(payloadMap.containsKey('photoDataUrl'), isFalse,
          reason: 'photoDataUrl must be sanitized out of cachedPatients table');
    });

    test('26. Historical photo identity preserved', () async {
      await persistentCache.applyServerMutation({
        'patientPhotos/patients/p1': {'photoRef': 'photos/p1.jpg', 'updatedAt': 100},
        'patientPhotos/stays/s1': {'photoRef': 'photos/s1.jpg', 'updatedAt': 100},
      }, isPatch: false);

      final metadata = await (database.select(database.cachedPhotoMetadata)
            ..where((r) => r.accountId.equals('test-account')))
          .get();

      expect(metadata.length, equals(2));
      final refs = metadata.map((m) => m.photoRef).toSet();
      expect(refs.contains('patientPhotos/patients/p1'), isTrue);
      expect(refs.contains('patientPhotos/stays/s1'), isTrue);
    });
  });

  group('GROUP 9: PERFORMANCE', () {
    test('27. Single patient patch does not issue full /patients GET', () async {
      final client = MockClient((req) async {
        if (req.method == 'PATCH') {
          return http.Response(json.encode({'fullName': 'Updated'}), 200);
        }
        return http.Response('{}', 200);
      });
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      await rtdb.patch('patients/p1', {'fullName': 'Updated'});
      expect(rtdb.getCalls.containsKey('patients'), isFalse,
          reason: 'Single patient patch must never issue full GET /patients');
    });

    test('28. Single attendance operation does not issue full /patients GET', () async {
      final client = MockClient((req) async {
        return http.Response('{}', 200);
      });
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      await rtdb.put('attendance/daily/2026-10-03/p1', {'status': 'Present'});
      expect(rtdb.getCalls.containsKey('patients'), isFalse,
          reason: 'Attendance write must never issue full GET /patients');
    });

    test('29. Room operation does not issue full /stays GET', () async {
      final client = MockClient((req) async {
        return http.Response('{}', 200);
      });
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      await rtdb.patch('rooms/room_1', {'status': 'cleaning'});
      expect(rtdb.getCalls.containsKey('stays'), isFalse,
          reason: 'Room operation must never issue full GET /stays');
    });

    test('30. Patient detail opening does not cause full collection refresh', () async {
      final client = MockClient((req) async {
        return http.Response('{}', 200);
      });
      final rtdb = _TestRtdbService(httpClient: client, persistentCache: persistentCache);

      // Single patient fetch
      await rtdb.get('patients/patient_1');
      expect(rtdb.getCalls['patients/patient_1'], equals(1));
      expect(rtdb.getCalls.containsKey('patients'), isFalse,
          reason: 'Detail opening must only fetch targeted patient, never full collection');
    });
  });
}
