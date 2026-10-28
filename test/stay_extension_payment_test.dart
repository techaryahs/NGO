import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/screens/patients/patient_profile_screen.dart';

void main() {
  testWidgets(
    'extension balance enables payment and retains other review warnings',
    (tester) async {
      final admission = DateTime.utc(2026, 10, 16).millisecondsSinceEpoch;
      PatientModel patient(double paid) => PatientModel.fromMap('fixture', {
        'fullName': 'Synthetic',
        'status': 'active',
        'admissionDate': admission,
        'advanceBilledAmount': 5200,
        'totalPaidAmount': paid,
        'currentDueAmount': 5200 - paid,
        'financialReconciliation': {
          'required': true,
          'cycleIdentityIssues': [
            {'stayId': 'older'},
          ],
        },
        'admissionBalances': {
          '$admission': {'reconciliationRequired': false, 'due': 5200 - paid},
        },
      });
      var tapped = false;
      Widget view(double paid) => MaterialApp(
        home: Scaffold(
          body: buildPatientOverviewForTesting(
            patient(paid),
            onRecordPayment: () => tapped = true,
          ),
        ),
      );
      await tester.pumpWidget(view(3200));
      expect(find.text('₹5,200'), findsOneWidget);
      expect(find.text('₹2,000'), findsOneWidget);
      expect(
        find.textContaining('admission identity conflict'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Record Payment'));
      await tester.tap(find.text('Record Payment'));
      expect(tapped, isTrue);
      await tester.pumpWidget(view(5200));
      expect(
        find.textContaining('admission identity conflict'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Record Payment'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    },
  );
}
