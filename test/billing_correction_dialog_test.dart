import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/screens/patients/widgets/billing_correction_dialog.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/service_locator.dart';

void main() {
  testWidgets('admin selects dates, reviews total and submits a reason', (
    tester,
  ) async {
    final admission = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
    final patient = PatientModel.fromMap('synthetic123', {
      'admissionDate': admission,
      'status': 'active',
    });
    Map<String, dynamic>? submitted;
    final api = BackendApiService(
      baseUrl: 'https://example.test/api',
      getAuthToken: () async => 'test',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'patient': {
                ...patient.toMap(),
                'admissionBalances': {
                  '$admission': {
                    'reconciliationRequired': false,
                    'dayCharges': [
                      {
                        'day': '2026-10-01',
                        'stayId': 's1',
                        'amount': 400,
                        'eligible': true,
                        'excluded': false,
                      },
                      {
                        'day': '2026-10-02',
                        'stayId': 's1',
                        'amount': 200,
                        'eligible': true,
                        'excluded': false,
                      },
                    ],
                  },
                },
              },
              'stays': [],
            }),
            200,
          );
        }
        submitted = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({'patient': patient.toMap(), 'stays': []}),
          201,
        );
      }),
    );
    ServiceLocator().backendApiService = api;
    addTearDown(() {
      ServiceLocator().backendApiService = null;
      api.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => BillingCorrectionDialog(patient: patient),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('01 Oct 2026'));
    await tester.tap(find.text('02 Oct 2026'));
    await tester.pump();
    expect(find.text('Selected total: ₹600.00'), findsOneWidget);
    await tester.tap(find.text('Review correction'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 date(s) totalling ₹600.00'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(submitted!['reason'], 'Billing correction');
    expect(submitted!['dates'], hasLength(2));
  });
}
