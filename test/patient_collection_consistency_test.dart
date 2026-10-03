import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/patients/patient_profile_screen.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/patient_collection_state.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';

Map<String, dynamic> patient(String id, {int version = 100}) => {
  'id': id,
  'fullName': 'Patient $id',
  'gender': 'female',
  'status': 'active',
  'admissionDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
  'dateOfBirth': DateTime(1980).millisecondsSinceEpoch,
  'updatedAt': version,
};

Map<String, dynamic> patients([int count = 109]) => {
  for (var i = 0; i < count; i++) 'p$i': patient('p$i'),
};

String frame(String type, String path, dynamic data) =>
    'event: $type\ndata: ${jsonEncode({'path': path, 'data': data})}\n\n';

class SseClient extends http.BaseClient {
  final events = StreamController<List<int>>();
  final ready = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    ready.complete();
    return http.StreamedResponse(events.stream, 200);
  }

  void emit(String text) => events.add(utf8.encode(text));

  @override
  void close() {
    if (!events.isClosed) unawaited(events.close());
  }
}

class Gate {
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> pause() async {
    entered.complete();
    await release.future;
  }
}

class GatedCache extends PersistentCache {
  GatedCache(super.database);
  Gate? snapshotGate;
  Gate? readGate;

  @override
  Future<void> replaceSnapshot(
    String path,
    dynamic value, {
    bool Function()? isCurrent,
  }) async {
    final gate = path == 'patients' ? snapshotGate : null;
    snapshotGate = null;
    if (gate != null) await gate.pause();
    await super.replaceSnapshot(path, value, isCurrent: isCurrent);
  }

  @override
  Future<CanonicalPatientCacheSnapshot?> readCanonicalPatients() async {
    final gate = readGate;
    readGate = null;
    final result = await super.readCanonicalPatients();
    if (gate != null) await gate.pause();
    return result;
  }
}

class Harness {
  Harness(this.cache) {
    rest = FirebaseRTDBRestService(
      projectId: 'test',
      databaseUrl: 'https://example.test',
      persistentCache: cache,
      getAuthToken: () async => 'test-token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          throw StateError('Unexpected REST read: ${request.url}');
        }
        final decoded = request.body.isEmpty ? null : jsonDecode(request.body);
        dynamic resolve(dynamic value) {
          if (value is Map) {
            if (value['.sv'] == 'timestamp') return ++clock;
            return value.map((key, item) => MapEntry(key, resolve(item)));
          }
          if (value is List) return value.map(resolve).toList();
          return value;
        }

        return http.Response(jsonEncode(resolve(decoded)), 200);
      }),
      sseClientFactory: () {
        final client = SseClient();
        connections.add(client);
        return client;
      },
    );
  }

  final GatedCache cache;
  late final FirebaseRTDBRestService rest;
  final requests = <http.Request>[];
  final connections = <SseClient>[];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final emissions = <Map<String, dynamic>>[];
  int clock = 1000;

  Map<String, dynamic>? get memory =>
      rest.latestValuesForTesting['patients'] as Map<String, dynamic>?;

  Future<void> seed({bool memory = true}) async {
    await cache.replaceSnapshot('patients', patients());
    if (memory) rest.seedCanonicalPatientsForTesting(patients());
  }

  Future<SseClient> listen() async {
    final previous = connections.length;
    subscriptions.add(
      rest.stream('patients').listen((value) {
        if (value is Map) emissions.add(Map<String, dynamic>.from(value));
      }),
    );
    await until(() => connections.length > previous);
    await connections.last.ready.future;
    return connections.last;
  }

  Future<void> close() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    rest.dispose();
    await cache.close();
  }
}

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('State transition timed out');
    await Future<void>.delayed(Duration.zero);
  }
}

class GatedBilling extends PaymentService {
  GatedBilling(super.rtdb);
  final gate = Gate();
  int calculations = 0;

