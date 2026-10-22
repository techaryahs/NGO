import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/screens/patients/widgets/payment_dialog.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/service_locator.dart';

void main() {
  final admission = DateTime(2026, 10, 1);
  final cycle = admission.millisecondsSinceEpoch.toString();
  late Map<String, dynamic> patient;
  late List<Map<String, dynamic>> writes;
  late BackendApiService api;
  late PaymentService service;
  Future<http.Response> Function(Map<String, dynamic>)? submit;

  PaymentModel payment({
    String reference = '123456789013',
    double amount = 2000,
  }) => PaymentModel(
    id: 'request',
    amount: amount,
    method: 'ONLINE',
    date: DateTime(2026, 10, 5),
    transactionId: reference,
    receiptNumber: 'new receipt',
    notes: 'additional payment',
    totalAmount: 4000,
    paidAmount: 2000 + amount,
    pendingAmount: 2000 - amount,
  );

  setUp(() {
    writes = [];
    submit = null;
    patient = {
      'fullName': 'Synthetic patient',
      'admissionDate': admission.millisecondsSinceEpoch,
      'advanceBilledAmount': 4000,
      'totalPaidAmount': 2000,
      'currentDueAmount': 2000,
      'payments': [
        PaymentModel(
          id: 'original',
          amount: 2000,
          totalAmount: 2000,
          method: 'ONLINE',
          date: admission,
          transactionId: '123456789012',
          cycleId: cycle,
        ).toMap(),
      ],
    };
    api = BackendApiService(
      baseUrl: 'https://backend.example/api',
      getAuthToken: () async => 'synthetic-auth',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer synthetic-auth');
        if (request.method == 'GET' && request.url.path == '/api/patients/p') {
          return http.Response(jsonEncode(patient), 200);
        }
        if (request.method == 'GET' && request.url.path == '/api/stays') {
          return http.Response('{}', 200);
        }
        if (request.method == 'GET' && request.url.path == '/api/payments') {
          return http.Response(
            jsonEncode({
              for (final row in (patient['payments'] as List).whereType<Map>())
                row['id']: row,
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.startsWith('/api/payments/')) {
          final id = request.url.pathSegments.last;
          final receipt = (patient['payments'] as List)
              .whereType<Map>()
              .where((row) => row['id'] == id)
              .first;
          return http.Response(jsonEncode(receipt), 200);
        }
        if (request.method == 'POST' && request.url.path == '/api/payments') {
          final body = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          writes.add(body);
          if (submit != null) return submit!(body);
          (patient['payments'] as List).add(body);
          patient['totalPaidAmount'] = 2000 + body['amount'];
          patient['currentDueAmount'] =
              4000 - (patient['totalPaidAmount'] as num);
          return http.Response(jsonEncode(body), 201);
        }
        throw StateError('Unexpected request ${request.method} ${request.url}');
      }),
    );
    service = PaymentService(null, api);
    ServiceLocator().paymentService = service;
  });
  tearDown(() {
    ServiceLocator().paymentService = null;
    service.disposeScheduler();
    api.dispose();
  });

  test(
    'additional receipt uses real POST, independent amount and active cycle; retry preserves both receipts',
    () async {
      final id = await service.recordPayment(
        patientId: 'p',
        patientName: 'Synthetic patient',
        payment: payment(),
        collectOutstanding: true,
      );
      expect(writes.single, containsPair('amount', 2000));
      expect(writes.single, containsPair('collectOutstanding', true));
      expect(writes.single, containsPair('cycleId', cycle));
      expect(writes.single['receiptNumber'], 'new receipt');
      expect(id.length, lessThanOrEqualTo(128));
      expect(patient['totalPaidAmount'], 4000);
      expect(patient['currentDueAmount'], 0);
      expect(patient['payments'], hasLength(2));
      final retried = await service.recordPayment(
        patientId: 'p',
        patientName: 'Synthetic patient',
        payment: payment(),
        collectOutstanding: true,
      );
      expect(retried, id);
      expect(writes, hasLength(1));
    },
  );

  test(
    'a committed retry refreshes the watched transaction ledger without another POST',
    () async {
      final initial = Completer<void>();
      final values = <List<Map<String, dynamic>>>[];
      final subscription = service.getAllPaymentsStream().listen((value) {
        values.add(value);
        if (!initial.isCompleted) initial.complete();
      });
      await initial.future;
      expect(values.last, hasLength(1));
      final otherSessionReceipt = payment().toMap()
        ..addAll({'id': 'other-session', 'patientId': 'p', 'cycleId': cycle});
      (patient['payments'] as List).add(otherSessionReceipt);
      patient['totalPaidAmount'] = 4000;
      patient['currentDueAmount'] = 0;
      final id = await service.recordPayment(
        patientId: 'p',
        patientName: 'Synthetic patient',
        payment: payment(),
        collectOutstanding: true,
      );
      expect(id, 'other-session');
      await Future<void>.delayed(Duration.zero);
      expect(values.last, hasLength(2));
      expect(writes, isEmpty);
      await subscription.cancel();
    },
  );

  test(
    'reusing original reference on the increased bill gives a meaningful failure instead of false new-payment success',
    () async {
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Synthetic patient',
          payment: payment(reference: '123456789012'),
          collectOutstanding: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('earlier payment'),
          ),
        ),
      );
      expect(writes, isEmpty);
      expect(patient['payments'], hasLength(1));
      expect(patient['currentDueAmount'], 2000);
    },
  );

  test(
    'same bill partial receipt reference cannot count as a new remaining payment',
    () async {
      final prior =
          (patient['payments'] as List).single as Map<String, dynamic>;
      prior.addAll({
        'totalAmount': 4000,
        'paidAmount': 2000,
        'pendingAmount': 2000,
      });
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Synthetic patient',
          payment: payment(reference: '123456789012'),
          collectOutstanding: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('No additional payment was recorded'),
          ),
        ),
      );
      expect(writes, isEmpty);
      expect(patient['currentDueAmount'], 2000);
      expect(patient['payments'], hasLength(1));
    },
  );

  test(
    'legacy reference without invoice metadata cannot imply a newly collected payment',
    () async {
      final prior =
          (patient['payments'] as List).single as Map<String, dynamic>;
      prior.addAll({'totalAmount': 0, 'paidAmount': 0, 'pendingAmount': 0});
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Synthetic patient',
          payment: payment(reference: '123456789012'),
          collectOutstanding: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already recorded'),
          ),
        ),
      );
      expect(writes, isEmpty);
      expect(patient['currentDueAmount'], 2000);
    },
  );

  test(
    'server rejection propagates and does not change history or balance',
    () async {
      submit = (_) async => http.Response(
        '{"message":"Payment exceeds the current outstanding balance"}',
        409,
      );
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Synthetic patient',
          payment: payment(),
          collectOutstanding: true,
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.serverMessage,
            'server message',
            contains('outstanding'),
          ),
        ),
      );
      expect(patient['payments'], hasLength(1));
      expect(patient['currentDueAmount'], 2000);
    },
  );

  test(
    'an HTTP success without a committed transaction identifier is not reported as recorded',
    () async {
      submit = (_) async => http.Response('{}', 201);
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Synthetic patient',
          payment: payment(),
          collectOutstanding: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('did not confirm'),
          ),
        ),
      );
      expect(patient['payments'], hasLength(1));
    },
  );

  test(
    'payment remains pending until the server responds and a concurrent submission is rejected',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      submit = (_) {
        started.complete();
        return pending.future;
      };
      var completed = false;
      final first = service
          .recordPayment(
            patientId: 'p',
            patientName: 'Synthetic patient',
            payment: payment(),
            collectOutstanding: true,
          )
          .then((id) {
            completed = true;
            return id;
          });
      await started.future;
      expect(completed, isFalse);
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Synthetic patient',
          payment: payment(),
          collectOutstanding: true,
        ),
        throwsStateError,
      );
      pending.complete(http.Response(jsonEncode(writes.single), 201));
      await first;
      expect(completed, isTrue);
      expect(writes, hasLength(1));
    },
  );

  for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
    test('rejects invalid payment amount $invalid without a request', () async {
      await expectLater(
        service.recordPayment(
          patientId: 'p',
          patientName: 'Synthetic patient',
          payment: payment(amount: invalid),
          collectOutstanding: true,
        ),
        throwsArgumentError,
      );
      expect(writes, isEmpty);
    });
  }

  Future<void> openDialog(
    WidgetTester tester, {
    String reference = '123456789013',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPatientPaymentDialog(
                context: context,
                patientName: 'Synthetic patient',
                contactNumber: '',
                bedsCount: 1,
                attendantsCount: 1,
                roomIdentifier: '101',
                totalBillOverride: 4000,
                alreadyPaid: 2000,
                patientId: 'p',
              ),
              child: const Text('Pay Remaining'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay Remaining'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'UTR / UPI reference'),
      reference,
    );
    await tester.ensureVisible(find.text('Confirm received payment'));
  }

  testWidgets(
    'real shared dialog stays open on failure; retry uses identical receipt metadata and closes after acknowledgement',
    (tester) async {
      submit = (_) async =>
          http.Response('{"message":"Synthetic rollback"}', 500);
      await openDialog(tester);
      await tester.tap(find.text('Confirm received payment'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Synthetic rollback'), findsOneWidget);
      expect(patient['payments'], hasLength(1));
      final first = writes.single;
      submit = (body) async => http.Response(jsonEncode(body), 201);
      await tester.tap(find.text('Confirm received payment'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(2));
      expect(writes.last['id'], first['id']);
      expect(writes.last['date'], first['date']);
      expect(writes.last['amount'], first['amount']);
      expect(writes.last['collectOutstanding'], isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy duplicate reference leaves the real shared dialog open with an already-recorded message',
    (tester) async {
      final prior =
          (patient['payments'] as List).single as Map<String, dynamic>;
      prior.addAll({'totalAmount': 0, 'paidAmount': 0, 'pendingAmount': 0});
      await openDialog(tester, reference: '123456789012');
      await tester.tap(find.text('Confirm received payment'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('No additional payment was recorded'),
        findsOneWidget,
      );
      expect(writes, isEmpty);
      expect(patient['currentDueAmount'], 2000);
    },
  );

  testWidgets(
    'lost commit acknowledgement retries the same dialog attempt without duplicating payment',
    (tester) async {
      submit = (body) async {
        (patient['payments'] as List).add(body);
        patient['totalPaidAmount'] = 4000;
        patient['currentDueAmount'] = 0;
        return http.Response(
          '{"message":"Synthetic response lost after commit"}',
          502,
        );
      };
      await openDialog(tester);
      await tester.tap(find.text('Confirm received payment'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(patient['payments'], hasLength(2));
      await tester.tap(find.text('Confirm received payment'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, hasLength(1));
      expect(patient['payments'], hasLength(2));
      expect(patient['currentDueAmount'], 0);
    },
  );
}
