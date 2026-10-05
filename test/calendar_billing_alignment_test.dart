import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/utils/pricing_helper.dart';
import 'package:ngo/utils/stay_billing.dart';

import 'planned_exit_attendance_regression_test.dart' show RangeDatabase;

const id = 'calendar-patient';
final admission = DateTime(2026, 10, 5, 13, 52);
final plannedExit = DateTime(2026, 10, 17, 9);
final cycle = admission.millisecondsSinceEpoch.toString();
const presentDates = {5, 6, 7, 8, 9, 10, 13, 14};

Map<String, String> productionAttendance() => {
  for (var date = 5; date <= 17; date++)
    StayBilling.dateKey(DateTime(2026, 10, date)): presentDates.contains(date)
        ? 'Present'
        : 'Absent',
};

Map<String, dynamic> pricing(double rate) => {
  'generalRoomBedPrice': rate,
  'privateRoomBasePrice': 850,
  'privateRoomIncludedAttendants': 1,
  'privateRoomExtraAttendantFee': 225,
};

PatientModel patient({
  double paid = 2600,
  DateTime? exit,
  bool discharged = false,
}) => PatientModel.fromMap(id, {
  'fullName': 'Calendar patient',
  'admissionDate': admission.millisecondsSinceEpoch,
  'registrationDate': admission.millisecondsSinceEpoch,
  'exitDate': (exit ?? plannedExit).millisecondsSinceEpoch,
  'status': discharged ? 'discharged' : 'active',
  if (discharged) 'dischargeDate': (exit ?? plannedExit).millisecondsSinceEpoch,
  'payments': [
    {
      'id': 'original-receipt',
      'method': 'ONLINE',
      'amount': paid,
      'date': admission.millisecondsSinceEpoch,
      'cycleId': cycle,
    },
  ],
});

StayModel stay({
  DateTime? exit,
  bool completed = false,
  double? dailyRate,
  bool manual = false,
  double? override,
  double? longStayRate,
}) => StayModel.fromMap('stay', {
  'patientId': id,
  'patientName': 'Calendar patient',
  'cycleId': cycle,
  'roomId': 'general',
  'roomNumber': 'General Ward',
  'roomType': 'general',
  'admissionDate': admission.millisecondsSinceEpoch,
  'expectedDischargeDate': (exit ?? plannedExit).millisecondsSinceEpoch,
  'expiryDate': (exit ?? plannedExit).millisecondsSinceEpoch,
  'durationDays': PricingHelper.calculateStayDays(
    admission,
    exit ?? plannedExit,
  ),
  'status': completed ? 'completed' : 'active',
  if (completed) 'completedAt': (exit ?? plannedExit).millisecondsSinceEpoch,
  'createdAt': admission.millisecondsSinceEpoch,
  'updatedAt':
      (completed ? exit ?? plannedExit : admission).millisecondsSinceEpoch,
  'dailyRate': dailyRate,
  'dailyRateIsManual': manual,
  'costOverride': override,
  'longStayDailyRate': longStayRate,
});

RangeDatabase database({
  double rate = 200,
  PatientModel? model,
  StayModel? segment,
  Map<String, String>? attendance,
}) => RangeDatabase({
  'patients': {id: (model ?? patient()).toMap()},
  'stays': {'stay': (segment ?? stay()).toMap()},
  'admin_settings': {'pricing': pricing(rate)},
  'attendance': <String, dynamic>{
    'daily': <String, dynamic>{
      for (final entry in (attendance ?? productionAttendance()).entries)
        entry.key: {
          id: {'status': entry.value, 'date': entry.key},
        },
    },
  },
});