  @override
  Future<Map<String, dynamic>> billingUpdates(
    String patientId, {
    Map<String, dynamic>? patientData,
    List<StayModel>? stays,
    Map<String, String?> patientAttendanceOverrides = const {},
    Map<String, Map<String, String?>> attendantAttendanceOverrides = const {},
  }) async {
    calculations++;
    if (calculations == 1) await gate.pause();
    return {
      'patients/$patientId/totalPaidAmount': 500,
      'stays/s1/patientId': patientId,
      'stays/s1/billableDays': 3,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canonical state owner', () {
    late PatientCollectionState state;
    setUp(() {
      state = PatientCollectionState()..bindAccount(1);
      expect(
        state.publish(patients(), state.capture(), complete: true),
        isTrue,
      );
    });

    test('whole record update preserves all 109 patients', () {
      state.mutate(
        'patients/p1',
        patient('p1', version: 200),
        isPatch: false,
        acknowledged: true,
      );
      expect(state.value, hasLength(109));
      expect(state.value!['p1']['updatedAt'], 200);
    });

    test('nested field update preserves every other patient and field', () {
      state.mutate(
        'patients/p1/totalPaidAmount',
        500,
        isPatch: true,
        acknowledged: true,
      );
      expect(state.value, hasLength(109));
      expect(state.value!['p1']['fullName'], 'Patient p1');
      expect(state.value!['p1']['totalPaidAmount'], 500);
      expect(state.value!['p108'], patient('p108'));
    });

    test('add is 109 to 110; delete removes exactly one', () {
      state.mutate(
        'patients/new',
        patient('new'),
        isPatch: false,
        acknowledged: true,
      );
      expect(state.value, hasLength(110));
      state.mutate('patients/p1', null, isPatch: false, acknowledged: true);
      expect(state.value, hasLength(109));
      expect(state.value!.containsKey('p1'), isFalse);
      expect(state.value!.containsKey('new'), isTrue);
    });

    test('exact resource notification is child deltas, never replacement', () {
      state.mutate(
        'patients',
        {
          'p1': {'totalPaidAmount': 99},
        },
        isPatch: true,
        acknowledged: true,
      );
      expect(state.value, hasLength(109));
      expect(state.value!['p1']['fullName'], 'Patient p1');
      expect(state.value!['p1']['totalPaidAmount'], 99);
    });

    for (final base in [
      <String, dynamic>{},
      {'p1': patient('p1')},
    ]) {
      test('incomplete base of ${base.length} never becomes canonical', () {
        state = PatientCollectionState()..bindAccount(1);
        expect(state.publish(base, state.capture(), complete: false), isFalse);
        state.mutate(
          'patients/new',
          patient('new'),
          isPatch: false,
          acknowledged: true,
        );
        expect(state.value, isNull);
        expect(state.completeness, PatientCollectionCompleteness.unknown);
        expect(
          state.publish(patients(), state.capture(), complete: true),
          isTrue,
        );
        expect(state.value, hasLength(110));
      });
    }

    test('late snapshot ticket cannot undo newer targeted mutation', () {
      final ticket = state.capture();
      state.mutate(
        'patients/new',
        patient('new'),
        isPatch: false,
        acknowledged: true,
      );
      expect(state.publish(patients(), ticket, complete: true), isFalse);
      expect(state.value, hasLength(110));
    });

    test(
      'later arrival of older contents preserves acknowledged add/update/delete',
      () {
        state.mutate(
          'patients/new',
          patient('new', version: 200),
          isPatch: false,
          acknowledged: true,
        );
        state.mutate(
          'patients/p1/totalPaidAmount',
          99,
          isPatch: true,
          acknowledged: true,
        );
        state.mutate('patients/p2', null, isPatch: false, acknowledged: true);
        expect(
          state.publish(patients(), state.capture(), complete: true),
          isTrue,
        );
        expect(state.value, hasLength(109));
        expect(state.value!['new']['fullName'], 'Patient new');
        expect(state.value!['p1']['totalPaidAmount'], 99);
        expect(state.value!.containsKey('p2'), isFalse);
      },
    );

    test('SSE child and later queued root retain receive order', () {
      final child = state.capture();
      final root = state.capture();
      state.mutate(
        'patients/p1/status',
        'Paid',
        isPatch: true,
        acknowledged: false,
        revision: child.revision,
      );
      expect(state.publish(patients(110), root, complete: true), isTrue);
      expect(state.value, hasLength(110));
    });

    test('account A hydration cannot publish into account B', () {
      final ticket = state.capture(hydrating: true);
      state.bindAccount(2);
      expect(state.publish(patients(), ticket, complete: true), isFalse);
      expect(state.value, isNull);
    });

    test('patch payload cannot masquerade as a complete root', () {
      expect(
        state.publish(
          {
            'p1': {'totalPaidAmount': 1},
          },
          state.capture(),
          complete: true,
        ),
        isFalse,
      );
      expect(state.value, hasLength(109));
    });
  });

