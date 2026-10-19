import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/services/payment_service.dart';
import 'package:ngo/utils/stay_billing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:drift/native.dart';

import '../tool/global_billing_restatement.dart' as migration;
import '../tool/restatement_cache_refresh.dart' show refreshVerifiedCache;
import 'stay_billing_test.dart' as fixtures;

Map<String, dynamic> clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Map<String, dynamic> snapshot({
  String status = 'active',
  double rate = 225,
  String room = 'general',
  double? manual,
  double? override,
  bool exitPresent = true,
  bool patientAbsent = false,
  bool attendantPresent = false,
}) {
  final patient = fixtures
      .patient(status: status, exit: 8, payments: [fixtures.payment(8 * rate)])
      .toMap();
  final segment =
      fixtures.segment(
          's',
          room,
          1,
          8,
          status: status == 'active' ? 'active' : 'completed',
        )
        ..['dailyRate'] = manual
        ..['dailyRateIsManual'] = manual != null
        ..['costOverride'] = override;
  return clone({
    'patients': {'p': patient},
    'stays': {'s': segment},
    'admin_settings/pricing': {
      'generalRoomBedPrice': rate,
      'privateRoomBasePrice': 850,
      'privateRoomIncludedAttendants': 1,
      'privateRoomExtraAttendantFee': 225,
    },
    'attendance': {
      'daily': {
        for (var day = 1; day <= 8; day++)
          '2026-01-${day.toString().padLeft(2, '0')}': {
            'p': {
              'status': patientAbsent || (!exitPresent && day == 8)
                  ? 'Absent'
                  : 'Present',
            },
          },
      },
    },
    'attendant_attendance': {
      'daily': {
        if (attendantPresent)
          '2026-01-08': {
            'p': {
              'A': {'attendantName': 'A', 'status': 'Present'},
            },
          },
      },
    },
    'payments': {
      'receipt': {'amount': 8 * rate, 'utr': '123456789012'},
    },
    'paymentHistory': {
      'receipt': {'amount': 8 * rate, 'method': 'ONLINE'},
    },
    'rooms': {
      'general': {'roomNumber': '1A'},
    },
  });
}

Map<String, dynamic> apply(
  Map<String, dynamic> source,
  Map<String, dynamic> updates,
) {
  final result = clone(source);
  for (final entry in updates.entries) {
    final parts = entry.key.split('/');
    Map<String, dynamic> parent = result;
    for (final part in parts.take(parts.length - 1)) {
      parent =
          parent.putIfAbsent(part, () => <String, dynamic>{})
              as Map<String, dynamic>;
    }
    if (entry.value == null) {
      parent.remove(parts.last);
    } else {
      parent[parts.last] = entry.value;
    }
  }
  return result;
}

