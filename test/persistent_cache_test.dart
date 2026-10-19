import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/services/auth_service.dart';
import 'package:ngo/services/firebase_auth_rest_service.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestAuthService extends FirebaseAuthRestService {
  _TestAuthService() : super(apiKey: 'test');

  final controller = StreamController<AuthUser?>.broadcast();

  @override
  Stream<AuthUser?> get authStateChanges => controller.stream;

  Future<void> closeTestStream() => controller.close();
}

void main() {
  late CacheDatabase database;
  late PersistentCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = CacheDatabase(NativeDatabase.memory());
    cache = PersistentCache(database);
    await cache.initialize();
    await cache.activateAccount('account-a');
  });

  tearDown(() => cache.close());

  Map<String, dynamic> patient(
    String id, {
    String status = 'active',
    String roomId = 'room-a',
    int updatedAt = 10,
  }) => {
    'id': id,
    'fullName': 'Patient $id',
    'searchKey': 'patient $id',
    'registrationNumber': 'REG-$id',
    'status': status,
    'roomId': roomId,
    'updatedAt': updatedAt,
  };

  test('Drift schema creates canonical tables and sync state', () async {
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll(<String>{
        'cached_patients',
        'cached_stays',
        'cached_rooms',
        'cached_attendance',
        'cached_payments',
        'cached_profiles',
        'cached_settings',
        'cached_photo_metadata',
        'sync_states',
      }),
    );
    expect(database.schemaVersion, 1);
  });

  test('filtered SQL membership reacts to canonical status changes', () async {
    await cache.replaceSnapshot('patients', {
      'one': patient('one'),
      'two': patient('two', status: 'discharged'),
    });

    expect(
      (await cache.read('patients', orderBy: 'status', equalTo: 'active')
              as Map)
          .keys,
      ['one'],
    );

    await cache.applyServerMutation({
      'patients/one/status': 'discharged',
      'patients/one/updatedAt': 20,
      'patients/two/status': 'active',
      'patients/two/updatedAt': 20,
    }, isPatch: true);

    expect(
      (await cache.read('patients', orderBy: 'status', equalTo: 'active')
              as Map)
          .keys,
      ['two'],
    );
  });

  test(
    'room and patient filtered queries use one canonical stay row',
    () async {
      await cache.replaceSnapshot('stays', {
        'stay-1': {
          'id': 'stay-1',
          'patientId': 'patient-1',
          'roomId': 'room-a',
          'status': 'active',
          'expectedDischargeDate': 100,
          'updatedAt': 10,
        },
      });

      expect(
        (await cache.read('stays', orderBy: 'roomId', equalTo: 'room-a') as Map)
            .keys,
        ['stay-1'],
      );
      await cache.applyServerMutation({
        'stays/stay-1/roomId': 'room-b',
        'stays/stay-1/updatedAt': 20,
      }, isPatch: true);
      expect(
        await cache.read('stays', orderBy: 'roomId', equalTo: 'room-a'),
        isEmpty,
      );
      expect(
        (await cache.read('stays', orderBy: 'roomId', equalTo: 'room-b') as Map)
            .keys,
        ['stay-1'],
      );
    },
  );

  test('reactive local query emits targeted membership updates', () async {
    await cache.replaceSnapshot('patients', {'one': patient('one')});
    final emissions = <Map<dynamic, dynamic>>[];
    final subscription = cache
        .watch('patients', orderBy: 'status', equalTo: 'active')
        .listen((value) => emissions.add(value as Map));
    await Future<void>.delayed(Duration.zero);
    await cache.applyServerMutation({
      'patients/one/status': 'discharged',
    }, isPatch: true);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emissions.first.keys, ['one']);
    expect(emissions.last, isEmpty);
  });

  test('patient and stay payloads never persist legacy photo bytes', () async {
    await cache.replaceSnapshot('patients', {
      'one': {
        ...patient('one'),
        'photoRef': 'patientPhotos/one/patient',
        'photoDataUrl': 'data:image/jpeg;base64,${'A' * 1000}',
        'attendants': [
          {
            'name': 'A',
            'photoRef': 'patientPhotos/one/attendants/a',
            'photoDataUrl': 'data:image/jpeg;base64,${'B' * 1000}',
          },
        ],
      },
    });
    final cached = await cache.read('patients/one') as Map;
    expect(cached['photoRef'], 'patientPhotos/one/patient');
    expect(cached, isNot(contains('photoDataUrl')));
    expect(
      (cached['attendants'] as List).single,
      isNot(contains('photoDataUrl')),
    );
  });

  test('account switch removes the previous PII partition', () async {
    await cache.replaceSnapshot('patients', {'one': patient('one')});
    cache.deactivateAccount();
    expect(await cache.read('patients'), isNull);

    await cache.activateAccount('account-b');
    expect(await cache.read('patients'), isEmpty);
    await cache.activateAccount('account-a');
    expect(await cache.read('patients'), isEmpty);
  });

  test(
    'cache-aware auth startup activates SQLite and sign-out hides cached PII',
    () async {
      await cache.replaceSnapshot('patients', {'one': patient('one')});
      cache.deactivateAccount();
      expect(await cache.read('patients'), isNull);

      final firebaseAuth = _TestAuthService();
      final rtdb = FirebaseRTDBRestService(projectId: 'test');
      final auth = AuthService(
        authService: firebaseAuth,
        rtdbService: rtdb,
        persistentCache: cache,
      );

      final signedIn = auth.authStateChanges.first;
      firebaseAuth.controller.add(AuthUser(uid: 'account-a', email: 'a@test'));
      expect((await signedIn)?.uid, 'account-a');
      expect((await cache.read('patients') as Map).keys, ['one']);

      final signedOut = auth.authStateChanges.first;
      firebaseAuth.controller.add(null);
      expect(await signedOut, isNull);
      expect(await cache.read('patients'), isNull);

      await firebaseAuth.closeTestStream();
      firebaseAuth.dispose();
      rtdb.dispose();
    },
  );

  test('AuthWrapper subscribes to the cache-aware AuthService stream', () {
    final source = File(
      'lib/screens/auth/auth_wrapper.dart',
    ).readAsStringSync();
    expect(source, contains('ServiceLocator().authService.authStateChanges'));
    expect(
      source,
      isNot(contains('ServiceLocator().authRestService.authStateChanges')),
    );
  });

  test('failed server write is not persisted locally', () async {
    await cache.replaceSnapshot('patients', {'one': patient('one')});
    final client = MockClient(
      (_) async => http.Response('permission denied', 403),
    );
    final rtdb = FirebaseRTDBRestService(
      projectId: 'test',
      databaseUrl: 'https://example.test',
      httpClient: client,
      persistentCache: cache,
    );

    await expectLater(
      rtdb.patch('patients/one', {'status': 'discharged'}),
      throwsException,
    );
    final cached = await cache.read('patients/one') as Map;
    expect(cached['status'], 'active');
    rtdb.dispose();
  });

  test(
    'successful PATCH is server-first and performs no collection GET',
    () async {
      await cache.replaceSnapshot('patients', {'one': patient('one')});
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.method, 'PATCH');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['updatedAt'], {'.sv': 'timestamp'});
        return http.Response(
          jsonEncode({'status': 'discharged', 'updatedAt': 500}),
          200,
        );
      });
      final rtdb = FirebaseRTDBRestService(
        projectId: 'test',
        databaseUrl: 'https://example.test',
        httpClient: client,
        persistentCache: cache,
      );

      await rtdb.patch('patients/one', {'status': 'discharged'});
      final cached = await cache.read('patients/one') as Map;
      expect(cached['status'], 'discharged');
      expect(cached['updatedAt'], 500);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/patients/one.json');
      rtdb.dispose();
    },
  );

  test('cached stream returns data before any network request', () async {
    await cache.replaceSnapshot('patients', {'one': patient('one')});
    var networkReads = 0;
    final client = MockClient((request) async {
      networkReads++;
      return http.Response('{}', 200);
    });
    final rtdb = FirebaseRTDBRestService(
      projectId: 'test',
      databaseUrl: 'https://example.test',
      httpClient: client,
      persistentCache: cache,
    );

    final value = await rtdb
        .stream('patients', pollInterval: const Duration(days: 1))
        .first;
    expect((value as Map).keys, ['one']);
    expect(networkReads, 0);
    rtdb.dispose();
  });
}