  group('real REST/SSE/SQLite overlap', () {
    late Harness h;
    setUp(() async {
      final cache = GatedCache(CacheDatabase(NativeDatabase.memory()));
      await cache.initialize();
      await cache.activateAccount('account-A');
      h = Harness(cache);
    });
    tearDown(() async => h.close());

    test(
      'queued PATCH keeps its type when a PUT header arrives before execution',
      () async {
        await h.seed();
        final sse = await h.listen();
        await h.rest.rehydratePatientsForTesting();
        final gate = Gate();
        h.cache.snapshotGate = gate;
        sse.emit(frame('put', '/', patients()));
        await gate.entered.future;
        sse.emit(
          frame('patch', '/p1', {'totalPaidAmount': 99}) +
              frame('put', '/p2', patient('p2', version: 300)),
        );
        gate.release.complete();
        await until(() => h.memory?['p2']['updatedAt'] == 300);
        expect(h.memory, hasLength(109));
        expect(h.memory!['p1']['fullName'], 'Patient p1');
        expect(h.memory!['p1']['totalPaidAmount'], 99);
        expect(h.emissions.every((value) => value.length == 109), isTrue);
        expect(h.requests, isEmpty);
      },
    );

    test(
      'root PATCH remains child changes while a PUT header is queued',
      () async {
        await h.seed();
        final sse = await h.listen();
        await h.rest.rehydratePatientsForTesting();
        final gate = Gate();
        h.cache.snapshotGate = gate;
        sse.emit(frame('put', '/', patients()));
        await gate.entered.future;
        sse.emit(
          frame('patch', '/', {
                'p1': {'totalPaidAmount': 99},
              }) +
              frame('put', '/p2', patient('p2', version: 300)),
        );
        gate.release.complete();
        await until(() => h.memory?['p2']['updatedAt'] == 300);
        expect(h.memory, hasLength(109));
        expect(h.memory!['p1']['totalPaidAmount'], 99);
        expect((await h.cache.read('patients')) as Map, hasLength(109));
      },
    );

    test(
      'paused full snapshot cannot overwrite an ACK in memory or SQLite',
      () async {
        await h.seed();
        final sse = await h.listen();
        await h.rest.rehydratePatientsForTesting();
        final gate = Gate();
        h.cache.snapshotGate = gate;
        sse.emit(frame('put', '/', patients()));
        await gate.entered.future;
        await h.rest.put('patients/new', patient('new', version: 200));
        gate.release.complete();
        sse.emit(frame('patch', '/p1', {'gender': 'male'}));
        await until(() => h.memory?['p1']['gender'] == 'male');
        expect(h.memory, hasLength(110));
        expect((await h.cache.read('patients')) as Map, hasLength(110));
        expect(h.emissions.every((value) => value.length >= 109), isTrue);
        expect(h.requests.where((request) => request.method == 'GET'), isEmpty);
      },
    );

    test(
      'old root received after ACK retains the acknowledged new patient',
      () async {
        await h.seed();
        final sse = await h.listen();
        await h.rest.rehydratePatientsForTesting();
        await h.rest.put('patients/new', patient('new'));
        sse.emit(
          frame('put', '/', patients()) +
              frame('patch', '/p1', {'gender': 'male'}),
        );
        await until(() => h.memory?['p1']['gender'] == 'male');
        expect(h.memory, hasLength(110));
        expect((await h.cache.read('patients')) as Map, hasLength(110));
      },
    );

    test(
      'explicit hydration started before ACK cannot publish its older read',
      () async {
        await h.seed();
        await h.listen();
        await h.rest.rehydratePatientsForTesting();
        final gate = Gate();
        h.cache.readGate = gate;
        final hydration = h.rest.rehydratePatientsForTesting();
        await gate.entered.future;
        await h.rest.put('patients/new', patient('new'));
        gate.release.complete();
        await hydration;
        expect(h.memory, hasLength(110));
        expect(h.emissions.every((value) => value.length >= 109), isTrue);
      },
    );

    test(
      'ACK during initial hydration is deferred without singleton emission',
      () async {
        await h.seed(memory: false);
        final gate = Gate();
        h.cache.readGate = gate;
        await h.listen();
        await gate.entered.future;
        await h.rest.put('patients/new', patient('new'));
        expect(h.memory, isNull);
        expect(h.emissions, isEmpty);
        gate.release.complete();
        await until(() => h.memory?.length == 110);
        expect(h.emissions.every((value) => value.length == 110), isTrue);
        expect(h.requests.where((request) => request.method == 'GET'), isEmpty);
      },
    );

    test(
      'partial SQLite and arbitrary memory Map never establish completeness',
      () async {
        await h.cache.mergeQuerySnapshot('patients', {'p1': patient('p1')});
        h.rest.latestValuesForTesting['patients'] = {'p1': patient('p1')};
        final sse = await h.listen();
        await h.rest.rehydratePatientsForTesting();
        expect(h.emissions, isEmpty);
        await h.rest.put('patients/new', patient('new'));
        expect(h.memory, isNull);
        sse.emit(frame('put', '/', patients()));
        await until(() => h.memory?.length == 110);
        expect(h.emissions.every((value) => value.length == 110), isTrue);
      },
    );

    test(
      'filtered SSE snapshot and query removal cannot replace canonical patients',
      () async {
        await h.seed();
        await h.listen();
        await h.rest.rehydratePatientsForTesting();
        final queryValues = <dynamic>[];
        h.subscriptions.add(
          h.rest
              .queryStream('patients', orderBy: 'status', equalTo: 'active')
              .listen(queryValues.add),
        );
        await until(() => h.connections.length == 2);
        final filtered = h.connections.last;
        await filtered.ready.future;
        filtered.emit(frame('put', '/', patients(17)));
        await until(
          () => queryValues.any((value) => value is Map && value.length == 17),
        );
        filtered.emit(frame('put', '/p1', null));
        await until(
          () => queryValues.last is Map && queryValues.last.length == 16,
        );
        expect(h.memory, hasLength(109));
        expect((await h.cache.read('patients')) as Map, hasLength(109));
        expect(h.memory!.containsKey('p1'), isTrue);
        expect((await h.cache.readCanonicalPatients())!.complete, isTrue);
      },
    );

    test(
      'two PatientService consumers replay and receive the same complete add',
      () async {
        await h.seed();
        final service = PatientService(rtdbService: h.rest);
        final stream = service.getPatientsStream();
        final header = <int>[];
        final list = <int>[];
        h.subscriptions.add(stream.listen((value) => header.add(value.length)));
        await until(() => header.isNotEmpty);
        h.subscriptions.add(stream.listen((value) => list.add(value.length)));
        await until(() => list.isNotEmpty);
        await h.rest.rehydratePatientsForTesting();
        await h.rest.put('patients/new', patient('new'));
        await until(() => list.last == 110 && header.last == 110);
        expect(header, [109, 110]);
        expect(list, [109, 110]);
      },
    );

    test('old connection snapshot is ignored after reconnect', () async {
      await h.seed();
      final old = await h.listen();
      await h.rest.rehydratePatientsForTesting();
      final gate = Gate();
      h.cache.snapshotGate = gate;
      old.emit(frame('put', '/', patients()));
      await gate.entered.future;
      await h.subscriptions.first.cancel();
      final fresh = await h.listen();
      await h.rest.put('patients/new', patient('new'));
      gate.release.complete();
      fresh.emit(
        frame('put', '/', {
              ...patients(),
              'new': patient('new', version: 2000),
            }) +
            frame('patch', '/p1', {'gender': 'male'}),
      );
      await until(() => h.memory?['p1']['gender'] == 'male');
      expect(h.memory, hasLength(110));
      expect((await h.cache.read('patients')) as Map, hasLength(110));
    });

    test(
      'account switch rejects a paused SQLite hydration from the old account',
      () async {
        await h.seed(memory: false);
        final gate = Gate();
        h.cache.readGate = gate;
        await h.listen();
        await gate.entered.future;
        await h.cache.activateAccount('account-B');
        await h.cache.replaceSnapshot('patients', {'b': patient('b')});
        gate.release.complete();
        await h.rest.rehydratePatientsForTesting();
        await until(() => h.memory?.containsKey('b') == true);
        expect(h.memory!.keys, ['b']);
        expect(h.emissions.any((value) => value.containsKey('p1')), isFalse);
      },
    );

    test(
      'actual Add Patient service, stay/payment ACKs, SSE and hydration: 109 to 110 to 111',
      () async {
        await h.seed();
        final sse = await h.listen();
        await h.rest.rehydratePatientsForTesting();
        final service = PatientService(rtdbService: h.rest);
        final added = <String>[];
        for (var addition = 0; addition < 2; addition++) {
          final hydrationGate = Gate();
          h.cache.readGate = hydrationGate;
          final hydration = h.rest.rehydratePatientsForTesting();
          await hydrationGate.entered.future;
          final snapshotGate = Gate();
          h.cache.snapshotGate = snapshotGate;
          sse.emit(frame('put', '/', patients()));
          await snapshotGate.entered.future;
          final id = await service.addPatient(
            fullName: 'New patient $addition',
            dateOfBirth: DateTime(1980),
            gender: 'female',
            contactNumber: '123',
            emergencyContact: '123',
            emergencyContactName: 'Contact',
            medicalCondition: 'Condition',
            admissionDate: DateTime(2026, 10, 3),
            createdBy: 'account-A',
          );
          added.add(id);
          await h.rest.patch('', {
            'stays/stay$addition': {'patientId': id, 'status': 'active'},
            'payments/pay$addition': {'patientId': id, 'amount': 500},
            'patients/$id/totalPaidAmount': 500,
          });
          snapshotGate.release.complete();
          hydrationGate.release.complete();
          await hydration;
          sse.emit(
            frame('patch', '/', {'$id/totalPaidAmount': 500}) +
                frame('put', '/', patients()) +
                frame('patch', '/p1', {'gender': 'round$addition'}),
          );
          await until(() => h.memory?['p1']['gender'] == 'round$addition');
          expect(h.memory, hasLength(110 + addition));
          expect(h.memory!.keys, containsAll(patients().keys));
          expect(h.memory!.keys, containsAll(added));
          expect(
            (await h.cache.read('patients')) as Map,
            hasLength(110 + addition),
          );
          expect(h.emissions.every((value) => value.length >= 109), isTrue);
        }
        expect(h.requests.where((request) => request.method == 'GET'), isEmpty);
      },
    );

    test(
      'profile and Stays billing coalesce and only mutate targeted records',
      () async {
        await h.seed();
        await h.listen();
        await h.rest.rehydratePatientsForTesting();
        final billing = GatedBilling(h.rest);
        final profile = billing.recalculatePatientAttendanceAndBilling('p1');
        await billing.gate.entered.future;
        final staysTab = billing.recalculatePatientAttendanceAndBilling('p1');
        expect(identical(profile, staysTab), isTrue);
        billing.gate.release.complete();
        await Future.wait([profile, staysTab]);
        expect(billing.calculations, 1);
        expect(h.memory, hasLength(109));
        expect(h.memory!['p1']['totalPaidAmount'], 500);
        expect(h.requests, hasLength(1));
        expect(h.requests.single.method, 'PATCH');
      },
    );
  });

