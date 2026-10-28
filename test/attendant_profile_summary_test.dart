import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';

void main() {
  test('ID marks override conflicting legacy marks for the same day', () {
    final roster = [AttendantModel(id: 'a1', name: 'Helper')];
    final dates = <String, dynamic>{
      for (var day = 21; day <= 22; day++)
        '2026-10-$day': {
          'Helper': {'attendantName': 'Helper', 'status': 'Present'},
        },
      '2026-10-23': {
        'Helper': {'attendantName': 'Helper', 'status': 'Present'},
        'a1': {
          'attendantId': 'a1',
          'attendantName': 'Helper',
          'status': 'Unmarked',
        },
      },
      for (var day = 24; day <= 27; day++)
        '2026-10-$day': {
          'Helper': {'attendantName': 'Helper', 'status': 'Present'},
          'a1': {
            'attendantId': 'a1',
            'attendantName': 'Helper',
            'status': 'Absent',
          },
        },
    };
    final result = AttendanceService.attendantSummary(dates, roster);
    expect(result, hasLength(1));
    expect(result.single.present, 2);
    expect(result.single.absent, 4);
    expect(dates['2026-10-23']['Helper']['status'], 'Present');
  });

  test(
    'distinct IDs, legacy-only names and historical identities remain distinct',
    () {
      final roster = [
        AttendantModel(id: 'a1', name: 'Same'),
        AttendantModel(id: 'a2', name: 'Same'),
        AttendantModel(id: 'a3', name: 'Legacy / helper'),
      ];
      final result = AttendanceService.attendantSummary({
        '2026-10-21': {
          'a1': {
            'attendantId': 'a1',
            'attendantName': 'Same',
            'status': 'Present',
          },
          'a2': {
            'attendantId': 'a2',
            'attendantName': 'Same',
            'status': 'Absent',
          },
          'Legacy _ helper': {
            'attendantName': 'Legacy / helper',
            'status': 'Present',
          },
          'old-id': {
            'attendantId': 'old-id',
            'attendantName': 'Former',
            'status': 'Absent',
          },
        },
      }, roster);
      expect(result.map((s) => (s.name, s.present, s.absent)).toList(), [
        ('Same', 1, 0),
        ('Same', 0, 1),
        ('Legacy / helper', 1, 0),
        ('Former', 0, 1),
      ]);
    },
  );

  test('an ambiguous legacy name is not assigned to either same-name ID', () {
    final result = AttendanceService.attendantSummary(
      {
        '2026-10-21': {
          'Same': {'attendantName': 'Same', 'status': 'Present'},
        },
      },
      [
        AttendantModel(id: 'a1', name: 'Same'),
        AttendantModel(id: 'a2', name: 'Same'),
      ],
    );
    expect(result.map((s) => s.present).toList(), [0, 0, 1]);
  });

  test(
    'an ID-keyed entry wins even when the legacy payload also has that ID',
    () {
      final result = AttendanceService.attendantSummary(
        {
          '2026-10-21': {
            'a1': {'attendantId': 'a1', 'status': 'Absent'},
            'Helper': {'attendantId': 'a1', 'status': 'Present'},
          },
        },
        [AttendantModel(id: 'a1', name: 'Helper')],
      );
      expect(result.single.present, 0);
      expect(result.single.absent, 1);
    },
  );

  test('admission date bounds exclude earlier and later cycle marks', () {
    final result = AttendanceService.attendantSummary(
      {
        '2026-09-30': {
          'a1': {'status': 'Present'},
        },
        '2026-10-10': {
          'a1': {'status': 'Absent'},
        },
        '2026-11-01': {
          'a1': {'status': 'Present'},
        },
      },
      [AttendantModel(id: 'a1', name: 'Helper')],
      startDate: '2026-10-01',
      endDate: '2026-10-31',
    );
    expect(result.single.present, 0);
    expect(result.single.absent, 1);
  });
}
