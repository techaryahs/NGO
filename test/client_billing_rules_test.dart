import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/utils/pricing_helper.dart';
import 'package:ngo/utils/stay_billing.dart';
import 'package:ngo/services/room_service.dart';
import 'stay_billing_test.dart' as fixtures;

DateTime at(int day, [int hour = 9, int minute = 0]) =>
    DateTime(2026, 1, day, hour, minute);
final cycle = at(1).millisecondsSinceEpoch.toString();
PatientModel patient(
  int days, {
  List<Map<String, dynamic>> attendants = const [],
  Map<String, dynamic> balances = const {},
}) => PatientModel.fromMap('p', {
  'admissionDate': at(1).millisecondsSinceEpoch,
  'registrationDate': at(1).millisecondsSinceEpoch,
  'exitDate': at(days).millisecondsSinceEpoch,
  'status': 'active',
  'attendants': attendants,
  'admissionBalances': balances,
});
StayModel stay(
  String type, {
  String id = 's',
  int from = 1,
  int through = 70,
  String status = 'active',
  List<Map<String, dynamic>> attendants = const [],
  Map<String, dynamic> extra = const {},
}) => StayModel.fromMap(id, {
  'patientId': 'p',
  'roomType': type,
  'cycleId': cycle,
  'admissionDate': at(from).millisecondsSinceEpoch,
  'expectedDischargeDate': at(through).millisecondsSinceEpoch,
  'createdAt': at(from).millisecondsSinceEpoch,
  'updatedAt': at(through).millisecondsSinceEpoch,
  if (status != 'active') 'completedAt': at(through).millisecondsSinceEpoch,
  'status': status,
  'patientSnapshot': {
    'admissionDate': at(1).millisecondsSinceEpoch,
    'attendants': attendants,
  },
  ...extra,
});
Map<String, String> present(int days) => {
  for (var i = 1; i <= days; i++) StayBilling.dateKey(at(i)): 'Present',
};
AdmissionBalance bill(
  int days, {
  String type = 'general',
  Map<String, String>? attendance,
  Map<String, Map<String, String>> attendants = const {},
  DateTime? checkoutAt,
  List<StayModel>? stays,
  PatientModel? model,
  bool finalize = false,
}) => StayBilling.calculate(
  patient: model ?? patient(days),
  stays: stays ?? [stay(type)],
  pricing: {},
  attendance: attendance ?? present(days),
  attendantAttendance: attendants,
  calendarDayBilling: true,
  checkoutAt: checkoutAt,
  finalize: finalize,
).single;

