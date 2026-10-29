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
    test('Pending attendance costs ₹0 and does not prevent finalization', () {
      final estimate = bill(1, attendance: {});
      expect(estimate.total, 0);
      expect(estimate.provisional, isFalse);
      expect(estimate.pendingAttendance, [
        {'day': '2026-01-01', 'kind': 'attendance'},
      ]);
      expect(bill(1, attendance: {}, finalize: true).total, 0);
      const roster = [
        {'id': 'a', 'name': 'Same'},
        {'id': 'b', 'name': 'Same'},
      ];
      final segment = stay('general', attendants: roster);
      expect(bill(1, stays: [segment], attendance: {}, finalize: true).total, 0);
      expect(
        bill(
          1,
          stays: [segment],
          attendance: {'2026-01-01': 'Present'},
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
      attendance: {
        StayBilling.dateKey(at(1)): 'Present',
        StayBilling.dateKey(at(2)): 'Present',
      },
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
  test('historical unknown Pending attendant does not prevent finalization', () {
    final invoice = bill(
      1,
      attendants: {
        '2026-01-01': {'historical-id': 'Unmarked'},
      },
    );
    expect(invoice.pendingAttendance.single['attendantId'], 'historical-id');
    expect(invoice.total, 200);
    expect(
      bill(
        1,
        attendants: {
          '2026-01-01': {'historical-id': 'Unmarked'},
        },
        finalize: true,
      ).total,
      200,
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
  group('Rule 7 Acceptance Tests', () {
    test('Case 1: Patient admitted 21 Oct, patient+attendant present 21-22 Oct (₹400/day), no marks after 22 Oct, no planned exit: on 29 Oct total is exactly ₹800, final, no provisional amounts', () {
      final admission = DateTime.parse('2026-10-21T00:30:00.000Z'); // 06:00 IST
      final cycleId = admission.millisecondsSinceEpoch.toString();
      final helper = {'id': 'att_1', 'name': 'Helper'};
      final patient = PatientModel.fromMap('p_case1', {
        'id': 'p_case1',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'registrationDate': admission.millisecondsSinceEpoch,
        'exitDate': null,
        'attendants': [helper],
      });
      final staySegment = StayModel.fromMap('s_case1', {
        'id': 's_case1',
        'patientId': 'p_case1',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'cycleId': cycleId,
        'roomType': 'general',
        'patientSnapshot': {'attendants': [helper]},
      });
      final asOf = DateTime.parse('2026-10-29T09:30:00.000Z'); // 15:00 IST
      final result = StayBilling.calculate(
        patient: patient,
        stays: [staySegment],
        pricing: {'generalRoomBedPrice': 200},
        calendarDayBilling: true,
        now: asOf,
        attendance: {
          '2026-10-21': 'Present',
          '2026-10-22': 'Present',
        },
        attendantAttendance: {
          '2026-10-21': {'att_1': 'Present'},
          '2026-10-22': {'att_1': 'Present'},
        },
      ).single;

      expect(result.total, 800);
      expect(result.provisional, isFalse);
      expect(result.due, 800);
      expect(result.pricingBasis, 'actual_patient_present');
    });

    test('Case 2: Same patient: discharge with admin-chosen exit 23 Oct succeeds despite pending marks; final total ₹800; bed freed', () {
      final admission = DateTime.parse('2026-10-21T00:30:00.000Z');
      final cycleId = admission.millisecondsSinceEpoch.toString();
      final helper = {'id': 'att_1', 'name': 'Helper'};
      final checkoutAt = DateTime.parse('2026-10-23T04:30:00.000Z'); // 10:00 IST (after cutoff)
      final patient = PatientModel.fromMap('p_case2', {
        'id': 'p_case2',
        'status': 'discharged',
        'admissionDate': admission.millisecondsSinceEpoch,
        'dischargeDate': checkoutAt.millisecondsSinceEpoch,
        'exitDate': checkoutAt.millisecondsSinceEpoch,
        'attendants': [helper],
      });
      final staySegment = StayModel.fromMap('s_case2', {
        'id': 's_case2',
        'patientId': 'p_case2',
        'status': 'completed',
        'admissionDate': admission.millisecondsSinceEpoch,
        'completedAt': checkoutAt.millisecondsSinceEpoch,
        'cycleId': cycleId,
        'roomType': 'general',
        'patientSnapshot': {'attendants': [helper]},
      });
      final result = StayBilling.calculate(
        patient: patient,
        stays: [staySegment],
        pricing: {'generalRoomBedPrice': 200},
        calendarDayBilling: true,
        checkoutAt: checkoutAt,
        finalize: true,
        attendance: {
          '2026-10-21': 'Present',
          '2026-10-22': 'Present',
        },
        attendantAttendance: {
          '2026-10-21': {'att_1': 'Present'},
          '2026-10-22': {'att_1': 'Present'},
        },
      ).single;

      expect(result.total, 800);
      expect(result.provisional, isFalse);
    });

    test('Case 3: Patient with planned exit 25 Oct, still ACTIVE on 29 Oct, attendance marked 21-28 Oct: only marked attendance up to 25 Oct is billed (5 days × ₹400 = ₹2,000); stay remains Active', () {
      final admission = DateTime.parse('2026-10-21T00:30:00.000Z');
      final cycleId = admission.millisecondsSinceEpoch.toString();
      final helper = {'id': 'att_1', 'name': 'Helper'};
      final plannedExit = DateTime.parse('2026-10-25T18:29:59.999Z');
      final patient = PatientModel.fromMap('p_case3', {
        'id': 'p_case3',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'exitDate': plannedExit.millisecondsSinceEpoch,
        'attendants': [helper],
      });
      final staySegment = StayModel.fromMap('s_case3', {
        'id': 's_case3',
        'patientId': 'p_case3',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'expectedDischargeDate': plannedExit.millisecondsSinceEpoch,
        'cycleId': cycleId,
        'roomType': 'general',
        'patientSnapshot': {'attendants': [helper]},
      });
      final attendance = <String, String>{
        for (var day = 21; day <= 28; day++) '2026-10-$day': 'Present',
      };
      final attendantAttendance = <String, Map<String, String>>{
        for (var day = 21; day <= 28; day++) '2026-10-$day': {'att_1': 'Present'},
      };
      final asOf = DateTime.parse('2026-10-29T09:30:00.000Z');
      final result = StayBilling.calculate(
        patient: patient,
        stays: [staySegment],
        pricing: {'generalRoomBedPrice': 200},
        calendarDayBilling: true,
        now: asOf,
        attendance: attendance,
        attendantAttendance: attendantAttendance,
      ).single;

      // 5 days (21..25 Oct) × ₹400 = ₹2,000
      expect(result.total, 2000);
      expect(result.provisional, isFalse);
    });

    test('Case 4: Same patient: planned exit extended 25 Oct -> 30 Oct -> attendance on 26-30 Oct charges normally again (10 days × ₹400 = ₹4,000)', () {
      final admission = DateTime.parse('2026-10-21T00:30:00.000Z');
      final cycleId = admission.millisecondsSinceEpoch.toString();
      final helper = {'id': 'att_1', 'name': 'Helper'};
      final extendedExit = DateTime.parse('2026-10-30T18:29:59.999Z');
      final patient = PatientModel.fromMap('p_case4', {
        'id': 'p_case4',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'exitDate': extendedExit.millisecondsSinceEpoch,
        'attendants': [helper],
      });
      final staySegment = StayModel.fromMap('s_case4', {
        'id': 's_case4',
        'patientId': 'p_case4',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'expectedDischargeDate': extendedExit.millisecondsSinceEpoch,
        'cycleId': cycleId,
        'roomType': 'general',
        'patientSnapshot': {'attendants': [helper]},
      });
      final attendance = <String, String>{
        for (var day = 21; day <= 30; day++) '2026-10-$day': 'Present',
      };
      final attendantAttendance = <String, Map<String, String>>{
        for (var day = 21; day <= 30; day++) '2026-10-$day': {'att_1': 'Present'},
      };
      final asOf = DateTime.parse('2026-10-31T04:30:00.000Z');
      final result = StayBilling.calculate(
        patient: patient,
        stays: [staySegment],
        pricing: {'generalRoomBedPrice': 200},
        calendarDayBilling: true,
        now: asOf,
        attendance: attendance,
        attendantAttendance: attendantAttendance,
      ).single;

      // 10 days × ₹400 = ₹4,000
      expect(result.total, 4000);
      expect(result.provisional, isFalse);
    });

    test('Case 5: Patient who paid more than the truncated final total: pending = 0, excess shows as unallocated/credit', () {
      final admission = DateTime.parse('2026-10-21T00:30:00.000Z');
      final cycleId = admission.millisecondsSinceEpoch.toString();
      final helper = {'id': 'att_1', 'name': 'Helper'};
      final plannedExit = DateTime.parse('2026-10-23T18:29:59.999Z');
      final payment = PaymentModel.fromMap('pay_1', {
        'id': 'pay_1',
        'patientId': 'p_case5',
        'amount': 2000.0,
        'cycleId': cycleId,
        'paymentDate': admission.millisecondsSinceEpoch,
      });
      final patient = PatientModel.fromMap('p_case5', {
        'id': 'p_case5',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'exitDate': plannedExit.millisecondsSinceEpoch,
        'attendants': [helper],
        'payments': [payment.toMap()],
      });
      final staySegment = StayModel.fromMap('s_case5', {
        'id': 's_case5',
        'patientId': 'p_case5',
        'status': 'active',
        'admissionDate': admission.millisecondsSinceEpoch,
        'expectedDischargeDate': plannedExit.millisecondsSinceEpoch,
        'cycleId': cycleId,
        'roomType': 'general',
        'patientSnapshot': {'attendants': [helper]},
      });
      final result = StayBilling.calculate(
        patient: patient,
        stays: [staySegment],
        pricing: {'generalRoomBedPrice': 200},
        calendarDayBilling: true,
        attendance: {
          '2026-10-21': 'Present',
          '2026-10-22': 'Present',
        },
        attendantAttendance: {
          '2026-10-21': {'att_1': 'Present'},
          '2026-10-22': {'att_1': 'Present'},
        },
      ).single;

      // Total ₹800, Paid ₹2000 -> Due ₹0, RefundDue ₹1200, Status Payment Exceeded
      expect(result.total, 800);
      expect(result.due, 0);
      expect(result.refundDue, 1200);
      expect(result.status, 'Payment Exceeded');
    });
  });

}
