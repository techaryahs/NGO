import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/patients/widgets/inline_stay_editor.dart';
import 'package:ngo/screens/patients/widgets/stay_history_card.dart';

final _start = DateTime(2026, 8, 30, 15, 21);
StayModel _stay() => StayModel.fromMap('stay', {
  'patientId': 'p',
  'patientName': 'Patient',
  'roomId': 'room',
  'roomNumber': '2B',
  'roomType': 'general',
  'status': 'active',
  'bedId': 'bed1',
  'bedLabel': '1',
  'admissionDate': _start.millisecondsSinceEpoch,
  'createdAt': _start.millisecondsSinceEpoch,
  'updatedAt': _start.millisecondsSinceEpoch,
  'expectedDischargeDate': _start
      .add(const Duration(days: 7))
      .millisecondsSinceEpoch,
  'patientSnapshot': {'registrationNumber': '5157', 'attendants': []},
});
final _patient = PatientModel.fromMap('p', {
  'fullName': 'Patient',
  'status': 'active',
  'admissionDate': _start.millisecondsSinceEpoch,
});
final _room = RoomModel.fromMap('room', {
  'roomNumber': '2B',
  'roomIdentifier': '2B',
  'roomType': 'general',
  'beds': {
    'bed1': {
      'id': 'bed1',
      'bedLabel': '1',
      'status': 'occupied',
      'currentStayId': 'stay',
    },
  },
});

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> openEdit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Edit stay and payment actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit stay'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byType(InlineStayEditor), findsOneWidget);
}

void main() {
  testWidgets(
    'editing is inline, uses real bed label, and Cancel discards the draft',
    (tester) async {
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                StayHistoryCard(
                  stay: _stay(),
                  patient: _patient,
                  summary: const {},
                  currentAdmission: true,
                  multipleSegments: false,
                  onPayments: () {},
                  onRefund: () {},
                  loadRooms: () async => [_room],
                  saveChanges: (_) async {
                    writes++;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Registration No. 5157'), findsOneWidget);
      await openEdit(tester);
      expect(find.text('Bed 3/4'), findsOneWidget);
      await tester.enterText(field('Registration number'), 'CHANGED');
      await tester.enterText(field('Patient name'), 'Changed name');
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.byType(InlineStayEditor), findsNothing);
      expect(find.text('Registration No. 5157'), findsOneWidget);
      await tester.ensureVisible(
        find.byTooltip('Edit stay and payment actions'),
      );
      await openEdit(tester);
      expect(
        tester.widget<TextField>(field('Registration number')).controller!.text,
        '5157',
      );
    },
  );

  testWidgets(
    'Save persists once, then returns to the normal card with saved values',
    (tester) async {
      var current = _stay();
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ListView(
                children: [
                  StayHistoryCard(
                    stay: current,
                    patient: _patient,
                    summary: const {},
                    currentAdmission: true,
                    multipleSegments: false,
                    onPayments: () {},
                    onRefund: () {},
                    loadRooms: () async => [_room],
                    saveChanges: (changes) async {
                      writes++;
                      expect(changes['bedId'], 'bed1');
                      expect(
                        changes['bedLabel'],
                        '1',
                      ); // Display labels never replace database bed identity.
                      setState(
                        () => current = StayModel.fromMap('stay', {
                          ...current.toMap(),
                          ...changes,
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await openEdit(tester);
      await tester.enterText(field('Registration number'), 'NEW-5158');
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.byType(InlineStayEditor), findsNothing);
      expect(find.text('Registration No. NEW-5158'), findsOneWidget);
    },
  );

  testWidgets('a failed save retains the draft and allows cancellation', (
    tester,
  ) async {
    final result = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              StayHistoryCard(
                stay: _stay(),
                patient: _patient,
                summary: const {},
                currentAdmission: true,
                multipleSegments: false,
                onPayments: () {},
                onRefund: () {},
                loadRooms: () async => [_room],
                saveChanges: (_) => result.future,
              ),
            ],
          ),
        ),
      ),
    );
    await openEdit(tester);
    await tester.enterText(field('Registration number'), 'UNSAVED');
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    result.completeError(StateError('Bed no longer available'));
    await tester.pumpAndSettle();
    expect(find.byType(InlineStayEditor), findsOneWidget);
    expect(find.textContaining('Bed no longer available'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('Registration number')).controller!.text,
      'UNSAVED',
    );
    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Registration No. 5157'), findsOneWidget);
  });
}
