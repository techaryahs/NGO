import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/utils/stay_billing.dart';
import 'attendance_payment_implementation_test.dart' show BatchDatabase;
import 'stay_billing_test.dart' as fixtures;

void main() {
  final admission = DateTime(2026, 1, 1);
  final arrival = DateTime(2026, 1, 6);
  final patient = fixtures
      .patient(status: 'active', exit: 10)
      .copyWith(
        attendants: [AttendantModel(id: 'helper', name: 'Family helper')],
      );
  StayModel stay({String? startDate = '2026-01-06', String type = 'general'}) =>
      StayModel.fromMap(
        's',
        fixtures.segment('s', type, 1, 11, status: 'active')
          ..['patientSnapshot'] = {
            'admissionDate': patient.admissionDate.millisecondsSinceEpoch,
            'attendants': [
              {
                'id': 'helper',
                'name': 'Family helper',
                if (startDate != null) 'startDate': startDate,
              },
            ],
          },
      );

  test(
    'post-edit roster creates one separate row; earlier dates are disabled',
    () {
      final data = MonthlyAttendanceData(admission, {});
      final rows = data.rows([patient], [stay()], now: arrival);
      expect(rows.map((r) => r.name), ['Patient', 'Family helper']);
      expect(rows.last.attendantId, 'helper');
      expect(rows.last.patientId, patient.id);
      expect(rows.first.enabled(admission), isTrue);
      expect(rows.last.enabled(admission), isFalse);
      expect(rows.last.enabled(arrival), isTrue);
      expect(rows.last.enabled(DateTime(2026, 1, 10)), isTrue);
      expect(rows.last.enabled(DateTime(2026, 1, 11)), isFalse);
      final editor = MonthlyAttendanceEditor(data);
      editor.edit(rows.last, admission, 'Present');
      expect(editor.dirty, isEmpty);
    },
  );

  test('admission-time roster retains full stay eligibility', () {
    final rows = MonthlyAttendanceData(
      admission,
      {},
    ).rows([patient], [stay(startDate: null)]);
    expect(rows.last.enabled(admission), isTrue);
  });

  test(
    'independent edits persist on reload without duplicate rows or records',
    () async {
      final db = BatchDatabase({});
      final data = MonthlyAttendanceData(admission, {});
      final rows = data.rows([patient], [stay()]);
      final editor = MonthlyAttendanceEditor(data);
      editor.edit(rows.first, arrival, 'Absent');
      editor.edit(rows.last, arrival, 'Present');
      expect(await editor.save(db), {patient.id});
      final reloaded = await AttendanceService(db).loadMonth(admission);
      final rebuilt = reloaded.rows([patient], [stay()]);
      final view = MonthlyAttendanceEditor(reloaded);
      expect(rebuilt, hasLength(2));
      expect(view.status(rebuilt.first, arrival), 'Absent');
      expect(view.status(rebuilt.last, arrival), 'Present');
      view.edit(rebuilt.last, arrival, 'Present');
      expect(view.dirty, isEmpty);
      final writes = db.writes;
      expect(await view.save(db), isEmpty);
      expect(db.writes, writes);
      db.dispose();
    },
  );

  test(
    'month navigation, room/name filtering and repeat rebuilds retain identity',
    () {
      for (final month in [
        DateTime(2026, 1),
        DateTime(2026, 2),
        DateTime(2026, 1),
      ]) {
        final rows = MonthlyAttendanceData(
          month,
          {},
        ).rows([patient], [stay()], now: arrival);
        if (month.month == 2) {
          expect(rows, isEmpty);
        } else {
          final filtered = rows
              .where((r) => r.room == 'general' && r.name.contains('helper'))
              .toList();
          expect(filtered, hasLength(1));
          expect(
            filtered.single.path(arrival),
            'attendant_attendance/daily/2026-01-06/p/helper',
          );
        }
      }
      final beforeArrival = MonthlyAttendanceData(
        DateTime(2025, 12),
        {},
      ).rows([patient], [stay()]);
      expect(beforeArrival, isEmpty);
    },
  );

  test(
    'arrival eligibility gates charges and Pending requirements in shared Flutter billing',
    () {
      final marks = {
        for (var i = 1; i <= 10; i++)
          '2026-01-${i.toString().padLeft(2, '0')}': {'helper': 'Present'},
      };
      for (final type in ['general', 'lobby', 'private']) {
        final bill = StayBilling.calculate(
          calendarDayBilling: true,
          patient: patient,
          stays: [stay(type: type)],
          pricing: {},
          attendance: {
            for (var i = 1; i <= 10; i++)
              '2026-01-${i.toString().padLeft(2, '0')}': 'Present',
          },
          attendantAttendance: marks,
        ).single;
        expect(bill.total, type == 'private' ? 7000 : 3000);
      }
      marks['2026-01-06']!['helper'] = 'Absent';
      marks['2026-01-07']!['helper'] = 'Pending';
      final bill = StayBilling.calculate(
        calendarDayBilling: true,
        patient: patient,
        stays: [stay()],
        pricing: {},
        attendantAttendance: marks,
      ).single;
      expect(bill.total, 2600);
      expect(
        bill.pendingAttendance.where(
          (mark) => mark['kind'] == 'attendant_attendance',
        ),
        [
          {
            'day': '2026-01-07',
            'kind': 'attendant_attendance',
            'attendantId': 'helper',
          },
        ],
      );
    },
  );
}
