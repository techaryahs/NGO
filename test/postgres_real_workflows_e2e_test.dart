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
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/registration_number_service.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/utils/stay_billing.dart';
import 'package:ngo/utils/pricing_helper.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Future<String?> _firstExecutableOnPath(String executable) async {
  final result = await Process.run(Platform.isWindows ? 'where.exe' : 'which', [
    executable,
  ]);
  if (result.exitCode != 0) return null;
  for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
    final candidate = line.trim();
    if (candidate.isNotEmpty && File(candidate).existsSync()) return candidate;
  }
  return null;
}

Future<String?> _resolvePostgresExecutable(String executable) async {
  final environmentKey = switch (executable) {
    'pg_ctl' => 'AUDIT_PG_CTL',
    'initdb' => 'AUDIT_PG_INITDB',
    'createdb' => 'AUDIT_PG_CREATEDB',
    _ => 'AUDIT_PG_${executable.toUpperCase()}',
  };
  final requested = Platform.environment[environmentKey];
  if (requested != null && requested.isNotEmpty) {
    if (File(requested).existsSync()) return requested;
    throw StateError(
      'AUDIT_PG_${executable.toUpperCase()} does not exist: $requested',
    );
  }

  final binDir =
      Platform.environment['AUDIT_PG_BIN_DIR'] ??
      Platform.environment['PG_BIN_DIR'];
  if (binDir != null && binDir.isNotEmpty) {
    final candidate = p.join(
      binDir,
      Platform.isWindows ? '$executable.exe' : executable,
    );
    if (File(candidate).existsSync()) return candidate;
    throw StateError(
      'PostgreSQL executable not found in AUDIT_PG_BIN_DIR/PG_BIN_DIR: $candidate',
    );
  }

  final onPath = await _firstExecutableOnPath(executable);
  if (onPath != null) return onPath;

  if (Platform.isWindows) {
    for (final root in [
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)'],
    ].whereType<String>()) {
      final postgresRoot = Directory(p.join(root, 'PostgreSQL'));
      if (!postgresRoot.existsSync()) continue;
      final versions = postgresRoot.listSync().whereType<Directory>().toList()
        ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final version in versions) {
        final candidate = p.join(version.path, 'bin', '$executable.exe');
        if (File(candidate).existsSync()) return candidate;
      }
    }
  }
  return null;
}

Future<void> _runPostgresCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'PostgreSQL command failed (${p.basename(executable)} ${arguments.join(' ')}): '
      '${result.stdout} ${result.stderr}',
    );
  }
}

Future<void> _runDetachedPostgresCommand(
  String executable,
  List<String> arguments,
) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw StateError(
      'PostgreSQL lifecycle command failed (${p.basename(executable)} '
      '${arguments.join(' ')}): exit $exitCode',
    );
  }
}

