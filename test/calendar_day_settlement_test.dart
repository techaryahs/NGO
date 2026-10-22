import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/utils/stay_billing.dart';
import 'package:ngo/utils/pricing_helper.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';

void main() {
  final admission = DateTime(2026, 10, 19, 12);
  final cycle = admission.millisecondsSinceEpoch.toString();
  for (final hour in [0, 8, 9, 12, 23]) {
    test(
      'PostgreSQL calendar billing includes October 31 at $hour:00 before and after discharge',
      () {
        final exit = DateTime(2026, 10, 31, hour);
        final marks = {
          for (var d = 19; d <= 31; d++)
            '2026-10-$d': d >= 29 ? 'Absent' : 'Present',
        };
        final invoices = <double>[];
        for (final completed in [false, true]) {
          final patient = PatientModel.fromMap('synthetic', {
            'fullName': 'Synthetic',
            'admissionDate': admission.millisecondsSinceEpoch,
            'exitDate': exit.millisecondsSinceEpoch,
            'status': completed ? 'discharged' : 'active',
            'payments': [
              {
                'id': 'paid',
                'cycleId': cycle,
                'amount': 2600,
                'date': admission.millisecondsSinceEpoch,
              },
            ],
          });
          final stay = StayModel.fromMap('s', {
            'patientId': 'synthetic',
            'roomId': 'r',
            'roomNumber': 'QA',
            'roomType': 'general',
            'cycleId': cycle,
            'admissionDate': admission.millisecondsSinceEpoch,
            'expectedDischargeDate': exit.millisecondsSinceEpoch,
            'completedAt': completed ? exit.millisecondsSinceEpoch : null,
            'status': completed ? 'completed' : 'active',
            if (completed) 'totalCost': 2000,
            if (completed) 'billingSummary': {'days': 10},
            'createdAt': admission.millisecondsSinceEpoch,
            'updatedAt': exit.millisecondsSinceEpoch,
          });
          final bill = StayBilling.calculate(
            patient: patient,
            stays: [stay],
            pricing: {},
            attendance: marks,
            calendarDayBilling: true,
          ).single;
          invoices.add(bill.total);
          expect(bill.total, 2000);
          expect(bill.refundDue, 600);
          expect(bill.days['s'], 10);
          final unmarked = StayBilling.calculate(
            patient: patient,
            stays: [stay],
            pricing: {},
            calendarDayBilling: true,
          ).single;
          expect(
            unmarked.total,
            completed ? 2000 : 2600,
            reason: completed
                ? 'Finalized history retains its stored invoice without repricing attendance'
                : 'The provisional estimate does not fabricate attendance',
          );
          expect(PricingHelper.calculateBillingDays(admission, exit), 13);
        }
        expect(invoices[0], invoices[1]);
        expect(marks.values.where((v) => v == 'Present').length, 10);
        expect(marks.values.where((v) => v == 'Absent').length, 3);
      },
    );
  }
  test(
    'open calendar admission retains a seven-day advance without creating presence',
    () {
      final patient = PatientModel.fromMap('p', {
        'fullName': 'Synthetic',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
      });
      final stay = StayModel.fromMap('s', {
        'patientId': 'p',
        'roomId': 'r',
        'roomType': 'general',
        'status': 'active',
        'cycleId': cycle,
        'admissionDate': admission.millisecondsSinceEpoch,
        'expectedDischargeDate': admission
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch,
        'createdAt': admission.millisecondsSinceEpoch,
      });
      final bill = StayBilling.calculate(
        patient: patient,
        stays: [stay],
        pricing: {},
        now: admission,
        calendarDayBilling: true,
      ).single;
      expect(bill.days['s'], 7);
      expect(bill.total, 1400);
    },
  );
}