  test(
    'eviction after 15 seconds preserves canonical owner and targeted add',
    () {
      fakeAsync((clock) {
        final sse = SseClient();
        final rest = FirebaseRTDBRestService(
          projectId: 'test',
          databaseUrl: 'https://example.test',
          getAuthToken: () async => 'token',
          sseClientFactory: () => sse,
          httpClient: MockClient(
            (request) async => http.Response(request.body, 200),
          ),
        );
        rest.seedCanonicalPatientsForTesting(patients());
        final subscription = rest.stream('patients').listen((_) {});
        clock.flushMicrotasks();
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 16));
        clock.flushMicrotasks();
        unawaited(rest.put('patients/new', patient('new')));
        clock.flushMicrotasks();
        expect(rest.latestValuesForTesting['patients'], hasLength(110));
        final sizes = <int>[];
        final remount = rest
            .stream('patients')
            .listen((value) => sizes.add((value as Map).length));
        clock.flushMicrotasks();
        expect(sizes, [110]);
        unawaited(remount.cancel());
        rest.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'partial/filtered SQLite partition is unavailable until full snapshot marker',
    () async {
      final cache = GatedCache(CacheDatabase(NativeDatabase.memory()));
      await cache.initialize();
      await cache.activateAccount('a');
      await cache.mergeQuerySnapshot('patients', patients(17));
      expect((await cache.readCanonicalPatients())!.complete, isFalse);
      await cache.applyServerMutation({
        'patients/new': patient('new'),
      }, isPatch: false);
      expect((await cache.readCanonicalPatients())!.complete, isFalse);
      await cache.replaceSnapshot('patients', patients());
      expect((await cache.readCanonicalPatients())!.complete, isTrue);
      expect((await cache.readCanonicalPatients())!.value, hasLength(109));
      await cache.close();
    },
  );

  for (final gender in [null, '', '   ', 'female']) {
    testWidgets(
      'Overview renders optional gender ${jsonEncode(gender)} safely',
      (tester) async {
        final data = patient('p1')..['gender'] = gender;
        final model = PatientModel.fromMap('p1', data);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: buildPatientOverviewForTesting(model)),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(gender == 'female' ? 'Female' : 'Not provided'),
          gender == 'female' ? findsOneWidget : findsWidgets,
        );
      },
    );
  }

  test('write notifications and child SSE do not schedule collection GETs', () {
    final source = File(
      'lib/services/firebase_rtdb_rest_service.dart',
    ).readAsStringSync();
    final notifications = source.substring(
      source.indexOf('void _notifyWritten('),
      source.indexOf('static const Map<String, String> _serverTimestamp'),
    );
    expect(notifications, isNot(contains('refreshSoon(')));
    expect(notifications, isNot(contains("get('patients')")));
    final mutation = source.substring(
      source.indexOf('Future<void> _applySseMutation('),
    );
    expect(mutation, isNot(contains('refreshSoon(')));
    expect(mutation, isNot(contains('.get(')));
    expect(source, contains('if (_isFilteredQuery) return;'));
    final room = File(
      'lib/screens/rooms/widgets/room_card.dart',
    ).readAsStringSync();
    expect(room, isNot(contains('getPatientsStream(')));
    expect(room, isNot(contains("stream('patients')")));
  });
}