Future<({String dataDir, String pgCtl, bool ownsDataDir, bool startedByTest})>
_ensureDisposablePostgres() async {
  final pgCtl = await _resolvePostgresExecutable('pg_ctl');
  final initdb = await _resolvePostgresExecutable('initdb');
  final psql = await _resolvePostgresExecutable('psql');
  final createdb = await _resolvePostgresExecutable('createdb');
  if (pgCtl == null || initdb == null || psql == null || createdb == null) {
    throw StateError(
      'Disposable PostgreSQL 16 is unavailable. Set AUDIT_PG_BIN_DIR (or '
      'AUDIT_PG_CTL/AUDIT_PG_INITDB/AUDIT_PG_PSQL/AUDIT_PG_CREATEDB) to '
      'PostgreSQL 16 binaries, or put pg_ctl, initdb, psql and createdb on PATH. '
      'No external database was used.',
    );
  }

  final requestedDir = Platform.environment['AUDIT_PG_DATA_DIR'];
  final ownsDataDir = requestedDir == null || requestedDir.isEmpty;
  final dataDir = requestedDir != null && requestedDir.isNotEmpty
      ? p.normalize(p.absolute(requestedDir))
      : (await Directory.systemTemp.createTemp('ngo-audit-pg16-e2e-')).path;
  if (!p.isWithin(Directory.systemTemp.path, dataDir) ||
      !p.basename(dataDir).startsWith('ngo-audit-pg16-')) {
    throw StateError('Refusing non-temporary audit cluster: $dataDir');
  }
  final dataDirectory = Directory(dataDir);
  var startedByTest = false;
  try {
    if (!dataDirectory.existsSync()) {
      await dataDirectory.create(recursive: true);
    }
    final versionFile = File(p.join(dataDir, 'PG_VERSION'));
    if (!versionFile.existsSync()) {
      if (!ownsDataDir && !p.isWithin(Directory.systemTemp.path, dataDir)) {
        throw StateError(
          'AUDIT_PG_DATA_DIR is not an initialized PostgreSQL cluster and is outside '
          'the system temp directory: $dataDir',
        );
      }
      if (dataDirectory.listSync().isNotEmpty) {
        throw StateError(
          'PostgreSQL data directory is non-empty but uninitialized: $dataDir',
        );
      }
      await _runPostgresCommand(initdb, [
        '-D',
        dataDir,
        '-U',
        'ngo_audit',
        '--auth=trust',
        '--encoding=UTF8',
        '--locale=C',
      ]);
    }

    if (versionFile.readAsStringSync().trim() != '16') {
      throw StateError('Disposable PostgreSQL cluster must use version 16');
    }
    final status = await Process.run(pgCtl, ['-D', dataDir, 'status']);
    if (status.exitCode != 0) {
      await _runDetachedPostgresCommand(pgCtl, [
        '-D',
        dataDir,
        '-l',
        p.join(dataDir, 'server.log'),
        '-o',
        '-p 55439 -h 127.0.0.1',
        '-w',
        '-t',
        '30',
        'start',
      ]);
      startedByTest = true;
    }
    final identity = await Process.run(psql, [
      '-h',
      '127.0.0.1',
      '-p',
      '55439',
      '-U',
      'ngo_audit',
      '-d',
      'postgres',
      '-tA',
      '-v',
      'ON_ERROR_STOP=1',
      '-c',
      "SHOW data_directory",
    ]);
    if (identity.exitCode != 0 ||
        p.normalize(identity.stdout.toString().trim()) !=
            p.normalize(dataDir)) {
      throw StateError(
        'Disposable PostgreSQL server identity mismatch; no tests ran',
      );
    }
    final databaseProbe = await Process.run(psql, [
      '-h',
      '127.0.0.1',
      '-p',
      '55439',
      '-U',
      'ngo_audit',
      '-d',
      'postgres',
      '-tA',
      '-v',
      'ON_ERROR_STOP=1',
      '-c',
      "SELECT 1 FROM pg_database WHERE datname = 'ngo_flutter_e2e'",
    ]);
    if (databaseProbe.exitCode != 0) {
      throw StateError(
        'Could not inspect disposable database catalog: '
        '${databaseProbe.stdout} ${databaseProbe.stderr}',
      );
    }
    if (databaseProbe.stdout.toString().trim() != '1') {
      await _runPostgresCommand(createdb, [
        '-h',
        '127.0.0.1',
        '-p',
        '55439',
        '-U',
        'ngo_audit',
        'ngo_flutter_e2e',
      ]);
    }
    return (
      dataDir: dataDir,
      pgCtl: pgCtl,
      ownsDataDir: ownsDataDir,
      startedByTest: startedByTest,
    );
  } catch (_) {
    if (startedByTest) {
      await _runDetachedPostgresCommand(pgCtl, [
        '-D',
        dataDir,
        '-w',
        '-t',
        '30',
        '-m',
        'fast',
        'stop',
      ]);
    }
    if (ownsDataDir && dataDirectory.existsSync()) {
      await dataDirectory.delete(recursive: true);
    }
    rethrow;
  }
}

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
  String? disposableDataDir;
  String? disposablePgCtl;
  var ownsDisposableDataDir = false;
  var startedDisposablePostgres = false;

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
      final target = Uri.parse(externalOrigin);
      if (Platform.environment['E2E_ALLOW_EXTERNAL_DISPOSABLE'] != '1' ||
          target.scheme != 'http' ||
          !['127.0.0.1', 'localhost', '::1'].contains(target.host)) {
        throw StateError(
          'External E2E server requires explicit disposable loopback opt-in',
        );
      }
      serverOrigin = externalOrigin;
      apiBaseUrl = '$serverOrigin/api';
      return;
    }

    final disposable = await _ensureDisposablePostgres();
    disposableDataDir = disposable.dataDir;
    disposablePgCtl = disposable.pgCtl;
    ownsDisposableDataDir = disposable.ownsDataDir;
    startedDisposablePostgres = disposable.startedByTest;
    // ignore: avoid_print
    print(
      'E2E_DISPOSABLE_POSTGRES_READY dataDir=${disposable.dataDir} '
      'pgCtl=${disposable.pgCtl} startedByTest=${disposable.startedByTest}',
    );

    final node = await _firstExecutableOnPath('node');
    if (node == null) {
      throw StateError(
        'Node.js 20+ is required on PATH for the disposable E2E API',
      );
    }
    serverProcess = await Process.start(
      node,
      ['--import', 'tsx', 'tests/helpers/e2e_server.ts'],
      workingDirectory: p.join(Directory.current.path, 'backend'),
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
    // ignore: avoid_print
    print('E2E_SERVER_PROCESS_STARTED');

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
    if (startedDisposablePostgres &&
        disposablePgCtl != null &&
        disposableDataDir != null) {
      await _runDetachedPostgresCommand(disposablePgCtl!, [
        '-D',
        disposableDataDir!,
        '-w',
        '-m',
        'fast',
        'stop',
      ]);
    }
    if (ownsDisposableDataDir && disposableDataDir != null) {
      final path = p.normalize(disposableDataDir!);
      if (p.isWithin(Directory.systemTemp.path, path) &&
          p.basename(path).startsWith('ngo-audit-pg16-e2e-')) {
        await Directory(path).delete(recursive: true);
      }
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
    'discharge readiness/cancel preserves booking and ignores a stale active preview through real services',
    () async {
      final pid = AttendantModel.generateId();
      final rid = AttendantModel.generateId();
      final sid = AttendantModel.generateId();
      final aid = AttendantModel.generateId();
      final admission = DateTime.parse('2026-10-22T11:57:00Z');
      final planned = DateTime.parse('2026-10-31T03:30:00Z');
      final checkout = DateTime.parse('2026-10-22T11:59:55.196Z');
      final cycle = admission.millisecondsSinceEpoch.toString();
      await roomService.addRoom(
        id: rid,
        roomNumber: 'Preview QA',
        roomIdentifier: '1D',
        floor: 1,
        roomType: 'general',
        totalBeds: 1,
        bedLabels: ['QA'],
      );
      final room = (await roomService.getRoomDirect(rid))!;
      await backendApi.registerPatient({
        'id': pid,
        'fullName': 'Synthetic preview',
        'dateOfBirth': '1990-01-01',
        'gender': 'Other',
        'contactNumber': '',
        'emergencyContact': '',
        'emergencyContactName': '',
        'medicalCondition': '',
        'admissionDate': admission.millisecondsSinceEpoch,
        'registrationDate': admission.millisecondsSinceEpoch,
        'registrationNumber': pid,
        'exitDate': planned.millisecondsSinceEpoch,
        'attendants': [
          {'id': aid, 'name': 'Synthetic helper', 'startDate': '2026-10-22'},
        ],
        'stays': [
          {
            'id': sid,
            'roomId': rid,
            'bedId': room.beds.single.id,
            'admissionDate': admission.millisecondsSinceEpoch,
            'durationDays': 9,
            'expectedDischargeDate': planned.millisecondsSinceEpoch,
            'cycleId': cycle,
          },
        ],
      });
      for (var day = 22; day <= 31; day++) {
        await backendApi.postAttendance(
          patientId: pid,
          date: '2026-10-$day',
          kind: 'attendance',
          payload: {'status': 'Present'},
        );
        await backendApi.postAttendance(
          patientId: pid,
          date: '2026-10-$day',
          kind: 'attendant_attendance',
          payload: {
            aid: {'attendantId': aid, 'status': 'Present'},
          },
        );
      }
      for (var index = 0; index < 2; index++) {
        await paymentService.recordPayment(
          patientId: pid,
          patientName: 'Synthetic preview',
          payment: PaymentModel(
            id: AttendantModel.generateId(),
            amount: 2000,
            method: 'CASH',
            date: admission,
            cycleId: cycle,
          ),
        );
      }
      // Simulate the stale preview already present in production, locally only.
      await backendApi.recalculateBilling(pid, checkoutAt: checkout);
      Future<List<Map<String, dynamic>>> stored() => queryRows(
        '''SELECT
      (SELECT to_jsonb(p) FROM patients p WHERE id=\$1) AS patient,
      (SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM stays s WHERE patient_id=\$1) AS stays,
      (SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM payments p WHERE patient_id=\$1) AS payments,
      (SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM attendance_records a WHERE patient_id=\$1) AS attendance''',
        [pid],
      );
      final before = await stored();
      final requests = <String>[];
      diagnosticClient.beforeSend = (request) async {
        requests.add('${request.method} ${request.url.path}');
      };
      final override = PatientModel.fromMap(
        pid,
        Map<String, dynamic>.from(
          (await backendApi.financialSnapshot(pid))['patient'] as Map,
        ),
      );
      for (var retry = 0; retry < 2; retry++) {
        final readiness = await patientService.getDischargeReadiness(
          pid,
          patientOverride: override,
          checkoutAt: checkout,
        );
        expect(readiness, containsPair('total', 400));
        expect(readiness, containsPair('refundDue', 3600));
        expect(readiness['ready'], isFalse);
        final overview =
            (await backendApi.financialSnapshot(pid))['patient'] as Map;
        expect(overview['advanceBilledAmount'], 4000);
        expect(overview['totalPaidAmount'], 4000);
        expect(overview['refundDueAmount'], 0);
        expect(overview['currentDueAmount'], 0);
      }
      expect(requests.every((request) => request.startsWith('GET ')), isTrue);
      expect(await stored(), before);
      final boundary = await patientService.getDischargeReadiness(
        pid,
        checkoutAt: planned,
      );
      expect(boundary['total'], 3600);
      expect(boundary['refundDue'], 400);
      expect(await stored(), before);
      await expectLater(
        patientService.dischargePatient(pid, checkoutAt: checkout),
        throwsA(isA<Exception>()),
      );
      expect(await stored(), before);
      final refundDate = DateTime.parse('2026-10-22T12:00:00Z');
      final requestId = AttendantModel.generateId();
      final refundId = await paymentService.recordRefund(
        patientId: pid,
        cycleId: cycle,
        amount: 3600,
        date: refundDate,
        method: 'cash',
        requestId: requestId,
        checkoutAt: checkout,
      );
      expect(
        await paymentService.recordRefund(
          patientId: pid,
          cycleId: cycle,
          amount: 3600,
          date: refundDate,
          method: 'cash',
          requestId: requestId,
          checkoutAt: checkout,
        ),
        refundId,
      );
      final refunded = await patientService.getDischargeReadiness(
        pid,
        checkoutAt: checkout,
      );
      expect(refunded['refundDue'], 0);
      expect(refunded['paid'], 400);
      expect(refunded['ready'], isTrue);
      expect(
        (await queryRows(
          'SELECT count(*)::int AS n,sum(amount)::text AS net FROM payments WHERE patient_id=\$1',
          [pid],
        )).single,
        {'n': 3, 'net': '400.00'},
      );
      await patientService.dischargePatient(pid, checkoutAt: checkout);
      final finalPatient =
          (await backendApi.financialSnapshot(pid))['patient'] as Map;
      expect(finalPatient['status'], 'discharged');
      expect(finalPatient['refundDueAmount'], 0);
      expect(finalPatient['totalRefundedAmount'], 3600);
    },
  );

  test(
    '3800 General bill: partial 1400 and remaining 2400 through real Flutter services retain both receipts and dashboard/profile balances',
    () async {
      final pid = AttendantModel.generateId(),
          rid = AttendantModel.generateId(),
          sid = AttendantModel.generateId();
      final admission = DateTime(2026, 10, 1);
      final cycle = admission.millisecondsSinceEpoch.toString();
      await roomService.addRoom(
        id: rid,
        roomNumber: 'Collection QA',
        roomIdentifier: '1D',
        floor: 1,
        roomType: 'general',
        totalBeds: 1,
        bedLabels: ['QA'],
      );
      final room = (await roomService.getRoomDirect(rid))!;
      await patientService.addPatient(
        id: pid,
        fullName: 'Collection $pid',
        dateOfBirth: DateTime(1990),
        gender: 'Other',
        contactNumber: '',
        emergencyContact: '',
        emergencyContactName: '',
        medicalCondition: '',
        admissionDate: admission,
        registrationDate: admission,
        exitDate: DateTime(2026, 10, 19, 9),
        createdBy: 'test-uid-admin',
        attendants: [],
        initialStays: [
          {
            'id': sid,
            'roomId': rid,
            'bedId': room.beds.single.id,
            'admissionDate': admission.millisecondsSinceEpoch,
            'durationDays': 19,
            'cycleId': cycle,
          },
        ],
      );
      final partial = PaymentModel(
        id: AttendantModel.generateId(),
        amount: 1400,
        method: 'ONLINE',
        date: DateTime.now(),
        cycleId: cycle,
        transactionId: 'abcd123456789',
        totalAmount: 3800,
        paidAmount: 1400,
        pendingAmount: 2400,
      );
      await paymentService.recordPayment(
        patientId: pid,
        patientName: 'Collection $pid',
        payment: partial,
        collectOutstanding: true,
      );
      final balance = await paymentService.collectionBalance(pid);
      expect(balance.total, 3800);
      expect(balance.paid, 1400);
      expect(balance.due, 2400);
      final settled = Completer<void>();
      final dashboard = <PatientModel>[];
      final subscription = patientService.getPatientsStream().listen((
        patients,
      ) {
        dashboard
          ..clear()
          ..addAll(patients);
        if (patients.any(
              (p) =>
                  p.id == pid &&
                  p.totalPaidAmount == 3800 &&
                  p.currentDueAmount == 0,
            ) &&
            !settled.isCompleted) {
          settled.complete();
        }
      });
      try {
        final payment = PaymentModel(
          id: AttendantModel.generateId(),
          amount: balance.due,
          method: 'ONLINE',
          date: DateTime.now(),
          cycleId: balance.cycleId,
          transactionId: DateTime.now().microsecondsSinceEpoch.toString(),
          totalAmount: balance.total,
          paidAmount: 3800,
          pendingAmount: 0,
        );
        await expectLater(
          paymentService.recordPayment(
            patientId: pid,
            patientName: 'Collection $pid',
            collectOutstanding: true,
            payment: PaymentModel(
              id: AttendantModel.generateId(),
              amount: 2400,
              method: 'ONLINE',
              date: DateTime.now(),
              transactionId: partial.transactionId,
              cycleId: cycle,
              totalAmount: 3800,
              paidAmount: 3800,
            ),
          ),
          throwsA(isA<PaymentReferenceException>()),
        );
        expect(
          (await queryRows(
            'SELECT count(*)::int AS n FROM payments WHERE patient_id=\$1',
            [pid],
          )).single['n'],
          1,
        );
        expect((await paymentService.collectionBalance(pid)).due, 2400);
        final id = await paymentService.recordPayment(
          patientId: pid,
          patientName: 'Collection $pid',
          payment: payment,
          collectOutstanding: true,
        );
        expect(
          await paymentService.recordPayment(
            patientId: pid,
            patientName: 'Collection $pid',
            payment: payment,
            collectOutstanding: true,
          ),
          id,
        );
        await backendApi.refresh('patients');
        await settled.future.timeout(const Duration(seconds: 5));
        final profile = (await patientService.getPatient(pid))!;
        expect(profile.payments, hasLength(2));
        expect(profile.payments!.map((p) => p.amount).toList()..sort(), [
          1400,
          2400,
        ]);
        expect(profile.totalPaidAmount, 3800);
        expect(profile.currentDueAmount, 0);
        expect(
          dashboard.singleWhere((p) => p.id == pid).totalPaidAmount,
          profile.totalPaidAmount,
        );
        expect(
          dashboard.singleWhere((p) => p.id == pid).currentDueAmount,
          profile.currentDueAmount,
        );
        expect(
          await backendApi.refresh('payments?patientId=$pid&format=map'),
          hasLength(2),
        );
        expect(
          (await queryRows(
            'SELECT count(*)::int AS n,sum(amount)::text AS paid FROM payments WHERE patient_id=\$1',
            [pid],
          )).single,
          {'n': 2, 'paid': '3800.00'},
        );
      } finally {
        await subscription.cancel();
      }
    },
  );

  for (final arrivalDay in [1, 6]) {
    test(
      'post-admission Flutter lifecycle: attendee arrives day $arrivalDay, attendance and remaining payment survive reload',
      () async {
        final id = AttendantModel.generateId();
        final roomId = AttendantModel.generateId();
        final stayId = AttendantModel.generateId();
        final attendeeId = AttendantModel.generateId();
        final admission = DateTime(2026, 10, 1);
        final cycle = admission.millisecondsSinceEpoch.toString();
        await roomService.addRoom(
          id: roomId,
          roomNumber: 'General QA',
          roomIdentifier: '1D',
          floor: 1,
          roomType: 'general',
          totalBeds: 1,
          bedLabels: ['QA'],
        );
        final room = (await roomService.getRoomDirect(roomId))!;
        final pid = await patientService.addPatient(
          id: id,
          fullName: 'Lifecycle $id',
          dateOfBirth: DateTime(1990),
          gender: 'Other',
          contactNumber: '',
          emergencyContact: '',
          emergencyContactName: '',
          medicalCondition: '',
          admissionDate: admission,
          registrationDate: admission,
          exitDate: DateTime(2026, 10, 10, 9),
          createdBy: 'test-uid-admin',
          attendants: [],
          initialStays: [
            {
              'id': stayId,
              'roomId': roomId,
              'bedId': room.beds.single.id,
              'admissionDate': admission.millisecondsSinceEpoch,
              'durationDays': 10,
              'cycleId': cycle,
            },
          ],
        );
        await paymentService.recalculatePatientAttendanceAndBilling(pid);
        var patient = (await patientService.getPatient(pid))!;
        expect(patient.advanceBilledAmount, 2000);
        await paymentService.recordPayment(
          patientId: pid,
          patientName: patient.fullName,
          collectOutstanding: true,
          payment: PaymentModel(
            id: AttendantModel.generateId(),
            amount: 2000,
            method: 'cash',
            date: DateTime.now(),
            cycleId: cycle,
            totalAmount: 2000,
            paidAmount: 2000,
          ),
        );
        // This is the actual service and payload used by Edit Details.
        final attendant = {
          'id': attendeeId,
          'name': 'Family $attendeeId',
          'startDate': '2026-10-${arrivalDay.toString().padLeft(2, '0')}',
        };
        await patientService.updatePatient(pid, {
          'attendants': [attendant],
        });
        await patientService.updatePatient(pid, {
          'attendants': [attendant],
        });
        patient = (await patientService.getPatient(pid))!;
        var stays = await paymentService.loadStays(pid);
        var month = await attendanceService.loadMonth(admission);
        var rows = month.rows([patient], stays);
        expect(rows, hasLength(2));
        expect(rows.last.attendantId, attendeeId);
        final editor = MonthlyAttendanceEditor(month);
        for (var d = 1; d <= 10; d++) {
          final date = DateTime(2026, 10, d);
          editor.edit(rows.first, date, 'Present');
          editor.edit(rows.last, date, 'Present');
        }
        expect(await editor.save(null, backendApi), {pid});
        await paymentService.recalculatePatientAttendanceAndBilling(pid);
        patient = (await patientService.getPatient(pid))!;
        final attendeeCost = (11 - arrivalDay) * 200.0;
        expect(patient.advanceBilledAmount, 2000 + attendeeCost);
        expect(patient.totalPaidAmount, 2000);
        expect(patient.currentDueAmount, attendeeCost);
        final payment = PaymentModel(
          id: AttendantModel.generateId(),
          amount: attendeeCost,
          method: 'ONLINE',
          date: DateTime.now(),
          transactionId: DateTime.now().microsecondsSinceEpoch.toString(),
          cycleId: cycle,
          totalAmount: patient.advanceBilledAmount,
          paidAmount: patient.advanceBilledAmount,
        );
        final paymentId = await paymentService.recordPayment(
          patientId: pid,
          patientName: patient.fullName,
          payment: payment,
          collectOutstanding: true,
        );
        expect(
          await paymentService.recordPayment(
            patientId: pid,
            patientName: patient.fullName,
            payment: payment,
            collectOutstanding: true,
          ),
          paymentId,
        );
        // Force every view back to persisted HTTP/database state.
        await backendApi.refresh('patients/$pid');
        await backendApi.refresh('stays?patientId=$pid&format=map');
        patient = (await patientService.getPatient(pid))!;
        stays = await paymentService.loadStays(pid);
        month = await attendanceService.loadMonth(admission);
        rows = month.rows([patient], stays);
        expect(rows, hasLength(2));
        expect(
          MonthlyAttendanceEditor(
            month,
          ).status(rows.last, DateTime(2026, 10, arrivalDay)),
          'Present',
        );
        if (arrivalDay > 1) {
          expect(rows.last.enabled(admission), isFalse);
          expect(
            MonthlyAttendanceEditor(month).status(rows.last, admission),
            'Unmarked',
          );
        }
        expect(patient.payments, hasLength(2));
        expect(patient.totalPaidAmount, 2000 + attendeeCost);
        expect(patient.currentDueAmount, 0);
        final ledger = await backendApi.get(
          'payments?patientId=$pid&format=map',
        );
        expect(ledger, hasLength(2));
        expect(
          (await queryRows(
            'SELECT count(*)::int AS n,sum(amount)::text AS paid FROM payments WHERE patient_id=\$1',
            [pid],
          )).single,
          {'n': 2, 'paid': (2000 + attendeeCost).toStringAsFixed(2)},
        );
        expect(
          (await queryRows(
            "SELECT count(*)::int AS n FROM attendance_records WHERE patient_id=\$1 AND kind='attendant_attendance'",
            [pid],
          )).single['n'],
          11 - arrivalDay,
        );
      },
    );
  }

  test(
    'client billing exposure audit validates the disposable schema without modifying records',
    () async {
      final source = await File(
        p.join(
          Directory.current.path,
          'test',
          'fixtures',
          'historical-billing-exposure.sql',
        ),
      ).readAsString();
      final select = source
          .split('-- CLIENT_BILLING_AUDIT_BEGIN')
          .last
          .split('-- CLIENT_BILLING_AUDIT_END')
          .first
          .trim();
      expect((await queryRows(select)).single, {
        'stays_examined': 0,
        'duration_double_count_candidates': 0,
        'duplicate_attendant_name_groups': 0,
        'individual_attendant_payloads': 0,
        'nested_attendant_payloads': 0,
        'discharged_without_actual_timestamp': 0,
        'actual_equals_planned_candidates': 0,
        'finalized_segment_summary_mismatch': 0,
      });
    },
  );

  for (final scenario in [
    (
      category: 'general',
      days: 70,
      beds: 2,
      late: false,
      estimate: 14500.0,
      finalAmount: 14250.0,
    ),
    (
      category: 'private',
      days: 70,
      beds: 1,
      late: false,
      estimate: 51000.0,
      finalAmount: 50100.0,
    ),
    (
      category: 'general',
      days: 61,
      beds: 1,
      late: true,
      estimate: 12250.0,
      finalAmount: 12250.0,
    ),
  ]) {
    test(
      'Flutter ${scenario.category} estimate, stored costs and final invoice agree at day ${scenario.days} with ${scenario.beds} beds and late=${scenario.late}',
      () async {
        final admission = DateTime(2026, 1, 1);
        final planned = DateTime(2026, 1, scenario.days, 9);
        final checkout = DateTime(
          2026,
          1,
          scenario.days,
          9,
          scenario.late ? 1 : 0,
        );
        await backendApi.updateSettingsCategory('pricing', {
          'generalRoomBedPrice': 350,
          'privateRoomBasePrice': 1100,
          'privateRoomExtraAttendantFee': 450,
          'privateRoomIncludedAttendants': 2,
        });
        await roomService.addRoom(
          id: 'approved_room',
          roomNumber: 'Approved QA',
          roomIdentifier: '1A',
          floor: 1,
          roomType: scenario.category,
          totalBeds: scenario.beds,
          bedLabels: List.generate(
            scenario.beds,
            (index) => 'Approved${index + 1}',
          ),
        );
        final room = (await roomService.getRoomDirect('approved_room'))!;
        final estimate = PricingHelper.calculateProjectedStayCost(
          scenario.category == 'private',
          0,
          scenario.days,
          bedsCount: scenario.beds,
          pricing: await roomService.getPricing(),
        );
        expect(estimate, scenario.estimate);
        await patientService.addPatient(
          id: 'approved_patient',
          fullName: 'Synthetic approved billing',
          dateOfBirth: DateTime(1990),
          gender: 'Other',
          contactNumber: '000',
          emergencyContact: '000',
          emergencyContactName: 'Synthetic',
          medicalCondition: 'Synthetic',
          admissionDate: admission,
          exitDate: planned,
          registrationNumber: 'approved_patient',
          createdBy: 'test-uid-admin',
          initialStays: [
            for (var index = 0; index < scenario.beds; index++)
              {
                'id': 'approved_stay_$index',
                'roomId': room.id,
                'bedId': room.beds[index].id,
                'admissionDate': admission.millisecondsSinceEpoch,
                'durationDays': scenario.days,
                'expectedDischargeDate': DateTime(
                  2026,
                  1,
                  scenario.days + 1,
                  9,
                ).millisecondsSinceEpoch,
                'billingSummary': {
                  'pricing': {
                    'generalRoomBedPrice': 350,
                    'privateRoomBasePrice': 1100,
                    'privateRoomExtraAttendantFee': 450,
                    'privateRoomIncludedAttendants': 2,
                  },
                },
              },
          ],
        );
        expect(
          (await queryRows(
            "SELECT sum(total_cost)::text AS total FROM stays WHERE patient_id='approved_patient'",
          )).single['total'],
          scenario.estimate.toStringAsFixed(2),
        );
        for (var day = 1; day <= scenario.days; day++) {
          await backendApi.postAttendance(
            kind: 'attendance',
            date: StayBilling.dateKey(DateTime(2026, 1, day)),
            patientId: 'approved_patient',
            payload: {'status': 'Present'},
          );
        }
        final projected = await backendApi.financialSnapshot(
          'approved_patient',
          checkoutAt: checkout,
        );
        expect(
          (projected['patient'] as Map)['advanceBilledAmount'],
          scenario.finalAmount,
        );
        final readiness = await patientService.getDischargeReadiness(
          'approved_patient',
          checkoutAt: checkout,
        );
        expect(readiness['pending'], scenario.finalAmount);
        await paymentService.recordPayment(
          patientId: 'approved_patient',
          patientName: 'Synthetic approved billing',
          payment: PaymentModel(
            id: 'approved_payment',
            amount: scenario.finalAmount,
            date: planned,
            method: 'CASH',
          ),
        );
        final settledPreview = await backendApi.financialSnapshot(
          'approved_patient',
        );
        expect((settledPreview['patient'] as Map)['refundDueAmount'], 0);
        expect(
          (settledPreview['patient'] as Map)['advanceBilledAmount'],
          scenario.estimate,
        );
        await patientService.dischargePatient(
          'approved_patient',
          checkoutAt: checkout,
        );
        final frozen = await backendApi.financialSnapshot('approved_patient');
        final patient = Map<String, dynamic>.from(frozen['patient'] as Map);
        expect(
          patient,
          containsPair('advanceBilledAmount', scenario.finalAmount),
        );
        expect(patient, containsPair('totalPaidAmount', scenario.finalAmount));
        expect(patient, containsPair('currentDueAmount', 0));
        expect(patient['exitDate'], planned.millisecondsSinceEpoch);
        expect(patient['dischargeDate'], checkout.millisecondsSinceEpoch);
        expect(
          (await queryRows(
            "SELECT sum(total_cost)::text AS total FROM stays WHERE patient_id='approved_patient'",
          )).single['total'],
          scenario.finalAmount.toStringAsFixed(2),
        );
        await patientService.dischargePatient(
          'approved_patient',
          checkoutAt: checkout,
        );
        expect(
          (await queryRows(
            "SELECT count(*)::int AS count FROM payments WHERE patient_id='approved_patient'",
          )).single['count'],
          1,
        );
        expect(
          (await backendApi.financialSnapshot('approved_patient'))['patient'],
          patient,
        );
      },
    );
  }

  test(
    'historical extension audit validates actual disposable schema read-only',
    () async {
      final columns = await queryRows(
        "SELECT column_name,data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='stays' AND column_name IN ('duration_days','total_extended_days','extensions') ORDER BY column_name",
      );
      expect(columns, [
        {'column_name': 'duration_days', 'data_type': 'integer'},
        {'column_name': 'extensions', 'data_type': 'jsonb'},
        {'column_name': 'total_extended_days', 'data_type': 'integer'},
      ]);
      final source = await File(
        p.join(
          Directory.current.path,
          'audit',
          'release-readiness-20261021',
          'historical-extension-audit.sql',
        ),
      ).readAsString();
      final select = source
          .split('-- AUDIT_COUNTS_BEGIN')
          .last
          .split('-- AUDIT_COUNTS_END')
          .first
          .trim();
      final counts = (await queryRows(select)).single;
      expect(counts, {
        'stays_examined': 0,
        'extended_stays': 0,
        'possible_double_count': 0,
        'consistent_separate_duration': 0,
        'date_formula_requires_review': 0,
        'extension_ledger_mismatch': 0,
      });
    },
  );

  test(
    'Flutter quote, stored extension and final invoice agree on billable days',
    () async {
      await roomService.addRoom(
        id: 'quote_room',
        roomNumber: 'Quote QA',
        roomIdentifier: '1A',
        floor: 1,
        roomType: 'general',
        totalBeds: 1,
        bedLabels: ['Q1'],
      );
      final room = (await roomService.getRoomDirect('quote_room'))!;
      await patientService.addPatient(
        id: 'quote_patient',
        fullName: 'Synthetic quote',
        dateOfBirth: DateTime(1990),
        gender: 'Other',
        contactNumber: '000',
        emergencyContact: '000',
        emergencyContactName: 'Synthetic',
        medicalCondition: 'Synthetic',
        admissionDate: DateTime(2026, 1, 1),
        exitDate: DateTime(2026, 1, 60, 9),
        registrationNumber: 'quote_patient',
        createdBy: 'test-uid-admin',
        initialStays: [
          {
            'id': 'quote_stay',
            'roomId': room.id,
            'bedId': room.beds.single.id,
            'admissionDate': DateTime(2026, 1, 1).millisecondsSinceEpoch,
            'durationDays': 60,
            'expectedDischargeDate': DateTime(
              2026,
              1,
              61,
              9,
            ).millisecondsSinceEpoch,
          },
        ],
      );
      final absent = <String, String>{};
      for (var day = 1; day <= 10; day++) {
        final key = StayBilling.dateKey(DateTime(2026, 1, day));
        absent[key] = 'Absent';
        await backendApi.post('attendance', {
          'patientId': 'quote_patient',
          'date': key,
          'payload': {'status': 'Absent'},
        });
      }
      expect(
        await roomService.quoteStayExtension(
          stayId: 'quote_stay',
          additionalDays: 10,
        ),
        2000,
      );
      await roomService.extendStay(
        stayId: 'quote_stay',
        additionalDays: 10,
        requestId: 'quote-approval',
        reason: 'Approved',
      );
      await roomService.extendStay(
        stayId: 'quote_stay',
        additionalDays: 10,
        requestId: 'quote-approval',
        reason: 'Approved',
      );
      final saved = (await queryRows(
        "SELECT duration_days,total_extended_days,total_cost::text,extensions FROM stays WHERE id='quote_stay'",
      )).single;
      expect(saved['duration_days'], 60);
      expect(saved['total_extended_days'], 10);
      expect(saved['total_cost'], '12000.00');
      expect((saved['extensions'] as List).single['additionalCost'], 2000);
      final snapshot = await backendApi.financialSnapshot('quote_patient');
      final rawPatient = Map<String, dynamic>.from(snapshot['patient'] as Map);
      expect(rawPatient['advanceBilledAmount'], 12000);
      expect(rawPatient['currentDueAmount'], 12000);
      final stays = (snapshot['stays'] as List)
          .map(
            (raw) =>
                StayModel.fromMap(raw['id'], Map<String, dynamic>.from(raw)),
          )
          .toList();
      expect(
        StayBilling.calculate(
          patient: PatientModel.fromMap('quote_patient', rawPatient),
          stays: stays,
          pricing: {'generalRoomBedPrice': 200},
          attendance: absent,
          calendarDayBilling: true,
        ).single.total,
        12000,
      );
      expect(
        (await queryRows(
          "SELECT COUNT(*)::int AS count FROM payments WHERE patient_id='quote_patient'",
        )).single['count'],
        0,
      );
    },
  );

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
      expect(saved['duration_days'], 2);
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
      expect((attPayload[att1Row.attendantId] as Map)['status'], 'Present');
      expect((attPayload[att2Row.attendantId] as Map)['status'], 'Absent');
      expect(attPayload.keys, isNot(contains('Mohan')));
      expect(attPayload.keys, isNot(contains('Sita')));

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
      expect(trackedStay2.durationDays, 2);
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
      final readiness1 = await patientService.getDischargeReadiness(
        p1Id,
        checkoutAt: plannedExit,
      );
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
      await patientService.dischargePatient(p1Id, checkoutAt: plannedExit);

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
      final exit = DateTime(2026, 4, 3, 9, 1);
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
      await mark('2026-04-03', 'Present', 400);
      await paymentService.recordPayment(
        patientId: 'p_attendance_accuracy',
        patientName: 'Synthetic attendance accuracy',
        payment: PaymentModel(
          id: 'attendance_settlement',
          amount: 400,
          date: exit,
          method: 'CASH',
        ),
      );
      await roomService.completeStay(
        stays.single['id'] as String,
        completedAt: exit,
      );
      expect(
        (await patientService.getPatient('p_attendance_accuracy'))!.status,
        'discharged',
      );
      await backendApi.postAttendanceBulk(
        kind: 'attendance',
        date: '2026-04-01',
        records: {
          'p_attendance_accuracy': {
            'status': 'Absent',
            'patientId': 'p_attendance_accuracy',
          },
        },
      );
      await paymentService.recalculatePatientAttendanceAndBilling(
        'p_attendance_accuracy',
      );
      final finalized = (await patientService.getPatient(
        'p_attendance_accuracy',
      ))!;
      expect(finalized.advanceBilledAmount, 400);
      expect(finalized.currentDueAmount, 0);
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
        if (request.method != 'POST' || request.url.path != '/api/payments') {
          return;
        }
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
      final readinessA = await patientService.getDischargeReadiness(
        patientAId,
        checkoutAt: plannedExit,
      );
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
      await patientService.dischargePatient(
        patientAId,
        checkoutAt: plannedExit,
      );

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
