import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/utils/stay_billing.dart';

void main() {
  test(
    'authoritative current cycle and account totals survive cache round trips',
    () {
      final patient = PatientModel.fromMap('synthetic', {
        'admissionDate': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
        'totalPaidAmount': 200,
        'currentDueAmount': 100,
        'totalRefundDueAmount': 1200,
        'financialReconciliation': {'required': true, 'accountNetPaid': 1400},
        'payments': [
          {
            'id': 'legacy',
            'amount': 1200,
            'date': DateTime.utc(2026, 10, 2).millisecondsSinceEpoch,
          },
        ],
      });
      for (final p in [
        patient,
        patient.copyWith(),
        PatientModel.fromMap('synthetic', patient.toMap()),
      ]) {
        expect(p.effectivePaidAmount, 200);
        expect(p.effectiveDueAmount, 100);
        expect(p.accountNetPaid, 1400);
        expect(p.confirmedRefundDueAmount, 0);
        expect(p.financialUncertain, isTrue);
      }
    },
  );
  test(
    'legacy receipt ownership does not follow timestamps or one remaining cycle',
    () {
      final admission = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
      final patient = PatientModel.fromMap('fixture', {
        'admissionDate': admission,
      });
      final payment = PaymentModel.fromMap('legacy', {
        'id': 'legacy',
        'amount': 1200,
        'date': admission,
      });
      expect(
        StayBilling.paymentCycle(payment, patient, []),
        'unallocated-payment:legacy',
      );
    },
  );
  test(
    'stay ownership uses saved segment evidence rather than recent creation time',
    () {
      final admission = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
      final patient = PatientModel.fromMap('fixture', {
        'admissionDate': admission,
        'admissionBalances': {
          'established': {
            'total': 1200,
            'segmentCharges': {'segment': 1200},
          },
        },
      });
      final stay = StayModel.fromMap('segment', {
        'admissionDate': admission,
        'createdAt': admission,
      });
      expect(StayBilling.cycleFor(stay, patient), 'established');
      final unknown = PatientModel.fromMap('fixture', {
        'admissionDate': admission,
      });
      expect(StayBilling.cycleFor(stay, unknown), 'unresolved-stay:segment');
    },
  );
}
