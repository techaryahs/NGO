import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/utils/stay_billing.dart';

class _Patients extends PatientService {
  final StreamController<List<PatientModel>> updates =
      StreamController.broadcast();
  final PatientModel initial;
  _Patients(this.initial);
  @override
  Stream<List<PatientModel>> getPatientsStream() async* {
    yield [initial];
    yield* updates.stream;
  }
}

class _Billing extends PaymentService {
  final List<String> recalculated = [];
  _Billing() : super(null);
  @override
  Future<void> schedulePatientBilling(
    String patientId, {
    bool immediate = false,
  }) async {
    recalculated.add(patientId);
  }
}

void main() {
  testWidgets(
    'retained Monthly Attendance receives post-edit roster; search, room filter, save and month return keep its independent mark',
    (tester) async {
      dotenv.loadFromString(
        isOptional: true,
        envString:
            'USE_POSTGRES_BACKEND=true\nBACKEND_BASE_URL=https://example.test/api\n',
      );
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      final patient = PatientModel.fromMap('patient', {
        'fullName': 'Patient',
        'admissionDate': start.millisecondsSinceEpoch,
        'registrationDate': start.millisecondsSinceEpoch,
        'exitDate': end.millisecondsSinceEpoch,
        'status': 'active',
      });
      final stay = StayModel.fromMap('stay', {
        'patientId': patient.id,
        'patientName': patient.fullName,
        'roomId': 'room',
        'roomNumber': '1D',
        'roomType': 'general',
        'status': 'active',
        'admissionDate': start.millisecondsSinceEpoch,
        'createdAt': start.millisecondsSinceEpoch,
        'updatedAt': start.millisecondsSinceEpoch,
        'expectedDischargeDate': end.millisecondsSinceEpoch,
        'cycleId': StayBilling.currentCycle(patient),
        'patientSnapshot': {'attendants': []},
      });
      final patients = _Patients(patient), billing = _Billing();
      var currentStay = stay;
      final records = <String, Map<String, dynamic>>{};
      final writes = <Map<String, dynamic>>[];
      final api = BackendApiService(
        baseUrl: 'https://example.test/api',
        getAuthToken: () async => 'synthetic',
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/stays') {
            return http.Response(
              jsonEncode({currentStay.id: currentStay.toMap()}),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/attendance') {
            final q = request.url.queryParameters;
            final selected = <String, dynamic>{};
            for (final entry in records.entries) {
              final parts = entry.key.split('/');
              if (parts[0] == q['kind'] &&
                  parts[1].compareTo(q['startDate']!) >= 0 &&
                  parts[1].compareTo(q['endDate']!) <= 0) {
                selected[parts[1]] = entry.value;
              }
            }
            return http.Response(jsonEncode(selected), 200);
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/attendance/bulk') {
            final body = Map<String, dynamic>.from(
              jsonDecode(request.body) as Map,
            );
            writes.add(body);
            records['${body['kind']}/${body['date']}'] =
                Map<String, dynamic>.from(body['records'] as Map);
            return http.Response('{"success":true}', 200);
          }
          throw StateError('Unexpected attendance UI request ${request.url}');
        }),
      );
      ServiceLocator().patientService = patients;
      ServiceLocator().roomService = RoomService(backendApiService: api);
      ServiceLocator().paymentService = billing;
      ServiceLocator().backendApiService = api;
      addTearDown(() async {
        await patients.updates.close();
        ServiceLocator().dispose();
        dotenv.loadFromString(isOptional: true, envString: '');
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Attendance())),
      );
      await tester.pumpAndSettle();
      expect(find.text('↳ Family helper'), findsNothing);
      final updated = patient.copyWith(
        attendants: [AttendantModel(id: 'helper', name: 'Family helper')],
      );
      final updatedStay = StayModel.fromMap(stay.id, {
        ...stay.toMap(),
        'patientSnapshot': {
          'attendants': [
            {
              'id': 'helper',
              'name': 'Family helper',
              'startDate': StayBilling.dateKey(start),
            },
          ],
        },
      });
      patients.updates.add([updated]);
      currentStay = updatedStay;
      await api.refresh('stays');
      await tester.pumpAndSettle();
      expect(find.text('↳ Family helper'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Family helper');
      await tester.pumpAndSettle();
      expect(find.text('↳ Family helper'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1D').last);
      await tester.pumpAndSettle();
      final cell = find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message ==
                'Family helper • 01 ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][start.month - 1]} • Pending',
      );
      expect(cell, findsOneWidget);
      await tester.tap(
        find.descendant(of: cell, matching: find.byType(InkWell)),
      );
      await tester.pump();
      await tester.tap(find.text('Save Changes (1)'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single['kind'], 'attendant_attendance');
      expect(
        writes.single['records'][patient.id]['helper']['status'],
        'Present',
      );
      expect(billing.recalculated, [patient.id]);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('↳ Family helper'), findsNothing);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('↳ Family helper'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message?.startsWith('Family helper • 01 ') == true &&
              widget.message!.endsWith(' • Present'),
        ),
        findsOneWidget,
      );
      expect(writes, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