void main() {
  final now = DateTime(2026, 10, 5);
  test('open active stays are restated beyond the old seven-day cap', () {
    final source = snapshot();
    source['patients']['p'].remove('exitDate');
    final plan = migration.restatementPlan(source, DateTime(2026, 1, 12));
    final repaired = apply(source, migration.object(plan['updates']));
    expect(migration.at(repaired, 'stays/s/billableDays'), 12);
    expect(migration.at(repaired, 'stays/s/totalCost'), 12 * 225);
  });
  test('historical long-stay rate overrides survive restatement', () {
    final source = snapshot();
    source['patients']['p']['exitDate'] = fixtures.stamp(63);
    source['stays']['s']['expectedDischargeDate'] = fixtures.stamp(63);
    source['stays']['s']['longStayDailyRate'] = 390;
    source['attendance']['daily'][StayBilling.dateKey(
      DateTime(2026, 1, 63),
    )] = {
      'p': {'status': 'Present'},
    };
    final plan = migration.restatementPlan(source, now);
    final repaired = apply(source, migration.object(plan['updates']));
    expect(migration.at(repaired, 'stays/s/billableDays'), 63);
    expect(migration.at(repaired, 'stays/s/totalCost'), 60 * 225 + 3 * 390);
    expect(migration.at(repaired, 'stays/s/longStayDailyRate'), 390);
  });
  test(
    'verified cache refresh preserves other partitions and unrelated rows',
    () async {
      final database = CacheDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      for (final account in ['a', 'other']) {
        for (final id in ['p', 'untouched']) {
          await database
              .into(database.cachedPatients)
              .insert(
                CachedPatientsCompanion.insert(
                  accountId: account,
                  id: id,
                  payload: jsonEncode({'id': id, 'advanceBilledAmount': 999}),
                ),
              );
        }
      }
      final results = await refreshVerifiedCache(
        database,
        'a',
        {
          'patients': {
            'p': {'id': 'p', 'status': 'active', 'advanceBilledAmount': 1800},
          },
        },
        {'patients/p/advanceBilledAmount': 1800},
      );
      expect(results['patientRowsRefreshed'], 1);
      final rows = await database.select(database.cachedPatients).get();
      expect(rows, hasLength(4));
      for (final row in rows) {
        expect(
          jsonDecode(row.payload)['advanceBilledAmount'],
          row.accountId == 'a' && row.id == 'p' ? 1800 : 999,
        );
      }
    },
  );
  test(
    'active planned exit and settlement agree with PaymentService production output',
    () async {
      final source = snapshot();
      final plan = migration.restatementPlan(source, now);
      final db = fixtures.TestDatabase(
        clone(source)
          ..['admin_settings'] = {'pricing': source['admin_settings/pricing']},
      );
      addTearDown(db.dispose);
      final production = await PaymentService(db).billingUpdates('p');
      final repaired = apply(source, migration.object(plan['updates']));
      for (final field in migration.patientFields.where(
        (field) => field != 'admissionBalances',
      )) {
        expect(
          migration.at(repaired, 'patients/p/$field'),
          production['patients/p/$field'],
          reason: field,
        );
      }
      expect(migration.at(repaired, 'stays/s/totalCost'), 1800);
      expect(migration.at(repaired, 'stays/s/billableDays'), 8);
      expect(
        migration.at(repaired, 'stays/s/billingSummary'),
        production['stays/s/billingSummary'],
      );
      expect(db.writes, 0);
    },
  );

  for (final rate in [200.0, 250.0]) {
    test('Absent planned exit reduces charge at dynamic rate $rate', () {
      final source = snapshot(rate: rate, exitPresent: false);
      final repaired = apply(
        source,
        migration.object(migration.restatementPlan(source, now)['updates']),
      );
      expect(migration.at(repaired, 'stays/s/totalCost'), 7 * rate);
      expect(migration.at(repaired, 'patients/p/refundDueAmount'), rate);
    });
  }

  test('patient Absent and attendant Present remain independent', () {
    final source = snapshot(patientAbsent: true, attendantPresent: true);
    final repaired = apply(
      source,
      migration.object(migration.restatementPlan(source, now)['updates']),
    );
    expect(migration.at(repaired, 'stays/s/totalCost'), 225);
    expect(migration.at(repaired, 'stays/s/billableDays'), 1);
  });

  test(
    'discharged historical stay keeps the actual 9 AM checkout threshold',
    () {
      for (final minute in [0, 1]) {
        final source = snapshot(status: 'discharged');
        source['stays']['s']['completedAt'] = DateTime(
          2026,
          1,
          8,
          9,
          minute,
        ).millisecondsSinceEpoch;
        final repaired = apply(
          source,
          migration.object(migration.restatementPlan(source, now)['updates']),
        );
        expect(
          migration.at(repaired, 'stays/s/billableDays'),
          minute == 0 ? 7 : 8,
        );
        expect(
          migration.at(repaired, 'stays/s/totalCost'),
          (minute == 0 ? 7 : 8) * 225,
        );
      }
    },
  );

  test(
    'multiple historical and active cycles retain independent segment charges',
    () {
      final source = snapshot();
      source['patients']['p'] = fixtures
          .patient(
            status: 'active',
            admission: 10,
            exit: 15,
            payments: [
              fixtures.payment(2800),
              fixtures.payment(
                1200,
                cycleId: fixtures.stamp(10).toString(),
                date: 10,
              ),
            ],
          )
          .toMap();
      source['stays'] = clone({
        'old': fixtures.segment('old', 'private', 1, 5),
        'new': fixtures.segment(
          'new',
          'general',
          10,
          15,
          status: 'active',
          cycleId: fixtures.stamp(10).toString(),
        ),
      });
      source['admin_settings/pricing']['privateRoomBasePrice'] = 700;
      source['admin_settings/pricing']['generalRoomBedPrice'] = 200;
      source['attendance']['daily']['2026-01-12'] = {
        'p': {'status': 'Absent'},
      };
      source['attendance']['daily']['2026-01-15'] = {
        'p': {'status': 'Present'},
      };
      source['attendance']['daily']['2026-01-16'] = {
        'p': {'status': 'Present'},
      };
      final plan = migration.restatementPlan(source, now);
      final repaired = apply(source, migration.object(plan['updates']));
      expect(migration.at(repaired, 'stays/old/totalCost'), 2800);
      expect(migration.at(repaired, 'stays/new/totalCost'), 1000);
      expect(migration.at(repaired, 'patients/p/refundDueAmount'), 200);
      expect(plan['safety']['calculatedStayIds'], ['new', 'old']);
    },
  );

  test(
    'manual pricing and costOverride remain immutable and authoritative',
    () {
      for (final override in [null, 1234.0]) {
        final source = snapshot(manual: 345, override: override);
        final plan = migration.restatementPlan(source, now);
        final repaired = apply(source, migration.object(plan['updates']));
        expect(
          migration.at(repaired, 'stays/s/totalCost'),
          override ?? 8 * 345,
        );
        expect(migration.at(repaired, 'stays/s/dailyRate'), 345);
        expect(migration.at(repaired, 'stays/s/costOverride'), override);
        expect(
          migration
              .object(plan['updates'])
              .keys
              .any(
                (path) =>
                    path.endsWith('/dailyRate') ||
                    path.endsWith('/costOverride'),
              ),
          false,
        );
      }
    },
  );

  test(
    'missing completion uses only the explicit production updatedAt fallback',
    () {
      final source = snapshot(status: 'discharged');
      source['stays']['s'].remove('completedAt');
      final plan = migration.restatementPlan(source, now);
      final repaired = apply(source, migration.object(plan['updates']));
      expect(migration.at(repaired, 'stays/s/totalCost'), 7 * 225);
      expect(migration.at(repaired, 'stays/s/completedAt'), isNull);
      expect(
        migration.at(repaired, 'stays/s/updatedAt'),
        source['stays']['s']['updatedAt'],
      );
    },
  );

  test(
    'orphans and missing stay sources are reported without fabricated billing',
    () {
      final source = snapshot();
      source['stays']['orphan'] = fixtures.segment('orphan', 'general', 1, 8)
        ..['patientId'] = 'missing';
      source['patients']['no-stay'] =
          fixtures.patient(status: 'active', exit: 8).toMap()
            ..['advanceBilledAmount'] = 99999;
      final plan = migration.restatementPlan(source, now);
      final updates = migration.object(plan['updates']);
      expect(
        updates.keys.any((path) => path.startsWith('stays/orphan/')),
        false,
      );
      expect(
        updates.containsKey('patients/no-stay/advanceBilledAmount'),
        false,
      );
      expect(
        plan['blocked'],
        contains(predicate<Map>((record) => record['id'] == 'orphan')),
      );
      expect(
        plan['blocked'],
        contains(predicate<Map>((record) => record['id'] == 'no-stay')),
      );
      expect(updates['patients/p/advanceBilledAmount'], 1800);
    },
  );

  test(
    'invalid historical checkout blocks only its admission; current cycle continues',
    () {
      final source = snapshot();
      source['stays']['bad'] = fixtures.segment(
        'bad',
        'general',
        10,
        8,
        cycleId: fixtures.stamp(10).toString(),
      );
      final plan = migration.restatementPlan(source, now);
      final updates = migration.object(plan['updates']);
      expect(updates.keys.any((path) => path.startsWith('stays/bad/')), false);
      expect(updates['patients/p/advanceBilledAmount'], 1800);
      expect(updates.containsKey('patients/p/totalRefundDueAmount'), false);
    },
  );

  test('stored billing totals cannot become calculation inputs', () {
    final source = snapshot();
    source['patients']['p']['advanceBilledAmount'] = 99999;
    source['patients']['p']['attendanceCharges'] = 99999;
    source['stays']['s']['totalCost'] = 99999;
    source['stays']['s']['billableDays'] = 999;
    final updates = migration.object(
      migration.restatementPlan(source, now)['updates'],
    );
    expect(updates['stays/s/totalCost'], 1800);
    expect(updates['stays/s/billableDays'], 8);
    expect(updates['patients/p/advanceBilledAmount'], 1800);
  });

  test(
    'second pass is empty and all source/transaction fields remain intact',
    () {
      final source = snapshot();
      final updates = migration.object(
        migration.restatementPlan(source, now)['updates'],
      );
      final repaired = apply(source, updates);
      final second = migration.restatementPlan(repaired, now);
      expect(second['updates'], isEmpty);
      expect(second['summary']['changedRecords'], 0);
      for (final branch in [
        'payments',
        'paymentHistory',
        'attendance',
        'attendant_attendance',
        'rooms',
        'admin_settings/pricing',
      ]) {
        expect(repaired[branch], source[branch], reason: branch);
      }
      for (final collection in ['patients', 'stays']) {
        for (final entry in migration.object(source[collection]).entries) {
          for (final field in migration.object(entry.value).entries) {
            if (!(collection == 'patients'
                    ? migration.patientFields
                    : migration.stayFields)
                .contains(field.key)) {
              expect(
                repaired[collection][entry.key][field.key],
                field.value,
                reason: '$collection/${entry.key}/${field.key}',
              );
            }
          }
        }
      }
    },
  );

  test(
    'whole objects, payments, source dates, pricing and unknown fields are rejected',
    () {
      for (final path in [
        'patients/p',
        'stays/s',
        'payments/p/amount',
        'attendance/daily/date/p',
        'patients/p/payments/receipt/amount',
        'patients/p/admissionDate',
        'stays/s/completedAt',
        'stays/s/costOverride',
        'stays/s/cycleId',
        'stays/s/paidAmount',
        'patients/p/admissionBalances/cycle',
        'stays/s/billingSummary/unknown',
      ]) {
        expect(migration.allowedPath(path), false, reason: path);
      }
    },
  );
}
