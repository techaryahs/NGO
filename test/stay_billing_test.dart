import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/stay_history_service.dart';
import 'package:ngo/utils/pricing_helper.dart';
import 'package:ngo/utils/stay_billing.dart';

int stamp(int day, [int hour = 9, int minute = 0]) =>
    DateTime(2026, 1, day, hour, minute).millisecondsSinceEpoch;
String get cycle => stamp(1).toString();
Map<String, dynamic> segment(
  String id,
  String type,
  int from,
  int until, {
  String? cycleId,
  String status = 'completed',
}) => {
  'id': id,
  'patientId': 'p',
  'patientName': 'Patient',
  'roomId': type,
  'roomNumber': type,
  'roomType': type,
  'cycleId': cycleId ?? cycle,
  'admissionDate': stamp(from),
  'completedAt': status == 'active' ? null : stamp(until),
  'expectedDischargeDate': stamp(until),
  'expiryDate': stamp(until),
  'createdAt': stamp(from),
  'updatedAt': stamp(until),
  'status': status,
  'attendantCount': 0,
  'bedId': 'bed',
  'bedLabel': '1',
  'patientSnapshot': {
    'registrationNumber': 'REG-1',
    'admissionDate': int.parse(cycleId ?? cycle),
    'attendants': [],
  },
};
PatientModel patient({
  List<Map<String, dynamic>> payments = const [],
  String status = 'discharged',
  int admission = 1,
  int? exit,
  int exitHour = 9,
  int exitMinute = 0,
}) => PatientModel.fromMap('p', {
  'fullName': 'Patient',
  'admissionDate': stamp(admission),
  'registrationDate': stamp(admission),
  'status': status,
  if (exit != null) 'exitDate': stamp(exit, exitHour, exitMinute),
  'payments': payments,
  'roomId': 'general',
  'roomNumber': 'general',
});
Map<String, dynamic> payment(double amount, {String? cycleId, int date = 2}) =>
    {
      'id': 'pay',
      'amount': amount,
      'date': stamp(date),
      'cycleId': cycleId ?? cycle,
    };
List<StayModel> mixedStays() => [
  StayModel.fromMap('private', segment('private', 'private', 1, 5)),
  StayModel.fromMap('general', segment('general', 'general', 5, 8)),
];

class TestDatabase extends FirebaseRTDBRestService {
  final Map<String, dynamic> root;
  int writes = 0;
  TestDatabase(this.root) : super(projectId: 'test');
  @override
  Future<dynamic> get(String path) async {
    dynamic value = root;
    for (final key in path.split('/').where((s) => s.isNotEmpty)) {
      if (value is! Map) return null;
      value = value[key];
    }
    return value == null ? null : jsonDecode(jsonEncode(value));
  }

  @override
  Future<dynamic> getByKeyRange(
    String path, {
    required String startKey,
    required String endKey,
  }) async {
    final value = await get(path);
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key.toString().compareTo(startKey) >= 0 &&
            entry.key.toString().compareTo(endKey) <= 0)
          entry.key.toString(): entry.value,
    };
  }

  @override
  Future<dynamic> getByChildValue(
    String path, {
    required String child,
    required Object value,
  }) async {
    final data = await get(path);
    if (data is! Map) return null;
    return {
      for (final entry in data.entries)
        if (entry.value is Map && entry.value[child] == value)
          entry.key.toString(): entry.value,
    };
  }

  @override
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    expect(path, '');
    writes++;
    for (final entry in updates.entries) {
      final keys = entry.key.split('/');
      Map parent = root;
      for (final key in keys.take(keys.length - 1)) {
        final child = parent.putIfAbsent(key, () => <String, dynamic>{});
        if (child is List) {
          parent[key] = {
            for (final entry in child.asMap().entries)
              entry.key.toString(): entry.value,
          };
        }
        parent = parent[key] as Map;
      }
      if (entry.value == null) {
        parent.remove(keys.last);
      } else {
        parent[keys.last] = jsonDecode(jsonEncode(entry.value));
      }
    }
  }
}

