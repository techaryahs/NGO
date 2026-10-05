import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/utils/stay_billing.dart';
import 'package:ngo/utils/upi_payment.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:ngo/screens/patients/widgets/payment_dialog.dart';
import 'stay_billing_test.dart' as fixtures;

class BatchDatabase extends fixtures.TestDatabase {
  Map<String, dynamic>? lastPatch;
  final List<String> ranges = [];
  bool fail = false;
  Completer<void>? barrier;
  BatchDatabase(super.root);
  @override
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    if (barrier != null) await barrier!.future;
    if (fail) throw StateError('Network unavailable');
    lastPatch = Map.from(updates);
    return super.patch(path, updates);
  }

  @override
  Future<dynamic> getByKeyRange(
    String path, {
    required String startKey,
    required String endKey,
  }) {
    ranges.add('$path:$startKey:$endKey');
    return super.getByKeyRange(path, startKey: startKey, endKey: endKey);
  }
}

void main() {
  final day = DateTime(2026, 1, 1);
  StayModel stay({String type = 'general', double? manual, double? override}) =>
      StayModel.fromMap(
        's',
        fixtures.segment('s', type, 1, 2)
          ..['dailyRate'] = manual
          ..['dailyRateIsManual'] = manual != null
          ..['costOverride'] = override,
      );

  group('Attendance billing', () {
    for (final scenario in [
      ('Present', {'A': 'Present'}, 400.0),
      ('Absent', {'A': 'Present'}, 200.0),
      ('Present', {'A': 'Absent'}, 200.0),
      ('Present', {'A': 'Present', 'B': 'Absent', 'C': 'Present'}, 600.0),
    ]) {
      test('patient ${scenario.$1}, attendants ${scenario.$2}', () {
        final bill = StayBilling.calculate(
          patient: fixtures.patient(),
          stays: [stay()],
          pricing: {},
          attendance: {'2026-01-01': scenario.$1},
          attendantAttendance: {'2026-01-01': scenario.$2},
        ).single;
        expect(bill.total, scenario.$3);
      });
    }
    test(
      'private occupant uses existing room tariff even when patient absent',
      () {
        final bill = StayBilling.calculate(
          patient: fixtures.patient(),
          stays: [stay(type: 'private')],
          pricing: {
            'privateRoomBasePrice': 850,
            'privateRoomIncludedAttendants': 1,
            'privateRoomExtraAttendantFee': 225,
          },
          attendance: {'2026-01-01': 'Absent'},
          attendantAttendance: {
            '2026-01-01': {'A': 'Present', 'B': 'Present'},
          },
        ).single;
        expect(bill.total, 1075);
      },
    );
    test('manual rate and explicit cost override remain authoritative', () {
      final args = {
        '2026-01-01': {'A': 'Present', 'B': 'Present'},
      };
      expect(
        StayBilling.calculate(
          patient: fixtures.patient(),
          stays: [stay(manual: 345)],
          pricing: {},
          attendantAttendance: args,
        ).single.total,
        345,
      );
      expect(
        StayBilling.calculate(
          patient: fixtures.patient(),
          stays: [stay(override: 123)],
          pricing: {},
          attendance: {'2026-01-01': 'Absent'},
        ).single.total,
        123,
      );
    });
    test('9 AM checkout preserved; one minute later adds a day', () {
      for (final minute in [0, 1]) {
        final data = fixtures.segment('s', 'general', 1, 2)
          ..['completedAt'] = DateTime(
            2026,
            1,
            2,
            9,
            minute,
          ).millisecondsSinceEpoch;
        final bill = StayBilling.calculate(
          patient: fixtures.patient(),
          stays: [StayModel.fromMap('s', data)],
          pricing: {},
        ).single;
        expect(bill.total, minute == 0 ? 200 : 400);
      }
    });
    test('recorded attendance extends ongoing window beyond expected date', () {
      final data = fixtures.segment('s', 'general', 1, 8, status: 'active');
      final bill = StayBilling.calculate(
        patient: fixtures.patient(status: 'active'),
        stays: [StayModel.fromMap('s', data)],
        pricing: {},
        now: DateTime(2026, 1, 9),
        attendance: {'2026-01-15': 'Present'},
      ).single;
      expect(bill.days['s'], 15);
      expect(bill.total, 3000);
    });
    test(
      'repeated identical recalculation produces no further RTDB write',
      () async {
        final db = BatchDatabase({
          'patients': {'p': fixtures.patient().toMap()},
          'stays': {'s': stay().toMap()},
        });
        final service = PaymentService(db);
        await service.recalculatePatientAttendanceAndBilling('p');
        expect(db.writes, 1);
        await service.recalculatePatientAttendanceAndBilling('p');
        expect(db.writes, 1);
        db.dispose();
      },
    );
    test(
      'RTDB equality handles omitted empty fields and legacy numeric arrays',
      () {
        expect(
          PaymentService.valuesEqual({'charges': null}, {'charges': {}}),
          true,
        );
        expect(PaymentService.valuesEqual(null, []), true);
        expect(
          PaymentService.valuesEqual(
            [
              {'amount': 25},
            ],
            {
              '0': {'amount': 25},
            },
          ),
          true,
        );
        expect(
          PaymentService.valuesEqual({'amount': 25}, {'amount': 26}),
          false,
        );
      },
    );
    test(
      'initial admission includes attendants before the first payment recalculation',
      () async {
        final p = fixtures.patient(
          status: 'active',
          exit: 8,
          payments: [fixtures.payment(3200)],
        );
        final db = BatchDatabase({
          'patients': {'p': p.toMap()},
          'stays': {
            's': fixtures.segment('s', 'general', 1, 8, status: 'active')
              ..['attendantCount'] = 1,
          },
        });
        final initial = PatientService.initialAdmissionAttendance(
          patientId: 'p',
          patientName: 'Patient',
          start: day,
          exit: DateTime(2026, 1, 8, 9),
          cycleId: fixtures.cycle,
          attendants: [AttendantModel(name: 'A')],
        );
        await db.patch('', initial);
        final updates = await PaymentService(db).billingUpdates('p');
        // Eight eligible dates include both patient and attendant attendance,
        // matching the admission quote without a false balance mismatch.
        expect(updates['patients/p/advanceBilledAmount'], 3200);
        expect(updates['patients/p/refundDueAmount'], 0);
        expect(updates['patients/p/currentDueAmount'], 0);
        expect(updates['patients/p/paymentStatus'], 'Paid');
        db.dispose();
      },
    );
  });

  group('Monthly attendance buffer', () {
    late MonthlyAttendanceData data;
    late List<AttendanceRow> rows;
    setUp(() {
      data = MonthlyAttendanceData(day, {});
      final p = fixtures.patient().copyWith(
        attendants: [
          AttendantModel(name: 'A'),
          AttendantModel(name: 'B'),
        ],
      );
      final s = fixtures.segment('s', 'general', 3, 6)
        ..['patientSnapshot'] = {
          'attendants': [
            {'name': 'A'},
            {'name': 'B'},
          ],
        };
      rows = data.rows(
        [p],
        [StayModel.fromMap('s', s)],
        now: DateTime(2026, 1, 31),
      );
    });
    test(
      'discharged patient overlaps month with attendants directly underneath',
      () {
        expect(rows.map((row) => row.name), ['Patient', 'A', 'B']);
        expect(rows.map((row) => row.isAttendant), [false, true, true]);
        expect(
          data.rows([fixtures.patient()], [stay()], now: DateTime(2026, 10, 1)),
          isNotEmpty,
        );
      },
    );
    test(
      'month has correct number of calendar days, including leap February',
      () {
        expect(data.dates.length, 31);
        expect(MonthlyAttendanceData(DateTime(2026, 4), {}).dates.length, 30);
        expect(MonthlyAttendanceData(DateTime(2026, 2), {}).dates.length, 28);
        expect(MonthlyAttendanceData(DateTime(2024, 2), {}).dates.length, 29);
      },
    );
    test('outside stay cells are disabled and cannot become dirty', () {
      final editor = MonthlyAttendanceEditor(data);
      expect(rows.first.enabled(day), false);
      expect(rows.first.enabled(DateTime(2026, 1, 3)), true);
      expect(rows.first.enabled(DateTime(2026, 1, 7)), false);
      editor.edit(rows.first, day, 'Present');
      expect(editor.dirty, isEmpty);
    });
    test('local edits are visible, and reverting removes dirty state', () {
      final editor = MonthlyAttendanceEditor(data);
      final date = DateTime(2026, 1, 3);
      editor.edit(rows.first, date, 'Present');
      expect(editor.status(rows.first, date), 'Present');
      expect(editor.isDirty(rows.first, date), true);
      expect(data.records, isEmpty);
      editor.edit(rows.first, date, 'Unmarked');
      expect(editor.dirty, isEmpty);
    });
    test(
      'many changed cells save once, only dirty paths, deduplicated patients',
      () async {
        final editor = MonthlyAttendanceEditor(data);
        final date = DateTime(2026, 1, 3);
        editor.edit(rows.first, date, 'Present');
        editor.edit(rows[1], date, 'Absent');
        editor.edit(rows[2], DateTime(2026, 1, 4), 'Present');
        final db = BatchDatabase({});
        final expectedPaths = editor.patch.keys.toSet();
        final ids = await editor.save(db);
        expect(db.writes, 1);
        expect(db.lastPatch!.keys.toSet(), expectedPaths);
        expect(db.lastPatch!.length, 3);
        expect(ids, {'p'});
        expect(editor.dirty, isEmpty);
        expect(editor.status(rows[1], date), 'Absent');
        expect(data.records.length, 3);
        db.dispose();
      },
    );
    test(
      'failed save retains dirty edits; simultaneous save cannot duplicate PATCH',
      () async {
        final editor = MonthlyAttendanceEditor(data);
        editor.edit(rows.first, DateTime(2026, 1, 3), 'Present');
        final db = BatchDatabase({})..fail = true;
        await expectLater(editor.save(db), throwsStateError);
        expect(editor.dirty.length, 1);
        db.fail = false;
        db.barrier = Completer<void>();
        final first = editor.save(db);
        expect(await editor.save(db), isEmpty);
        db.barrier!.complete();
        await first;
        expect(db.writes, 1);
        expect(editor.dirty, isEmpty);
        db.dispose();
      },
    );
    test('month loads through exactly two date range queries', () async {
      final db = BatchDatabase({});
      await AttendanceService(db).loadMonth(DateTime(2026, 2));
      expect(db.ranges, [
        'attendance/daily:2026-02-01:2026-02-28',
        'attendant_attendance/daily:2026-02-01:2026-02-28',
      ]);
      expect(db.writes, 0);
      db.dispose();
    });
    testWidgets('grid cells edit locally with sticky grouped names', (
      tester,
    ) async {
      final editor = MonthlyAttendanceEditor(data);
      final date = DateTime(2026, 1, 3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => StickyAttendanceTable(
                data: {for (var i = 0; i < rows.length; i++) '$i': {}},
                dates: ['2026-01-03'],
                monthLabel: (_) => 'Jan',
                nameBuilder: (key) => Text(rows[int.parse(key)].name),
                cellBuilder: (key, _, status) => TextButton(
                  onPressed: () => setState(() {
                    editor.edit(rows[int.parse(key)], date, 'Present');
                  }),
                  child: Text(editor.status(rows[int.parse(key)], date)),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      await tester.tap(find.text('Unmarked').first);
      await tester.pump();
      expect(editor.dirty.length, 1);
      expect(find.text('Present'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Online UPI', () {
    testWidgets('dialog opens QR directly; invalid reference cannot confirm', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPatientPaymentDialog(
                  context: context,
                  patientName: 'Patient',
                  contactNumber: '',
                  bedsCount: 1,
                  attendantsCount: 0,
                  roomIdentifier: '101',
                  totalBillOverride: 1600,
                  patientId: 'p',
                ),
                child: const Text('Pay'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      expect(find.text('Scan QR & Pay ₹1600.00'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      expect(find.text('Check'), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.ensureVisible(find.text('Confirm received payment'));
      await tester.tap(find.text('Confirm received payment'));
      await tester.pump();
      expect(find.textContaining('12–35 character'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('verified merchant URI has exact amount and encoded note/name', () {
      final uri = Uri.parse(UpiPayment.uri(1600, note: 'Stay & receipt / P'));
      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], '9821125743m@pnb');
      expect(uri.queryParameters['pn'], 'PARMARTH SEVA SAMITI');
      expect(uri.queryParameters['mc'], '8398');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['am'], '1600.00');
      expect(uri.queryParameters['tn'], 'Stay & receipt / P');
      expect(UpiPayment.uri(1600), contains('PARMARTH%20SEVA%20SAMITI'));
    });
    test('amount uses two decimals and rejects zero/non-finite amounts', () {
      expect(UpiPayment.formatAmount(1600.5), '1600.50');
      expect(UpiPayment.formatAmount(12.34), '12.34');
      expect(UpiPayment.formatAmount(0.01), '0.01');
      expect(() => UpiPayment.uri(0), throwsArgumentError);
      expect(() => UpiPayment.uri(double.nan), throwsArgumentError);
      expect(() => UpiPayment.uri(double.infinity), throwsArgumentError);
    });
    test(
      'reference validation accepts UPI references and rejects invalid entries',
      () {
        expect(UpiPayment.validateReference(' 123456789012 '), isNull);
        expect(UpiPayment.validateReference('AXIS123456789012'), isNull);
        for (final reference in [
          '',
          '123',
          '12345 6789012',
          '12345678901/',
          'A' * 36,
        ]) {
          expect(UpiPayment.validateReference(reference), isNotNull);
        }
      },
    );
    test(
      'record uses ONLINE, both ledgers, same cycle; retries create no duplicate',
      () async {
        final old = fixtures.payment(25)..['id'] = 'old';
        final db = BatchDatabase({
          'patients': {
            'p': fixtures.patient(payments: [old]).toMap(),
          },
          'stays': {'s': stay().toMap()},
        });
        final service = PaymentService(db);
        final p = PaymentModel(
          id: 'request',
          amount: 175,
          method: 'online',
          date: day,
          transactionId: '123456789012',
        );
        final id = await service.recordPayment(
          patientId: 'p',
          patientName: 'Patient',
          payment: p,
        );
        expect(db.writes, 1);
        expect((await db.get('payments/$id'))['method'], 'ONLINE');
        expect((await db.get('paymentHistory/$id'))['cycleId'], fixtures.cycle);
        expect((await db.get('patients/p/payments') as Map).length, 2);
        expect(db.lastPatch, isNot(contains('patients/p/payments')));
        expect(
          await service.recordPayment(
            patientId: 'p',
            patientName: 'Patient',
            payment: p,
          ),
          id,
        );
        expect(db.writes, 1);
        db.dispose();
      },
    );
    test('concurrent submit rejected while first submit is pending', () async {
      final db = BatchDatabase({
        'patients': {'p': fixtures.patient().toMap()},
      })..barrier = Completer<void>();
      final service = PaymentService(db);
      final payment = PaymentModel(
        id: 'request',
        amount: 1,
        method: 'ONLINE',
        date: day,
        transactionId: '123456789012',
      );
      final first = service.recordPayment(
        patientId: 'p',
        patientName: 'Patient',
        payment: payment,
      );
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Patient',
          payment: payment,
        ),
        throwsStateError,
      );
      db.barrier!.complete();
      await first;
      expect(db.writes, 1);
      db.dispose();
    });
  });

  test(
    'atomic attendance PATCH updates SQLite and preserves untouched records',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cache = PersistentCache(CacheDatabase(NativeDatabase.memory()));
      await cache.initialize();
      await cache.activateAccount('test');
      await cache.replaceSnapshot('attendance/daily/2026-01-03', {
        'untouched': {'status': 'Absent'},
      });
      await cache.replaceSnapshot('patients/p', {
        ...fixtures.patient().toMap(),
        'payments': [fixtures.payment(25)],
      });
      final requests = <http.Request>[];
      final db = FirebaseRTDBRestService(
        projectId: 'test',
        persistentCache: cache,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(request.body, 200);
        }),
      );
      await db.patch('', {
        'attendance/daily/2026-01-03/p': {
          'status': 'Present',
          'date': '2026-01-03',
        },
        'attendant_attendance/daily/2026-01-03/p/A': {
          'status': 'Absent',
          'attendantName': 'A',
        },
        'patients/p/payments/new': {'id': 'new', 'amount': 50},
      });
      expect(requests.length, 1);
      expect(requests.single.method, 'PATCH');
      expect(
        jsonDecode(requests.single.body),
        contains('attendance/daily/2026-01-03/p'),
      );
      final daily = await cache.read('attendance/daily/2026-01-03') as Map;
      expect(daily['p']['status'], 'Present');
      expect(daily['untouched']['status'], 'Absent');
      final saved = await cache.read('patients/p') as Map;
      expect((saved['payments'] as Map).length, 2);
      db.dispose();
      await cache.close();
    },
  );
}
