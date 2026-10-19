import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/services/backend_api_service.dart';

void main() {
  late PersistentCache cache;

  setUp(() async {
    cache = PersistentCache(CacheDatabase(NativeDatabase.memory()));
    await cache.initialize();
    await cache.activateAccount('synthetic-pagination-account');
  });
  tearDown(() => cache.close());

  BackendApiService serviceFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final service = BackendApiService(
      baseUrl: 'https://backend.example/api',
      persistentCache: cache,
      getAuthToken: () async => 'synthetic-token',
      client: MockClient(handler),
    );
    addTearDown(service.dispose);
    return service;
  }

  List<Map<String, dynamic>> rowsFor(String collection, int count) => [
    for (var i = count; i > 0; i--)
      {
        'id': 'synthetic-$collection-${i.toString().padLeft(5, '0')}',
        'fullName': 'Synthetic patient $i',
        'patientId': 'synthetic-patient',
        'amount': i,
        'admissionDate': i,
        'date': i,
      },
  ];

  http.Response pageResponse(
    List<Map<String, dynamic>> rows,
    int start,
    int limit, {
    bool asArray = false,
    bool cursorMode = true,
  }) {
    final selected = rows.skip(start).take(limit).toList();
    return http.Response(
      jsonEncode(
        asArray
            ? selected
            : {for (final row in selected) row['id'] as String: row},
      ),
      200,
      headers: {
        if (cursorMode) 'x-pagination-mode': 'cursor',
        if (cursorMode && start + selected.length < rows.length)
          'x-next-cursor': 'synthetic-cursor-${start + selected.length}',
      },
    );
  }

  for (final collection in ['patients', 'payments', 'paymentHistory']) {
    test(
      '$collection reads all 1201 records in ordered bounded pages',
      () async {
        final rows = rowsFor(collection, 1201);
        final requests = <Uri>[];
        final service = serviceFor((request) async {
          requests.add(request.url);
          expect(request.headers['authorization'], 'Bearer synthetic-token');
          expect(request.url.queryParameters['limit'], '500');
          expect(request.url.queryParameters['format'], 'map');
          final cursor = request.url.queryParameters['cursor'];
          final start = cursor == null ? 0 : int.parse(cursor.split('-').last);
          expect(
            request.url.queryParameters['offset'],
            cursor == null ? '0' : null,
          );
          return pageResponse(rows, start, 500);
        });
        final result = await service.get(collection) as Map;
        expect(result.keys.toList(), rows.map((row) => row['id']).toList());
        expect(result.length, 1201);
        expect(requests, hasLength(3));
        expect(await cache.read(collection), hasLength(1201));
      },
    );
  }

  test(
    'cursor marker ends an exactly full final page without extra GET',
    () async {
      final rows = rowsFor('patients', 1000);
      var calls = 0;
      final service = serviceFor((request) async {
        final start = calls++ * 500;
        return pageResponse(rows, start, 500);
      });
      expect(await service.get('patients'), hasLength(1000));
      expect(calls, 2);
    },
  );

  test(
    'filtered array collection keeps filters and representation on every page',
    () async {
      final rows = rowsFor('patients', 1101);
      var calls = 0;
      final service = serviceFor((request) async {
        final query = request.url.queryParameters;
        expect(query['format'], 'array');
        expect(query['status'], 'Active');
        expect(query['search'], 'Synthetic & test');
        return pageResponse(rows, calls++ * 500, 500, asArray: true);
      });
      final result = await service.get(
        'patients?status=Active&search=Synthetic%20%26%20test&format=array',
      );
      expect(result, rows);
      expect(calls, 3);
    },
  );

  for (final query in [
    'limit=7',
    'offset=7',
    'limit=7&offset=21',
    'cursor=manual',
  ]) {
    test(
      'explicit page query $query remains one caller-controlled request',
      () async {
        var calls = 0;
        final service = serviceFor((request) async {
          calls++;
          expect(request.url.queryParameters, {
            'format': 'map',
            'patientId': 'synthetic-patient',
            ...Uri.splitQueryString(query),
          });
          return http.Response(
            '{}',
            200,
            headers: {'x-next-cursor': 'ignored'},
          );
        });
        expect(
          await service.get('payments?patientId=synthetic-patient&$query'),
          isEmpty,
        );
        expect(calls, 1);
      },
    );
  }

  test(
    'legacy offset pages overlap to verify boundaries and retain ordering',
    () async {
      final rows = rowsFor('payments', 1501);
      final offsets = <int>[];
      final service = serviceFor((request) async {
        final query = request.url.queryParameters;
        final start = int.parse(query['offset']!);
        final limit = int.parse(query['limit']!);
        offsets.add(start);
        expect(limit, lessThanOrEqualTo(501));
        return pageResponse(rows, start, limit, cursorMode: false);
      });
      final result = await service.get('payments') as Map;
      expect(result.keys.toList(), rows.map((row) => row['id']).toList());
      expect(offsets, [0, 499, 999, 1499]);
    },
  );

  test(
    'cursor continues after the boundary row is deleted between pages',
    () async {
      final rows = rowsFor('patients', 1101);
      final originalIds = rows.map((row) => row['id']).toList();
      final deletedId = rows[499]['id'];
      var calls = 0;
      final service = serviceFor((request) async {
        calls++;
        final cursor = request.url.queryParameters['cursor'];
        // A keyset server compares against the cursor's ordering value; it
        // does not need to look up the now-deleted boundary row.
        final selected = rows
            .where(
              (row) =>
                  cursor == null || (row['id'] as String).compareTo(cursor) < 0,
            )
            .take(500)
            .toList();
        final lastId = selected.last['id'] as String;
        final hasMore = rows.any(
          (row) => (row['id'] as String).compareTo(lastId) < 0,
        );
        final response = http.Response(
          jsonEncode({for (final row in selected) row['id'] as String: row}),
          200,
          headers: {
            'x-pagination-mode': 'cursor',
            if (hasMore) 'x-next-cursor': lastId,
          },
        );
        if (calls == 1) rows.removeWhere((row) => row['id'] == deletedId);
        return response;
      });
      final result = await service.get('patients') as Map;
      expect(rows, hasLength(1100));
      expect(result.keys.toList(), originalIds);
      expect(calls, 3);
    },
  );

  for (final status in [404, 503]) {
    test(
      'later page HTTP $status preserves the previous complete SQLite snapshot',
      () async {
        final saved = {
          'cached-patient': {'id': 'cached-patient', 'fullName': 'Saved'},
        };
        await cache.replaceSnapshot('patients', saved);
        final rows = rowsFor('patients', 1201);
        var calls = 0;
        final service = serviceFor((_) async {
          if (calls++ == 0) return pageResponse(rows, 0, 500);
          return http.Response('failed later page', status);
        });
        await expectLater(
          service.get('patients', allowCacheFallback: false),
          throwsA(
            isA<BackendApiException>().having(
              (e) => e.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(await cache.read('patients'), saved);
      },
    );
  }

  test(
    'later transient page failure falls back only to the old complete snapshot',
    () async {
      final saved = {
        'cached-patient': {'id': 'cached-patient', 'fullName': 'Saved'},
      };
      await cache.replaceSnapshot('patients', saved);
      var calls = 0;
      final service = serviceFor((_) async {
        if (calls++ == 0) return pageResponse(rowsFor('patients', 600), 0, 500);
        return http.Response('unavailable', 503);
      });
      expect(await service.get('patients'), saved);
      expect(await cache.read('patients'), saved);
    },
  );

  for (final cursorMode in [false, true]) {
    test(
      'server ignoring ${cursorMode ? 'cursor' : 'offset'} pagination fails instead of looping',
      () async {
        var calls = 0;
        final service = serviceFor((_) async {
          calls++;
          return pageResponse(
            rowsFor('patients', 600),
            0,
            500,
            cursorMode: cursorMode,
          );
        });
        await expectLater(service.get('patients'), throwsStateError);
        expect(calls, 2);
        expect(await cache.read('patients'), isEmpty);
      },
    );
  }

  test(
    'legacy page shift from deletion fails without caching missing rows',
    () async {
      final rows = rowsFor('patients', 1201);
      var calls = 0;
      final service = serviceFor((_) async {
        if (calls++ == 0) return pageResponse(rows, 0, 500, cursorMode: false);
        return pageResponse(rows.skip(1).toList(), 499, 501, cursorMode: false);
      });
      await expectLater(service.get('patients'), throwsStateError);
      expect(await cache.read('patients'), isEmpty);
    },
  );

  test(
    'account change during a later page cancels without populating new cache',
    () async {
      final secondRequested = Completer<void>();
      final secondResponse = Completer<http.Response>();
      final rows = rowsFor('patients', 1001);
      var calls = 0;
      final service = serviceFor((_) async {
        if (calls++ == 0) return pageResponse(rows, 0, 500);
        secondRequested.complete();
        return secondResponse.future;
      });
      final result = service.get('patients');
      final assertion = expectLater(result, throwsStateError);
      await secondRequested.future;
      await cache.activateAccount('synthetic-pagination-other-account');
      secondResponse.complete(pageResponse(rows, 500, 500));
      await assertion;
      expect(calls, 2);
      expect(await cache.read('patients'), isEmpty);
    },
  );

  test(
    'acknowledged mutation during paging keeps its newer SQLite representation',
    () async {
      final rows = rowsFor('patients', 501);
      final id = rows.first['id'] as String;
      final saved = {...rows.first, 'fullName': 'Acknowledged newer name'};
      final secondRequested = Completer<void>();
      final secondResponse = Completer<http.Response>();
      final service = serviceFor((request) async {
        if (request.method == 'PUT') {
          rows[0] = saved;
          return http.Response(jsonEncode(saved), 200);
        }
        if (!request.url.queryParameters.containsKey('cursor')) {
          return pageResponse(rows, 0, 500);
        }
        if (!secondRequested.isCompleted) secondRequested.complete();
        return secondResponse.future;
      });
      final read = service.get('patients');
      await secondRequested.future;
      await service.put('patients/$id', {'fullName': saved['fullName']});
      secondResponse.complete(pageResponse(rows, 500, 500));
      expect(await read, hasLength(501));
      expect(await cache.read('patients/$id'), saved);
    },
  );

  group('patient-filtered attendance ranges', () {
    Future<void> seedAttendance() async {
      for (final date in ['2026-10-15', '2026-10-16', '2026-10-17']) {
        await cache.replaceSnapshot('attendance/daily/$date', {
          'synthetic-target': {'status': 'Present'},
          'synthetic-other': {'status': 'Present'},
        });
      }
    }

    test(
      'SQLite filters the patient before decoding other patient payloads',
      () async {
        await seedAttendance();
        await cache.database.customStatement(
          'UPDATE cached_attendance SET payload = ? WHERE patient_id = ?',
          ['{intentionally-invalid-other-patient-json', 'synthetic-other'],
        );
        expect(
          await cache.readKeyRange(
            'attendance/daily',
            startKey: '2026-10-16',
            endKey: '2026-10-17',
            patientId: 'synthetic-target',
          ),
          {
            for (final date in ['2026-10-16', '2026-10-17'])
              date: {
                'synthetic-target': {'status': 'Present'},
              },
          },
        );
      },
    );

    test(
      'reconciles only the selected patient within the requested date window',
      () async {
        await seedAttendance();
        final fresh = {
          '2026-10-16': {
            'synthetic-target': {'status': 'Absent'},
          },
        };
        final service = serviceFor((request) async {
          expect(request.url.queryParameters, {
            'kind': 'attendance',
            'startDate': '2026-10-16',
            'endDate': '2026-10-17',
            'format': 'map',
            'patientId': 'synthetic-target',
          });
          return http.Response(jsonEncode(fresh), 200);
        });
        expect(
          await service.getAttendanceRange(
            kind: 'attendance',
            startKey: '2026-10-16',
            endKey: '2026-10-17',
            patientId: 'synthetic-target',
            allowCacheFallback: false,
          ),
          fresh,
        );
        expect(await cache.read('attendance/daily/2026-10-16'), {
          'synthetic-target': {'status': 'Absent'},
          'synthetic-other': {'status': 'Present'},
        });
        expect(await cache.read('attendance/daily/2026-10-17'), {
          'synthetic-other': {'status': 'Present'},
        });
        expect(await cache.read('attendance/daily/2026-10-15'), hasLength(2));
      },
    );

    test(
      'offline read returns only the selected patient and requested dates',
      () async {
        await seedAttendance();
        final service = serviceFor(
          (_) async => http.Response('unavailable', 503),
        );
        expect(
          await service.getAttendanceRange(
            kind: 'attendance',
            startKey: '2026-10-16',
            endKey: '2026-10-17',
            patientId: 'synthetic-target',
          ),
          {
            for (final date in ['2026-10-16', '2026-10-17'])
              date: {
                'synthetic-target': {'status': 'Present'},
              },
          },
        );
      },
    );

    for (final status in [403, 503]) {
      test(
        'financial attendance read surfaces HTTP $status despite cached records',
        () async {
          await seedAttendance();
          final service = serviceFor(
            (_) async => http.Response('unavailable', status),
          );
          await expectLater(
            service.getAttendanceRange(
              kind: 'attendance',
              startKey: '2026-10-16',
              endKey: '2026-10-17',
              patientId: 'synthetic-target',
              allowCacheFallback: false,
            ),
            throwsA(
              isA<BackendApiException>().having(
                (e) => e.statusCode,
                'status',
                status,
              ),
            ),
          );
          expect(await cache.read('attendance/daily/2026-10-16'), hasLength(2));
        },
      );
    }
  });
}
