import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/patients/widgets/refund_dialog.dart';
import 'package:ngo/screens/payments/patient_financial_dialog.dart';
import 'package:ngo/screens/payments/payments_screen.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/service_locator.dart';

class _FakePatientService extends Fake implements PatientService {
  final List<PatientModel> _patients;
  _FakePatientService(this._patients);

  @override
  Stream<List<PatientModel>> getPatientsStream() =>
      Stream.value(_patients).asBroadcastStream();

  @override
  Future<PatientModel?> getPatient(String patientId) async =>
      _patients.where((p) => p.id == patientId).firstOrNull;
}

class _FakePaymentService extends Fake implements PaymentService {
  final List<Map<String, dynamic>> ledger;
  final Map<String, dynamic> billing;
  final List<StayModel> stays;
  final List<Map<String, dynamic>> recordedRefunds = [];

  _FakePaymentService({
    required this.ledger,
    required this.billing,
    required this.stays,
  });

  @override
  Stream<List<Map<String, dynamic>>> getAllPaymentsStream() =>
      Stream.value(ledger);

  @override
  Future<List<StayModel>> loadStays(String patientId) async => stays;

  @override
  Future<Map<String, dynamic>> billingUpdates(
    String patientId, {
    Map<String, dynamic>? patientData,
    List<StayModel>? stays,
    Map<String, String?> patientAttendanceOverrides = const {},
    Map<String, Map<String, String?>> attendantAttendanceOverrides = const {},
  }) async => billing;

