import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/screens/patients/patient_profile_screen.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/service_locator.dart';

class _Patients extends Fake implements PatientService {
  _Patients(this.patient);
  final PatientModel patient;
  @override
  bool get isPostgres => true;
  @override
  Stream<List<PatientModel>> getPatientsStream() => Stream.value([patient]);
}

class _Rooms extends Fake implements RoomService {}

void main() {
  testWidgets(
    'profile uses checkout snapshot when the patient stream has the stale planned bill',
    (tester) async {
      final admission = DateTime.now().subtract(const Duration(days: 13));
      final exit = DateTime.now().subtract(const Duration(days: 5));
      final cycle = admission.millisecondsSinceEpoch.toString();
      final stale = PatientModel.fromMap('fixture123', {
        'fullName': 'Synthetic',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'exitDate': exit.millisecondsSinceEpoch,
        'advanceBilledAmount': 3200,
        'totalPaidAmount': 3200,
        'currentDueAmount': 0,
        'financialReconciliation': {'required': false},
      });
      var quotes = 0;
      final api = BackendApiService(
        baseUrl: 'https://example.test/api',
        getAuthToken: () async => 'token',
        client: MockClient((request) async {
          if (request.url.path == '/api/patients/fixture123/financials') {
            expect(request.url.queryParameters['checkoutAt'], isNotNull);
            quotes++;
            return http.Response(
              jsonEncode({
                'patient': {
                  ...stale.toMap(),
                  'advanceBilledAmount': 5200,
                  'currentDueAmount': 2000,
                  'admissionBalances': {
                    cycle: {
                      'total': 5200,
                      'netPaid': 3200,
                      'due': 2000,
                      'reconciliationRequired': false,
                    },
                  },
                },
                'stays': [],
              }),
              200,
            );
          }
          throw StateError('Unexpected request: ${request.url.path}');
        }),
      );
      final locator = ServiceLocator();
      locator.backendApiService = api;
      locator.patientService = _Patients(stale);
      locator.roomService = _Rooms();
      final paymentService = PaymentService(null, api);
      locator.paymentService = paymentService;
      addTearDown(() {
        locator.backendApiService = null;
        locator.patientService = null;
        locator.roomService = null;
        locator.paymentService = null;
        paymentService.disposeScheduler();
        api.dispose();
      });
      tester.view.physicalSize = const Size(2200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: PatientProfileScreen(patient: stale)),
      );
      await tester.pumpAndSettle();
      expect(quotes, greaterThan(0));
      expect(find.text('₹5,200'), findsOneWidget);
      expect(find.text('₹2,000'), findsOneWidget);
      await tester.ensureVisible(find.text('Record Payment'));
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Record Payment'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      expect(find.text('Pending: ₹2000.00'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Amount to collect (₹)'),
        findsOneWidget,
      );
      expect(quotes, greaterThanOrEqualTo(2));
    },
  );
}
