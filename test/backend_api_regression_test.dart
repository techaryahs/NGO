import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/services/backend_api_service.dart';

class _DelayedCache extends PersistentCache {
  _DelayedCache(super.database);

  final initialRead = Completer<dynamic>();
  bool delayNextRead = true;

  @override
  Future<dynamic> read(
    String path, {
    String? orderBy,
    dynamic equalTo,
    List<dynamic>? equalToAny,
  }) {
    if (delayNextRead) {
      delayNextRead = false;
      return initialRead.future;
    }
    return super.read(
      path,
      orderBy: orderBy,
      equalTo: equalTo,
      equalToAny: equalToAny,
    );
  }
}

class _DelayedAckCache extends PersistentCache {
  _DelayedAckCache(super.database);

  bool holdNext = false;
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();

  @override
  Future<void> replaceSnapshot(
    String path,
    dynamic value, {
    bool Function()? isCurrent,
  }) async {
    if (holdNext && path == 'patients/patient-a') {
      holdNext = false;
      writeStarted.complete();
      await releaseWrite.future;
    }
    await super.replaceSnapshot(path, value, isCurrent: isCurrent);
  }
}

void main() {
  late PersistentCache cache;
  final patient = <String, dynamic>{
    'id': 'synthetic-patient',
    'fullName': 'Synthetic patient',
    'registrationNumber': 'TEST-1',
    'updatedAt': 100,
  };

  setUp(() async {
    cache = PersistentCache(CacheDatabase(NativeDatabase.memory()));
    await cache.initialize();
    await cache.activateAccount('synthetic-account-a');
  });
  tearDown(() => cache.close());

  BackendApiService serviceFor(
    Future<http.Response> Function(http.Request) handler, {
    PersistentCache? selectedCache,
    Future<String?> Function()? getAuthToken,
  }) {
    final service = BackendApiService(
      baseUrl: 'https://backend.example/api',
      persistentCache: selectedCache ?? cache,
      client: MockClient(handler),
      getAuthToken: getAuthToken,
    );
    addTearDown(service.dispose);
    return service;
  }

  test(
    'older attendance range response cannot replace a newer range in SQLite or its caller',
    () async {
      final firstStarted = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final api = serviceFor((request) async {
        final call = ++calls;
        if (call == 1) {
          firstStarted.complete();
          await release.future;
        }
        return http.Response(
          jsonEncode({
            '2026-10-19': {
              'p': {
                'status': call == 1 ? 'Present' : 'Absent',
                'date': '2026-10-19',
              },
            },
          }),
          200,
        );
      });
      Future<Map<String, dynamic>> load() => api.getAttendanceRange(
        kind: 'attendance',
        startKey: '2026-10-01',
        endKey: '2026-10-31',
      );
      final old = load();
      await firstStarted.future;
      await load();
      release.complete();
      expect((await old)['2026-10-19']['p']['status'], 'Absent');
      expect(
        (await cache.read('attendance/daily/2026-10-19/p'))['status'],
        'Absent',
      );
    },
  );

  test(
    'older patient GET cannot resurrect a deleted patient for caller or cache',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var deleted = false;
      final api = serviceFor((request) async {
        if (request.method == 'DELETE') {
          deleted = true;
          return http.Response('{}', 200);
        }
        if (deleted) return http.Response('{}', 404);
        started.complete();
        await release.future;
        return http.Response(jsonEncode(patient), 200);
      });
      final old = api.get('patients/synthetic-patient');
      await started.future;
      await api.delete('patients/synthetic-patient');
      release.complete();
      expect(await old, isNull);
      expect(await cache.read('patients/synthetic-patient'), isNull);
    },
  );

  final supportedReads = <String, (String, Map<String, String>)>{
    'patients': (
      '/api/patients',
      {'format': 'map', 'limit': '500', 'offset': '0'},
    ),
    'patients/synthetic-patient': ('/api/patients/synthetic-patient', {}),
    'rooms': ('/api/rooms', {'format': 'map'}),
    'rooms/synthetic-room': ('/api/rooms/synthetic-room', {}),
    'stays': ('/api/stays', {'format': 'map'}),
    'stays/synthetic-stay': ('/api/stays/synthetic-stay', {}),
    'payments': (
      '/api/payments',
      {'format': 'map', 'limit': '500', 'offset': '0'},
    ),
    'paymentHistory/synthetic-payment': ('/api/payments/synthetic-payment', {}),
    'admin_settings/pricing': ('/api/settings/pricing', {}),
    'admin_settings/pricing/dailyRate': ('/api/settings/pricing/dailyRate', {}),
    'system_counters/registrationNumber': (
      '/api/counters/registrationNumber',
      {},
    ),
    'patientPhotos/synthetic-patient/patient': (
      '/api/photos/synthetic-patient/patient',
      {},
    ),
  };
  for (final entry in supportedReads.entries) {
    test('supported read contract: ${entry.key}', () async {
      final service = serviceFor((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, entry.value.$1);
        expect(request.url.queryParameters, entry.value.$2);
        expect(request.headers['authorization'], 'Bearer synthetic-token');
        return http.Response('{}', 200);
      }, getAuthToken: () async => 'synthetic-token');
      await service.get(entry.key);
    });
  }

  for (final kind in ['attendance', 'attendant_attendance']) {
    test(
      '$kind daily date read matches API query and SQLite date shape',
      () async {
        final payload = {
          'synthetic-patient': {'status': 'Present'},
        };
        final service = serviceFor((request) async {
          expect(request.url.path, '/api/attendance');
          expect(request.url.queryParameters, {
            'kind': kind,
            'date': '2026-10-16',
            'format': 'map',
          });
          return http.Response(jsonEncode(payload), 200);
        });
        expect(await service.get('$kind/daily/2026-10-16'), payload);
        expect(await cache.read('$kind/daily/2026-10-16'), payload);
      },
    );
  }

  test(
    'attendance patient read unwraps API map and cache targets that patient',
    () async {
      final payload = {'status': 'Present'};
      await cache.replaceSnapshot('attendance/daily/2026-10-16', {
        'other-synthetic-patient': {'status': 'Absent'},
      });
      final service = serviceFor((request) async {
        expect(request.url.queryParameters['date'], '2026-10-16');
        expect(request.url.queryParameters['patientId'], 'synthetic-patient');
        return http.Response(jsonEncode({'synthetic-patient': payload}), 200);
      });
      expect(
        await service.get('attendance/daily/2026-10-16/synthetic-patient'),
        payload,
      );
      expect(
        await cache.read('attendance/daily/2026-10-16/synthetic-patient'),
        payload,
      );
      expect(
        await cache.read('attendance/daily/2026-10-16/other-synthetic-patient'),
        {'status': 'Absent'},
      );
    },
  );

  test('attendance root read retains daily and date nesting', () async {
    final dates = {
      '2026-10-16': {
        'synthetic-patient': {'status': 'Present'},
      },
    };
    final service = serviceFor((request) async {
      expect(request.url.queryParameters, {
        'kind': 'attendance',
        'format': 'map',
      });
      return http.Response(jsonEncode(dates), 200);
    });
    expect(await service.get('attendance'), {'daily': dates});
    expect(await service.get('attendance/daily'), dates);
  });

  for (final status in [400, 401, 403, 409]) {
    test('GET $status cannot be masked by cached patient data', () async {
      await cache.replaceSnapshot('patients/synthetic-patient', patient);
      final service = serviceFor((_) async => http.Response('denied', status));
      await expectLater(
        service.get('patients/synthetic-patient'),
        throwsA(isA<HttpException>()),
      );
    });
  }

  test(
    'attendance range network failure uses only the current cached date window',
    () async {
      for (final date in [
        '2026-10-15',
        '2026-10-16',
        '2026-10-17',
        '2026-10-18',
      ]) {
        await cache.replaceSnapshot('attendance/daily/$date', {
          'synthetic-patient': {'status': 'Present', 'date': date},
        });
      }
      final service = serviceFor(
        (_) async => throw http.ClientException('offline'),
      );
      expect(
        await service.getAttendanceRange(
          kind: 'attendance',
          startKey: '2026-10-16',
          endKey: '2026-10-17',
        ),
        {
          for (final date in ['2026-10-16', '2026-10-17'])
            date: {
              'synthetic-patient': {'status': 'Present', 'date': date},
            },
        },
      );
    },
  );

  test('server error body is not exposed in client exceptions', () async {
    final service = serviceFor(
      (_) async => http.Response('postgres-password-sensitive-detail', 500),
    );
    await expectLater(
      service.get('patients/synthetic-patient'),
      throwsA(
        predicate<Object>(
          (e) =>
              e is HttpException &&
              !e.toString().contains('postgres-password-sensitive-detail'),
        ),
      ),
    );
  });

  test('network failure can use the current account SQLite cache', () async {
    await cache.replaceSnapshot('patients/synthetic-patient', patient);
    final service = serviceFor(
      (_) async => throw http.ClientException('offline'),
    );
    expect(await service.get('patients/synthetic-patient'), patient);
  });

  test('500 can use the current account SQLite cache', () async {
    await cache.replaceSnapshot('patients/synthetic-patient', patient);
    final service = serviceFor((_) async => http.Response('unavailable', 500));
    expect(await service.get('patients/synthetic-patient'), patient);
  });

  test(
    'explicit refresh cannot present offline cache as an authoritative balance',
    () async {
      await cache.replaceSnapshot('patients/synthetic-patient', patient);
      final service = serviceFor(
        (_) async => http.Response('unavailable', 503),
      );
      await expectLater(
        service.refresh('patients/synthetic-patient'),
        throwsA(
          isA<BackendApiException>().having((e) => e.statusCode, 'status', 503),
        ),
      );
      expect(await cache.read('patients/synthetic-patient'), patient);
    },
  );

  for (final status in [400, 401, 403, 409]) {
    test('attendance range $status cannot be masked by SQLite', () async {
      await cache.replaceSnapshot('attendance/daily/2026-10-16', {
        'synthetic-patient': {'status': 'Present'},
      });
      final service = serviceFor((_) async => http.Response('denied', status));
      await expectLater(
        service.getAttendanceRange(
          kind: 'attendance',
          startKey: '2026-10-16',
          endKey: '2026-10-17',
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'status',
            status,
          ),
        ),
      );
    });
  }

  test(
    'attendance range replaces the authoritative date window only',
    () async {
      for (final date in ['2026-10-15', '2026-10-16', '2026-10-17']) {
        await cache.replaceSnapshot('attendance/daily/$date', {
          'synthetic-patient': {'status': 'Present', 'date': date},
        });
      }
      final fresh = {
        '2026-10-16': {
          'synthetic-patient': {'status': 'Absent', 'date': '2026-10-16'},
        },
      };
      final service = serviceFor((request) async {
        expect(request.url.queryParameters, {
          'kind': 'attendance',
          'startDate': '2026-10-16',
          'endDate': '2026-10-17',
          'format': 'map',
        });
        return http.Response(jsonEncode(fresh), 200);
      });
      expect(
        await service.getAttendanceRange(
          kind: 'attendance',
          startKey: '2026-10-16',
          endKey: '2026-10-17',
        ),
        fresh,
      );
      expect(
        await cache.read('attendance/daily/2026-10-16'),
        fresh['2026-10-16'],
      );
      expect(await cache.read('attendance/daily/2026-10-17'), isEmpty);
      expect(await cache.read('attendance/daily/2026-10-15'), isNotEmpty);
    },
  );

  test(
    'attendance range from a previous account cannot populate the new partition',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final service = serviceFor((_) {
        requested.complete();
        return response.future;
      });
      final result = service.getAttendanceRange(
        kind: 'attendance',
        startKey: '2026-10-16',
        endKey: '2026-10-17',
      );
      final assertion = expectLater(result, throwsStateError);
      await requested.future;
      await cache.activateAccount('synthetic-account-b');
      response.complete(
        http.Response(
          jsonEncode({
            '2026-10-16': {
              'synthetic-patient': {'status': 'Present'},
            },
          }),
          200,
        ),
      );
      await assertion;
      expect(await cache.read('attendance/daily/2026-10-16'), isEmpty);
    },
  );

  test('request timeout can use acknowledged cache', () async {
    await cache.replaceSnapshot('patients/synthetic-patient', patient);
    final service = serviceFor(
      (_) async => throw TimeoutException('simulated deadline'),
    );
    expect(await service.get('patients/synthetic-patient'), patient);
  });

  test(
    'malformed successful JSON is surfaced instead of stale fallback',
    () async {
      await cache.replaceSnapshot('patients/synthetic-patient', patient);
      final service = serviceFor((_) async => http.Response('{broken', 200));
      await expectLater(
        service.get('patients/synthetic-patient'),
        throwsFormatException,
      );
    },
  );

  test('404 evicts previously cached patient', () async {
    await cache.replaceSnapshot('patients/synthetic-patient', patient);
    final service = serviceFor((_) async => http.Response('{}', 404));
    expect(await service.get('patients/synthetic-patient'), isNull);
    expect(await cache.read('patients/synthetic-patient'), isNull);
  });

  test('server null clears cached collection', () async {
    await cache.replaceSnapshot('patients', {'synthetic-patient': patient});
    final service = serviceFor((_) async => http.Response('null', 200));
    expect(await service.get('patients'), isNull);
    expect(await cache.read('patients'), isEmpty);
  });

  test(
    'PUT caches server representation including normalized fields',
    () async {
      final saved = {
        ...patient,
        'fullName': 'Server normalized',
        'updatedAt': 200,
      };
      final service = serviceFor(
        (_) async => http.Response(jsonEncode(saved), 200),
      );
      await service.put('patients/synthetic-patient', patient);
      expect(await cache.read('patients/synthetic-patient'), saved);
    },
  );

  test(
    'PATCH uses supported PUT endpoint and caches server representation',
    () async {
      await cache.replaceSnapshot('patients/synthetic-patient', patient);
      final saved = {...patient, 'fullName': 'Updated', 'updatedAt': 300};
      final service = serviceFor((request) async {
        expect(request.method, 'PUT');
        expect(jsonDecode(request.body), {'fullName': 'Updated'});
        return http.Response(jsonEncode(saved), 200);
      });
      await service.patch('patients/synthetic-patient', {
        'fullName': 'Updated',
      });
      expect(await cache.read('patients/synthetic-patient'), saved);
    },
  );

  test('failed write leaves acknowledged cache unchanged', () async {
    await cache.replaceSnapshot('patients/synthetic-patient', patient);
    final service = serviceFor((_) async => http.Response('{}', 409));
    await expectLater(
      service.patch('patients/synthetic-patient', {'fullName': 'rejected'}),
      throwsA(isA<HttpException>()),
    );
    expect(await cache.read('patients/synthetic-patient'), patient);
  });

  test(
    'successful response without entity invalidates instead of guessing state',
    () async {
      await cache.replaceSnapshot('patients/synthetic-patient', patient);
      final service = serviceFor((_) async => http.Response('', 204));
      await service.patch('patients/synthetic-patient', {
        'fullName': 'unknown result',
      });
      expect(await cache.read('patients/synthetic-patient'), isNull);
    },
  );

  test('POST cannot invent a record ID when server omits it', () async {
    final service = serviceFor((_) async => http.Response('{}', 201));
    await expectLater(service.push('patients', patient), throwsFormatException);
  });

  test('POST caches authoritative created record', () async {
    final saved = {...patient, 'updatedAt': 500};
    final service = serviceFor(
      (_) async => http.Response(jsonEncode(saved), 201),
    );
    expect(await service.push('patients', patient), 'synthetic-patient');
    expect(await cache.read('patients/synthetic-patient'), saved);
  });

  test(
    'caller retry after lost write response retains the submitted ID',
    () async {
      final submitted = <Map<String, dynamic>>[];
      final service = serviceFor((request) async {
        submitted.add(
          Map<String, dynamic>.from(jsonDecode(request.body) as Map),
        );
        if (submitted.length == 1) throw http.ClientException('response lost');
        return http.Response(jsonEncode(patient), 200);
      });
      await expectLater(
        service.push('patients', patient),
        throwsA(isA<http.ClientException>()),
      );
      expect(await cache.read('patients/synthetic-patient'), isNull);
      expect(await service.push('patients', patient), 'synthetic-patient');
      expect(submitted, [patient, patient]);
      expect(await cache.read('patients/synthetic-patient'), patient);
    },
  );

  test('idempotent 404 DELETE also evicts local record', () async {
    await cache.replaceSnapshot('patients/synthetic-patient', patient);
    final service = serviceFor((_) async => http.Response('{}', 404));
    await service.delete('patients/synthetic-patient');
    expect(await cache.read('patients/synthetic-patient'), isNull);
  });

  test(
    'auth provider failures do not send an anonymous request or use cache',
    () async {
      await cache.replaceSnapshot('patients/synthetic-patient', patient);
      var requests = 0;
      final service = serviceFor((_) async {
        requests++;
        return http.Response('{}', 401);
      }, getAuthToken: () async => throw StateError('token unavailable'));
      await expectLater(
        service.get('patients/synthetic-patient'),
        throwsStateError,
      );
      expect(requests, 0);
    },
  );

  test(
    'missing configured auth token fails without HTTP or cache fallback',
    () async {
      await cache.replaceSnapshot('patients/synthetic-patient', patient);
      var requests = 0;
      final service = serviceFor((_) async {
        requests++;
        return http.Response('{}', 401);
      }, getAuthToken: () async => null);
      await expectLater(
        service.get('patients/synthetic-patient'),
        throwsA(isA<HttpException>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'response from previous account is not returned or cached in new partition',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final service = serviceFor((_) {
        requested.complete();
        return response.future;
      });
      final request = service.get('patients/synthetic-patient');
      final assertion = expectLater(request, throwsStateError);
      await requested.future;
      await cache.activateAccount('synthetic-account-b');
      response.complete(http.Response(jsonEncode(patient), 200));
      await assertion;
      expect(await cache.read('patients/synthetic-patient'), isNull);
    },
  );

  test(
    'acknowledged write from previous account cannot contaminate new cache',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final service = serviceFor((_) {
        requested.complete();
        return response.future;
      });
      final request = service.put('patients/synthetic-patient', patient);
      await requested.future;
      await cache.activateAccount('synthetic-account-b');
      response.complete(http.Response(jsonEncode(patient), 200));
      await request;
      expect(await cache.read('patients/synthetic-patient'), isNull);
    },
  );

  test(
    'older in-flight read cannot replace a newer acknowledged write in cache',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final saved = {...patient, 'fullName': 'Newer write', 'updatedAt': 600};
      final service = serviceFor((request) {
        if (request.method == 'GET') {
          requested.complete();
          return response.future;
        }
        return Future.value(http.Response(jsonEncode(saved), 200));
      });
      final oldRead = service.get('patients/synthetic-patient');
      await requested.future;
      await service.put('patients/synthetic-patient', saved);
      response.complete(http.Response(jsonEncode(patient), 200));
      await oldRead;
      expect(await cache.read('patients/synthetic-patient'), saved);
    },
  );

  test(
    'delayed cache hydration cannot follow a newer server stream value',
    () async {
      await cache.close();
      final delayed = _DelayedCache(CacheDatabase(NativeDatabase.memory()));
      cache = delayed;
      await delayed.initialize();
      await delayed.activateAccount('synthetic-account-a');
      final service = serviceFor(
        (_) async => http.Response(jsonEncode(patient), 200),
        selectedCache: delayed,
      );
      final values = <dynamic>[];
      final freshArrived = Completer<void>();
      final subscription = service.stream('patients/synthetic-patient').listen((
        value,
      ) {
        values.add(value);
        if (!freshArrived.isCompleted) freshArrived.complete();
      });
      addTearDown(subscription.cancel);
      await freshArrived.future;
      delayed.initialRead.complete({...patient, 'fullName': 'Stale cache'});
      await Future<void>.delayed(Duration.zero);
      expect(values, [patient]);
    },
  );

  test(
    'slow polling never overlaps requests and cancel stops timers',
    () async {
      var requests = 0;
      final response = Completer<http.Response>();
      final service = serviceFor((_) {
        requests++;
        return response.future;
      });
      final subscription = service
          .stream('patients', pollInterval: const Duration(milliseconds: 2))
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(requests, 1);
      await subscription.cancel();
      response.complete(http.Response('{}', 200));
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(requests, 1);
    },
  );

  test(
    'late shared room subscriber receives the latest value before the 10-second poll',
    () async {
      final room = {
        'synthetic-room': {'id': 'synthetic-room', 'roomNumber': 'QA'},
      };
      var requests = 0;
      final service = serviceFor((_) async {
        requests++;
        return http.Response(jsonEncode(room), 200);
      });
      final loaded = Completer<void>();
      final subscription = service.stream('rooms').listen((value) {
        if (value is Map &&
            value.containsKey('synthetic-room') &&
            !loaded.isCompleted) {
          loaded.complete();
        }
      });
      addTearDown(subscription.cancel);
      await loaded.future;
      expect(
        await service
            .stream('rooms')
            .first
            .timeout(const Duration(milliseconds: 500)),
        room,
      );
      expect(
        requests,
        1,
        reason:
            'A late subscriber should replay the shared result without another collection GET.',
      );
    },
  );

  test(
    'cold room stream waits for its real server value instead of empty SQLite',
    () async {
      final room = {
        'synthetic-room': {'id': 'synthetic-room', 'roomNumber': 'QA'},
      };
      final response = Completer<http.Response>();
      final service = serviceFor((_) => response.future);
      var completed = false;
      final first = service.stream('rooms').first.then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, isFalse);
      response.complete(http.Response(jsonEncode(room), 200));
      expect(await first, room);
    },
  );

  test('shared replay never crosses an account change', () async {
    var accountRoom = 'account-a-room';
    final service = serviceFor(
      (_) async => http.Response(
        jsonEncode({
          accountRoom: {'id': accountRoom},
        }),
        200,
      ),
    );
    final loaded = Completer<void>();
    final subscription = service.stream('rooms').listen((value) {
      if (value is Map &&
          value.containsKey('account-a-room') &&
          !loaded.isCompleted) {
        loaded.complete();
      }
    });
    addTearDown(subscription.cancel);
    await loaded.future;
    await cache.activateAccount('synthetic-account-b');
    accountRoom = 'account-b-room';
    expect(
      await service
          .stream('rooms')
          .first
          .timeout(const Duration(milliseconds: 500)),
      {
        'account-b-room': {'id': 'account-b-room'},
      },
    );
  });

  test('stream errors reach both current and late subscribers', () async {
    final service = serviceFor((_) async => http.Response('denied', 403));
    final firstError = Completer<void>();
    final subscription = service
        .stream('rooms')
        .listen(
          (_) {},
          onError: (Object error) {
            if (!firstError.isCompleted) firstError.complete();
          },
        );
    addTearDown(subscription.cancel);
    await firstError.future;
    await expectLater(
      service.stream('rooms').first.timeout(const Duration(milliseconds: 500)),
      throwsA(
        isA<BackendApiException>().having((e) => e.statusCode, 'status', 403),
      ),
    );
  });

  test(
    'payment ACK refreshes one affected patient without collection reloads',
    () async {
      final saved = {
        ...patient,
        'totalPaidAmount': 200,
        'currentDueAmount': 300,
        'updatedAt': 800,
      };
      var paid = false;
      final reads = <String>[];
      final service = serviceFor((request) async {
        if (request.method == 'POST') {
          paid = true;
          return http.Response(
            jsonEncode({
              'id': 'synthetic-payment',
              'patientId': 'synthetic-patient',
              'amount': 200,
            }),
            201,
          );
        }
        reads.add(request.url.path);
        final displayed = paid ? saved : patient;
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/patients')
                ? {'synthetic-patient': displayed}
                : displayed,
          ),
          200,
        );
      });
      final loaded = Completer<void>();
      final updated = Completer<void>();
      final subscription = service.stream('patients').listen((value) {
        if (value is! Map || value['synthetic-patient'] is! Map) return;
        if (!loaded.isCompleted) loaded.complete();
        if (value['synthetic-patient']['totalPaidAmount'] == 200 &&
            !updated.isCompleted) {
          updated.complete();
        }
      });
      addTearDown(subscription.cancel);
      await loaded.future;
      await service.createPayment({
        'id': 'synthetic-payment',
        'patientId': 'synthetic-patient',
        'amount': 200,
      });
      await updated.future.timeout(const Duration(milliseconds: 500));
      expect(reads, ['/api/patients', '/api/patients/synthetic-patient']);
      expect(await cache.read('patients/synthetic-patient'), saved);
    },
  );

  test(
    'mutation acknowledgement updates active entity and collection streams immediately',
    () async {
      final saved = {
        ...patient,
        'fullName': 'Authoritative updated patient',
        'updatedAt': 700,
      };
      var reads = 0;
      final service = serviceFor((request) async {
        if (request.method == 'PUT') {
          return http.Response(jsonEncode(saved), 200);
        }
        reads++;
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/patients')
                ? {'synthetic-patient': patient}
                : patient,
          ),
          200,
        );
      });
      final recordLoaded = Completer<void>();
      final collectionLoaded = Completer<void>();
      final recordUpdated = Completer<void>();
      final collectionUpdated = Completer<void>();
      final recordSubscription = service
          .stream('patients/synthetic-patient')
          .listen((value) {
            if (value is! Map) return;
            if (value['fullName'] == patient['fullName'] &&
                !recordLoaded.isCompleted) {
              recordLoaded.complete();
            }
            if (value['fullName'] == saved['fullName'] &&
                !recordUpdated.isCompleted) {
              recordUpdated.complete();
            }
          });
      final collectionSubscription = service.stream('patients').listen((value) {
        if (value is! Map || value['synthetic-patient'] is! Map) return;
        if (value['synthetic-patient']['fullName'] == patient['fullName'] &&
            !collectionLoaded.isCompleted) {
          collectionLoaded.complete();
        }
        if (value['synthetic-patient']['fullName'] == saved['fullName'] &&
            !collectionUpdated.isCompleted) {
          collectionUpdated.complete();
        }
      });
      addTearDown(recordSubscription.cancel);
      addTearDown(collectionSubscription.cancel);
      await Future.wait([recordLoaded.future, collectionLoaded.future]);
      await service.patch('patients/synthetic-patient', {
        'fullName': 'Client submitted name',
      });
      await Future.wait([
        recordUpdated.future,
        collectionUpdated.future,
      ]).timeout(const Duration(milliseconds: 500));
      expect(
        reads,
        2,
        reason:
            'The mutation already contains the authoritative patient; do not refetch entire collections.',
      );
    },
  );

  test(
    'concurrent unrelated ACKs both update their record cache and streams',
    () async {
      await cache.close();
      final delayed = _DelayedAckCache(CacheDatabase(NativeDatabase.memory()));
      cache = delayed;
      await cache.initialize();
      await cache.activateAccount('synthetic-account-a');
      final initial = {
        for (final id in ['patient-a', 'patient-b']) id: {...patient, 'id': id},
      };
      final saved = {
        for (final id in initial.keys)
          id: {...initial[id]!, 'fullName': 'Updated $id', 'updatedAt': 900},
      };
      final service = serviceFor((request) async {
        final id = request.url.path.split('/').last;
        return http.Response(
          jsonEncode(request.method == 'GET' ? initial[id] : saved[id]),
          200,
        );
      }, selectedCache: delayed);
      final loaded = {for (final id in initial.keys) id: Completer<void>()};
      final latest = <String, dynamic>{};
      for (final id in initial.keys) {
        final sub = service.stream('patients/$id').listen((value) {
          latest[id] = value;
          if (!loaded[id]!.isCompleted) loaded[id]!.complete();
        });
        addTearDown(sub.cancel);
      }
      await Future.wait(loaded.values.map((value) => value.future));
      delayed.holdNext = true;
      final first = service.put('patients/patient-a', saved['patient-a']!);
      await delayed.writeStarted.future;
      await service.put('patients/patient-b', saved['patient-b']!);
      delayed.releaseWrite.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      for (final id in initial.keys) {
        expect(await cache.read('patients/$id'), saved[id]);
        expect(latest[id], saved[id]);
      }
    },
  );

  test('payment deletion refreshes only its known patient balance', () async {
    await cache.replaceSnapshot('payments/synthetic-payment', {
      'id': 'synthetic-payment',
      'patientId': 'synthetic-patient',
      'amount': 200,
    });
    var deleted = false;
    final reads = <String>[];
    final updated = Completer<void>();
    final loaded = Completer<void>();
    final service = serviceFor((request) async {
      if (request.method == 'DELETE') {
        deleted = true;
        return http.Response('', 204);
      }
      reads.add(request.url.path);
      final displayed = deleted
          ? {...patient, 'totalPaidAmount': 0, 'currentDueAmount': 500}
          : patient;
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/patients')
              ? {'synthetic-patient': displayed}
              : displayed,
        ),
        200,
      );
    });
    final subscription = service.stream('patients').listen((value) {
      if (value is! Map || value['synthetic-patient'] is! Map) return;
      if (!loaded.isCompleted) loaded.complete();
      if (value['synthetic-patient']['currentDueAmount'] == 500 &&
          !updated.isCompleted) {
        updated.complete();
      }
    });
    addTearDown(subscription.cancel);
    await loaded.future;
    await service.delete('payments/synthetic-payment');
    await updated.future.timeout(const Duration(milliseconds: 500));
    expect(reads, ['/api/patients', '/api/patients/synthetic-patient']);
    expect(await cache.read('payments/synthetic-payment'), isNull);
  });

  test('dispose closes active streams and cancels their polling', () async {
    var requests = 0;
    final service = serviceFor((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    final subscription = service
        .stream('patients', pollInterval: const Duration(milliseconds: 2))
        .listen((_) {});
    final completed = subscription.asFuture<void>();
    service.dispose();
    await completed;
    final afterDispose = requests;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(requests, afterDispose);
  });
}