void main() {
  test('legacy automatic sync leaves all marks unchanged', () async {
    final db = TestDatabase(
      jsonDecode(
            jsonEncode({
              'attendance': {
                'daily': {
                  '2026-01-01': {
                    'p': {
                      'status': 'Unmarked',
                      'source': 'manual',
                      'date': '2026-01-01',
                    },
                  },
                },
              },
            }),
          )
          as Map<String, dynamic>,
    );
    await PatientService(rtdbService: db).syncAutomaticPatientAttendance(
      patientId: 'p',
      patientName: 'Patient',
      start: DateTime(2026, 1, 1),
      end: DateTime(2026, 1, 2),
      cycleId: cycle,
    );

    expect(
      (await db.get('attendance/daily/2026-01-01/p'))['status'],
      'Unmarked',
    );
    expect(await db.get('attendance/daily/2026-01-02/p'), isNull);
  });

  test('recorded exit date stops billing for an active patient', () {
    final bill = StayBilling.calculate(
      patient: patient(status: 'active', exit: 8),
      stays: [
        StayModel.fromMap(
          'active',
          segment('active', 'general', 1, 8, status: 'active'),
        ),
      ],
      pricing: {},
      attendance: {for (var i = 1; i <= 7; i++) '2026-01-0$i': 'Present'},
      now: DateTime(2026, 2, 7),
    ).single;

    expect(bill.days['active'], 7);
  });

  test(
    'an active stay without an exit date bills elapsed days beyond seven',
    () {
      final bill = StayBilling.calculate(
        patient: patient(status: 'active'),
        stays: [
          StayModel.fromMap(
            'active',
            segment('active', 'general', 1, 8, status: 'active'),
          ),
        ],
        pricing: {'generalRoomBedPrice': 200},
        attendance: {for (var i = 1; i <= 38; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
        now: DateTime(2026, 2, 7),
      ).single;

      expect(bill.days['active'], 38);
      expect(bill.total, 7600);
    },
  );

  test('active shifted segment without exit date gets its own estimate', () {
    final bill = StayBilling.calculate(
      patient: patient(status: 'active'),
      stays: [
        StayModel.fromMap(
          'lobby',
          segment('lobby', 'lobby', 1, 8, status: 'completed'),
        ),
        StayModel.fromMap(
          'room',
          segment('room', 'general', 20, 27, status: 'active'),
        ),
      ],
      pricing: {'generalRoomBedPrice': 200},
      attendance: {
        for (var i = 1; i <= 7; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present',
        for (var i = 20; i <= 38; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present',
      },
      now: DateTime(2026, 2, 7),
    ).single;

    expect(bill.days['lobby'], 7);
    expect(bill.days['room'], 19);
    expect(bill.charges['room'], 3800);
    expect(bill.total, 5200);
  });

  test('present marks do not erase other unmarked patient days', () {
    final data = segment('lobby', 'lobby', 1, 8, status: 'active')
      ..['attendantCount'] = 1;
    final bill = StayBilling.calculate(
      patient: patient(status: 'active', exit: 8),
      stays: [StayModel.fromMap('lobby', data)],
      pricing: {'generalRoomBedPrice': 200},
      attendance: {
        for (var day = 1; day <= 4; day++)
          '2026-01-${day.toString().padLeft(2, '0')}': 'Present',
      },
      attendantAttendance: {
        for (var day = 1; day <= 3; day++)
          '2026-01-${day.toString().padLeft(2, '0')}': {'Attendant': 'Present'},
      },
    ).single;

    expect(bill.days['lobby'], 4);
    expect(bill.total, 1400);
  });

  test('patient marks do not create unmarked attendant charges', () {
    final data = segment('lobby', 'lobby', 1, 8, status: 'active')
      ..['attendantCount'] = 1;
    final bill = StayBilling.calculate(
      patient: patient(status: 'active', exit: 8),
      stays: [StayModel.fromMap('lobby', data)],
      pricing: {'generalRoomBedPrice': 200},
      attendance: {
        for (var day = 1; day <= 4; day++)
          '2026-01-${day.toString().padLeft(2, '0')}': 'Present',
      },
    ).single;

    expect(bill.days['lobby'], 4);
    expect(bill.total, 800);
  });

  test(
    'saved attendant mark updates billing even when the next read is stale',
    () async {
      final db = TestDatabase({
        'patients': {'p': patient(status: 'active', exit: 8).toMap()},
        'stays': {'lobby': segment('lobby', 'lobby', 1, 8, status: 'active')},
        'attendance': {
          'daily': {
            for (var day = 1; day <= 5; day++)
              '2026-01-${day.toString().padLeft(2, '0')}': {
                'p': {'status': 'Present'},
              },
          },
        },
        'attendant_attendance': {
          'daily': {
            for (var day = 1; day <= 4; day++)
              '2026-01-${day.toString().padLeft(2, '0')}': {
                'p': {
                  'a': {'attendantName': 'Attendant', 'status': 'Present'},
                },
              },
          },
        },
      });
      final paymentService = PaymentService(db);
      final stale = await paymentService.billingUpdates('p');
      final corrected = await paymentService.billingUpdates(
        'p',
        attendantAttendanceOverrides: {
          '2026-01-05': {'Attendant': 'Present'},
        },
      );

      expect(stale['patients/p/advanceBilledAmount'], 1800);
      expect(corrected['patients/p/advanceBilledAmount'], 2000);
    },
  );

  test('only manually present attendant days are charged', () {
    final data = segment('general', 'general', 1, 3);
    data['attendantCount'] = 1;
    data['patientSnapshot'] = {
      ...data['patientSnapshot'] as Map,
      'attendants': [
        {'name': 'Attendant'},
      ],
    };
    final bill = StayBilling.calculate(
      patient: patient(),
      stays: [StayModel.fromMap('general', data)],
      pricing: {},
      attendance: {
        '2026-01-01': 'Present',
        '2026-01-02': 'Present',
      },
      attendantAttendance: {
        '2026-01-01': {'Attendant': 'Present'},
        '2026-01-02': {'Attendant': 'Absent'},
      },
    ).single;
    expect(bill.total, 600);
  });

  test('unmarked attendant days are not charged', () {
    final data = segment('general', 'general', 1, 3);
    data['attendantCount'] = 1;
    data['patientSnapshot'] = {
      ...data['patientSnapshot'] as Map,
      'attendants': [
        {'name': 'Attendant'},
      ],
    };
    final bill = StayBilling.calculate(
      patient: patient(),
      stays: [StayModel.fromMap('general', data)],
      pricing: {},
      attendance: {
        '2026-01-01': 'Present',
        '2026-01-02': 'Present',
      },
    ).single;
    expect(bill.total, 400);
  });

  test('general 60-day base plus extension uses the historical ₹250 rate', () {
    final data = segment('general', 'general', 1, 71, status: 'active');
    final bill = StayBilling.calculate(
      patient: patient(status: 'active', exit: 71),
      stays: [StayModel.fromMap('general', data)],
      pricing: {'generalRoomBedPrice': 200},
      attendance: {for (var i = 1; i <= 70; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
    ).single;

    expect(bill.days['general'], 70);
    expect(bill.total, 60 * 200 + 10 * 250);
  });

  test('projected admission estimates use category and long-stay tiers', () {
    final pricing = {
      'generalRoomBedPrice': 200,
      'privateRoomBasePrice': 700,
      'privateRoomIncludedAttendants': 1,
      'privateRoomExtraAttendantFee': 200,
    };

    expect(
      PricingHelper.calculateProjectedStayCost(false, 0, 60, pricing: pricing),
      12000,
    );
    expect(
      PricingHelper.calculateProjectedStayCost(false, 0, 70, pricing: pricing),
      14500,
    );
    expect(
      PricingHelper.calculateProjectedStayCost(
        false,
        0,
        70,
        pricing: pricing,
        bedsCount: 2,
      ),
      14500,
    );
    expect(
      PricingHelper.calculateProjectedStayCost(false, 1, 70, pricing: pricing),
      29000,
    );
    expect(
      PricingHelper.calculateProjectedStayCost(true, 2, 70, pricing: pricing),
      66000,
    );
  });

  test('projected estimates preserve manual base and long-stay overrides', () {
    expect(
      PricingHelper.calculateProjectedStayCost(
        false,
        0,
        70,
        pricing: {'generalRoomBedPrice': 200},
        dailyRateOverride: 180,
        longStayRateOverride: 230,
      ),
      13100,
    );
    expect(
      PricingHelper.calculateBillingDays(
        DateTime(2026, 1, 1),
        DateTime(2026, 3, 11),
      ),
      70,
    );
  });

  test(
    'calendar billing tier counts attendance days, not extension metadata',
    () {
      final data = segment('general', 'general', 1, 72, status: 'active');
      data['durationDays'] = 60;
      data['totalExtendedDays'] = 10;
      final attendance60 = <String, String>{
        for (var day = 1; day <= 10; day++)
          StayBilling.dateKey(DateTime(2026, 1, day)): 'Absent',
        for (var day = 11; day <= 70; day++)
          StayBilling.dateKey(DateTime(2026, 1, day)): 'Present',
      };
      final attendance61 = <String, String>{
        ...attendance60,
        StayBilling.dateKey(DateTime(2026, 1, 71)): 'Present',
      };
      final sixty = StayBilling.calculate(
        patient: patient(status: 'active', exit: 70, exitMinute: 1),
        stays: [StayModel.fromMap('general', data)],
        pricing: {},
        attendance: attendance60,
        calendarDayBilling: true,
      ).single;
      final sixtyOne = StayBilling.calculate(
        patient: patient(status: 'active', exit: 71, exitMinute: 1),
        stays: [StayModel.fromMap('general', data)],
        pricing: {},
        attendance: attendance61,
        calendarDayBilling: true,
      ).single;
      expect(sixty.days['general'], 60);
      expect(sixty.total, 12000);
      expect(sixtyOne.total, 12250);
      expect(StayModel.fromMap('general', data).totalDays, 70);
    },
  );

  test(
    'legacy approval quote shares attendance billing and performs no writes',
    () async {
      final data = segment('general', 'general', 1, 61, status: 'active');
      data['durationDays'] = 60;
      final db = TestDatabase({
        'patients': {'p': patient(status: 'active', exit: 61).toMap()},
        'stays': {'general': data},
        'admin_settings': {
          'pricing': {'generalRoomBedPrice': 200},
        },
        'attendance': {
          'daily': {
            for (var day = 1; day <= 10; day++)
              StayBilling.dateKey(DateTime(2026, 1, day)): {
                'p': {'status': 'Absent'},
              },
            for (var day = 11; day <= 60; day++)
              StayBilling.dateKey(DateTime(2026, 1, day)): {
                'p': {'status': 'Present'},
              },
          },
        },
      });
      final service = PaymentService(db);
      final stay = StayModel.fromMap('general', data);
      expect(await service.quoteLegacyStayExtension(stay, 10), 2000);
      expect(await service.quoteLegacyStayExtension(stay, 11), 2250);
      expect(db.writes, 0);
    },
  );

  test(
    'extension estimates use the same category-specific long-stay rules',
    () {
      expect(
        PricingHelper.calculateExtensionCost(
          false,
          0,
          10,
          pricing: {'generalRoomBedPrice': 200},
          priorBillableDays: 60,
        ),
        2500,
      );
      expect(
        PricingHelper.calculateExtensionCost(
          false,
          0,
          10,
          pricing: {'generalRoomBedPrice': 200},
          priorBillableDays: 0,
        ),
        2000,
      );
      expect(
        PricingHelper.calculateExtensionCost(
          false,
          0,
          1,
          pricing: {'generalRoomBedPrice': 200},
          priorBillableDays: 60,
          longStayRateOverride: 300,
        ),
        300,
      );
      expect(
        PricingHelper.calculateExtensionCost(
          false,
          0,
          10,
          pricing: {'generalRoomBedPrice': 150},
          priorBillableDays: 0,
        ),
        2000,
      );
      expect(
        PricingHelper.calculateExtensionCost(
          true,
          2,
          1,
          pricing: {
            'privateRoomBasePrice': 700,
            'privateRoomIncludedAttendants': 1,
            'privateRoomExtraAttendantFee': 200,
          },
          priorBillableDays: 60,
        ),
        1200,
      );
      expect(
        StayBilling.calculate(
          patient: patient(status: 'active', exit: 71),
          stays: [
            StayModel.fromMap(
              'lobby',
              segment('lobby', 'lobby', 1, 71, status: 'active'),
            ),
          ],
          pricing: {'generalRoomBedPrice': 200},
          attendance: {for (var i = 1; i <= 70; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
        ).single.total,
        60 * 200 + 10 * 250,
        reason: 'Lobby uses the verified General pricing path',
      );
    },
  );

  test(
    'extension request IDs round-trip while legacy records remain readable',
    () {
      final legacy = StayExtension.fromMap({
        'additionalDays': 3,
        'extendedOn': stamp(2),
        'reason': 'legacy',
        'additionalCost': 600,
      });
      expect(legacy.requestId, isNull);

      final current = StayExtension(
        requestId: 'extension-retry-1',
        additionalDays: 10,
        extendedOn: DateTime(2026, 1, 1),
        reason: 'approved',
        additionalCost: 2500,
      );
      expect(
        StayExtension.fromMap(current.toMap()).requestId,
        'extension-retry-1',
      );
    },
  );

  test('9 AM checkout excludes last day and charges six attendant days', () {
    final data = segment('lobby', 'lobby', 1, 8, status: 'active');
    data['attendantCount'] = 1;
    final present = <String, Map<String, String>>{
      for (var day = 1; day <= 6; day++)
        '2026-01-${day.toString().padLeft(2, '0')}': {'Attendant': 'Present'},
    };
    final bill = StayBilling.calculate(
      patient: patient(status: 'active', exit: 8, payments: [payment(800)]),
      stays: [StayModel.fromMap('lobby', data)],
      pricing: {'generalRoomBedPrice': 200},
      attendance: {for (var i = 1; i <= 7; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
      attendantAttendance: present,
    ).single;

    expect(bill.days['lobby'], 7);
    expect(bill.total, 2600);
    expect(bill.netPaid, 800);
    expect(bill.due, 1800);
  });

  test(
    'legacy generated daily rate does not override attendant attendance',
    () {
      final data = segment('lobby', 'lobby', 1, 10, status: 'active');
      data['dailyRate'] = 400;
      data['attendantCount'] = 1;
      final bill = StayBilling.calculate(
        patient: patient(status: 'active', exit: 10),
        stays: [StayModel.fromMap('lobby', data)],
        pricing: {'generalRoomBedPrice': 200},
        attendance: {for (var i = 1; i <= 9; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
        attendantAttendance: {
          for (final day in [1, 2, 3, 6, 7, 8])
            '2026-01-${day.toString().padLeft(2, '0')}': {
              'Attendant': 'Present',
            },
        },
      ).single;

      expect(bill.total, 3000);
    },
  );

  test(
    'legacy patient override does not replace attendance-aware stay bill',
    () {
      final patientData = patient(status: 'active', exit: 10).toMap()
        ..['billingAmountOverride'] = 3600;
      final data = segment('lobby', 'lobby', 1, 10, status: 'active')
        ..['attendantCount'] = 1;
      final bill = StayBilling.calculate(
        patient: PatientModel.fromMap('p', patientData),
        stays: [StayModel.fromMap('lobby', data)],
        pricing: {'generalRoomBedPrice': 200},
        attendance: {for (var i = 1; i <= 9; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
        attendantAttendance: {
          for (final day in [1, 2, 3, 6, 7, 8])
            '2026-01-${day.toString().padLeft(2, '0')}': {
              'Attendant': 'Present',
            },
        },
      ).single;

      expect(bill.total, 3000);
    },
  );

  test('a gap between room segments does not charge the departed room', () {
    final stays = [
      mixedStays().first,
      StayModel.fromMap('general', segment('general', 'general', 7, 9)),
    ];
    final bill = StayBilling.calculate(
      patient: patient(),
      stays: stays,
      pricing: {},
      attendance: {for (var i = 1; i <= 9; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
    ).single;
    expect(bill.total, 4 * 700 + 2 * 200);
  });

  Map<String, dynamic> room(
    String type, {
    bool occupied = false,
    String owner = 'p',
  }) => {
    'roomType': type,
    'roomNumber': type,
    'roomIdentifier': type,
    'floor': 1,
    'maxAttendants': 5,
    'currentAttendants': 0,
    'status': occupied ? 'occupied' : 'available',
    'beds': {
      'bed': {
        'id': 'bed',
        'bedLabel': '1',
        'status': occupied ? 'occupied' : 'available',
        'currentPatientId': occupied ? owner : null,
        'currentStayId': occupied ? 'current' : null,
      },
    },
  };

  test(
    'editing current room updates bed occupancy and patient placement atomically',
    () async {
      final current = segment('current', 'private', 1, 8, status: 'active');
      final db = TestDatabase({
        'patients': {'p': patient(status: 'active').toMap()},
        'stays': {'current': current},
        'rooms': {
          'private': room('private', occupied: true),
          'general': room('general'),
        },
      });
      await StayHistoryService(db).updateStay(
        'current',
        {'roomId': 'general', 'roomType': 'general', 'roomNumber': 'general'},
        expectedUpdatedAt: DateTime.fromMillisecondsSinceEpoch(stamp(8)),
      );
      expect(db.writes, 1);
      expect((await db.get('rooms/private/beds/bed'))['status'], 'available');
      expect((await db.get('rooms/general/beds/bed'))['currentPatientId'], 'p');
      expect((await db.get('patients/p'))['roomId'], 'general');
    },
  );

  test('unavailable room correction cannot release the original bed', () async {
    final current = segment('current', 'private', 1, 8, status: 'active');
    final occupied = room('general', occupied: true, owner: 'other');
    (occupied['beds']['bed'] as Map)['currentStayId'] = 'other-stay';
    final db = TestDatabase({
      'patients': {'p': patient(status: 'active').toMap()},
      'stays': {'current': current},
      'rooms': {
        'private': room('private', occupied: true),
        'general': occupied,
      },
    });
    await expectLater(
      StayHistoryService(db).updateStay(
        'current',
        {'roomId': 'general', 'roomType': 'general', 'roomNumber': 'general'},
        expectedUpdatedAt: DateTime.fromMillisecondsSinceEpoch(stamp(8)),
      ),
      throwsStateError,
    );
    expect(db.writes, 0);
    expect((await db.get('rooms/private/beds/bed'))['status'], 'occupied');
  });

  test('four private days and three general days use their own rates', () {
    final bill = StayBilling.calculate(
      patient: patient(),
      stays: mixedStays(),
      pricing: {},
      attendance: {for (var i = 1; i <= 7; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
    ).single;
    expect(bill.charges['private'], 4 * 700);
    expect(bill.charges['general'], 3 * 200);
    expect(bill.total, 3400);
    expect(bill.days.values.fold<int>(0, (a, b) => a + b), 7);
  });
  test('transfer day is billed once at the destination category rate', () {
    final old = segment('private', 'private', 1, 5)
      ..['completedAt'] = stamp(5, 14);
    final next = segment('general', 'general', 5, 8)
      ..['admissionDate'] = stamp(5, 14);
    final bill = StayBilling.calculate(
      patient: patient(),
      stays: [
        StayModel.fromMap('private', old),
        StayModel.fromMap('general', next),
      ],
      pricing: {},
      attendance: {for (var i = 1; i <= 7; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
    ).single;
    expect(bill.total, 3400);
    expect(bill.days.values.fold<int>(0, (a, b) => a + b), 7);
    expect(bill.days['private'], 4);
    expect(bill.days['general'], 3);
  });
  test('absent Private patient retains the reserved room base', () {
    final bill = StayBilling.calculate(
      patient: patient(),
      stays: mixedStays(),
      pricing: {},
      attendance: {
        for (var i = 1; i <= 7; i++)
          '2026-01-0$i': i == 2 ? 'Absent' : 'Present',
      },
    ).single;
    expect(bill.total, 3400);
  });
  test('overpayment and partial refund preserve receipt and refund totals', () {
    final bill = StayBilling.calculate(
      patient: patient(payments: [payment(4000), payment(-250, date: 9)]),
      stays: mixedStays(),
      pricing: {},
      attendance: {for (var i = 5; i <= 7; i++) '2026-01-0$i': 'Present'},
    ).single;
    expect(bill.paid, 4000);
    expect(bill.refunded, 250);
    expect(bill.refundDue, 350);
    expect(bill.status, 'Payment Exceeded');
  });
  test('refund paid after rejoin remains in the previous admission', () {
    final newCycle = stamp(15).toString();
    final stays = [
      ...mixedStays(),
      StayModel.fromMap(
        'new',
        segment('new', 'general', 15, 17, cycleId: newCycle),
      ),
    ];
    final bills = StayBilling.calculate(
      patient: patient(
        admission: 15,
        payments: [
          payment(4000),
          payment(-750, date: 18),
          payment(300, cycleId: newCycle, date: 16),
        ],
      ),
      stays: stays,
      pricing: {},
      attendance: {
        for (var i = 5; i <= 7; i++) '2026-01-0$i': 'Present',
        for (var i = 15; i <= 16; i++) '2026-01-$i': 'Present',
      },
    );
    expect(bills.firstWhere((b) => b.id == cycle).refundDue, 0);
    expect(bills.firstWhere((b) => b.id == newCycle).netPaid, 300);
    expect(bills.firstWhere((b) => b.id == newCycle).due, 100);
  });

  test('legacy same-day receipt remains unallocated without admission evidence', () {
    final admitted = DateTime(2026, 1, 1, 15, 34);
    final legacyPayment = PaymentModel(
      id: 'legacy',
      amount: 400,
      method: 'online',
      date: DateTime(2026, 1, 1, 10, 48),
    );
    final currentPatient = patient().copyWith(admissionDate: admitted);

    expect(
      StayBilling.paymentCycle(legacyPayment, currentPatient, const []),
      'unallocated-payment:legacy',
    );
  });
  test('active admission estimate uses both room segments', () {
    final stays = [
      mixedStays().first,
      StayModel.fromMap(
        'general',
        segment('general', 'general', 5, 8, status: 'active'),
      ),
    ];
    final bill = StayBilling.calculate(
      patient: patient(status: 'active'),
      stays: stays,
      pricing: {},
      attendance: {for (var i = 1; i <= 7; i++) StayBilling.dateKey(DateTime(2026, 1, i)): 'Present'},
      now: DateTime(2026, 1, 7),
    ).single;
    expect(bill.total, 3400);
  });
  test(
    'completed stay correction updates bill, refund and patient in one write',
    () async {
      final data = patient(payments: [payment(4000)]).toMap();
      final db = TestDatabase({
        'patients': {'p': data},
        'stays': {for (final s in mixedStays()) s.id: s.toMap()},
        'attendance': {
          'daily': {
            for (var day = 5; day <= 7; day++)
              '2026-01-${day.toString().padLeft(2, '0')}': {
                'p': {'status': 'Present'},
              },
          },
        },
      });
      await StayHistoryService(db).updateStay(
        'general',
        {
          'completedAt': stamp(7),
          'patientSnapshot': {
            'registrationNumber': 'REG-CORRECTED',
            'attendants': [],
          },
        },
        expectedUpdatedAt: DateTime.fromMillisecondsSinceEpoch(stamp(8)),
      );
      expect(db.writes, 1);
      final result = await db.get('patients/p');
      expect(result['advanceBilledAmount'], 3200);
      expect(result['refundDueAmount'], 800);
      expect(result['registrationNumber'], 'REG-CORRECTED');
      expect((await db.get('stays/general'))['completedAt'], stamp(7));
      expect((await db.get('stays/private'))['completedAt'], stamp(5));
    },
  );
  test(
    'historical correction leaves a later rejoin patient profile intact',
    () async {
      final newCycle = stamp(15).toString();
      final data = patient(
        admission: 15,
        payments: [
          payment(4000),
          payment(300, cycleId: newCycle, date: 16),
        ],
      ).toMap()..['registrationNumber'] = 'NEW-REG';
      final db = TestDatabase({
        'patients': {'p': data},
        'stays': {
          for (final s in mixedStays()) s.id: s.toMap(),
          'new': segment('new', 'general', 15, 17, cycleId: newCycle),
        },
        'attendance': {
          'daily': {
            for (var day = 5; day <= 7; day++)
              '2026-01-${day.toString().padLeft(2, '0')}': {
                'p': {'status': 'Present'},
              },
            for (var day = 15; day <= 16; day++)
              '2026-01-$day': {
                'p': {'status': 'Present'},
              },
          },
        },
      });
      await StayHistoryService(db).updateStay(
        'general',
        {
          'completedAt': stamp(7),
          'patientSnapshot': {
            'registrationNumber': 'OLD-CORRECTED',
            'attendants': [],
          },
        },
        expectedUpdatedAt: DateTime.fromMillisecondsSinceEpoch(stamp(8)),
      );
      final result = await db.get('patients/p');
      expect(result['registrationNumber'], 'NEW-REG');
      expect(result['advanceBilledAmount'], 400);
      expect(result['totalPaidAmount'], 300);
      expect(result['totalRefundDueAmount'], 800);
    },
  );
  test(
    'refund creates signed entries in both ledgers and settles excess',
    () async {
      final db = TestDatabase({
        'patients': {
          'p': patient(payments: [payment(4000)]).toMap(),
        },
        'stays': {for (final s in mixedStays()) s.id: s.toMap()},
        'attendance': {
          'daily': {
            for (var day = 5; day <= 7; day++)
              '2026-01-${day.toString().padLeft(2, '0')}': {
                'p': {'status': 'Present'},
              },
          },
        },
      });
      final id = await PaymentService(db).recordRefund(
        patientId: 'p',
        cycleId: cycle,
        amount: 600,
        date: DateTime(2026, 2, 1),
        method: 'cash',
        receiptNumber: 'REF-1',
      );
      expect(db.writes, 1);
      expect((await db.get('payments/$id'))['amount'], -600);
      expect((await db.get('paymentHistory/$id'))['receiptNumber'], 'REF-1');
      expect((await db.get('patients/p'))['refundDueAmount'], 0);
      expect((await db.get('patients/p'))['totalPaidAmount'], 3400);
    },
  );
  test('refund above excess does not write anything', () async {
    final db = TestDatabase({
      'patients': {
        'p': patient(payments: [payment(4000)]).toMap(),
      },
      'stays': {for (final s in mixedStays()) s.id: s.toMap()},
      'attendance': {
        'daily': {
          for (var day = 5; day <= 7; day++)
            '2026-01-${day.toString().padLeft(2, '0')}': {
              'p': {'status': 'Present'},
            },
        },
      },
    });
    await expectLater(
      PaymentService(db).recordRefund(
        patientId: 'p',
        cycleId: cycle,
        amount: 601,
        date: DateTime(2026, 2, 1),
        method: 'cash',
      ),
      throwsStateError,
    );
    expect(db.writes, 0);
  });
}
