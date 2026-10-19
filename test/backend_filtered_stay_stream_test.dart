import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/room_service.dart';

class _Observed<T> {
  _Observed(Stream<T> stream) {
    subscription = stream.listen((value) {
      values.add(value);
      _changed.complete();
      _changed = Completer<void>();
    });
  }

  final values = <T>[];
  late final StreamSubscription<T> subscription;
  var _changed = Completer<void>();

  Future<T> waitFor(bool Function(T) matches, {int after = 0}) async {
    while (true) {
      for (final value in values.skip(after)) {
        if (matches(value)) return value;
      }
      await _changed.future.timeout(const Duration(seconds: 1));
    }
  }
}

void main() {
  late PersistentCache cache;

  setUp(() async {
    cache = PersistentCache(CacheDatabase(NativeDatabase.memory()));
    await cache.initialize();
    await cache.activateAccount('synthetic-filtered-stay-account');
  });

  tearDown(() => cache.close());

  BackendApiService serviceFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final service = BackendApiService(
      baseUrl: 'https://backend.example/api',
      persistentCache: cache,
      client: MockClient(handler),
    );
    addTearDown(service.dispose);
    return service;
  }

  _Observed<T> observe<T>(Stream<T> stream) {
    final observed = _Observed(stream);
    addTearDown(observed.subscription.cancel);
    return observed;
  }

  Map<String, dynamic> stay(
    String id, {
    String patientId = 'synthetic-patient',
    String roomId = 'synthetic-room',
    String status = 'active',
    int updatedAt = 100,
  }) => {
    'id': id,
    'patientId': patientId,
    'patientName': 'Synthetic patient',
    'roomId': roomId,
    'roomNumber': 'QA',
    'roomType': 'general',
    'admissionDate': 100,
    'durationDays': 7,
    'expectedDischargeDate': 604800100,
    'expiryDate': 604800100,
    'status': status,
    'createdAt': 100,
    'updatedAt': updatedAt,
    'createdBy': 'synthetic-user',
  };

  List<String> ids(List<StayModel> values) =>
      values.map((value) => value.id).toList()..sort();

  http.Response filteredResponse(
    http.Request request,
    Map<String, Map<String, dynamic>> records,
  ) {
    final query = request.url.queryParameters;
    final selected = {
      for (final entry in records.entries)
        if (['status', 'patientId', 'roomId'].every(
          (key) => !query.containsKey(key) || entry.value[key] == query[key],
        ))
          entry.key: entry.value,
    };
    return http.Response(jsonEncode(selected), 200);
  }

  test('RoomService stays streams request encoded server filters', () async {
    const patientId = 'synthetic patient & second';
    const roomId = 'synthetic room + second';
    final records = {
      'matching': stay('matching', patientId: patientId, roomId: roomId),
      'completed': stay(
        'completed',
        patientId: patientId,
        roomId: roomId,
        status: 'completed',
      ),
      'other': stay('other'),
    };
    final queries = <Map<String, String>>[];
    final service = serviceFor((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/stays');
      queries.add(request.url.queryParameters);
      return filteredResponse(request, records);
    });
    final rooms = RoomService(backendApiService: service);

    expect(ids(await rooms.getActiveStaysStream().first), [
      'matching',
      'other',
    ]);
    expect(ids(await rooms.getStaysByRoomStream(roomId).first), ['matching']);
    expect(ids(await rooms.getStaysByPatientStream(patientId).first), [
      'completed',
      'matching',
    ]);
    expect(queries, [
      {'status': 'active', 'format': 'map'},
      {'roomId': roomId, 'status': 'active', 'format': 'map'},
      {'patientId': patientId, 'format': 'map'},
    ]);
  });

  test(
    'active stay query excludes nonmatching ACKs and removes a completed stay',
    () async {
      final records = {'original': stay('original')};
      final reads = <Uri>[];
      dynamic acknowledgement;
      final service = serviceFor((request) async {
        if (request.method == 'PUT') {
          return http.Response(jsonEncode(acknowledgement), 200);
        }
        reads.add(request.url);
        expect(request.url.queryParameters, {
          'status': 'active',
          'format': 'map',
        });
        return filteredResponse(request, records);
      });
      final rooms = RoomService(backendApiService: service);
      final active = observe(rooms.getActiveStaysStream());
      await active.waitFor((values) => ids(values).contains('original'));

      acknowledgement = stay('completed-elsewhere', status: 'completed');
      await service.patch('stays/completed-elsewhere', {'status': 'completed'});
      await Future<void>.delayed(Duration.zero);
      expect(ids(active.values.last), ['original']);

      acknowledgement = stay('new-active', updatedAt: 200);
      await service.patch('stays/new-active', {'status': 'active'});
      await active.waitFor((values) => ids(values).contains('new-active'));
      expect(ids(active.values.last), ['new-active', 'original']);

      acknowledgement = stay('original', status: 'completed', updatedAt: 300);
      await service.patch('stays/original', {'status': 'completed'});
      await active.waitFor(
        (values) => ids(values).length == 1 && values.single.id == 'new-active',
      );
      expect(ids(active.values.last), ['new-active']);
      expect(reads, hasLength(1));
      expect(await cache.read('stays?status=active&format=map'), {
        'new-active': stay('new-active', updatedAt: 200),
      });
    },
  );

  test(
    'patient and room queries follow authoritative reassignment without collection GETs',
    () async {
      final records = {'moving': stay('moving')};
      final reads = <Uri>[];
      final acknowledgement = stay(
        'moving',
        patientId: 'second-patient',
        roomId: 'second-room',
        updatedAt: 200,
      );
      final service = serviceFor((request) async {
        if (request.method == 'PUT') {
          return http.Response(jsonEncode(acknowledgement), 200);
        }
        reads.add(request.url);
        expect(request.url.queryParameters.length, greaterThan(1));
        return filteredResponse(request, records);
      });
      final rooms = RoomService(backendApiService: service);
      final oldPatient = observe(
        rooms.getStaysByPatientStream('synthetic-patient'),
      );
      final newPatient = observe(
        rooms.getStaysByPatientStream('second-patient'),
      );
      final oldRoom = observe(rooms.getStaysByRoomStream('synthetic-room'));
      final newRoom = observe(rooms.getStaysByRoomStream('second-room'));
      await Future.wait([
        oldPatient.waitFor((values) => ids(values).contains('moving')),
        oldRoom.waitFor((values) => ids(values).contains('moving')),
        newPatient.waitFor((values) => values.isEmpty),
        newRoom.waitFor((values) => values.isEmpty),
      ]);
      final oldPatientCount = oldPatient.values.length;
      final oldRoomCount = oldRoom.values.length;

      await service.patch('stays/moving', {
        'patientId': 'client-submitted-patient',
        'roomId': 'client-submitted-room',
      });
      await Future.wait([
        oldPatient.waitFor((values) => values.isEmpty, after: oldPatientCount),
        oldRoom.waitFor((values) => values.isEmpty, after: oldRoomCount),
        newPatient.waitFor((values) => ids(values).contains('moving')),
        newRoom.waitFor((values) => ids(values).contains('moving')),
      ]);
      expect(newPatient.values.last.single.patientId, 'second-patient');
      expect(newRoom.values.last.single.roomId, 'second-room');
      expect(reads, hasLength(4));
      expect(await cache.read('stays/moving'), acknowledgement);
    },
  );

  test(
    'null stay acknowledgement removes it from each matching query',
    () async {
      final original = stay('removed');
      var reads = 0;
      final service = serviceFor((request) async {
        if (request.method == 'PUT') return http.Response('', 204);
        reads++;
        return filteredResponse(request, {'removed': original});
      });
      final rooms = RoomService(backendApiService: service);
      final active = observe(rooms.getActiveStaysStream());
      final patient = observe(
        rooms.getStaysByPatientStream('synthetic-patient'),
      );
      final room = observe(rooms.getStaysByRoomStream('synthetic-room'));
      final queries = [active, patient, room];
      await Future.wait([
        for (final query in queries)
          query.waitFor((values) => ids(values).contains('removed')),
      ]);
      final counts = [for (final query in queries) query.values.length];

      await service.patch('stays/removed', {'status': 'completed'});
      await Future.wait([
        for (var i = 0; i < queries.length; i++)
          queries[i].waitFor((values) => values.isEmpty, after: counts[i]),
      ]);
      expect(await cache.read('stays/removed'), isNull);
      expect(reads, 3);
    },
  );

  test(
    'filtered stream hydrates its previous successful query result',
    () async {
      const path = 'stays?status=active&format=map';
      final saved = {'cached': stay('cached')};
      final response = Completer<http.Response>();
      final refreshStarted = Completer<void>();
      var reads = 0;
      final service = serviceFor((request) {
        reads++;
        if (reads == 1) {
          return Future.value(http.Response(jsonEncode(saved), 200));
        }
        refreshStarted.complete();
        return response.future;
      });
      expect(await service.get(path), saved);
      expect(await cache.read(path), saved);
      final active = observe(
        RoomService(backendApiService: service).getActiveStaysStream(),
      );
      await active.waitFor((values) => ids(values).contains('cached'));
      await refreshStarted.future;
      expect(response.isCompleted, isFalse);
      expect(reads, 2);
      response.complete(http.Response('{}', 200));
      await active.waitFor((values) => values.isEmpty);
    },
  );

  test(
    'ACK during initial filtered poll fences its stale result and promptly repolls',
    () async {
      final initialStarted = Completer<void>();
      final initialResponse = Completer<http.Response>();
      final created = stay('created', updatedAt: 200);
      final reads = <Uri>[];
      final service = serviceFor((request) {
        if (request.method == 'PUT') {
          return Future.value(http.Response(jsonEncode(created), 200));
        }
        reads.add(request.url);
        expect(request.url.path, '/api/stays');
        expect(request.url.queryParameters, {
          'status': 'active',
          'format': 'map',
        });
        if (reads.length == 1) {
          initialStarted.complete();
          return initialResponse.future;
        }
        return Future.value(
          http.Response(jsonEncode({'created': created}), 200),
        );
      });
      final observed = observe(
        RoomService(backendApiService: service).getActiveStaysStream(),
      );
      await initialStarted.future;

      await service.patch('stays/created', {'status': 'active'});
      expect(observed.values, isEmpty);
      initialResponse.complete(http.Response('{}', 200));
      await observed.waitFor((values) => ids(values).contains('created'));

      expect(observed.values.map(ids), [
        ['created'],
      ]);
      expect(reads, hasLength(2));
      expect(await cache.read('stays?status=active&format=map'), {
        'created': created,
      });
    },
  );

  test(
    'late filtered stay subscriber replays before the ten-second poll',
    () async {
      var reads = 0;
      final saved = {'loaded': stay('loaded')};
      final service = serviceFor((request) async {
        reads++;
        return http.Response(jsonEncode(saved), 200);
      });
      final rooms = RoomService(backendApiService: service);
      final firstSubscriber = observe(rooms.getActiveStaysStream());
      await firstSubscriber.waitFor((values) => ids(values).contains('loaded'));

      expect(
        ids(
          await rooms.getActiveStaysStream().first.timeout(
            const Duration(milliseconds: 500),
          ),
        ),
        ['loaded'],
      );
      expect(reads, 1);
    },
  );

  for (final query in [
    'status=active&limit=1&format=map',
    'status=active&search=Synthetic&format=map',
    'status=active&format=array',
  ]) {
    test(
      'ACK does not guess membership for unsupported query $query',
      () async {
        final original = stay('existing');
        final saved = query.contains('format=array')
            ? [original]
            : {'existing': original};
        var reads = 0;
        final service = serviceFor((request) async {
          if (request.method == 'PUT') {
            return http.Response(
              jsonEncode(stay('added', updatedAt: 200)),
              200,
            );
          }
          reads++;
          return http.Response(jsonEncode(saved), 200);
        });
        final observed = observe(service.stream('stays?$query'));
        await observed.waitFor((_) => true);
        final count = observed.values.length;

        await service.patch('stays/added', {'status': 'active'});
        await Future<void>.delayed(Duration.zero);
        expect(observed.values, hasLength(count));
        expect(observed.values.last, saved);
        expect(reads, 1);
      },
    );
  }

  test(
    'room list uses active stays and still refreshes the acknowledged related room',
    () async {
      final room = {
        'id': 'synthetic-room',
        'roomNumber': 'QA',
        'roomIdentifier': 'QA',
        'notes': 'Before',
      };
      final refreshed = {
        ...room,
        'notes': 'Authoritative room after completion',
      };
      final reads = <Uri>[];
      final service = serviceFor((request) async {
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode(stay('original', status: 'completed', updatedAt: 200)),
            200,
          );
        }
        reads.add(request.url);
        if (request.url.path == '/api/stays') {
          expect(request.url.queryParameters, {
            'status': 'active',
            'format': 'map',
          });
          return http.Response(jsonEncode({'original': stay('original')}), 200);
        }
        if (request.url.path == '/api/rooms/synthetic-room') {
          return http.Response(jsonEncode(refreshed), 200);
        }
        expect(request.url.path, '/api/rooms');
        return http.Response(jsonEncode({'synthetic-room': room}), 200);
      });
      final observed = observe(
        RoomService(backendApiService: service).streamRooms(),
      );
      await observed.waitFor(
        (values) => values.length == 1 && values.single.notes == 'Before',
      );

      await service.patch('stays/original', {'status': 'completed'});
      await observed.waitFor(
        (values) =>
            values.length == 1 && values.single.notes == refreshed['notes'],
      );
      expect(reads.map((uri) => uri.path), [
        '/api/rooms',
        '/api/stays',
        '/api/rooms/synthetic-room',
      ]);
    },
  );

  test(
    'deleting a stay known only by its filtered query refreshes its related room',
    () async {
      final room = {
        'id': 'synthetic-room',
        'roomNumber': 'QA',
        'roomIdentifier': 'QA',
        'notes': 'Before delete',
      };
      final refreshed = {...room, 'notes': 'Authoritative room after delete'};
      final reads = <Uri>[];
      var deletes = 0;
      final service = serviceFor((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          expect(request.url.path, '/api/stays/deleted');
          return http.Response('', 204);
        }
        expect(request.method, 'GET');
        reads.add(request.url);
        if (request.url.path == '/api/stays') {
          expect(request.url.queryParameters, {
            'status': 'active',
            'format': 'map',
          });
          return http.Response(jsonEncode({'deleted': stay('deleted')}), 200);
        }
        if (request.url.path == '/api/rooms/synthetic-room') {
          return http.Response(jsonEncode(refreshed), 200);
        }
        expect(request.url.path, '/api/rooms');
        return http.Response(jsonEncode({'synthetic-room': room}), 200);
      });
      final rooms = RoomService(backendApiService: service);
      final observedRooms = observe(rooms.streamRooms());
      final active = observe(rooms.getActiveStaysStream());
      await Future.wait([
        observedRooms.waitFor(
          (values) =>
              values.length == 1 && values.single.notes == 'Before delete',
        ),
        active.waitFor((values) => ids(values).contains('deleted')),
      ]);
      expect(
        await cache.read('stays/deleted'),
        isNull,
        reason: 'The stay exists only in the filtered query snapshot.',
      );

      await service.deleteStay('deleted');
      await Future.wait([
        active.waitFor((values) => values.isEmpty),
        observedRooms.waitFor(
          (values) =>
              values.length == 1 && values.single.notes == refreshed['notes'],
        ),
      ]);

      expect(deletes, 1);
      expect(reads.map((uri) => uri.path), [
        '/api/rooms',
        '/api/stays',
        '/api/rooms/synthetic-room',
      ]);
      expect(await cache.read('rooms/synthetic-room'), refreshed);
      expect(await cache.read('stays?status=active&format=map'), isEmpty);
    },
  );
  test(
    'atomic discharge updates persisted filtered snapshots even without an open stream and with slash IDs',
    () async {
      const key = 'stay_synthetic_bed_1/2';
      final opened = stay(key);
      final closed = stay(key, status: 'completed', updatedAt: 200);
      final api = serviceFor(
        (r) async => r.method == 'POST'
            ? http.Response(
                jsonEncode({
                  'patient': {
                    'id': 'synthetic-patient',
                    'status': 'discharged',
                  },
                  'stays': [closed],
                }),
                200,
              )
            : http.Response(jsonEncode({key: opened}), 200),
      );
      const path = 'stays?patientId=synthetic-patient&format=map';
      await api.get(path);
      await api.dischargePatient('synthetic-patient');
      final restored = await cache.read(path) as Map;
      expect(restored[key]['status'], 'completed');
      expect((await cache.read('stays') as Map)[key]['status'], 'completed');
    },
  );
}
