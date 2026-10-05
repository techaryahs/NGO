import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/utils/stay_billing.dart';

import 'stay_billing_test.dart' show TestDatabase;

const patientId = 'p_1791185403261280_327df8e24a6918cb1cc93bcc';
final admission = DateTime(2026, 10, 5, 12, 58);
final plannedExit = DateTime(2026, 10, 17, 9);
final cycleId = admission.millisecondsSinceEpoch.toString();

PatientModel patient({bool discharged = false, DateTime? actualExit}) =>
    PatientModel.fromMap(patientId, {
      'fullName': 'test',
      'admissionDate': admission.millisecondsSinceEpoch,
      'registrationDate': admission.millisecondsSinceEpoch,
      'exitDate': plannedExit.millisecondsSinceEpoch,
      'status': discharged ? 'discharged' : 'active',
      if (actualExit != null)
        'dischargeDate': actualExit.millisecondsSinceEpoch,
      'attendants': [],
      'payments': [
        {
          'id': 'receipt',
          'amount': 8400.0,
          'method': 'ONLINE',
          'date': admission.millisecondsSinceEpoch,
          'cycleId': cycleId,
        },
      ],
    });

StayModel stay({
  String type = 'private',
  double? manualRate,
  bool manual = false,
  double? override,
  DateTime? actualExit,
}) => StayModel.fromMap('stay', {
  'patientId': patientId,
  'patientName': 'test',
  'cycleId': cycleId,
  'roomId': 'room_1A',
  'roomNumber': '1A',
  'roomType': type,
  'admissionDate': admission.millisecondsSinceEpoch,
  'expectedDischargeDate': plannedExit.millisecondsSinceEpoch,
  'expiryDate': plannedExit.millisecondsSinceEpoch,
  'durationDays': 12,
  'attendantCount': 0,
  'status': actualExit == null ? 'active' : 'completed',
  if (actualExit != null) 'completedAt': actualExit.millisecondsSinceEpoch,
  'createdAt': admission.millisecondsSinceEpoch,
  'updatedAt': (actualExit ?? admission).millisecondsSinceEpoch,
  'dailyRate': manualRate,
  'dailyRateIsManual': manual,
  'costOverride': override,
});

Map<String, dynamic> pricing(double rate) => {
  'privateRoomBasePrice': rate,
  'privateRoomIncludedAttendants': 1,
  'privateRoomExtraAttendantFee': 200,
  'generalRoomBedPrice': 275,
};

Map<String, String> beforeAttendance() => {
  for (var day = 5; day <= 17; day++)
    StayBilling.dateKey(DateTime(2026, 10, day)): day <= 12
        ? 'Present'
        : 'Absent',
};
Map<String, String> onlyExitPresent() => {
  for (var day = 5; day <= 17; day++)
    StayBilling.dateKey(DateTime(2026, 10, day)): day == 17
        ? 'Present'
        : 'Absent',
};

class RangeDatabase extends TestDatabase {
  final ranges = <({String path, String start, String end})>[];
  RangeDatabase(super.root);
  @override
  Future<dynamic> getByKeyRange(
    String path, {
    required String startKey,
    required String endKey,
  }) {
    ranges.add((path: path, start: startKey, end: endKey));
    return super.getByKeyRange(path, startKey: startKey, endKey: endKey);
  }
}

