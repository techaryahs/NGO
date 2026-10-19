import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/config/app_config.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/registration_number_service.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/utils/stay_billing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DiagnosticE2eClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  Future<void> Function(http.BaseRequest request)? beforeSend;
  Future<void> Function(http.BaseRequest request, http.Response response)?
  afterSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await beforeSend?.call(request);
    final response = await http.Response.fromStream(await _inner.send(request));
    await afterSend?.call(request, response);
    if (response.statusCode >= 400) {
      final payload = request is http.Request && request.body.isNotEmpty
          ? jsonDecode(request.body)
          : null;
      final keys = payload is Map ? payload.keys.join(',') : '';
      // Only field names and error diagnostics; never tokens or patient data.
      // ignore: avoid_print
      print(
        'E2E_HTTP_FAILURE ${request.method} ${request.url.path} status=${response.statusCode} fields=[$keys] response=${response.body}',
      );
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  Process? serverProcess;
  late String serverOrigin;
  late String apiBaseUrl;
  late http.Client rawHttp;
  late PersistentCache cache;
  late String currentToken;

  late BackendApiService backendApi;
  late _DiagnosticE2eClient diagnosticClient;
  late RoomService roomService;
  late PaymentService paymentService;
  late PatientService patientService;
  late RegistrationNumberService regNumService;
  late AttendanceService attendanceService;

  Future<Map<String, dynamic>> execSql(
    String sql, [
    List<dynamic> params = const [],
  ]) async {
    final res = await rawHttp.post(
      Uri.parse('$serverOrigin/__test__/sql'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'sql': sql, 'params': params}),
    );
    if (res.statusCode != 200) {
      throw StateError('SQL helper failed (${res.statusCode}): ${res.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<List<Map<String, dynamic>>> queryRows(
    String sql, [
    List<dynamic> params = const [],
  ]) async {
    final res = await execSql(sql, params);
    final rows = res['rows'] as List<dynamic>? ?? const [];
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<String> fetchToken([String role = 'admin']) async {
    final res = await rawHttp.get(
      Uri.parse('$serverOrigin/__test__/token?role=$role'),
    );
    if (res.statusCode != 200) {
      throw StateError('Token helper failed: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map;
    return data['token'] as String;
  }

  Future<void> resetBackend() async {
    final res = await rawHttp.post(
      Uri.parse('$serverOrigin/__test__/reset'),
      headers: {'content-type': 'application/json'},
      body: '{}',
    );
    if (res.statusCode != 200) {
      throw StateError('Reset helper failed: ${res.body}');
    }
  }

  Future<void> setDbOutage(bool outage) async {
    final res = await rawHttp.post(
      Uri.parse('$serverOrigin/__test__/db-outage'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'outage': outage}),
    );
    if (res.statusCode != 200) {
      throw StateError('DB outage helper failed: ${res.body}');
    }
  }

  setUpAll(() async {
    rawHttp = http.Client();
    final externalOrigin = Platform.environment['E2E_SERVER_ORIGIN'];
    if (externalOrigin != null && externalOrigin.isNotEmpty) {
      serverOrigin = externalOrigin;
      apiBaseUrl = '$serverOrigin/api';
      return;
    }

    // Ensure disposable PostgreSQL 16 instance on 127.0.0.1:55439 is running.
    final pgBin = r'C:\Program Files\PostgreSQL\16\bin';
    final pgData =
        Platform.environment['AUDIT_PG_DATA_DIR'] ??
        '${Platform.environment['TEMP']}\\ngo-audit-pg16-e2e';
    final statusResult = await Process.run('$pgBin\\pg_ctl.exe', [
      '-D',
      pgData,
      'status',
    ]);
    if (statusResult.exitCode != 0) {
      final startResult = await Process.run('$pgBin\\pg_ctl.exe', [
        '-D',
        pgData,
        '-l',
        '$pgData\\server.log',
        '-o',
        '-p 55439 -h 127.0.0.1',
        '-w',
        'start',
      ]);
      if (startResult.exitCode != 0) {
        throw StateError(
          'Failed to start disposable PostgreSQL 16: ${startResult.stdout} ${startResult.stderr}',
        );
      }
    }

    final npxCmd = Platform.isWindows ? 'npx.cmd' : 'npx';
    serverProcess = await Process.start(
      npxCmd,
      ['tsx', 'tests/helpers/e2e_server.ts'],
      workingDirectory: '${Directory.current.path}\\backend',
      environment: {
        ...Platform.environment,
        'NODE_ENV': 'test',
        'POSTGRES_HOST': '127.0.0.1',
        'POSTGRES_PORT': '55439',
        'POSTGRES_DB': 'ngo_flutter_e2e',
        'POSTGRES_USER': 'ngo_audit',
        'POSTGRES_PASSWORD': 'unused',
        'DATABASE_URL': 'postgres://ngo_audit@127.0.0.1:55439/ngo_flutter_e2e',
      },
    );

    final readyCompleter = Completer<String>();
    final stderrBuffer = StringBuffer();

    serverProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('E2E_SERVER_READY:')) {
            final origin = line.substring('E2E_SERVER_READY:'.length).trim();
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete(origin);
            }
          }
        });

    serverProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderrBuffer.writeln);

    serverProcess!.exitCode.then((code) {
      if (!readyCompleter.isCompleted) {
        readyCompleter.completeError(
          StateError('E2E server exited prematurely ($code): $stderrBuffer'),
        );
      }
    });

    serverOrigin = await readyCompleter.future.timeout(
      const Duration(seconds: 30),
    );
    apiBaseUrl = '$serverOrigin/api';
  });

  tearDownAll(() async {
    rawHttp.close();
    if (serverProcess != null) {
      serverProcess!.kill();
      await serverProcess!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      isOptional: true,
      envString: 'USE_POSTGRES_BACKEND=true\nBACKEND_BASE_URL=$apiBaseUrl\n',
    );
    await resetBackend();
    currentToken = await fetchToken('admin');

    cache = PersistentCache(CacheDatabase(NativeDatabase.memory()));
    await cache.initialize();
    await cache.activateAccount('e2e-postgres-account');

    diagnosticClient = _DiagnosticE2eClient();
    backendApi = BackendApiService(
      baseUrl: apiBaseUrl,
      persistentCache: cache,
      client: diagnosticClient,
      getAuthToken: () async => currentToken,
    );

    roomService = RoomService(backendApiService: backendApi);
    paymentService = PaymentService(null, backendApi);
    patientService = PatientService(
      backendApiService: backendApi,
      roomService: roomService,
      paymentService: paymentService,
    );
    regNumService = RegistrationNumberService(backendApiService: backendApi);
    attendanceService = AttendanceService(null, backendApi);
  });

  tearDown(() async {
    paymentService.disposeScheduler();
    backendApi.dispose();
    await cache.close();
    ServiceLocator().dispose();
    dotenv.loadFromString(isOptional: true, envString: '');
  });

  test(
    'October 19 planned registration stays Unmarked through retries, extension and disk cache reopen',
    () async {
      final admission = DateTime(2026, 10, 19);
      final exit = DateTime(2026, 10, 31, 9);
      await roomService.addRoom(
        id: 'oct_room',
        roomNumber: 'October QA',
        roomIdentifier: '1A',
        floor: 1,
        roomType: 'general',
        totalBeds: 2,
        bedLabels: ['Oct1', 'Oct2'],
      );
      final room = (await roomService.getRoomDirect('oct_room'))!;
      final placements = [
        {
          'id': 'oct_stay',
          'roomId': room.id,
          'bedId': room.beds.first.id,
          'admissionDate': admission.millisecondsSinceEpoch,
          'durationDays': 13,
          'cycleId': admission.millisecondsSinceEpoch.toString(),
        },
      ];
      Future<String> register(String id, List<Map<String, dynamic>> stays) =>
          patientService.addPatient(
            id: id,
            fullName: 'Same synthetic October name',
            dateOfBirth: DateTime(1990),
            gender: 'Other',
            contactNumber: '000',
            emergencyContact: '000',
            emergencyContactName: 'Synthetic',
            medicalCondition: 'Synthetic',
            admissionDate: admission,
            registrationDate: admission,
            exitDate: exit,
            registrationNumber: id,
            createdBy: 'test-uid-admin',
            attendants: [AttendantModel(name: 'Synthetic October helper')],
            initialStays: stays,
          );
      await register('oct_patient', placements);
      expect(await queryRows('SELECT * FROM attendance_records'), isEmpty);
      var model = (await patientService.getPatient('oct_patient'))!;
      var stays = await paymentService.loadStays('oct_patient');
      var month = await attendanceService.loadMonth(admission);
      var row = month.rows([model], stays).firstWhere((r) => !r.isAttendant);
      var editor = MonthlyAttendanceEditor(month);
      for (var d = 19; d <= 31; d++) {
        expect(editor.status(row, DateTime(2026, 10, d)), 'Unmarked');
      }
      final emptyProfile = AttendanceService.patientRecords(
        await patientService.getAttendanceRangeForProfile(
          kind: 'attendance',
          startKey: '2026-10-19',
          endKey: '2026-10-31',
        ),
        model.id,
      );
      expect(emptyProfile, isEmpty);
      expect(AttendanceService.summary(emptyProfile.values).total, 0);
      expect(
        StayBilling.calculate(
          patient: model,
          stays: stays,
          pricing: {},
          onlyPresent: true,
          now: admission,
        ).single.total,
        0,
      );
      editor.edit(row, admission, 'Present');
      editor.edit(row, DateTime(2026, 10, 20), 'Absent');
      await editor.save(null, backendApi);
      await register('oct_patient', placements);
      await register('oct_same_name', []);
      await roomService.extendStay(stayId: 'oct_stay', additionalDays: 7);
      await patientService.updatePatient('oct_patient', {
        'exitDate': DateTime(2026, 11, 7, 9).millisecondsSinceEpoch,
      });
      final stored = await queryRows(
        'SELECT patient_id,attendance_date::text AS day,payload FROM attendance_records ORDER BY attendance_date',
      );
      expect(stored, hasLength(2));
      expect(
        stored
            .map(
              (r) => [
                r['patient_id'],
                r['day'],
                (r['payload'] as Map)['status'],
              ],
            )
            .toList(),
        [
          ['oct_patient', '2026-10-19', 'Present'],
          ['oct_patient', '2026-10-20', 'Absent'],
        ],
      );
      final raw = await patientService.getAttendanceRangeForProfile(
        kind: 'attendance',
        startKey: '2026-10-19',
        endKey: '2026-11-07',
      );
      final profile = AttendanceService.patientRecords(raw, model.id);
      expect(AttendanceService.summary(profile.values), (
        present: 1,
        absent: 1,
        total: 2,
        percentage: 50.0,
      ));
      expect(AttendanceService.patientRecords(raw, 'oct_same_name'), isEmpty);
      model = (await patientService.getPatient(model.id))!;
      stays = await paymentService.loadStays(model.id);
      expect(
        StayBilling.calculate(
          patient: model,
          stays: stays,
          pricing: {},
          attendance: {
            for (final e in profile.entries) e.key: e.value['status'] as String,
          },
          onlyPresent: true,
          now: admission,
        ).single.days['oct_stay'],
        1,
      );

      final directory = await Directory.systemTemp.createTemp(
        'ngo-attendance-reopen-',
      );
      final file = File('${directory.path}/cache.sqlite');
      Future<PersistentCache> openCache() async {
        final value = PersistentCache(CacheDatabase(NativeDatabase(file)));
        await value.initialize();
        await value.activateAccount('synthetic-october');
        return value;
      }

      var disk = await openCache();
      var api = BackendApiService(
        baseUrl: apiBaseUrl,
        persistentCache: disk,
        getAuthToken: () async => currentToken,
      );
      try {
        await AttendanceService(null, api).loadMonth(admission);
        api.dispose();
        await disk.close();
        disk = await openCache();
        expect(
          (await disk.read(
            'attendance/daily/2026-10-19/oct_patient',
          ))['status'],
          'Present',
        );
        expect(
          await disk.read('attendance/daily/2026-10-21/oct_patient'),
          isNull,
        );
        api = BackendApiService(
          baseUrl: apiBaseUrl,
          persistentCache: disk,
          getAuthToken: () async => currentToken,
        );
        month = await AttendanceService(null, api).loadMonth(admission);
        row = month.rows([model], stays).firstWhere((r) => !r.isAttendant);
        editor = MonthlyAttendanceEditor(month);
        expect(editor.status(row, admission), 'Present');
        expect(editor.status(row, DateTime(2026, 10, 20)), 'Absent');
        expect(editor.status(row, exit), 'Unmarked');
        final november = await AttendanceService(
          null,
          api,
        ).loadMonth(DateTime(2026, 11));
        final extendedRow = november
            .rows([model], stays)
            .firstWhere((r) => !r.isAttendant);
        expect(
          MonthlyAttendanceEditor(
            november,
          ).status(extendedRow, DateTime(2026, 11, 7)),
          'Unmarked',
        );
      } finally {
        api.dispose();
        await disk.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'concurrent stay extensions retain both increments and never initialize attendance',
    () async {
      await roomService.addRoom(
        id: 'extend_room',
        roomNumber: 'Extension QA',
        roomIdentifier: '1A',
        floor: 1,
        roomType: 'general',
        totalBeds: 1,
        bedLabels: ['E1'],
      );
      final room = (await roomService.getRoomDirect('extend_room'))!;
      await patientService.addPatient(
        id: 'extend_patient',
        fullName: 'Synthetic extensions',
        dateOfBirth: DateTime(1990),
        gender: 'Other',
        contactNumber: '000',
        emergencyContact: '000',
        emergencyContactName: 'Synthetic',
        medicalCondition: 'Synthetic',
        admissionDate: DateTime(2026, 10, 19),
        registrationNumber: 'extend_patient',
        createdBy: 'test-uid-admin',
        initialStays: [
          {
            'id': 'extend_stay',
            'roomId': room.id,
            'bedId': room.beds.single.id,
            'admissionDate': DateTime(2026, 10, 19).millisecondsSinceEpoch,
            'durationDays': 2,
          },
        ],
      );
      final bothRead = Completer<void>();
      var reads = 0;
      diagnosticClient.afterSend = (request, response) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/stays/extend_stay') {
          if (++reads == 2) bothRead.complete();
          if (reads <= 2) await bothRead.future;
        }
      };
      await Future.wait([
        roomService.extendStay(
          stayId: 'extend_stay',
          additionalDays: 2,
          reason: 'first',
        ),
        roomService.extendStay(
          stayId: 'extend_stay',
          additionalDays: 3,
          reason: 'second',
        ),
      ]);
      diagnosticClient.afterSend = null;
      final saved = (await queryRows(
        "SELECT duration_days,total_extended_days,extensions FROM stays WHERE id='extend_stay'",
      )).single;
      expect(saved['duration_days'], 7);
      expect(saved['total_extended_days'], 5);
      expect(saved['extensions'] as List, hasLength(2));
      expect(await queryRows('SELECT * FROM attendance_records'), isEmpty);
    },
  );

  test('billing failure rolls back patient and stay totals together', () async {
    await roomService.addRoom(
      id: 'billing_room',
      roomNumber: 'Billing QA',
      roomIdentifier: '1A',
      floor: 1,
      roomType: 'general',
      totalBeds: 1,
      bedLabels: ['B1'],
    );
    final room = (await roomService.getRoomDirect('billing_room'))!;
    await patientService.addPatient(
      id: 'billing_patient',
      fullName: 'Synthetic billing rollback',
      dateOfBirth: DateTime(1990),
      gender: 'Other',
      contactNumber: '000',
      emergencyContact: '000',
      emergencyContactName: 'Synthetic',
      medicalCondition: 'Synthetic',
      admissionDate: DateTime(2026, 10, 19),
      exitDate: DateTime(2026, 10, 21, 9),
      registrationNumber: 'billing_patient',
      createdBy: 'test-uid-admin',
      initialStays: [
        {
          'id': 'billing_stay',
          'roomId': room.id,
          'bedId': room.beds.single.id,
          'admissionDate': DateTime(2026, 10, 19).millisecondsSinceEpoch,
          'durationDays': 2,
        },
      ],
    );
    await backendApi.postAttendance(
      kind: 'attendance',
      date: '2026-10-19',
      patientId: 'billing_patient',
      payload: {'status': 'Absent'},
    );
    final before = await queryRows(
      "SELECT * FROM patients WHERE id='billing_patient'",
    );
    await execSql(
      "CREATE FUNCTION e2e_fail_billing() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION 'synthetic stay billing failure'; END \$\$; "
      "CREATE TRIGGER e2e_fail_billing BEFORE UPDATE ON stays FOR EACH ROW EXECUTE FUNCTION e2e_fail_billing()",
    );
    try {
      await expectLater(
        paymentService.recalculatePatientAttendanceAndBilling(
          'billing_patient',
        ),
        throwsA(anything),
      );
      expect(
        await queryRows("SELECT * FROM patients WHERE id='billing_patient'"),
        before,
      );
    } finally {
      await execSql(
        'DROP TRIGGER e2e_fail_billing ON stays; DROP FUNCTION e2e_fail_billing()',
      );
    }
    await paymentService.recalculatePatientAttendanceAndBilling(
      'billing_patient',
    );
    expect(
      (await patientService.getPatient('billing_patient'))!.totalAbsentDays,
      1,
    );
  });

  test(
    'room transfer preserves original placement if the selected destination is taken',
    () async {
      for (final id in ['transfer_from', 'transfer_to']) {
        await roomService.addRoom(
          id: id,
          roomNumber: id,
          roomIdentifier: id.endsWith('from') ? '1A' : '1B',
          floor: 1,
          roomType: 'general',
          totalBeds: 1,
          bedLabels: ['T1'],
        );
      }
      final rooms = [
        (await roomService.getRoomDirect('transfer_from'))!,
        (await roomService.getRoomDirect('transfer_to'))!,
      ];
      for (var i = 0; i < 2; i++) {
        await patientService.addPatient(
          id: 'transfer_p$i',
          fullName: 'Synthetic transfer $i',
          dateOfBirth: DateTime(1990),
          gender: 'Other',
          contactNumber: '000',
          emergencyContact: '000',
          emergencyContactName: 'Synthetic',
          medicalCondition: 'Synthetic',
          admissionDate: DateTime(2026, 10, 19),
          registrationNumber: 'transfer_p$i',
          createdBy: 'test-uid-admin',
          initialStays: [
            {
              'id': 'transfer_s$i',
              'roomId': rooms[i].id,
              'bedId': rooms[i].beds.single.id,
              'admissionDate': DateTime(2026, 10, 19).millisecondsSinceEpoch,
              'durationDays': 2,
            },
          ],
        );
      }
      Future<void> transfer() => roomService.transferPatient(
        patientId: 'transfer_p0',
        expectedStayIds: ['transfer_s0'],
        roomId: rooms[1].id,
        roomNumber: rooms[1].roomNumber,
        roomType: 'general',
        bedId: rooms[1].beds.single.id,
        shiftedAt: DateTime(2026, 10, 20),
        requestId: 'synthetic_transfer',
      );
      final before = await queryRows(
        "SELECT * FROM patients WHERE id='transfer_p0'",
      );
      await expectLater(transfer(), throwsA(anything));
      expect(
        await queryRows("SELECT * FROM patients WHERE id='transfer_p0'"),
        before,
      );
      expect(
        (await queryRows(
          "SELECT status FROM stays WHERE id='transfer_s0'",
        )).single['status'],
        'active',
      );
      await backendApi.delete('patients/transfer_p1');
      await transfer();
      await transfer();
      final stays = await queryRows(
        "SELECT id,status FROM stays WHERE patient_id='transfer_p0' ORDER BY id",
      );
      expect(stays, [
        {'id': 'synthetic_transfer', 'status': 'active'},
        {'id': 'transfer_s0', 'status': 'completed'},
      ]);
      expect(
        (await patientService.getPatient('transfer_p0'))!.status,
        'active',
      );
      expect(await queryRows('SELECT * FROM attendance_records'), isEmpty);
    },
  );

  test(
    'Environment & Safety Verification: PostgreSQL 16 schema and default feature flag',
    () async {
      // Verify default AppConfig when .env does not enable USE_POSTGRES_BACKEND
      dotenv.loadFromString(isOptional: true, envString: '');
      expect(AppConfig.usePostgresBackend, isFalse);

      // Re-enable for the rest of the test
      dotenv.loadFromString(
        isOptional: true,
        envString: 'USE_POSTGRES_BACKEND=true\nBACKEND_BASE_URL=$apiBaseUrl\n',
      );
      expect(AppConfig.usePostgresBackend, isTrue);

      final dbInfo = (await queryRows(
        "SELECT current_database() AS db, current_setting('server_version_num')::int AS ver",
      )).single;
      expect(dbInfo['db'], 'ngo_flutter_e2e');
      expect(dbInfo['ver'] as int, greaterThanOrEqualTo(160000));

      final tables = await queryRows(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
      );
      expect(tables.length, 18); // 17 domain tables + pgmigrations
    },
  );

  test(
    'Workflow A: Room & Bed Management (Create, Retrieve, Add/Update Bed, Reject Duplicates/Invalid, Cache Sync)',
    () async {
      final createdRoomId = await roomService.addRoom(
        id: 'room_101',
        roomNumber: '101',
        roomIdentifier: '1A',
        floor: 1,
        roomType: 'general',
        totalBeds: 2,
        bedLabels: ['101-A', '101-B'],
      );
      expect(createdRoomId, 'room_101');

      // 1. Verify directly in PostgreSQL rooms and room_beds tables
      final pgRooms = await queryRows(
        'SELECT id, room_number, room_type, floor, total_beds, occupied_beds, status FROM rooms WHERE id = \$1',
        ['room_101'],
      );
      expect(pgRooms, hasLength(1));
      expect(pgRooms.single['room_number'], '101');
      expect(pgRooms.single['total_beds'], 2);
      expect(pgRooms.single['occupied_beds'], 0);
      expect(pgRooms.single['status'], 'available');

      final pgBeds = await queryRows(
        'SELECT id, room_id, bed_label, status FROM room_beds WHERE room_id = \$1 ORDER BY bed_label',
        ['room_101'],
      );
      expect(pgBeds, hasLength(2));
      expect(pgBeds[0]['bed_label'], '101-A');
      expect(pgBeds[1]['bed_label'], '101-B');

      // 2. Add a third bed via RoomService.addBed
      await roomService.addBed(
        roomId: 'room_101',
        id: 'room_101_bed_3',
        bedLabel: '101-C',
      );

      // 3. Retrieve room through Flutter RoomService and verify deserialization
      final fetchedRoom = await roomService.getRoom('room_101');
      expect(fetchedRoom, isNotNull);
      expect(fetchedRoom!.totalBeds, 3);
      expect(fetchedRoom.beds.map((b) => b.bedLabel).toSet(), {
        '101-A',
        '101-B',
        '101-C',
      });

      // 4. Update bed label and status via RoomService.updateBed and updateBedStatus
      await roomService.updateBed(
        roomId: 'room_101',
        bedId: 'room_101_bed_3',
        bedLabel: '101-C-VIP',
      );
      await roomService.updateBedStatus(
        roomId: 'room_101',
        bedId: 'room_101_bed_3',
        status: 'maintenance',
      );

      final updatedRoom = await roomService.getRoomDirect('room_101');
      final bed3 = updatedRoom!.beds.firstWhere(
        (b) => b.id == 'room_101_bed_3',
      );
      expect(bed3.bedLabel, '101-C-VIP');
      expect(bed3.status, 'maintenance');

      // Verify PostgreSQL row updated
      final pgBed3 = (await queryRows(
        'SELECT bed_label, status FROM room_beds WHERE id = \$1',
        ['room_101_bed_3'],
      )).single;
      expect(pgBed3['bed_label'], '101-C-VIP');
      expect(pgBed3['status'], 'maintenance');

      // Verify local SQLite cache holds updated room
      final cachedRoom = await cache.read('rooms/room_101') as Map?;
      expect(cachedRoom, isNotNull);
      expect(cachedRoom!['totalBeds'], 3);

      // 5. Edge/Failure cases:
      // Duplicate bed label in same room -> 409 Conflict
      await expectLater(
        () => roomService.addBed(
          roomId: 'room_101',
          id: 'room_101_bed_dup',
          bedLabel: '101-A',
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            409,
          ),
        ),
      );

      // Invalid room reference -> 404 Not Found
      await expectLater(
        () => roomService.updateBed(
          roomId: 'non_existent_room',
          bedId: 'room_101_bed_3',
          bedLabel: 'X',
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );

      // Confirm no orphan beds created
      final bedCount = (await queryRows(
        'SELECT count(*)::int AS cnt FROM room_beds WHERE room_id = \$1',
        ['room_101'],
      )).single['cnt'];
      expect(bedCount, 3);
    },
  );

  test(
    'Workflow B: Patient Registration (Allocation, Attendants, Search, Cache Consistency, Duplicate/Invalid Rejection)',
    () async {
      // 1. Allocate registration number via RegistrationNumberService
      final regNo1 = await regNumService.allocateNextRegistrationNumber();
      final regNo2 = await regNumService.allocateNextRegistrationNumber();
      expect(regNo1, '1');
      expect(regNo2, '2');

      // Verify system_counters in PostgreSQL
      final counterRow = (await queryRows(
        "SELECT current_value::int AS val FROM system_counters WHERE counter_name = 'registrationNumber'",
      )).single;
      expect(counterRow['val'], 2);

      // 2. Register patient with attendants via PatientService.addPatient
      final admissionDate = DateTime(2026, 3, 10, 8, 30);
      final exitDate = DateTime(2026, 3, 12, 8, 30);
      final patientId = await patientService.addPatient(
        fullName: 'Ramesh Kumar',
        dateOfBirth: DateTime(1975, 5, 20),
        gender: 'Male',
        contactNumber: '9876543210',
        emergencyContact: '9123456789',
        emergencyContactName: 'Suresh Kumar',
        medicalCondition: 'Post-op recovery',
        allergies: 'Penicillin',
        address: '12 MG Road, Pune',
        admissionDate: admissionDate,
        exitDate: exitDate,
        registrationNumber: regNo1,
        registrationDate: admissionDate,
        advanceBilledAmount: 1000,
        initialTotalAmount: 1000,
        createdBy: 'test-uid-admin',
        attendants: [
          AttendantModel(
            name: 'Suresh Kumar',
            age: '42',
            relation: 'Brother',
            mobileNumber: '9123456789',
          ),
        ],
      );
      expect(patientId, isNotEmpty);

      // 3. Verify directly in PostgreSQL patients, patient_attendants, and attendance_records
      final pgPatient = (await queryRows(
        'SELECT id, full_name, registration_number, gender, contact_number, allergies, status, advance_billed_amount::text FROM patients WHERE id = \$1',
        [patientId],
      )).single;
      expect(pgPatient['full_name'], 'Ramesh Kumar');
      expect(pgPatient['registration_number'], '1');
      expect(pgPatient['allergies'], 'Penicillin');
      expect(pgPatient['status'], 'active');
      expect(pgPatient['advance_billed_amount'], '1000.00');

      final pgAttendants = await queryRows(
        'SELECT patient_id, name, relation, mobile_number FROM patient_attendants WHERE patient_id = \$1',
        [patientId],
      );
      expect(pgAttendants, hasLength(1));
      expect(pgAttendants.single['name'], 'Suresh Kumar');
      expect(pgAttendants.single['relation'], 'Brother');

      final pgInitialAtt = await queryRows(
        'SELECT kind, attendance_date::text AS dk, payload FROM attendance_records WHERE patient_id = \$1 ORDER BY kind, attendance_date',
        [patientId],
      );
      expect(pgInitialAtt, isEmpty);

      // 4. Retrieve patient via getPatient, getPatientByRegistrationNumber, and searchPatients
      final fetched = await patientService.getPatient(patientId);
      expect(fetched, isNotNull);
      expect(fetched!.fullName, 'Ramesh Kumar');
      expect(fetched.registrationNumber, '1');
      expect(fetched.attendants, hasLength(1));
      expect(fetched.attendants!.first.name, 'Suresh Kumar');

      final byRegNo = await patientService.getPatientByRegistrationNumber('1');
      expect(byRegNo, isNotNull);
      expect(byRegNo!.id, patientId);

      final searchResults = await patientService.searchPatients('Ramesh').first;
      expect(searchResults.map((p) => p.id), contains(patientId));

      // Verify SQLite cache was updated after server acknowledgement
      final cachedPatient = await cache.read('patients/$patientId') as Map?;
      expect(cachedPatient, isNotNull);
      expect(cachedPatient!['fullName'], 'Ramesh Kumar');

      // 5. Edge/Failure cases:
      // Duplicate registration number must fail with 409 and NOT overwrite cache or insert duplicate
      await expectLater(
        () => patientService.addPatient(
          fullName: 'Duplicate Reg Patient',
          dateOfBirth: DateTime(1980, 1, 1),
          gender: 'Female',
          contactNumber: '9000000000',
          emergencyContact: '9000000001',
          emergencyContactName: 'Kin',
          medicalCondition: 'Observation',
          admissionDate: admissionDate,
          registrationNumber: regNo1, // duplicate '1'
          createdBy: 'test-uid-admin',
        ),
        throwsA(anything),
      );

      final totalPatientsInPg = (await queryRows(
        'SELECT count(*)::int AS cnt FROM patients',
      )).single['cnt'];
      expect(totalPatientsInPg, 1);

      // Invalid payload / missing required fields via BackendApiService -> 400
      await expectLater(
        () => backendApi.createPatient({'id': 'bad_patient'}),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
      expect(await cache.read('patients/bad_patient'), isNull);
    },
  );

  test(
    'Atomic Flutter registration persists placement and attendants without attendance, preserves retries, and rolls back a conflicting second bed',
    () async {
      await roomService.addRoom(
        id: 'room_atomic_flutter',
        roomNumber: 'Atomic QA',
        roomIdentifier: '1A',
        floor: 1,
        roomType: 'general',
        totalBeds: 2,
        bedLabels: ['Atomic-1', 'Atomic-2'],
      );
      final room = (await roomService.getRoomDirect('room_atomic_flutter'))!;
      final bed1 = room.beds[0].id;
      final bed2 = room.beds[1].id;
      final admission = DateTime.utc(2026, 10, 10);
      final exit = DateTime.utc(2026, 10, 12);
      final stays = <Map<String, dynamic>>[
        {
          'id': 'stay_atomic_flutter_first',
          'roomId': room.id,
          'bedId': bed1,
          'admissionDate': admission.millisecondsSinceEpoch,
          'durationDays': 3,
          'attendantCount': 2,
          'cycleId': admission.millisecondsSinceEpoch.toString(),
        },
      ];
      Future<String> register(
        String id,
        List<Map<String, dynamic>> placements,
      ) {
        return patientService.addPatient(
          id: id,
          fullName: 'Synthetic atomic Flutter patient',
          dateOfBirth: DateTime.utc(1990, 1, 1),
          gender: 'Other',
          contactNumber: '0000000000',
          emergencyContact: '0000000000',
          emergencyContactName: 'Synthetic contact',
          medicalCondition: 'Synthetic QA',
          admissionDate: admission,
          exitDate: exit,
          registrationDate: admission,
          registrationNumber: id,
          createdBy: 'test-uid-admin',
          initialTotalAmount: 600,
          initialStays: placements,
          attendants: [
            AttendantModel(name: 'Synthetic helper one', relation: 'Sibling'),
            AttendantModel(name: 'Synthetic helper two', relation: 'Parent'),
          ],
        );
      }

      const patientId = 'p_atomic_flutter';
      final timer = Stopwatch()..start();
      expect(await register(patientId, stays), patientId);
      final registrationMs = timer.elapsedMilliseconds;
      final saved = (await patientService.getPatient(patientId))!;
      expect(saved.registrationNumber, patientId);
      expect(saved.bedIds, [bed1]);
      expect(saved.attendants!.map((a) => a.name), [
        'Synthetic helper one',
        'Synthetic helper two',
      ]);
      expect(
        (await queryRows(
          'SELECT status,current_patient_id,current_stay_id FROM room_beds WHERE id=\$1',
          [bed1],
        )).single,
        {
          'status': 'occupied',
          'current_patient_id': patientId,
          'current_stay_id': 'stay_atomic_flutter_first',
        },
      );
      expect(
        (await queryRows('SELECT occupied_beds FROM rooms WHERE id=\$1', [
          room.id,
        ])).single['occupied_beds'],
        1,
      );
      final attendance = await queryRows(
        'SELECT kind,attendance_date::text AS day,payload FROM attendance_records WHERE patient_id=\$1 ORDER BY kind,attendance_date',
        [patientId],
      );
      expect(attendance, isEmpty);

      await backendApi.createPayment({
        'id': 'atomic_flutter_cash',
        'patientId': patientId,
        'amount': '50.00',
        'method': 'Cash',
      });
      final beforeRetry = (await queryRows(
        'SELECT * FROM patients WHERE id=\$1',
        [patientId],
      )).single;
      expect(await register(patientId, stays), patientId);
      expect(
        (await queryRows('SELECT * FROM patients WHERE id=\$1', [
          patientId,
        ])).single,
        beforeRetry,
      );
      expect(
        (await queryRows(
          'SELECT * FROM attendance_records WHERE patient_id=\$1 ORDER BY kind,attendance_date',
          [patientId],
        )).length,
        0,
      );
      expect(
        (await cache.read('patients/$patientId') as Map)['totalPaidAmount'],
        50,
      );

      await expectLater(
        () => backendApi.registerPatient({
          ...saved.toMap(),
          'stays': [
            {...stays.single, 'bedId': bed2},
          ],
        }),
        throwsA(
          isA<BackendApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            409,
          ),
        ),
      );
      expect(
        (await queryRows('SELECT * FROM patients WHERE id=\$1', [
          patientId,
        ])).single,
        beforeRetry,
      );

      await expectLater(
        () => register('p_atomic_rollback', [
          {...stays.single, 'id': 'stay_atomic_rollback_free', 'bedId': bed2},
          {...stays.single, 'id': 'stay_atomic_rollback_occupied'},
        ]),
        throwsA(anything),
      );
      for (final table in [
        'patients',
        'patient_attendants',
        'stays',
        'attendance_records',
      ]) {
        final key = table == 'patients' ? 'id' : 'patient_id';
        expect(
          (await queryRows(
            'SELECT count(*)::int AS count FROM $table WHERE $key=\$1',
            ['p_atomic_rollback'],
          )).single['count'],
          0,
        );
      }
      expect(
        (await queryRows(
          'SELECT status,current_stay_id FROM room_beds WHERE id=\$1',
          [bed2],
        )).single,
        {'status': 'available', 'current_stay_id': null},
      );
      expect(
        (await queryRows(
          'SELECT count(*)::int AS count FROM stays WHERE patient_id=\$1',
          [patientId],
        )).single['count'],
        1,
      );
      expect(
        (await queryRows(
          'SELECT count(*)::int AS count FROM patient_attendants WHERE patient_id=\$1',
          [patientId],
        )).single['count'],
        2,
      );
      expect(
        (await queryRows(
          'SELECT count(*)::int AS count FROM payments WHERE patient_id=\$1',
          [patientId],
        )).single['count'],
        1,
      );
      // ignore: avoid_print
      print(
        'FLUTTER_ATOMIC_POSTGRES_E2E registrationMs=$registrationMs patient=$patientId occupiedBeds=1 attendants=2 attendanceRows=0 identicalRetry=preserved differentBed=409 secondBedFailure=rolledBack',
      );
    },
  );

  test(
    'Workflow C: Admission & Bed Allocation (Single Bed, Second Patient, Conflict 409, Concurrent Race, Atomic Multi-Bed Batch)',
    () async {
      // Create room with 2 beds
      await roomService.addRoom(
        id: 'room_201',
        roomNumber: '201',
        roomIdentifier: '1B',
        floor: 1,
        roomType: 'general',
        totalBeds: 2,
        bedLabels: ['201-1', '201-2'],
      );
      final createdRoom201 = (await roomService.getRoomDirect('room_201'))!;
      final bed1Id = createdRoom201.beds[0].id;
      final bed2Id = createdRoom201.beds[1].id;

      final p1Id = await patientService.addPatient(
        fullName: 'Anita Sharma',
        dateOfBirth: DateTime(1985, 4, 12),
        gender: 'Female',
        contactNumber: '9811111111',
        emergencyContact: '9822222222',
        emergencyContactName: 'Raj Sharma',
        medicalCondition: 'Dialysis',
        admissionDate: DateTime(2026, 3, 10),
        exitDate: DateTime(2026, 3, 15),
        registrationNumber: '10',
        createdBy: 'test-uid-admin',
      );

      final p2Id = await patientService.addPatient(
        fullName: 'Vikram Patel',
        dateOfBirth: DateTime(1978, 8, 22),
        gender: 'Male',
        contactNumber: '9833333333',
        emergencyContact: '9844444444',
        emergencyContactName: 'Meera Patel',
        medicalCondition: 'Chemo',
        admissionDate: DateTime(2026, 3, 10),
        exitDate: DateTime(2026, 3, 15),
        registrationNumber: '11',
        createdBy: 'test-uid-admin',
      );

      // 1. Admit Patient 1 into Bed 1
      final stay1Id = await roomService.createStay(
        patientId: p1Id,
        patientName: 'Anita Sharma',
        roomId: 'room_201',
        roomNumber: '1B',
        roomType: 'general',
        bedId: bed1Id,
        bedLabel: '201-1',
        admissionDate: DateTime(2026, 3, 10),
        durationDays: 5,
        attendantCount: 1,
        createdBy: 'test-uid-admin',
      );
      expect(stay1Id, isNotEmpty);

      // Verify PostgreSQL tables: stays, room_beds, rooms, patients
      final pgStay1 = (await queryRows(
        'SELECT id, patient_id, room_id, bed_id, status, duration_days FROM stays WHERE id = \$1',
        [stay1Id],
      )).single;
      expect(pgStay1['patient_id'], p1Id);
      expect(pgStay1['bed_id'], bed1Id);
      expect(pgStay1['status'], 'active');

      final pgBed1 = (await queryRows(
        'SELECT status, current_patient_id, current_stay_id FROM room_beds WHERE id = \$1',
        [bed1Id],
      )).single;
      expect(pgBed1['status'], 'occupied');
      expect(pgBed1['current_patient_id'], p1Id);
      expect(pgBed1['current_stay_id'], stay1Id);

      final pgRoomAfter1 = (await queryRows(
        'SELECT occupied_beds, status FROM rooms WHERE id = \$1',
        ['room_201'],
      )).single;
      expect(pgRoomAfter1['occupied_beds'], 1);
      expect(pgRoomAfter1['status'], 'partially_occupied');

      final pgPatient1 = (await queryRows(
        'SELECT room_id, room_number, bed_ids, bed_labels FROM patients WHERE id = \$1',
        [p1Id],
      )).single;
      expect(pgPatient1['room_id'], 'room_201');
      expect(pgPatient1['bed_ids'], [bed1Id]);

      // 2. Attempt to allocate already occupied Bed 1 to Patient 2 -> must throw BedConflictException
      await expectLater(
        () => roomService.createStay(
          patientId: p2Id,
          patientName: 'Vikram Patel',
          roomId: 'room_201',
          roomNumber: '1B',
          roomType: 'general',
          bedId: bed1Id,
          bedLabel: '201-1',
          admissionDate: DateTime(2026, 3, 10),
          durationDays: 5,
          attendantCount: 0,
          createdBy: 'test-uid-admin',
        ),
        throwsA(isA<BedConflictException>()),
      );

      // 3. Concurrent conflicting allocation attempts for Bed 2
      final p3Id = await patientService.addPatient(
        fullName: 'Concurrent Challenger',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: 'Male',
        contactNumber: '9855555555',
        emergencyContact: '9866666666',
        emergencyContactName: 'Kin',
        medicalCondition: 'Checkup',
        admissionDate: DateTime(2026, 3, 10),
        registrationNumber: '12',
        createdBy: 'test-uid-admin',
      );

      final raceOutcomes = await Future.wait([
        roomService
            .createStay(
              patientId: p2Id,
              patientName: 'Vikram Patel',
              roomId: 'room_201',
              roomNumber: '1B',
              roomType: 'general',
              bedId: bed2Id,
              bedLabel: '201-2',
              admissionDate: DateTime(2026, 3, 10),
              durationDays: 5,
              attendantCount: 0,
              createdBy: 'test-uid-admin',
            )
            .then((_) => 'ok')
            .catchError(
              (Object e) => e is BedConflictException ? 'conflict' : 'other:$e',
            ),
        roomService
            .createStay(
              patientId: p3Id,
              patientName: 'Concurrent Challenger',
              roomId: 'room_201',
              roomNumber: '1B',
              roomType: 'general',
              bedId: bed2Id,
              bedLabel: '201-2',
              admissionDate: DateTime(2026, 3, 10),
              durationDays: 5,
              attendantCount: 0,
              createdBy: 'test-uid-admin',
            )
            .then((_) => 'ok')
            .catchError(
              (Object e) => e is BedConflictException ? 'conflict' : 'other:$e',
            ),
      ]);
      expect(raceOutcomes..sort(), ['conflict', 'ok']);

      // Verify room_201 now has 2 occupied beds and status 'occupied'
      final pgRoomAfter2 = (await queryRows(
        'SELECT occupied_beds, status FROM rooms WHERE id = \$1',
        ['room_201'],
      )).single;
      expect(pgRoomAfter2['occupied_beds'], 2);
      expect(pgRoomAfter2['status'], 'occupied');

      // 4. Multi-bed atomic batch admission via RoomService.createStaysForBeds
      await roomService.addRoom(
        id: 'room_202',
        roomNumber: '202',
        roomIdentifier: '1C',
        floor: 1,
        roomType: 'general',
        totalBeds: 2,
        bedLabels: ['202-1', '202-2'],
      );
      final pMultiId = await patientService.addPatient(
        fullName: 'Multi Bed Patient',
        dateOfBirth: DateTime(1982, 2, 2),
        gender: 'Female',
        contactNumber: '9877777777',
        emergencyContact: '9888888888',
        emergencyContactName: 'Kin',
        medicalCondition: 'Recovery',
        admissionDate: DateTime(2026, 3, 10),
        registrationNumber: '13',
        createdBy: 'test-uid-admin',
      );
      final room202 = (await roomService.getRoomDirect('room_202'))!;
      final room202BedIds = room202.beds.map((b) => b.id).toList();
      final batchIds = await roomService.createStaysForBeds(
        patientId: pMultiId,
        patientName: 'Multi Bed Patient',
        roomId: 'room_202',
        bedIds: room202BedIds,
        admissionDate: DateTime(2026, 3, 10),
        durationDays: 4,
        attendantCount: 2,
        createdBy: 'test-uid-admin',
      );
      expect(batchIds, hasLength(2));
      final multiPatient = (await patientService.getPatient(pMultiId))!;
      expect(multiPatient.bedIds!.toSet(), room202BedIds.toSet());
    },
  );

  test(
    'Workflow D: Attendance (Mark Present/Absent, Upsert, Range Query, Attendant JSONB Merge, Calendar Date Preservation, Invalid Rejection)',
    () async {
      final pId = await patientService.addPatient(
        fullName: 'Meena Devi',
        dateOfBirth: DateTime(1970, 6, 15),
        gender: 'Female',
        contactNumber: '9711111111',
        emergencyContact: '9722222222',
        emergencyContactName: 'Mohan',
        medicalCondition: 'Observation',
        admissionDate: DateTime(2026, 4, 1, 8, 0),
        exitDate: DateTime(2026, 4, 5, 8, 0),
        registrationNumber: '20',
        createdBy: 'test-uid-admin',
        attendants: [
          AttendantModel(name: 'Mohan', age: '45', relation: 'Husband'),
          AttendantModel(name: 'Sita', age: '22', relation: 'Daughter'),
        ],
      );

      final patient = (await patientService.getPatient(pId))!;

      // 1. Load month via AttendanceService and mark Present/Absent using MonthlyAttendanceEditor
      final monthData = await attendanceService.loadMonth(DateTime(2026, 4));
      final editor = MonthlyAttendanceEditor(monthData);
      final rows = monthData.rows(
        [patient],
        const [],
        now: DateTime(2026, 4, 5),
      );
      final patientRow = rows.firstWhere(
        (r) => r.patientId == pId && !r.isAttendant,
      );
      final att1Row = rows.firstWhere(
        (r) => r.patientId == pId && r.attendantName == 'Mohan',
      );
      final att2Row = rows.firstWhere(
        (r) => r.patientId == pId && r.attendantName == 'Sita',
      );

      editor.edit(patientRow, DateTime(2026, 4, 1), 'Present');
      editor.edit(att1Row, DateTime(2026, 4, 1), 'Present');
      // Edit attendance on 2026-04-02 (Absent) and attendants on 2026-04-01
      editor.edit(patientRow, DateTime(2026, 4, 2), 'Absent');
      editor.edit(att2Row, DateTime(2026, 4, 1), 'Absent');

      final affected = await editor.save(null, backendApi);
      expect(affected, contains(pId));

      // Update existing date 2026-04-02 from Absent to Present (idempotent upsert)
      await backendApi.postAttendance(
        kind: 'attendance',
        date: '2026-04-02',
        patientId: pId,
        payload: {'status': 'Present', 'name': 'Meena Devi'},
      );

      // 2. Verify PostgreSQL attendance_records rows and exact calendar date preservation
      final pgPatientAtt = await queryRows(
        "SELECT attendance_date::text AS dk, payload->>'status' AS status, payload FROM attendance_records WHERE kind = 'attendance' AND patient_id = \$1 AND attendance_date IN ('2026-04-01', '2026-04-02') ORDER BY attendance_date",
        [pId],
      );
      expect(pgPatientAtt, hasLength(2));
      expect(pgPatientAtt[0]['dk'], '2026-04-01');
      expect(pgPatientAtt[0]['status'], 'Present');
      expect(pgPatientAtt[1]['dk'], '2026-04-02');
      expect(pgPatientAtt[1]['status'], 'Present');

      final pgAttendantRow = (await queryRows(
        "SELECT attendance_date::text AS dk, payload FROM attendance_records WHERE kind = 'attendant_attendance' AND patient_id = \$1 AND attendance_date = '2026-04-01'",
        [pId],
      )).single;
      expect(pgAttendantRow['dk'], '2026-04-01');
      final attPayload = Map<String, dynamic>.from(
        pgAttendantRow['payload'] as Map,
      );
      expect((attPayload['Mohan'] as Map)['status'], 'Present');
      expect((attPayload['Sita'] as Map)['status'], 'Absent');

      // 3. Retrieve historical range via BackendApiService.getAttendanceRange and AttendanceService.loadMonth
      final rangeMap = await backendApi.getAttendanceRange(
        kind: 'attendance',
        startKey: '2026-04-01',
        endKey: '2026-04-02',
      );
      expect((rangeMap['2026-04-01'][pId] as Map)['status'], 'Present');
      expect((rangeMap['2026-04-02'][pId] as Map)['status'], 'Present');

      final reloadedMonth = await attendanceService.loadMonth(
        DateTime(2026, 4),
      );
      final reloadedEditor = MonthlyAttendanceEditor(reloadedMonth);
      expect(
        reloadedEditor.status(patientRow, DateTime(2026, 4, 1)),
        'Present',
      );
      expect(
        reloadedEditor.status(patientRow, DateTime(2026, 4, 2)),
        'Present',
      );
      expect(reloadedEditor.status(att1Row, DateTime(2026, 4, 1)), 'Present');
      expect(reloadedEditor.status(att2Row, DateTime(2026, 4, 1)), 'Absent');

      // 4. Edge/Failure cases: invalid date format & non-existent patient ID
      await expectLater(
        () => backendApi.postAttendanceBulk(
          kind: 'attendance',
          date: '2026-13-45',
          records: {
            pId: {'status': 'Present'},
          },
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            400,
          ),
        ),
      );

      await expectLater(
        () => backendApi.postAttendanceBulk(
          kind: 'attendance',
          date: '2026-04-03',
          records: {
            'non_existent_patient_999': {'status': 'Present'},
          },
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            409,
          ),
        ),
      );
    },
  );

  test(
    'Workflow E & F: Track Patient/Stay, Extend Stay, and Discharge Patient (Partial Room Occupancy, Full Discharge, Repeat Safety, Mid-Discharge Rollback)',
    () async {
      await roomService.addRoom(
        id: 'room_301',
        roomNumber: '301',
        roomIdentifier: '1A',
        floor: 1,
        roomType: 'general',
        totalBeds: 2,
        bedLabels: ['301-A', '301-B'],
      );
      final room301 = (await roomService.getRoomDirect('room_301'))!;
      final bed1Id = room301.beds[0].id;
      final bed2Id = room301.beds[1].id;

      final admission = DateTime(2026, 4, 10, 8, 0);
      final plannedExit = DateTime(2026, 4, 12, 8, 0);

      final p1Id = await patientService.addPatient(
        fullName: 'Kiran Desai',
        dateOfBirth: DateTime(1968, 11, 5),
        gender: 'Male',
        contactNumber: '9611111111',
        emergencyContact: '9622222222',
        emergencyContactName: 'Neha Desai',
        medicalCondition: 'Radiation therapy',
        admissionDate: admission,
        exitDate: plannedExit,
        registrationNumber: '30',
        advanceBilledAmount: 0,
        initialTotalAmount: 0,
        createdBy: 'test-uid-admin',
      );

      final p2Id = await patientService.addPatient(
        fullName: 'Deepak Verma',
        dateOfBirth: DateTime(1972, 3, 18),
        gender: 'Male',
        contactNumber: '9633333333',
        emergencyContact: '9644444444',
        emergencyContactName: 'Pooja Verma',
        medicalCondition: 'Checkup',
        admissionDate: admission,
        exitDate: plannedExit,
        registrationNumber: '31',
        advanceBilledAmount: 0,
        initialTotalAmount: 0,
        createdBy: 'test-uid-admin',
      );

      final stay1Id = await roomService.createStay(
        patientId: p1Id,
        patientName: 'Kiran Desai',
        roomId: 'room_301',
        roomNumber: '1A',
        roomType: 'general',
        bedId: bed1Id,
        bedLabel: '301-A',
        admissionDate: admission,
        durationDays: 2,
        attendantCount: 0,
        createdBy: 'test-uid-admin',
      );

      final stay2Id = await roomService.createStay(
        patientId: p2Id,
        patientName: 'Deepak Verma',
        roomId: 'room_301',
        roomNumber: '1A',
        roomType: 'general',
        bedId: bed2Id,
        bedLabel: '301-B',
        admissionDate: admission,
        durationDays: 2,
        attendantCount: 0,
        createdBy: 'test-uid-admin',
      );

      // Workflow E: Track patient & stay, extend stay for Patient 2
      await roomService.extendStay(
        stayId: stay2Id,
        additionalDays: 2,
        reason: 'Extended recovery',
      );
      final stays2 = await roomService.getStaysByPatientStream(p2Id).first;
      final trackedStay2 = stays2.firstWhere((s) => s.id == stay2Id);
      expect(trackedStay2.durationDays, 4);
      expect(trackedStay2.bedId, bed2Id);

      // Workflow F (Part 1): Test mid-discharge failure rollback using a PostgreSQL trigger
      await execSql(
        "CREATE FUNCTION e2e_fail_discharge() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION 'simulated discharge failure'; END \$\$; "
        "CREATE TRIGGER e2e_fail_discharge BEFORE UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION e2e_fail_discharge()",
      );
      try {
        await expectLater(
          () => roomService.completeStay(stay1Id, completedAt: plannedExit),
          throwsA(anything),
        );
        // Verify stay1 and bed1Id were NOT partially updated!
        final stayRowAfterFail = (await queryRows(
          'SELECT status FROM stays WHERE id = \$1',
          [stay1Id],
        )).single;
        expect(stayRowAfterFail['status'], 'active');

        final bedRowAfterFail = (await queryRows(
          'SELECT status, current_patient_id FROM room_beds WHERE id = \$1',
          [bed1Id],
        )).single;
        expect(bedRowAfterFail['status'], 'occupied');
        expect(bedRowAfterFail['current_patient_id'], p1Id);
      } finally {
        await execSql(
          'DROP TRIGGER e2e_fail_discharge ON patients; DROP FUNCTION e2e_fail_discharge()',
        );
      }

      // Workflow F (Part 2): Settle any billing due for Patient 1 and discharge Patient 1 via PatientService.dischargePatient
      for (final day in ['2026-04-10', '2026-04-11', '2026-04-12']) {
        await backendApi.postAttendance(
          kind: 'attendance',
          date: day,
          patientId: p1Id,
          payload: {'status': 'Present', 'date': day, 'source': 'manual'},
        );
      }
      final readiness1 = await patientService.getDischargeReadiness(p1Id);
      final pending1 = (readiness1['pending'] as num?)?.toDouble() ?? 0;
      if (pending1 > 0) {
        await paymentService.recordPayment(
          patientId: p1Id,
          patientName: 'Kiran Desai',
          payment: PaymentModel(
            id: 'pay_settle_p1',
            amount: pending1,
            date: DateTime(2026, 4, 12),
            method: 'CASH',
            notes: 'Settlement',
          ),
        );
      }
      await patientService.dischargePatient(p1Id);

      // Verify in PostgreSQL:
      // - Patient 1 is discharged, room_id cleared, bed1Id available
      // - Patient 2's bed2Id is STILL occupied, and room_301 is partially_occupied with occupied_beds = 1
      final pgP1 = (await queryRows(
        'SELECT status, room_id, bed_ids FROM patients WHERE id = \$1',
        [p1Id],
      )).single;
      expect(pgP1['status'], 'discharged');
      expect(pgP1['room_id'], isNull);
      expect(pgP1['bed_ids'], isEmpty);

      final pgStay1After = (await queryRows(
        'SELECT status, completed_at FROM stays WHERE id = \$1',
        [stay1Id],
      )).single;
      expect(pgStay1After['status'], 'completed');
      expect(pgStay1After['completed_at'], isNotNull);

      final pgBed1After = (await queryRows(
        'SELECT id, status, current_patient_id, current_stay_id FROM room_beds WHERE id = \$1',
        [bed1Id],
      )).single;
      expect(pgBed1After['status'], 'available');
      expect(pgBed1After['current_patient_id'], isNull);
      expect(pgBed1After['current_stay_id'], isNull);

      final pgBed2After = (await queryRows(
        'SELECT id, status, current_patient_id, current_stay_id FROM room_beds WHERE id = \$1',
        [bed2Id],
      )).single;
      expect(pgBed2After['status'], 'occupied');
      expect(pgBed2After['current_patient_id'], p2Id);
      expect(pgBed2After['current_stay_id'], stay2Id);

      final pgRoomAfter1 = (await queryRows(
        'SELECT occupied_beds, status FROM rooms WHERE id = \$1',
        ['room_301'],
      )).single;
      expect(pgRoomAfter1['occupied_beds'], 1);
      expect(pgRoomAfter1['status'], 'partially_occupied');

      // Repeated completion of stay1Id is safe and idempotent
      await roomService.completeStay(stay1Id, completedAt: plannedExit);
    },
  );

  test(
    'Workflow G: Cash & UPI QR Payments (Balances, Idempotency, Exact Decimal Arithmetic, Concurrency, Rollback on Failure)',
    () async {
      final pId = await patientService.addPatient(
        fullName: 'Arjun Mehta',
        dateOfBirth: DateTime(1980, 7, 10),
        gender: 'Male',
        contactNumber: '9511111111',
        emergencyContact: '9522222222',
        emergencyContactName: 'Kavita Mehta',
        medicalCondition: 'Post-surgery',
        admissionDate: DateTime(2026, 4, 1, 8, 0),
        exitDate: DateTime(2026, 4, 4, 8, 0),
        registrationNumber: '40',
        advanceBilledAmount: 1000,
        initialTotalAmount: 1000,
        createdBy: 'test-uid-admin',
      );

      // Set initial current_due_amount to 1000.00 in PostgreSQL so we can verify exact balance reductions
      await execSql(
        'UPDATE patients SET current_due_amount = 1000.00, total_paid_amount = 0.00 WHERE id = \$1',
        [pId],
      );

      // 1. Record Cash payment via PaymentService.recordPayment
      await paymentService.recordPayment(
        patientId: pId,
        patientName: 'Arjun Mehta',
        payment: PaymentModel(
          id: 'pay_cash_400',
          amount: 400.00,
          date: DateTime(2026, 4, 1),
          method: 'CASH',
          notes: 'Cash advance at counter',
        ),
      );

      // 2. Record UPI QR payment via PaymentService.recordPayment (method: 'ONLINE')
      await paymentService.recordPayment(
        patientId: pId,
        patientName: 'Arjun Mehta',
        payment: PaymentModel(
          id: 'pay_upi_temp',
          amount: 350.00,
          date: DateTime(2026, 4, 2),
          method: 'ONLINE',
          transactionId: 'UPI20260401998877',
          notes: 'Scanned NGO UPI QR',
        ),
      );

      // Verify PostgreSQL payments rows and patients balance columns
      final pgPayments = await queryRows(
        'SELECT id, method, amount::text, payment_status, transaction_id, notes FROM payments WHERE patient_id = \$1 ORDER BY amount DESC',
        [pId],
      );
      expect(pgPayments, hasLength(2));
      expect(pgPayments[0]['method'], 'CASH');
      expect(pgPayments[0]['amount'], '400.00');
      expect(pgPayments[0]['payment_status'], 'Paid');

      expect(pgPayments[1]['method'], 'ONLINE');
      expect(pgPayments[1]['amount'], '350.00');
      expect(pgPayments[1]['transaction_id'], 'UPI20260401998877');
      expect((pgPayments[1]['id'] as String).length, lessThanOrEqualTo(64));

      // 3. Duplicate UPI QR submission with the same transactionId is idempotent (applies balance once)
      await paymentService.recordPayment(
        patientId: pId,
        patientName: 'Arjun Mehta',
        payment: PaymentModel(
          id: 'pay_upi_retry',
          amount: 350.00,
          date: DateTime(2026, 4, 2),
          method: 'ONLINE',
          transactionId: 'UPI20260401998877',
          notes: 'Scanned NGO UPI QR',
        ),
      );
      final countAfterDup = (await queryRows(
        'SELECT count(*)::int AS cnt FROM payments WHERE patient_id = \$1',
        [pId],
      )).single['cnt'];
      expect(countAfterDup, 2);

      // Conflicting reuse of same transactionId with different amount must fail
      await expectLater(
        () => paymentService.recordPayment(
          patientId: pId,
          patientName: 'Arjun Mehta',
          payment: PaymentModel(
            id: 'pay_upi_conflict',
            amount: 999.00,
            date: DateTime(2026, 4, 2),
            method: 'ONLINE',
            transactionId: 'UPI20260401998877',
          ),
        ),
        throwsA(anything),
      );

      // 4. Exact decimal precision & concurrent payment writes (0.10 + 0.20 = 0.30)
      await Future.wait([
        backendApi.createPayment({
          'id': 'pay_dec_10',
          'patientId': pId,
          'patientName': 'Arjun Mehta',
          'amount': '0.10',
          'method': 'cash',
        }),
        backendApi.createPayment({
          'id': 'pay_dec_20',
          'patientId': pId,
          'patientName': 'Arjun Mehta',
          'amount': '0.20',
          'method': 'upi_qr',
          'transactionId': 'upi-cents-20',
        }),
      ]);

      final sumRow = (await queryRows(
        'SELECT sum(amount)::text AS total FROM payments WHERE patient_id = \$1',
        [pId],
      )).single;
      expect(sumRow['total'], '750.30');

      // 5. Retrieve payment history via PatientService
      final refreshedPatient = (await patientService.getPatient(pId))!;
      expect(refreshedPatient.payments, isNotNull);
      expect(refreshedPatient.payments!.length, 4);

      // 6. Transaction rollback if patient balance update fails midway
      await execSql(
        "CREATE FUNCTION e2e_fail_payment() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION 'simulated balance failure'; END \$\$; "
        "CREATE TRIGGER e2e_fail_payment BEFORE UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION e2e_fail_payment()",
      );
      try {
        await expectLater(
          () => backendApi.createPayment({
            'id': 'pay_should_rollback',
            'patientId': pId,
            'amount': '50.00',
            'method': 'cash',
          }),
          throwsA(
            isA<BackendApiException>().having(
              (e) => e.statusCode,
              'statusCode',
              500,
            ),
          ),
        );
        final rolledBackRow = await queryRows(
          'SELECT id FROM payments WHERE id = \$1',
          ['pay_should_rollback'],
        );
        expect(rolledBackRow, isEmpty);
        expect(await cache.read('payments/pay_should_rollback'), isNull);
      } finally {
        await execSql(
          'DROP TRIGGER e2e_fail_payment ON patients; DROP FUNCTION e2e_fail_payment()',
        );
      }
    },
  );

  test(
    'Receipt retry, refund, edit and delete keep authoritative balances exact',
    () async {
      final patientId = await patientService.addPatient(
        id: 'p_financial_accuracy',
        fullName: 'Synthetic financial accuracy',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: 'Other',
        contactNumber: '9000000101',
        emergencyContact: '',
        emergencyContactName: '',
        medicalCondition: 'Synthetic',
        admissionDate: DateTime(2026, 4, 1, 8),
        exitDate: DateTime(2026, 4, 4, 8),
        registrationNumber: '9901',
        initialTotalAmount: 1000,
        createdBy: 'test-uid-admin',
      );
      Future<void> balances(double paid, double due, double refund) async {
        final patient = (await patientService.getPatient(patientId))!;
        expect(patient.totalPaidAmount, paid);
        expect(patient.currentDueAmount, due);
        expect(patient.refundDueAmount, refund);
        final ledger = (await queryRows(
          'SELECT COALESCE(SUM(amount),0)::text AS net FROM payments WHERE patient_id=\$1',
          [patientId],
        )).single;
        expect(double.parse(ledger['net'] as String), paid);
      }

      await paymentService.recordPayment(
        patientId: patientId,
        patientName: 'Synthetic financial accuracy',
        payment: PaymentModel(
          id: 'accuracy_cash',
          amount: 300,
          method: 'CASH',
          date: DateTime(2026, 4, 1),
        ),
      );
      await balances(300, 700, 0);
      final onlineId = await paymentService.recordPayment(
        patientId: patientId,
        patientName: 'Synthetic financial accuracy',
        payment: PaymentModel(
          id: 'accuracy_online',
          amount: 900,
          method: 'ONLINE',
          transactionId: 'QA202604010009',
          date: DateTime(2026, 4, 2),
        ),
      );
      await balances(1200, 0, 200);
      expect(
        await paymentService.recordPayment(
          patientId: patientId,
          patientName: 'Synthetic financial accuracy',
          payment: PaymentModel(
            id: 'retry_with_new_ui_date',
            amount: 900,
            method: 'ONLINE',
            transactionId: 'QA202604010009',
            date: DateTime(2026, 4, 3),
          ),
        ),
        onlineId,
      );
      expect(
        (await queryRows('SELECT id FROM payments WHERE patient_id=\$1', [
          patientId,
        ])),
        hasLength(2),
      );
      final cycle = StayBilling.currentCycle(
        (await patientService.getPatient(patientId))!,
      );
      await paymentService.recordRefund(
        patientId: patientId,
        cycleId: cycle,
        amount: 100,
        date: DateTime(2026, 4, 3),
        method: 'CASH',
        requestId: 'accuracy_refund',
      );
      await balances(1100, 0, 100);
      // A UI retry with a later timestamp returns the already committed refund.
      expect(
        await paymentService.recordRefund(
          patientId: patientId,
          cycleId: cycle,
          amount: 100,
          date: DateTime(2026, 4, 4),
          method: 'CASH',
          requestId: 'accuracy_refund',
        ),
        'accuracy_refund',
      );
      expect(
        (await queryRows('SELECT id FROM payments WHERE patient_id=\$1', [
          patientId,
        ])),
        hasLength(3),
      );
      await paymentService.updatePaymentDetails(
        patientId,
        'accuracy_cash',
        'QA-CASH-EDIT',
        DateTime(2026, 4, 1),
        amount: 200,
      );
      await balances(1000, 0, 0);
      await paymentService.deletePayment(patientId, 'accuracy_cash');
      await balances(800, 200, 0);
      await paymentService.deletePayment(patientId, 'accuracy_cash');
      await balances(800, 200, 0);
      await expectLater(
        () => paymentService.deletePayment(patientId, onlineId),
        throwsA(anything),
      );
      await balances(800, 200, 0);
    },
  );

  test(
    'Attendance at configured 200 rate corrects charges without duplicate days',
    () async {
      await roomService.addRoom(
        id: 'r_attendance_accuracy',
        roomNumber: '1C',
        roomIdentifier: '1C',
        floor: 1,
        roomType: 'general',
        totalBeds: 1,
        bedLabels: ['QA-1'],
      );
      final room = (await roomService.getRoomDirect('r_attendance_accuracy'))!;
      final admission = DateTime(2026, 4, 1, 8);
      final exit = DateTime(2026, 4, 3, 9);
      final stays = await roomService.buildRegistrationStaysPayload(
        patientId: 'p_attendance_accuracy',
        patientName: 'Synthetic attendance accuracy',
        admissionDate: admission,
        durationDays: 2,
        attendantCount: 0,
        createdBy: 'test-uid-admin',
        room: room,
        bedIds: [room.beds.single.id],
      );
      await patientService.addPatient(
        id: 'p_attendance_accuracy',
        fullName: 'Synthetic attendance accuracy',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: 'Other',
        contactNumber: '9000000102',
        emergencyContact: '',
        emergencyContactName: '',
        medicalCondition: 'Synthetic',
        admissionDate: admission,
        registrationDate: admission,
        exitDate: exit,
        registrationNumber: '9902',
        createdBy: 'test-uid-admin',
        initialStays: stays,
      );
      await backendApi.updateSettingsCategory('pricing', {
        'generalRoomBedPrice': 200,
      });
      await roomService.completeStay(
        stays.single['id'] as String,
        completedAt: exit,
      );
      await backendApi.updatePatient('p_attendance_accuracy', {
        'status': 'discharged',
        'dischargeDate': exit.millisecondsSinceEpoch,
      });
      await paymentService.recalculatePatientAttendanceAndBilling(
        'p_attendance_accuracy',
      );
      expect(
        (await patientService.getPatient(
          'p_attendance_accuracy',
        ))!.currentDueAmount,
        600,
      );
      Future<void> mark(String date, String status, double expected) async {
        await backendApi.postAttendanceBulk(
          kind: 'attendance',
          date: date,
          records: {
            'p_attendance_accuracy': {
              'status': status,
              'patientId': 'p_attendance_accuracy',
            },
          },
        );
        await paymentService.recalculatePatientAttendanceAndBilling(
          'p_attendance_accuracy',
        );
        expect(
          (await patientService.getPatient(
            'p_attendance_accuracy',
          ))!.currentDueAmount,
          expected,
        );
      }

      // Preserve the existing policy: general-room absence reduces the charge.
      await mark('2026-04-01', 'Absent', 400);
      await mark('2026-04-02', 'Absent', 200);
      await mark('2026-04-01', 'Present', 400);
      final before = (await queryRows(
        "SELECT COUNT(*)::int AS count FROM attendance_records WHERE patient_id='p_attendance_accuracy'",
      )).single['count'];
      await mark('2026-04-01', 'Present', 400);
      expect(
        (await queryRows(
          "SELECT COUNT(*)::int AS count FROM attendance_records WHERE patient_id='p_attendance_accuracy'",
        )).single['count'],
        before,
      );
    },
  );

  test(
    'Receipt reconciliation reads the current server ledger and acknowledged receipt survives refresh outage',
    () async {
      final patientId = await patientService.addPatient(
        id: 'p_receipt_race',
        fullName: 'Synthetic receipt race',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: 'Other',
        contactNumber: '9000000103',
        emergencyContact: '',
        emergencyContactName: '',
        medicalCondition: 'Synthetic',
        admissionDate: DateTime(2026, 4, 1, 8),
        exitDate: DateTime(2026, 4, 4, 8),
        registrationNumber: '9903',
        initialTotalAmount: 100,
        createdBy: 'test-uid-admin',
      );
      await backendApi.postAttendance(
        kind: 'attendance',
        date: '2026-04-01',
        patientId: patientId,
        payload: {'status': 'Present', 'source': 'manual'},
      );
      var injected = false;
      var financialPuts = 0;
      diagnosticClient.beforeSend = (request) async {
        if (request.method != 'POST' || request.url.path != '/api/payments')
          return;
        financialPuts++;
        if (injected) return;
        injected = true;
        final response = await rawHttp.post(
          Uri.parse('$apiBaseUrl/payments'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $currentToken',
          },
          body: jsonEncode({
            'id': 'race_external',
            'patientId': patientId,
            'amount': 5,
            'method': 'CASH',
          }),
        );
        expect(response.statusCode, 201);
      };
      await paymentService.recordPayment(
        patientId: patientId,
        patientName: 'Synthetic receipt race',
        payment: PaymentModel(
          id: 'race_original',
          amount: 20,
          method: 'CASH',
          date: DateTime(2026, 4, 1),
        ),
      );
      diagnosticClient.beforeSend = null;
      expect(injected, isTrue);
      expect(
        financialPuts,
        1,
        reason:
            'The backend recalculates under the patient lock using current receipts',
      );
      var patient = (await patientService.getPatient(patientId))!;
      expect(patient.totalPaidAmount, 25);
      expect(patient.currentDueAmount, 75);
      diagnosticClient.afterSend = (request, response) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/payments' &&
            response.statusCode == 201) {
          await setDbOutage(true);
        }
      };
      try {
        expect(
          await paymentService.recordPayment(
            patientId: patientId,
            patientName: 'Synthetic receipt race',
            payment: PaymentModel(
              id: 'receipt_before_outage',
              amount: 5,
              method: 'CASH',
              date: DateTime(2026, 4, 2),
            ),
          ),
          'receipt_before_outage',
        );
      } finally {
        diagnosticClient.afterSend = null;
        await setDbOutage(false);
      }
      expect(
        await paymentService.recordPayment(
          patientId: patientId,
          patientName: 'Synthetic receipt race',
          payment: PaymentModel(
            id: 'receipt_before_outage',
            amount: 5,
            method: 'CASH',
            date: DateTime(2026, 4, 3),
          ),
        ),
        'receipt_before_outage',
      );
      patient = (await patientService.getPatient(patientId))!;
      expect(patient.totalPaidAmount, 30);
      expect(patient.currentDueAmount, 70);
      expect(
        (await queryRows('SELECT id FROM payments WHERE patient_id=\$1', [
          patientId,
        ])),
        hasLength(3),
      );
    },
  );

  test(
    'Combined End-to-End Lifecycle 1 (Full Patient Journey & Bed Reuse) and Lifecycle 2 (Multi-Bed Room Concurrency)',
    () async {
      // Step 1: Create room & 2 beds
      await roomService.addRoom(
        id: 'room_lifecycle',
        roomNumber: '102',
        roomIdentifier: '1C',
        floor: 1,
        roomType: 'general',
        totalBeds: 2,
        bedLabels: ['L-1', 'L-2'],
      );
      final createdRoom = (await roomService.getRoomDirect('room_lifecycle'))!;
      final bed1Id = createdRoom.beds[0].id;
      final bed2Id = createdRoom.beds[1].id;

      // Step 2: Register Patient A and Patient B
      final regA = await regNumService.allocateNextRegistrationNumber();
      final regB = await regNumService.allocateNextRegistrationNumber();

      final admission = DateTime(2026, 5, 1, 8, 0);
      final plannedExit = DateTime(2026, 5, 3, 8, 0);

      final patientAId = await patientService.addPatient(
        fullName: 'Lifecycle Patient A',
        dateOfBirth: DateTime(1975, 1, 10),
        gender: 'Female',
        contactNumber: '9411111111',
        emergencyContact: '9422222222',
        emergencyContactName: 'Kin A',
        medicalCondition: 'Oncology',
        admissionDate: admission,
        exitDate: plannedExit,
        registrationNumber: regA,
        advanceBilledAmount: 500,
        initialTotalAmount: 500,
        createdBy: 'test-uid-admin',
      );

      final patientBId = await patientService.addPatient(
        fullName: 'Lifecycle Patient B',
        dateOfBirth: DateTime(1980, 2, 20),
        gender: 'Male',
        contactNumber: '9433333333',
        emergencyContact: '9444444444',
        emergencyContactName: 'Kin B',
        medicalCondition: 'Surgery',
        admissionDate: admission,
        exitDate: plannedExit,
        registrationNumber: regB,
        advanceBilledAmount: 500,
        initialTotalAmount: 500,
        createdBy: 'test-uid-admin',
      );

      // Step 3: Admit Patient A to Bed 1
      final stayAId = await roomService.createStay(
        patientId: patientAId,
        patientName: 'Lifecycle Patient A',
        roomId: 'room_lifecycle',
        roomNumber: '102',
        roomType: 'general',
        bedId: bed1Id,
        bedLabel: 'L-1',
        admissionDate: admission,
        durationDays: 2,
        attendantCount: 0,
        createdBy: 'test-uid-admin',
      );
      expect(stayAId, isNotEmpty);

      // Step 4: Attempt to admit Patient B to Bed 1 -> must fail with BedConflictException
      await expectLater(
        () => roomService.createStay(
          patientId: patientBId,
          patientName: 'Lifecycle Patient B',
          roomId: 'room_lifecycle',
          roomNumber: '102',
          roomType: 'general',
          bedId: bed1Id,
          bedLabel: 'L-1',
          admissionDate: admission,
          durationDays: 2,
          attendantCount: 0,
          createdBy: 'test-uid-admin',
        ),
        throwsA(isA<BedConflictException>()),
      );

      // Step 5: Admit Patient B to Bed 2 -> succeeds
      final stayBId = await roomService.createStay(
        patientId: patientBId,
        patientName: 'Lifecycle Patient B',
        roomId: 'room_lifecycle',
        roomNumber: '102',
        roomType: 'general',
        bedId: bed2Id,
        bedLabel: 'L-2',
        admissionDate: admission,
        durationDays: 2,
        attendantCount: 0,
        createdBy: 'test-uid-admin',
      );
      expect(stayBId, isNotEmpty);

      // Step 6: Mark attendance for both patients across 2026-05-01 and 2026-05-02
      for (final dateKey in ['2026-05-01', '2026-05-02', '2026-05-03']) {
        await backendApi.postAttendanceBulk(
          kind: 'attendance',
          date: dateKey,
          records: {
            patientAId: {
              'status': 'Present',
              'name': 'Lifecycle Patient A',
              'cycleId': admission.millisecondsSinceEpoch.toString(),
            },
            patientBId: {
              'status': 'Present',
              'name': 'Lifecycle Patient B',
              'cycleId': admission.millisecondsSinceEpoch.toString(),
            },
          },
        );
      }

      // Step 7: Record Cash and UPI QR payments for Patient A
      await paymentService.recordPayment(
        patientId: patientAId,
        patientName: 'Lifecycle Patient A',
        payment: PaymentModel(
          id: 'pay_lc_a_cash',
          amount: 250,
          date: admission,
          method: 'CASH',
        ),
      );
      final readinessA = await patientService.getDischargeReadiness(patientAId);
      final remainingDueA = (readinessA['pending'] as num?)?.toDouble() ?? 0;
      if (remainingDueA > 0) {
        await paymentService.recordPayment(
          patientId: patientAId,
          patientName: 'Lifecycle Patient A',
          payment: PaymentModel(
            id: 'pay_lc_a_upi',
            amount: remainingDueA,
            date: plannedExit,
            method: 'ONLINE',
            transactionId: 'UTRLIFECYCLEAFINAL',
          ),
        );
      }

      // Step 8: Discharge Patient A
      await patientService.dischargePatient(patientAId);

      // Step 9: Verify Bed 1 is available while Bed 2 remains occupied, and room occupancy count is 1
      final roomAfterADischarge = (await roomService.getRoomDirect(
        'room_lifecycle',
      ))!;
      expect(roomAfterADischarge.occupiedBeds, 1);
      expect(roomAfterADischarge.status, 'partially_occupied');
      final bed1 = roomAfterADischarge.beds.firstWhere((b) => b.id == bed1Id);
      final bed2 = roomAfterADischarge.beds.firstWhere((b) => b.id == bed2Id);
      expect(bed1.status, 'available');
      expect(bed1.currentPatientId, isNull);
      expect(bed2.status, 'occupied');
      expect(bed2.currentPatientId, patientBId);

      // Step 10: Admit a new Patient C into the released Bed 1
      final patientCId = await patientService.addPatient(
        fullName: 'Lifecycle Patient C',
        dateOfBirth: DateTime(1992, 9, 9),
        gender: 'Female',
        contactNumber: '9455555555',
        emergencyContact: '9466666666',
        emergencyContactName: 'Kin C',
        medicalCondition: 'Recovery',
        admissionDate: DateTime(2026, 5, 3, 10, 0),
        exitDate: DateTime(2026, 5, 6, 8, 0),
        registrationNumber: '99',
        createdBy: 'test-uid-admin',
      );
      final stayCId = await roomService.createStay(
        patientId: patientCId,
        patientName: 'Lifecycle Patient C',
        roomId: 'room_lifecycle',
        roomNumber: '102',
        roomType: 'general',
        bedId: bed1Id,
        bedLabel: 'L-1',
        admissionDate: DateTime(2026, 5, 3, 10, 0),
        durationDays: 3,
        attendantCount: 0,
        createdBy: 'test-uid-admin',
      );
      expect(stayCId, isNotEmpty);

      // Step 11: Verify historical records for discharged Patient A remain completely intact
      final historicalA = (await patientService.getPatient(patientAId))!;
      expect(historicalA.status, 'discharged');
      final staysA = await roomService
          .getStaysByPatientStream(patientAId)
          .first;
      expect(staysA, hasLength(1));
      expect(staysA.single.status, 'completed');
      expect(historicalA.payments!.length, greaterThanOrEqualTo(1));
    },
  );

  test(
    'Regression & Failure Testing: Auth 401/403, DB Outage 503 & Recovery, Stale Cache Refresh, Failed Write Cache Integrity',
    () async {
      // 1. Expired token -> 401 Unauthorized
      currentToken = await fetchToken('expired');
      await expectLater(
        () => backendApi.get('patients'),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );

      // 2. Unregistered user -> 403 Forbidden
      currentToken = await fetchToken('unregistered');
      await expectLater(
        () => backendApi.get('patients'),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            403,
          ),
        ),
      );

      // 3. Insufficient role ('volunteer' attempting settings write -> 403 Forbidden)
      currentToken = await fetchToken('volunteer');
      await expectLater(
        () => backendApi.updateSettingsKey('security', 'twoFactorAuth', true),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            403,
          ),
        ),
      );

      // Restore admin token
      currentToken = await fetchToken('admin');

      // 4. Stale SQLite cache vs authoritative PostgreSQL state
      await cache.replaceSnapshot('patients/p_stale', {
        'id': 'p_stale',
        'fullName': 'Stale Cached Name',
        'registrationNumber': '777',
      });
      await backendApi.createPatient({
        'id': 'p_stale',
        'fullName': 'Authoritative Server Name',
        'dateOfBirth': '1990-01-01',
        'gender': 'Male',
        'contactNumber': '9000000000',
        'emergencyContact': '9000000001',
        'emergencyContactName': 'Kin',
        'medicalCondition': 'Healthy',
        'admissionDate': '2026-05-01',
        'registrationNumber': '777',
      });
      final freshPatient = await patientService.getPatient('p_stale');
      expect(freshPatient!.fullName, 'Authoritative Server Name');
      final updatedCacheNode = await cache.read('patients/p_stale') as Map?;
      expect(updatedCacheNode!['fullName'], 'Authoritative Server Name');

      // 5. Simulated Backend / Database Outage (503 Service Unavailable) & Recovery
      await setDbOutage(true);
      await expectLater(
        () => backendApi.createPatient({
          'id': 'p_during_outage',
          'fullName': 'Should Not Cache',
          'dateOfBirth': '1990-01-01',
          'gender': 'Female',
          'contactNumber': '9000000000',
          'emergencyContact': '9000000001',
          'emergencyContactName': 'Kin',
          'medicalCondition': 'Healthy',
          'admissionDate': '2026-05-01',
        }),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
      // Verify failed write did NOT pollute local SQLite cache
      expect(await cache.read('patients/p_during_outage'), isNull);

      // Recover from outage
      await setDbOutage(false);
      final afterRecovery = await patientService.getPatient('p_stale');
      expect(afterRecovery!.fullName, 'Authoritative Server Name');
    },
  );
}
