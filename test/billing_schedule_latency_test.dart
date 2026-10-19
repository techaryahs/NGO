import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/services/payment_service.dart';

class _BillingProbe extends PaymentService {
  final completed = Completer<void>();
  int calls = 0;

  @override
  Future<void> recalculatePatientAttendanceAndBilling(
    String patientId, {
    bool updateBilling = true,
    Map<String, String?> patientAttendanceOverrides = const {},
    Map<String, Map<String, String?>> attendantAttendanceOverrides = const {},
  }) {
    calls++;
    return completed.future;
  }
}

void main() {
  testWidgets(
    'disposing a scheduler cancels a pass already waiting on earlier billing',
    (tester) async {
      final billing = _BillingProbe();
      final first = billing.schedulePatientBilling('p', immediate: true);
      await tester.pump(const Duration(milliseconds: 1));
      final waiting = billing.schedulePatientBilling('p', immediate: true);
      await tester.pump(const Duration(milliseconds: 1));
      billing.disposeScheduler();
      billing.completed.complete();
      await tester.pump();
      await Future.wait([first, waiting]);
      expect(billing.calls, 1);
    },
  );

  testWidgets(
    'explicit save starts billing immediately and awaits completion',
    (tester) async {
      final billing = _BillingProbe();
      final background = billing.schedulePatientBilling('synthetic-patient');
      var finished = false;
      final explicitSave = billing
          .schedulePatientBilling('synthetic-patient', immediate: true)
          .then((_) => finished = true);

      await tester.pump(const Duration(milliseconds: 1));
      expect(billing.calls, 1, reason: 'No 1200ms wait after explicit Save');
      expect(finished, isFalse, reason: 'Save still waits for billing');

      billing.completed.complete();
      await tester.pump();
      await Future.wait([background, explicitSave]);
      expect(finished, isTrue);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(billing.calls, 1, reason: 'The old debounce must not run again');
    },
  );
}
