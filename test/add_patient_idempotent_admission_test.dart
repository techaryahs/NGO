import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/room_service.dart';
import 'package:ngo/services/service_locator.dart';

/// Test mock RTDB service for room stay and bed operations.
class MockAdmissionRTDBService extends FirebaseRTDBRestService {
  MockAdmissionRTDBService() : super(projectId: 'test-idempotent');

  final Map<String, dynamic> db = {};
  int getCount = 0;
  int patchCount = 0;
  final List<String> queriedPaths = [];

  @override
  Future<dynamic> get(String path) async {
    getCount++;
    queriedPaths.add(path);
    return db[path];
  }

  @override
  Future<RtdbValue> getWithEtag(String path) async {
    getCount++;
    queriedPaths.add(path);
    return RtdbValue(db[path], 'etag_1');
  }

  @override
  Future<bool> put(String path, dynamic data) async {
    patchCount++;
    db[path] = data;
    return true;
  }

  @override
  Future<bool> putIfMatch(String path, dynamic data, String etag) async {
    patchCount++;
    db[path] = data;
    return true;
  }

  @override
  Future<void> patch(String path, Map<String, dynamic> data) async {
    patchCount++;
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
  }

  @override
  Future<dynamic> getByChildValue(
    String path, {
    required String child,
    required dynamic value,
  }) async {
    queriedPaths.add('$path?$child=$value');
    if (path == 'stays' && child == 'patientId') {
      throw Exception(
        'Index not defined, add ".indexOn": "patientId", for path "/stays"',
      );
    }
    return db[path];
  }
}

void main() {
  late MockAdmissionRTDBService mockRtdb;
  late RoomService roomService;

  setUp(() {
    mockRtdb = MockAdmissionRTDBService();
    roomService = RoomService(rtdbService: mockRtdb);

    // Seed pricing with standard schema
    mockRtdb.db['admin_settings/pricing'] = Map<String, dynamic>.from(RoomService.defaultPricing);

    // Seed a room
    mockRtdb.db['rooms/room_101'] = {
      'id': 'room_101',
      'roomNumber': '101',
      'floor': '1',
      'roomType': 'general',
      'status': 'available',
      'version': 1,
      'currentAttendants': 0,
      'maxAttendants': 4,
      'beds': {
        'bed_1': {
          'id': 'bed_1',
          'bedLabel': '101-A',
          'status': 'available',
          'currentPatientId': null,
          'currentStayId': null,
        },
        'bed_2': {
          'id': 'bed_2',
          'bedLabel': '101-B',
          'status': 'available',
          'currentPatientId': null,
          'currentStayId': null,
        },
      },
    };
  });

  test('createStaysForBeds uses deterministic stay IDs when provided', () async {
    final patientId = 'patient_test_001';
    final deterministicStayIds = ['stay_patient_test_001_bed_1'];

    final stayIds = await roomService.createStaysForBeds(
      patientId: patientId,
      patientName: 'Test Patient',
      roomId: 'room_101',
      admissionDate: DateTime(2026, 10, 2),
      durationDays: 5,
      attendantCount: 1,
      bedIds: ['bed_1'],
      createdBy: 'test_admin',
      deterministicStayIds: deterministicStayIds,
    );

    expect(stayIds, equals(['stay_patient_test_001_bed_1']));
    expect(mockRtdb.db['stays/stay_patient_test_001_bed_1'], isNotNull);
    final savedStay = mockRtdb.db['stays/stay_patient_test_001_bed_1'] as Map;
    expect(savedStay['id'], equals('stay_patient_test_001_bed_1'));
    expect(savedStay['patientId'], equals(patientId));
    expect(savedStay['bedId'], equals('bed_1'));
    expect(savedStay['status'], equals('active'));
  });

  test('createLobbyStay uses deterministic stay ID when provided', () async {
    final patientId = 'patient_test_002';
    final deterministicStayId = 'stay_patient_test_002_lobby_Main_Lobby';

    final stayId = await roomService.createLobbyStay(
      patientId: patientId,
      patientName: 'Lobby Patient',
      lobbyName: 'Main Lobby',
      admissionDate: DateTime(2026, 10, 2),
      durationDays: 3,
      attendantCount: 0,
      createdBy: 'test_admin',
      deterministicStayId: deterministicStayId,
    );

    expect(stayId, equals('stay_patient_test_002_lobby_Main_Lobby'));
    expect(mockRtdb.db['stays/stay_patient_test_002_lobby_Main_Lobby'], isNotNull);
    final savedStay = mockRtdb.db['stays/stay_patient_test_002_lobby_Main_Lobby'] as Map;
    expect(savedStay['id'], equals('stay_patient_test_002_lobby_Main_Lobby'));
    expect(savedStay['roomType'], equals('lobby'));
  });

  test('reserveBeds allows retry for the same patient without throwing conflict', () async {
    final patientId = 'patient_retry_test';
    final bedIds = ['bed_1'];
    final stayIds = ['stay_patient_retry_test_bed_1'];

    // First reservation
    await roomService.reserveBeds(
      roomId: 'room_101',
      bedIds: bedIds,
      patientId: patientId,
      stayIds: stayIds,
    );

    // Verify bed is now marked occupied by patient_retry_test
    final roomData = mockRtdb.db['rooms/room_101'] as Map;
    final bedData = (roomData['beds'] as Map)['bed_1'] as Map;
    expect(bedData['status'], equals('occupied'));
    expect(bedData['currentPatientId'], equals(patientId));

    // Second reservation (retry of the same admission) should SUCCEED without throwing BedConflictException
    final retriedRoom = await roomService.reserveBeds(
      roomId: 'room_101',
      bedIds: bedIds,
      patientId: patientId,
      stayIds: stayIds,
    );

    expect(retriedRoom.beds.firstWhere((b) => b.id == 'bed_1').status, equals('occupied'));
    expect(retriedRoom.beds.firstWhere((b) => b.id == 'bed_1').currentPatientId, equals(patientId));
  });

  test('reserveBeds rejects different patient trying to reserve the occupied bed', () async {
    // Bed 1 already reserved by patient_retry_test
    await roomService.reserveBeds(
      roomId: 'room_101',
      bedIds: ['bed_1'],
      patientId: 'patient_retry_test',
      stayIds: ['stay_1'],
    );

    // A DIFFERENT patient attempts to reserve Bed 1 -> MUST throw BedConflictException
    expect(
      () => roomService.reserveBeds(
        roomId: 'room_101',
        bedIds: ['bed_1'],
        patientId: 'different_patient_999',
        stayIds: ['stay_2'],
      ),
      throwsA(isA<BedConflictException>()),
    );
  });

  test('stays patientId query is never called during stay creation', () async {
    mockRtdb.queriedPaths.clear();

    await roomService.createStaysForBeds(
      patientId: 'patient_new_001',
      patientName: 'New Patient',
      roomId: 'room_101',
      admissionDate: DateTime(2026, 10, 2),
      durationDays: 5,
      attendantCount: 0,
      bedIds: ['bed_2'],
      createdBy: 'test_admin',
      deterministicStayIds: ['stay_patient_new_001_bed_2'],
    );

    // Assert that getByChildValue('stays', child: 'patientId') was NEVER invoked
    final hasPatientIdQuery = mockRtdb.queriedPaths.any(
      (path) => path.startsWith('stays?') && path.contains('patientId'),
    );
    expect(hasPatientIdQuery, isFalse);
  });
}
