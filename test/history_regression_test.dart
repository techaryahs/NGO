import 'package:flutter/material.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/screens/attendance/attendance.dart';

class MemoryDatabase extends FirebaseRTDBRestService {
  MemoryDatabase() : super(projectId: 'test');
  final records = <String, dynamic>{};
  Map<String, dynamic>? written;
  @override
  Future<dynamic> get(String path) async => records[path];
  @override
  Future<dynamic> getByChildValue(
    String path, {
    required String child,
    required Object value,
  }) async {
    final data = records[path];
    if (data is! Map) return null;
    return {
      for (final entry in data.entries)
        if (entry.value is Map && entry.value[child] == value)
          entry.key.toString(): entry.value,
    };
  }
  @override
  Future<dynamic> getByKeyRange(
    String path, {
    required String startKey,
    required String endKey,
  }) async => records[path];
  @override
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    expect(path, '');
    written = updates;
  }
}

void main() {
  test('stay retains original registration and photos after serialization', () {
    final stay = StayModel.fromMap('stay', {
      'patientSnapshot': {
        'registrationNumber': 'OLD-123',
        'photoDataUrl': 'old-photo',
        'attendants': [
          {'name': 'First attendant', 'photoDataUrl': 'first-photo'},
        ],
      },
    });
    final restored = StayModel.fromMap(
      'stay',
      stay.copyWith(status: 'completed').toMap(),
    );
    expect(restored.patientSnapshot['registrationNumber'], 'OLD-123');
    expect(
      restored.patientSnapshot['attendants'][0]['photoDataUrl'],
      'first-photo',
    );
    expect(StayModel.fromMap('legacy', {}).patientSnapshot, isEmpty);
  });

  late MemoryDatabase db;
  late PaymentService service;
  setUp(() {
    db = MemoryDatabase();
    service = PaymentService(db);
    db.records['patients/p'] = {
      'fullName': 'Patient',
      'admissionDate': 2000,
      'advanceBilledAmount': 1000,
      'attendanceCharges': 200,
      'payments': [
        {'id': 'old', 'amount': 900, 'date': 1000},
        {'id': 'local', 'amount': 300, 'date': 3000},
      ],
    };
    db.records['payments/global'] = {
      'id': 'local',
      'patientId': 'p',
      'amount': 300,
      'date': 3000,
    };
  });

  test(
    'edit updates ledger, embedded payment and balances atomically',
    () async {
      await service.updatePaymentDetails(
        'p',
        'global',
        'TX-2',
        DateTime.fromMillisecondsSinceEpoch(4000),
        embeddedPaymentId: 'local',
        amount: 500,
        receiptNumber: 'R-2',
      );
      final updates = db.written!;
      expect(updates['payments/global'], updates['paymentHistory/global']);
      expect(updates['payments/global']['receiptNumber'], 'R-2');
      expect(updates['patients/p/totalPaidAmount'], 500);
      expect(updates['patients/p/currentDueAmount'], 700);
      expect(updates['patients/p/paymentStatus'], 'Partially Paid');
      expect((updates['patients/p/payments'] as List).length, 2);
    },
  );

  test(
    'delete removes selected payment and excludes old admission payments',
    () async {
      await service.deletePayment('p', 'global', embeddedPaymentId: 'local');
      expect(db.written!['payments/global'], isNull);
      expect(db.written!['paymentHistory/global'], isNull);
      expect(db.written!['patients/p/totalPaidAmount'], 0);
      expect(db.written!['patients/p/currentDueAmount'], 1200);
      expect(db.written!['patients/p/paymentStatus'], 'Unpaid');
      expect((db.written!['patients/p/payments'] as List).single['id'], 'old');
    },
  );

  test('invalid amount cannot write a payment', () async {
    await expectLater(
      service.updatePaymentDetails(
        'p',
        'global',
        '',
        DateTime.now(),
        amount: -1,
      ),
      throwsArgumentError,
    );
    expect(db.written, isNull);
  });

  testWidgets('attendance scrolls vertically and keeps names aligned', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StickyAttendanceTable(
            data: {
              for (var i = 0; i < 40; i++)
                'Patient $i': {'2026-09-01': 'Present'},
            },
            dates: ['2026-09-01', '2026-09-02'],
            monthLabel: (_) => 'Sep',
            cellBuilder: (_, __, status) => Text(status ?? '-'),
          ),
        ),
      ),
    );
    final state = tester.state<StickyAttendanceTableState>(
      find.byType(StickyAttendanceTable),
    );
    expect(state.verticalController.position.maxScrollExtent, greaterThan(0));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(776, 100));
    await gesture.down(const Offset(776, 100));
    await gesture.moveTo(const Offset(776, 250));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.verticalController.offset, greaterThan(0));
    state.verticalController.jumpTo(300);
    await tester.pump();
    expect(state.namesController.offset, 300);
    state.namesController.jumpTo(500);
    await tester.pump();
    expect(state.verticalController.offset, 500);
    expect(tester.takeException(), isNull);
  });
}