  @override
  Future<String> recordRefund({
    required String patientId,
    required String cycleId,
    required double amount,
    required DateTime date,
    required String method,
    String receiptNumber = '',
    String transactionId = '',
    String? requestId,
  }) async {
    recordedRefunds.add({
      'patientId': patientId,
      'cycleId': cycleId,
      'amount': amount,
      'date': date,
      'method': method,
      'receiptNumber': receiptNumber,
      'transactionId': transactionId,
      'requestId': requestId,
    });
    return 'refund_ok_123';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackendApiException Server Error Formatting', () {
    test('extracts message from json response body correctly', () {
      const jsonBody = '{"statusCode":409,"error":"Conflict","message":"Refund exceeds the remaining excess payment"}';
      final msg = BackendApiException.extractMessage(jsonBody);
      expect(msg, 'Refund exceeds the remaining excess payment');

      final exception = BackendApiException(409, 'POST', serverMessage: msg, responseBody: jsonBody);
      expect(exception.statusCode, 409);
      expect(exception.serverMessage, 'Refund exceeds the remaining excess payment');
      expect(exception.message, contains('POST failed (HTTP 409): Refund exceeds the remaining excess payment'));
    });

    test('extracts error field when message is absent', () {
      const jsonBody = '{"error":"Forbidden"}';
      final msg = BackendApiException.extractMessage(jsonBody);
      expect(msg, 'Forbidden');
    });

    test('falls back safely when response body is not valid json', () {
      const rawBody = '<html>502 Bad Gateway</html>';
      final msg = BackendApiException.extractMessage(rawBody);
      expect(msg, isNull);

      final exception = BackendApiException(502, 'POST', serverMessage: msg);
      expect(exception.message, 'POST failed (HTTP 502)');
    });
  });

  group('RefundDialog Widget & Flow', () {
    late _FakePatientService fakePatientService;
    late _FakePaymentService fakePaymentService;
    late PatientModel testPatient;

    setUp(() {
      const cycleKey = '1792316340000';
      testPatient = PatientModel.fromMap('p_test_1', {
        'fullName': 'Test Patient Scenario',
        'contactNumber': '9876543210',
        'status': 'active',
        'totalPaidAmount': 2800.0,
        'currentDueAmount': 0.0,
        'refundDueAmount': 1200.0,
        'totalRefundDueAmount': 1200.0,
        'totalRefundedAmount': 0.0,
        'advanceBilledAmount': 1600.0,
        'attendanceCharges': 0.0,
        'roomNumber': '101',
        'registrationNumber': 'REG-2026-001',
      });

      fakePatientService = _FakePatientService([testPatient]);
      fakePaymentService = _FakePaymentService(
        ledger: [
          {
            'id': 'pay_1',
            'patientId': 'p_test_1',
            'patientName': 'Test Patient Scenario',
            'amount': 2800.0,
            'type': 'payment',
            'method': 'ONLINE',
            'date': 1792316340000,
          },
        ],
        billing: {
          'patients/p_test_1/admissionBalances': {
            cycleKey: {
              'cycleId': cycleKey,
              'total': 1600.0,
              'paid': 2800.0,
              'refunded': 0.0,
              'netPaid': 2800.0,
              'due': 0.0,
              'refundDue': 1200.0,
              'status': 'Payment Exceeded',
            },
          },
        },
        stays: [],
      );

      ServiceLocator().patientService = fakePatientService;
      ServiceLocator().paymentService = fakePaymentService;
    });

    testWidgets('loads excess amount and pre-fills ₹1,200 refundable balance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefundDialog(patient: testPatient),
          ),
        ),
      );

      // Loading spinner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Verified dialog header & contents
      expect(find.text('Record refund paid'), findsNWidgets(2));
      expect(find.text('Record money already returned to the patient. This updates the balance and adds a refund to the transaction ledger.'), findsOneWidget);

      // Verified pre-filled refund amount of 1200.00
      expect(find.widgetWithText(TextField, '1200.00'), findsOneWidget);

      // Verified method choices
      expect(find.text('Cash'), findsOneWidget);

      // Verified confirm button
      expect(find.widgetWithText(FilledButton, 'Record refund paid'), findsOneWidget);
    });

    testWidgets('records refund with valid values and invokes PaymentService', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefundDialog(patient: testPatient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap confirm button
      final recordButton = find.widgetWithText(FilledButton, 'Record refund paid');
      expect(recordButton, findsOneWidget);
      await tester.tap(recordButton);
      await tester.pumpAndSettle();

      // Verify refund was passed to fake payment service
      expect(fakePaymentService.recordedRefunds, hasLength(1));
      final refund = fakePaymentService.recordedRefunds.first;
      expect(refund['patientId'], 'p_test_1');
      expect(refund['amount'], 1200.0);
      expect(refund['cycleId'], '1792316340000');
    });
  });

  group('PaymentsScreen Sidebar and Financial Overview', () {
    late PatientModel testPatient;

    setUp(() {
      testPatient = PatientModel.fromMap('p_test_1', {
        'fullName': 'Patient With Refund Due',
        'contactNumber': '9876543210',
        'status': 'active',
        'totalPaidAmount': 2800.0,
        'currentDueAmount': 0.0,
        'refundDueAmount': 1200.0,
        'totalRefundDueAmount': 1200.0,
        'totalRefundedAmount': 0.0,
        'advanceBilledAmount': 1600.0,
        'attendanceCharges': 0.0,
        'roomNumber': '101',
      });

      ServiceLocator().patientService = _FakePatientService([testPatient]);
      ServiceLocator().paymentService = _FakePaymentService(
        ledger: [
          {
            'id': 'pay_1',
            'patientId': 'p_test_1',
            'patientName': 'Patient With Refund Due',
            'amount': 2800.0,
            'type': 'payment',
            'method': 'ONLINE',
            'date': 1792316340000,
          },
          {
            'id': 'ref_1',
            'patientId': 'p_test_1',
            'patientName': 'Patient With Refund Due',
            'amount': -1200.0,
            'type': 'refund',
            'method': 'online',
            'date': 1792347900000,
          },
        ],
        billing: {},
        stays: [],
      );
    });

    testWidgets('renders Payments Dashboard with Record Refund header button, summary cards and filter chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header and tile refund buttons
      expect(find.text('Record Refund'), findsWidgets);
      expect(find.text('Show QR Code'), findsOneWidget);

      // Summary cards
      expect(find.text('Total Outstanding Due'), findsOneWidget);
      expect(find.text('Net Collected'), findsOneWidget);
      expect(find.text('Total Refund Due'), findsOneWidget);

      // Filter chips
      expect(find.textContaining('All Patients'), findsOneWidget);
      expect(find.textContaining('Due Patients'), findsOneWidget);
      expect(find.textContaining('Refund Due ('), findsOneWidget);

      // Patient billing tile displays excess and Record Refund action
      expect(find.text('Patient With Refund Due'), findsOneWidget);
      expect(find.textContaining('Excess: ₹1,200'), findsOneWidget);
    });

    testWidgets('PatientFinancialDialog displays admission cycles and transaction history', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientFinancialDialog(initialPatient: testPatient),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Financial overview metrics
      expect(find.text('Total Billed'), findsOneWidget);
      expect(find.text('Net Paid'), findsOneWidget);
      expect(find.text('Outstanding Due'), findsOneWidget);
      expect(find.text('Refund Due (Excess)'), findsOneWidget);

      // Excess banner
      expect(find.textContaining('Payment exceeded by ₹1,200.00'), findsOneWidget);
    });
  });
}