void main() {
  test(
    '13-day admission baseline settles eight Present and five Absent dates',
    () async {
      final period = PricingHelper.attendancePeriod(admission, plannedExit);
      // The admission quote uses this inclusive period, not physical duration.
      final quote =
          period.days *
          PricingHelper.calculateDailyCharge(false, 0, pricing: pricing(200));
      expect(period.days, 13);
      expect(quote, 2600);
      final db = database(
        attendance: {},
        model: patient(paid: quote),
      );
      addTearDown(db.dispose);
      await db.patch(
        '',
        PatientService.initialAdmissionAttendance(
          patientId: id,
          patientName: 'Calendar patient',
          start: admission,
          exit: plannedExit,
          cycleId: cycle,
          attendants: [],
        ),
      );
      final service = PaymentService(db);
      final baseline = await service.billingUpdates(id);
      expect(baseline['patients/$id/advanceBilledAmount'], quote);
      expect(baseline['stays/stay/billableDays'], 13);
      expect(baseline['patients/$id/refundDueAmount'], 0);

      final settled = await service.billingUpdates(
        id,
        patientAttendanceOverrides: productionAttendance(),
      );
      expect(settled['patients/$id/totalPresentDays'], 8);
      expect(settled['patients/$id/totalAbsentDays'], 5);
      expect(settled['stays/stay/billableDays'], 8);
      expect(settled['patients/$id/advanceBilledAmount'], 1600);
      expect(settled['patients/$id/totalPaidAmount'], 2600);
      expect(settled['patients/$id/refundDueAmount'], 1000);
      expect(quote - settled['patients/$id/advanceBilledAmount'], 5 * 200);
      expect(
        db.ranges,
        everyElement(
          predicate<({String path, String start, String end})>(
            (range) => range.start == '2026-10-05' && range.end == '2026-10-17',
          ),
        ),
      );
      // Reading a calculation never writes billing or rewrites a receipt.
      expect(db.writes, 1);
      expect((await db.get('patients/$id/payments'))[0]['amount'], 2600);
    },
  );

  test(
    'Absent exit credits one eligible day; Present exit charges it once',
    () async {
      final db = database(
        attendance: {
          for (var date = 5; date <= 17; date++)
            StayBilling.dateKey(DateTime(2026, 10, date)): 'Present',
        },
      );
      addTearDown(db.dispose);
      final service = PaymentService(db);
      final present = await service.billingUpdates(id);
      final absent = await service.billingUpdates(
        id,
        patientAttendanceOverrides: {'2026-10-17': 'Absent'},
      );
      expect(present['stays/stay/billableDays'], 13);
      expect(present['patients/$id/advanceBilledAmount'], 2600);
      expect(absent['stays/stay/billableDays'], 12);
      expect(absent['patients/$id/advanceBilledAmount'], 2400);
      expect(absent['patients/$id/refundDueAmount'], 200);
      expect(
        present['patients/$id/advanceBilledAmount'] -
            absent['patients/$id/advanceBilledAmount'],
        200,
      );
    },
  );

  for (final direction in ['Absent to Present', 'Present to Absent']) {
    test('two-date $direction delta follows the configured rate', () async {
      final increasing = direction == 'Absent to Present';
      final db = database(
        attendance: {
          ...productionAttendance(),
          '2026-10-16': increasing ? 'Absent' : 'Present',
          '2026-10-17': increasing ? 'Absent' : 'Present',
        },
      );
      addTearDown(db.dispose);
      final service = PaymentService(db);
      final before = await service.billingUpdates(id);
      final after = await service.billingUpdates(
        id,
        patientAttendanceOverrides: {
          '2026-10-16': increasing ? 'Present' : 'Absent',
          '2026-10-17': increasing ? 'Present' : 'Absent',
        },
      );
      expect(
        after['patients/$id/advanceBilledAmount'] -
            before['patients/$id/advanceBilledAmount'],
        increasing ? 400 : -400,
      );
      expect(
        after['patients/$id/refundDueAmount'] -
            before['patients/$id/refundDueAmount'],
        increasing ? -400 : 400,
      );
      expect(db.writes, 0);
    });
  }

  test('admin price changes flow through the real billing service', () async {
    final db = database();
    addTearDown(db.dispose);
    final service = PaymentService(db);
    for (final rate in [200.0, 250.0]) {
      db.root['admin_settings'] = {'pricing': pricing(rate)};
      final settled = await service.billingUpdates(id);
      final baseline = await service.billingUpdates(
        id,
        patientAttendanceOverrides: {
          for (final key in productionAttendance().keys) key: 'Present',
        },
      );
      expect(baseline['patients/$id/advanceBilledAmount'], 13 * rate);
      expect(settled['patients/$id/advanceBilledAmount'], 8 * rate);
      expect(
        baseline['patients/$id/advanceBilledAmount'] -
            settled['patients/$id/advanceBilledAmount'],
        5 * rate,
      );
      // Changing prices cannot increase the amount of a historical receipt.
      expect(settled['patients/$id/totalPaidAmount'], 2600);
      expect(settled['patients/$id/refundDueAmount'], 2600 - 8 * rate);
    }
  });

  test(
    'manual rates and explicit cost overrides retain their authority',
    () async {
      for (final manual in [false, true]) {
        final db = database(segment: stay(dailyRate: 390, manual: manual));
        addTearDown(db.dispose);
        final updates = await PaymentService(db).billingUpdates(id);
        expect(
          updates['patients/$id/advanceBilledAmount'],
          8 * (manual ? 390 : 200),
        );
      }
      final db = database(
        segment: stay(dailyRate: 390, manual: true, override: 1234),
      );
      addTearDown(db.dispose);
      final updates = await PaymentService(db).billingUpdates(id);
      expect(updates['patients/$id/advanceBilledAmount'], 1234);
      expect(updates['patients/$id/refundDueAmount'], 1366);
    },
  );

  test(
    'patient absence does not suppress a Present attendant on the exit',
    () async {
      final db = database(
        attendance: {
          for (final key in productionAttendance().keys) key: 'Absent',
        },
      );
      addTearDown(db.dispose);
      final updates = await PaymentService(db).billingUpdates(
        id,
        attendantAttendanceOverrides: {
          '2026-10-17': {'A': 'Present', 'B': 'Absent'},
        },
      );
      expect(updates['patients/$id/advanceBilledAmount'], 200);
      expect(updates['stays/stay/billableDays'], 1);
    },
  );

  test(
    'admission seeds patient and attendant over the same inclusive period',
    () async {
      final db = database(attendance: {}, model: patient(paid: 5200));
      addTearDown(db.dispose);
      final initial = PatientService.initialAdmissionAttendance(
        patientId: id,
        patientName: 'Calendar patient',
        start: admission,
        exit: plannedExit,
        cycleId: cycle,
        attendants: [AttendantModel(name: 'A')],
      );
      expect(
        initial.keys.where((key) => key.startsWith('attendance/')),
        hasLength(13),
      );
      expect(
        initial.keys.where((key) => key.startsWith('attendant_attendance/')),
        hasLength(13),
      );
      await db.patch('', initial);
      final updates = await PaymentService(db).billingUpdates(id);
      expect(updates['patients/$id/advanceBilledAmount'], 5200);
      expect(updates['patients/$id/refundDueAmount'], 0);
      expect(updates['patients/$id/currentDueAmount'], 0);
      expect(updates['patients/$id/paymentStatus'], 'Paid');
    },
  );

  test(
    'long-stay rates still apply beyond the sixtieth billable date',
    () async {
      final exit = DateTime(2026, 12, 5, 9);
      final period = PricingHelper.attendancePeriod(admission, exit);
      expect(period.days, 62);
      final attendance = {
        for (var index = 0; index < period.days; index++)
          StayBilling.dateKey(DateTime(2026, 10, 5 + index)): 'Present',
      };
      for (final longRate in [null, 390.0]) {
        final db = database(
          model: patient(exit: exit),
          segment: stay(exit: exit, longStayRate: longRate),
          attendance: attendance,
        );
        addTearDown(db.dispose);
        final service = PaymentService(db);
        final present = await service.billingUpdates(id);
        final absent = await service.billingUpdates(
          id,
          patientAttendanceOverrides: {'2026-12-05': 'Absent'},
        );
        final applicableLongRate = longRate ?? 250;
        expect(present['stays/stay/billableDays'], 62);
        expect(
          present['patients/$id/advanceBilledAmount'],
          60 * 200 + 2 * applicableLongRate,
        );
        expect(
          absent['patients/$id/advanceBilledAmount'],
          60 * 200 + applicableLongRate,
        );
      }
    },
  );

  test(
    'actual checkout retains 9 AM threshold without an attendance exception',
    () async {
      for (final minute in [0, 1]) {
        final exit = DateTime(2026, 10, 17, 9, minute);
        expect(
          PricingHelper.calculateStayDays(admission, exit),
          minute == 0 ? 12 : 13,
        );
        final db = database(
          model: patient(exit: exit, discharged: true),
          segment: stay(exit: exit, completed: true),
          attendance: {},
        );
        addTearDown(db.dispose);
        final updates = await PaymentService(db).billingUpdates(id);
        expect(updates['stays/stay/billableDays'], minute == 0 ? 12 : 13);
        expect(
          updates['patients/$id/advanceBilledAmount'],
          (minute == 0 ? 12 : 13) * 200,
        );
      }
    },
  );

  test('profile, grid and admission share all thirteen planned dates', () {
    final p = patient();
    expect(StayBilling.attendanceDateRange(p, now: admission), (
      start: '2026-10-05',
      end: '2026-10-17',
    ));
    final grid = MonthlyAttendanceData(DateTime(2026, 10), {});
    final row = grid.rows([p], [stay()], now: admission).single;
    final enabled = grid.dates
        .where(row.enabled)
        .map(StayBilling.dateKey)
        .toList();
    expect(enabled, productionAttendance().keys.toList());
    expect(enabled, hasLength(13));
    expect(row.enabled(DateTime(2026, 10, 4)), false);
    expect(row.enabled(DateTime(2026, 10, 18)), false);
    final historical = patient(
      exit: DateTime(2026, 10, 15, 8),
      discharged: true,
    );
    expect(
      StayBilling.attendanceDateRange(historical, now: DateTime(2026, 11)).end,
      '2026-10-15',
    );
    expect(
      grid
          .rows(
            [historical],
            [stay(exit: DateTime(2026, 10, 15, 8), completed: true)],
            now: DateTime(2026, 11),
          )
          .single
          .enabled(DateTime(2026, 10, 15)),
      true,
    );
  });

  test(
    'recalculation is idempotent and preserves the original payment',
    () async {
      final db = database();
      addTearDown(db.dispose);
      final original = await db.get('patients/$id/payments');
      final service = PaymentService(db);
      await service.recalculatePatientAttendanceAndBilling(id);
      expect(db.writes, 1);
      expect(await db.get('patients/$id/advanceBilledAmount'), 1600);
      expect(await db.get('patients/$id/refundDueAmount'), 1000);
      await service.recalculatePatientAttendanceAndBilling(id);
      expect(db.writes, 1);
      expect(await db.get('patients/$id/payments'), original);
    },
  );
}