void main() {
  test(
    'active 9 AM planned exit evaluates explicit patient presence on exit date',
    () {
      final bill = StayBilling.calculate(
        patient: patient(),
        stays: [stay()],
        pricing: pricing(700),
        attendance: onlyExitPresent(),
        now: admission,
      ).single;
      expect(bill.days['stay'], 1);
      expect(bill.total, 700);
    },
  );

  test(
    'exact two-cell reproduction through bounded billing query: 5600 to 7000',
    () async {
      final attendance = beforeAttendance();
      final db = RangeDatabase({
        'patients': {patientId: patient().toMap()},
        'stays': {'stay': stay().toMap()},
        'admin_settings': {'pricing': pricing(700)},
        'attendance': {
          'daily': {
            for (final entry in attendance.entries)
              entry.key: {
                patientId: {'status': entry.value, 'date': entry.key},
              },
          },
        },
      });
      addTearDown(db.dispose);
      final service = PaymentService(db);
      final before = await service.billingUpdates(patientId);
      final after = await service.billingUpdates(
        patientId,
        patientAttendanceOverrides: {
          '2026-10-16': 'Present',
          '2026-10-17': 'Present',
        },
      );
      final amountPath = 'patients/$patientId/advanceBilledAmount';
      expect(before[amountPath], 5600);
      expect(before['stays/stay/billableDays'], 8);
      expect(before['patients/$patientId/refundDueAmount'], 2800);
      expect(after[amountPath], 7000);
      expect(after['stays/stay/billableDays'], 10);
      expect(after[amountPath] - before[amountPath], 1400);
      expect(after['patients/$patientId/totalPaidAmount'], 8400);
      expect(after['patients/$patientId/refundDueAmount'], 1400);
      expect(
        db.ranges,
        everyElement(
          predicate<({String path, String start, String end})>(
            (range) => range.start == '2026-10-05' && range.end == '2026-10-17',
          ),
        ),
      );
      expect(db.ranges.map((range) => range.path), [
        'attendance/daily',
        'attendant_attendance/daily',
        'attendance/daily',
        'attendant_attendance/daily',
      ]);
      expect(db.writes, 0);
    },
  );

  test(
    'no exit-date attendance retains 9 AM checkout; later checkout adds a day',
    () {
      for (final minute in [0, 1]) {
        final exit = DateTime(2026, 10, 17, 9, minute);
        final p = PatientModel.fromMap(
          patientId,
          patient().toMap()..['exitDate'] = exit.millisecondsSinceEpoch,
        );
        final bill = StayBilling.calculate(
          patient: p,
          stays: [stay()],
          pricing: pricing(700),
          attendance: {'2026-10-16': 'Present'},
          now: admission,
        ).single;
        expect(bill.days['stay'], minute == 0 ? 12 : 13);
        expect(bill.total, (minute == 0 ? 12 : 13) * 700);
      }
    },
  );

  test(
    'both edited dates follow dynamically configured private room rates',
    () {
      for (final rate in [700.0, 850.0]) {
        final before = StayBilling.calculate(
          patient: patient(),
          stays: [stay()],
          pricing: pricing(rate),
          attendance: beforeAttendance(),
          now: admission,
        ).single;
        final after = StayBilling.calculate(
          patient: patient(),
          stays: [stay()],
          pricing: pricing(rate),
          attendance: {
            ...beforeAttendance(),
            '2026-10-16': 'Present',
            '2026-10-17': 'Present',
          },
          now: admission,
        ).single;
        expect(before.total, 8 * rate);
        expect(after.total, 10 * rate);
        expect(after.total - before.total, 2 * rate);
      }
    },
  );

  test('manual daily rate flag and cost override retain existing behavior', () {
    for (final manual in [false, true]) {
      final bill = StayBilling.calculate(
        patient: patient(),
        stays: [stay(manualRate: 390, manual: manual)],
        pricing: pricing(850),
        attendance: onlyExitPresent(),
        now: admission,
      ).single;
      expect(bill.total, manual ? 390 : 850);
    }
    final overridden = StayBilling.calculate(
      patient: patient(),
      stays: [stay(manualRate: 390, manual: true, override: 1234)],
      pricing: pricing(850),
      attendance: onlyExitPresent(),
      now: admission,
    ).single;
    expect(overridden.total, 1234);
  });

  test(
    'patient absent on planned exit does not suppress present attendant',
    () {
      final bill = StayBilling.calculate(
        patient: patient(),
        stays: [stay(type: 'general')],
        pricing: pricing(850),
        attendance: {
          for (var day = 5; day <= 17; day++)
            StayBilling.dateKey(DateTime(2026, 10, day)): 'Absent',
        },
        attendantAttendance: {
          '2026-10-17': {'A': 'Present', 'B': 'Absent'},
        },
        now: admission,
      ).single;
      expect(bill.total, 275);
      expect(bill.days['stay'], 1);
    },
  );

  test(
    'attendant-only exit presence and explicit Unmarked do not add a patient day',
    () {
      for (final status in [null, 'Unmarked']) {
        final attendance = {
          for (var day = 5; day <= 16; day++)
            StayBilling.dateKey(DateTime(2026, 10, day)): 'Absent',
          if (status != null) '2026-10-17': status,
        };
        final bill = StayBilling.calculate(
          patient: patient(),
          stays: [stay(type: 'general')],
          pricing: pricing(850),
          attendance: attendance,
          attendantAttendance: {
            '2026-10-17': {'A': 'Present'},
          },
          now: admission,
        ).single;
        expect(bill.total, 275);
      }
      final unmarked = StayBilling.calculate(
        patient: patient(),
        stays: [stay()],
        pricing: pricing(850),
        attendance: {...onlyExitPresent(), '2026-10-17': 'Unmarked'},
        now: admission,
      ).single;
      expect(unmarked.total, 0);
    },
  );

  test(
    'planned exit presence stays within its admission and active segment context',
    () {
      final beyond = StayBilling.calculate(
        patient: patient(),
        stays: [stay()],
        pricing: pricing(700),
        attendance: {
          ...beforeAttendance(),
          '2026-10-04': 'Present',
          '2026-10-18': 'Present',
        },
        now: admission,
      ).single;
      expect(beyond.total, 5600);
      final completed = StayBilling.calculate(
        patient: patient(),
        stays: [stay(actualExit: DateTime(2026, 10, 16, 9))],
        pricing: pricing(700),
        attendance: onlyExitPresent(),
        now: admission,
      ).single;
      expect(completed.total, 0);
    },
  );

  test(
    'profile resolver covers full active planned stay rather than stopping today',
    () {
      final range = StayBilling.attendanceDateRange(patient(), now: admission);
      expect(range, (start: '2026-10-05', end: '2026-10-17'));
      final grid = MonthlyAttendanceData(
        DateTime(2026, 10),
        {},
      ).rows([patient()], [stay()], now: admission);
      expect(grid.single.enabled(plannedExit), true);
      final initial = PatientService.initialAdmissionAttendance(
        patientId: patientId,
        patientName: 'test',
        start: admission,
        exit: plannedExit,
        cycleId: cycleId,
        attendants: [],
      );
      expect(
        initial.containsKey('attendance/daily/2026-10-17/$patientId'),
        true,
      );
    },
  );

  test(
    'discharged profile uses actual discharge and billing retains actual 9 AM checkout',
    () {
      final p = patient(discharged: true, actualExit: plannedExit);
      expect(StayBilling.attendanceDateRange(p, now: DateTime(2026, 11)), (
        start: '2026-10-05',
        end: '2026-10-17',
      ));
      final earlier = patient(
        discharged: true,
        actualExit: DateTime(2026, 10, 15, 8),
      );
      expect(
        StayBilling.attendanceDateRange(earlier, now: DateTime(2026, 11)).end,
        '2026-10-15',
      );
      final bill = StayBilling.calculate(
        patient: p,
        stays: [stay(actualExit: plannedExit)],
        pricing: pricing(700),
        attendance: onlyExitPresent(),
        now: DateTime(2026, 11),
      ).single;
      expect(bill.total, 0);
    },
  );
}