void main() {
  group('Approved pricing and attendance', () {
    for (final category in ['general', 'lobby']) {
      test('$category 60/70 days and multiple allocated beds', () {
        expect(bill(60, type: category).total, 12000);
        expect(bill(70, type: category).total, 14500);
        expect(
          bill(
            70,
            stays: [
              stay(category, id: 'a'),
              stay(category, id: 'b'),
            ],
          ).total,
          14500,
        );
        expect(
          PricingHelper.calculateProjectedStayCost(false, 0, 70, bedsCount: 3),
          14500,
        );
      });
    }
    test('General patient and attendant attendance are independent', () {
      expect(
        bill(
          1,
          attendants: {
            '2026-01-01': {'a': 'Present'},
          },
        ).total,
        400,
      );
      expect(
        bill(
          1,
          attendance: {'2026-01-01': 'Absent'},
          attendants: {
            '2026-01-01': {'a': 'Present'},
          },
        ).total,
        200,
      );
      expect(
        bill(
          1,
          attendants: {
            '2026-01-01': {'a': 'Absent'},
          },
        ).total,
        200,
      );
      expect(
        bill(
          61,
          attendants: {
            for (var i = 1; i <= 61; i++)
              StayBilling.dateKey(at(i)): {'a': 'Present'},
          },
        ).total,
        24500,
      );
    });
    test(
      'Private one-patient base, one included attendant and absent patient',
      () {
        expect(bill(60, type: 'private').total, 42000);
        expect(bill(70, type: 'private').total, 51000);
        expect(
          bill(1, type: 'private', attendance: {'2026-01-01': 'Absent'}).total,
          700,
        );
        expect(
          bill(
            1,
            type: 'private',
            attendants: {
              '2026-01-01': {'a': 'Present'},
            },
          ).total,
          700,
        );
        expect(
          bill(
            1,
            type: 'private',
            attendants: {
              '2026-01-01': {'a': 'Present', 'b': 'Absent'},
            },
          ).total,
          700,
        );
        expect(
          bill(
            1,
            type: 'private',
            attendants: {
              '2026-01-01': {'a': 'Present', 'b': 'Present'},
            },
          ).total,
          900,
        );
        expect(
          bill(
            61,
            type: 'private',
            attendants: {
              for (var i = 1; i <= 61; i++)
                StayBilling.dateKey(at(i)): {'a': 'Present', 'b': 'Present'},
            },
          ).total,
          55200,
        );
        expect(
          PricingHelper.calculateDailyCharge(
            true,
            2,
            pricing: {'privateRoomIncludedAttendants': 5},
          ),
          900,
        );
      },
    );
    test('Pending is provisional and prevents finalization', () {
      final estimate = bill(1, attendance: {});
      expect(estimate.total, 200);
      expect(estimate.provisional, isTrue);
      expect(estimate.pendingAttendance, [
        {'day': '2026-01-01', 'kind': 'attendance'},
      ]);
      expect(() => bill(1, attendance: {}, finalize: true), throwsStateError);
      const roster = [
        {'id': 'a', 'name': 'Same'},
        {'id': 'b', 'name': 'Same'},
      ];
      final segment = stay('general', attendants: roster);
      expect(() => bill(1, stays: [segment], finalize: true), throwsStateError);
      expect(
        bill(
          1,
          stays: [segment],
          attendants: {
            '2026-01-01': {'a': 'Present', 'b': 'Absent'},
          },
          finalize: true,
        ).total,
        400,
      );
    });
  });
  group('Actual checkout in Asia/Kolkata', () {
    for (final scenario in [
      (7, 8, 59, 1200.0, 6, 0.0),
      (7, 9, 0, 1200.0, 6, 0.0),
      (7, 9, 1, 1400.0, 7, 200.0),
      (60, 9, 1, 12000.0, 60, 200.0),
      (61, 8, 59, 12000.0, 60, 0.0),
      (61, 9, 0, 12000.0, 60, 0.0),
      (61, 9, 1, 12250.0, 61, 250.0),
    ]) {
      test('day ${scenario.$1} ${scenario.$2}:${scenario.$3}', () {
        final checkout = at(scenario.$1, scenario.$2, scenario.$3);
        final invoice = bill(scenario.$1, checkoutAt: checkout);
        expect(invoice.total, scenario.$4);
        expect(invoice.days.values.single, scenario.$5);
        expect(invoice.checkoutAdjustment?['amount'] ?? 0.0, scenario.$6);
        expect(bill(scenario.$1, checkoutAt: checkout).total, invoice.total);
      });
    }
    test(
      'late checkout charges Present attendants only and uses the applicable tier',
      () {
        final marks = {
          '2026-03-02': {'a': 'Present', 'b': 'Absent'},
        };
        final invoice = bill(61, attendants: marks, checkoutAt: at(61, 9, 1));
        expect(invoice.checkoutAdjustment?['amount'], 500);
        expect(invoice.total, 12500);
        expect(
          bill(
            7,
            attendance: {...present(7), '2026-01-07': 'Absent'},
            checkoutAt: at(7, 9, 1),
          ).total,
          1200,
        );
      },
    );
    test(
      'Private retains inclusive base and introduces no General surcharge',
      () {
        final invoice = bill(61, type: 'private', checkoutAt: at(61, 9, 1));
        expect(invoice.total, 42900);
        expect(invoice.checkoutAdjustment?['amount'], 900);
        expect(invoice.checkoutAdjustment?['included'], isTrue);
        expect(invoice.checkoutAdjustment?['includedInTotal'], isTrue);
      },
    );
    test('manual rate and all-in override stay authoritative at checkout', () {
      expect(
        bill(
          7,
          stays: [
            stay(
              'general',
              extra: {'dailyRateIsManual': true, 'dailyRate': 123.45},
            ),
          ],
          checkoutAt: at(7, 9, 1),
        ).total,
        closeTo(864.15, 0.001),
      );
      expect(
        bill(
          7,
          stays: [
            stay('general', extra: {'costOverride': 1000}),
          ],
          checkoutAt: at(7, 9, 1),
        ).total,
        1000,
      );
    });
  });
  test(
    'General-to-Private transfer date billed once and threshold continues',
    () {
      final invoice = bill(
        70,
        stays: [
          stay('general', through: 61, status: 'completed'),
          stay('private', id: 'next', from: 61),
        ],
      );
      expect(invoice.total, 51000 - 30000);
      expect(invoice.days, {'s': 60, 'next': 10});
    },
  );
  test('stored segment pricing survives a global setting change', () {
    final invoice = StayBilling.calculate(
      // Include both fixture dates; exactly 09:00 excludes an unmarked exit day.
      patient: patient(2).copyWith(exitDate: at(2, 9, 1)),
      stays: [
        stay(
          'general',
          extra: {
            'billingSummary': {
              'pricing': {'generalRoomBedPrice': 200},
            },
          },
        ),
      ],
      pricing: {'generalRoomBedPrice': 500},
      calendarDayBilling: true,
    ).single;
    expect(invoice.total, 400);
  });
  test('UTC near midnight belongs to the Kolkata admission date', () {
    final instant = DateTime.parse('2026-01-01T22:00:00Z');
    final model = PatientModel.fromMap('p', {
      'status': 'active',
      'admissionDate': instant.millisecondsSinceEpoch,
      'exitDate': DateTime.parse('2026-01-02T03:30:00Z').millisecondsSinceEpoch,
    });
    final segment = StayModel.fromMap('s', {
      'status': 'active',
      'patientId': 'p',
      'cycleId': instant.millisecondsSinceEpoch.toString(),
      'roomType': 'general',
      'admissionDate': instant.millisecondsSinceEpoch,
      'expectedDischargeDate': DateTime.parse(
        '2026-01-02T03:30:00Z',
      ).millisecondsSinceEpoch,
    });
    final invoice = StayBilling.calculate(
      patient: model,
      stays: [segment],
      pricing: {},
      attendance: {'2026-01-02': 'Present'},
      calendarDayBilling: true,
    ).single;
    expect(invoice.total, 200);
    expect(invoice.days['s'], 1);
    expect(invoice.pendingAttendance, isEmpty);
    expect(StayBilling.kolkataDay(instant), DateTime(2026, 1, 2));
  });
  test(
    'ambiguous legacy-name mark is pending and cannot create an extra charge',
    () {
      const roster = [
        {'id': 'a', 'name': 'Same'},
        {'id': 'b', 'name': 'Same'},
      ];
      final invoice = bill(
        1,
        stays: [stay('general', attendants: roster)],
        attendants: {
          '2026-01-01': {'Same': 'Present'},
        },
      );
      expect(invoice.total, 200);
      expect(invoice.pendingAttendance.length, 2);
      final legacy = bill(
        1,
        stays: [
          stay(
            'general',
            attendants: const [
              {'name': 'Same'},
              {'name': 'Same'},
            ],
          ),
        ],
        attendants: {
          '2026-01-01': {'Same': 'Present'},
        },
      );
      expect(legacy.total, 200);
      expect(legacy.pendingAttendance.length, 2);
      final dedup = bill(
        1,
        stays: [
          stay(
            'general',
            attendants: const [
              {'id': 'a', 'name': 'Same'},
            ],
          ),
        ],
        attendants: {
          '2026-01-01': {'a': 'Present', 'Same': 'Present'},
        },
      );
      expect(dedup.total, 400);
    },
  );
  test(
    'approved new tariffs normalize old global settings without a write',
    () async {
      final adverse = {
        'generalRoomBedPrice': 350,
        'privateRoomBasePrice': 1000,
        'privateRoomExtraAttendantFee': 500,
        'privateRoomIncludedAttendants': 2,
        'generalRoomMaxAttendants': 4,
      };
      final db = fixtures.TestDatabase({
        'admin_settings': {'pricing': adverse},
      });
      addTearDown(db.dispose);
      final rates = await RoomService(rtdbService: db).getPricing();
      expect(rates, containsPair('generalRoomBedPrice', 200));
      expect(rates, containsPair('privateRoomBasePrice', 700));
      expect(rates, containsPair('privateRoomExtraAttendantFee', 200));
      expect(rates, containsPair('privateRoomIncludedAttendants', 1));
      expect(rates, containsPair('generalRoomMaxAttendants', 4));
      expect(db.writes, 0);
      expect(
        StayBilling.calculate(
          patient: patient(1),
          stays: [stay('private')],
          pricing: adverse,
          calendarDayBilling: true,
        ).single.total,
        700,
      );
    },
  );
  test('historical unknown Pending attendant prevents finalization', () {
    final invoice = bill(
      1,
      attendants: {
        '2026-01-01': {'historical-id': 'Unmarked'},
      },
    );
    expect(invoice.pendingAttendance.single['attendantId'], 'historical-id');
    expect(
      () => bill(
        1,
        attendants: {
          '2026-01-01': {'historical-id': 'Unmarked'},
        },
        finalize: true,
      ),
      throwsStateError,
    );
  });
  test(
    'saved checkout preview remains consistent for later payment calculations',
    () {
      final checkout = at(7, 9, 1);
      final model = patient(
        7,
        balances: {
          cycle: {'checkoutAt': checkout.millisecondsSinceEpoch},
        },
      );
      expect(bill(7, model: model).total, 1400);
    },
  );
  test(
    'legacy finalized charges remain unchanged after new tariff calculations',
    () {
      final model = PatientModel.fromMap('p', {
        ...patient(7).toMap(),
        'status': 'discharged',
        'dischargeDate': at(7).millisecondsSinceEpoch,
      });
      final invoice = bill(
        7,
        model: model,
        stays: [
          stay(
            'general',
            through: 7,
            status: 'completed',
            extra: {'totalCost': 1234.5},
          ),
        ],
      );
      expect(invoice.total, 1234.5);
      expect(invoice.charges['s'], 1234.5);
    },
  );
  test('an already extended expected exit is not extended again', () {
    final segment = stay(
      'general',
      through: 70,
      extra: {'durationDays': 60, 'totalExtendedDays': 10},
    );
    expect(segment.effectiveExpiryDate, at(70));
    expect(segment.totalDays, 70);
  });
  test(
    'duplicate legacy attendants remain separate and require identity resolution',
    () {
      const roster = [
        {'name': 'Same'},
        {'name': 'Same'},
      ];
      final data = MonthlyAttendanceData(at(1), {
        'attendant_attendance/daily/2026-01-01/p/Same': {
          'attendantName': 'Same',
          'status': 'Present',
        },
      });
      final rows = data
          .rows(
            [patient(1, attendants: roster)],
            [stay('general', attendants: roster)],
            now: at(1),
          )
          .where((row) => row.isAttendant)
          .toList();
      expect(rows.length, 2);
      expect(rows.every((row) => row.identityUnresolved), isTrue);
      expect(rows.every((row) => !row.enabled(at(1))), isTrue);
      expect(data.records.length, 1);
    },
  );
  test(
    'two same-name attendants use independent stable IDs and preserve legacy marks',
    () {
      const roster = [
        {'id': 'a', 'name': 'Same'},
        {'id': 'b', 'name': 'Same'},
      ];
      final data = MonthlyAttendanceData(at(1), {
        'attendant_attendance/daily/2026-01-01/p/Same': {
          'attendantName': 'Same',
          'status': 'Present',
        },
      });
      final rows = data
          .rows(
            [patient(1, attendants: roster)],
            [stay('general', attendants: roster)],
            now: at(1),
          )
          .where((row) => row.isAttendant)
          .toList();
      expect(rows.length, 2);
      expect(rows.map((row) => row.path(at(1))).toSet().length, 2);
      final editor = MonthlyAttendanceEditor(data);
      expect(rows.map((row) => editor.status(row, at(1))).toSet(), {
        'Unmarked',
      });
      editor.edit(rows[0], at(1), 'Present');
      editor.edit(rows[1], at(1), 'Absent');
      expect(
        editor
            .patch['attendant_attendance/daily/2026-01-01/p/a']['attendantId'],
        'a',
      );
      expect(
        editor.patch['attendant_attendance/daily/2026-01-01/p/b']['status'],
        'Absent',
      );
      expect(
        data.records['attendant_attendance/daily/2026-01-01/p/Same']?['status'],
        'Present',
      );
    },
  );

  group('Explicit threshold boundaries and non-advancing charges', () {
    test('day 59 to 60 uses initial rate, day 60 to 61 triggers long-stay rate', () {
      final bill60 = bill(60);
      expect(bill60.total, 12000); // 60 * 200
      expect(bill60.actualPatientPresentDays, 60);

      final bill61 = bill(61);
      expect(bill61.total, 12250); // 60 * 200 + 1 * 250
      expect(bill61.actualPatientPresentDays, 61);
    });

    test('attendant-only General days do not advance the patient 60-day threshold', () {
      final patientMarks = <String, String>{
        for (var i = 1; i <= 10; i++) StayBilling.dateKey(at(i)): 'Absent',
        for (var i = 11; i <= 70; i++) StayBilling.dateKey(at(i)): 'Present',
      };
      final attendantMarks = <String, Map<String, String>>{
        for (var i = 1; i <= 10; i++)
          StayBilling.dateKey(at(i)): {'a': 'Present'},
      };
      final invoice = bill(
        70,
        attendance: patientMarks,
        attendants: attendantMarks,
      );
      expect(invoice.total, 14000);
      expect(invoice.actualPatientPresentDays, 60);
    });

    test('Private room reserved base during patient absence does not advance patient threshold', () {
      final patientMarks = <String, String>{
        for (var i = 1; i <= 10; i++) StayBilling.dateKey(at(i)): 'Absent',
        for (var i = 11; i <= 70; i++) StayBilling.dateKey(at(i)): 'Present',
      };
      final invoice = bill(
        70,
        type: 'private',
        attendance: patientMarks,
      );
      expect(invoice.total, 49000);
      expect(invoice.actualPatientPresentDays, 60);
    });
  });
}
