import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';

void main() {
  group('Patient Deletion Persistent Cache Suite', () {
    late CacheDatabase db;
    late PersistentCache cache;
    const account = 'acc_test_user';

    setUp(() async {
      db = CacheDatabase(NativeDatabase.memory());
      cache = PersistentCache(db);
      await cache.activateAccount(account);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'deleting a patient purges patient, stays, attendance, payments, and frees bed occupancy in SQLite',
      () async {
        const victimId = 'p_victim';
        const otherId = 'p_other';

        // 1. Populate patients
        await cache.replaceSnapshot('patients/$victimId', {
          'id': victimId,
          'fullName': 'Victim Patient',
          'status': 'active',
          'roomId': 'room_1',
          'bedId': 'bed_1',
        });
        await cache.replaceSnapshot('patients/$otherId', {
          'id': otherId,
          'fullName': 'Other Patient',
          'status': 'active',
          'roomId': 'room_1',
          'bedId': 'bed_2',
        });

        // 2. Populate stays
        await cache.replaceSnapshot('stays/stay_victim', {
          'id': 'stay_victim',
          'patientId': victimId,
          'roomId': 'room_1',
          'bedId': 'bed_1',
          'status': 'active',
        });
        await cache.replaceSnapshot('stays/stay_other', {
          'id': 'stay_other',
          'patientId': otherId,
          'roomId': 'room_1',
          'bedId': 'bed_2',
          'status': 'active',
        });

        // 3. Populate attendance
        await cache.replaceSnapshot('attendance/daily/2026-10-18/$victimId', {
          'status': 'Present',
          'patientId': victimId,
        });
        await cache.replaceSnapshot('attendance/daily/2026-10-18/$otherId', {
          'status': 'Present',
          'patientId': otherId,
        });

        // 4. Populate payments
        await cache.replaceSnapshot('payments/pay_victim', {
          'id': 'pay_victim',
          'patientId': victimId,
          'amount': 500,
        });
        await cache.replaceSnapshot('payments/pay_other', {
          'id': 'pay_other',
          'patientId': otherId,
          'amount': 800,
        });

        // 5. Populate rooms with 2 occupied beds
        await cache.replaceSnapshot('rooms/room_1', {
          'id': 'room_1',
          'roomNumber': '101',
          'roomIdentifier': 'R101',
          'floor': 1,
          'roomType': 'general',
          'status': 'occupied',
          'totalBeds': 2,
          'occupiedBeds': 2,
          'beds': [
            {
              'id': 'bed_1',
              'bedLabel': '1A',
              'status': 'occupied',
              'currentPatientId': victimId,
              'currentStayId': 'stay_victim',
            },
            {
              'id': 'bed_2',
              'bedLabel': '1B',
              'status': 'occupied',
              'currentPatientId': otherId,
              'currentStayId': 'stay_other',
            },
          ],
        });

        // Verify initial state
        final initialVictimPatient = await cache.read('patients/$victimId');
        expect(initialVictimPatient, isNotNull);
        final initialOtherPatient = await cache.read('patients/$otherId');
        expect(initialOtherPatient, isNotNull);

        // Delete the victim patient
        await cache.replaceSnapshot('patients/$victimId', null);

        // A. Verify patient record is deleted from SQLite
        final deletedPatient = await cache.read('patients/$victimId');
        expect(deletedPatient, isNull);

        // Other patient must be untouched
        final remainingPatient = await cache.read('patients/$otherId');
        expect(remainingPatient, isNotNull);
        expect(remainingPatient!['id'], otherId);

        // B. Verify stays
        final victimStay = await (db.select(db.cachedStays)
              ..where(
                (r) => r.accountId.equals(account) & r.id.equals('stay_victim'),
              ))
            .getSingleOrNull();
        expect(victimStay, isNull);

        final otherStay = await (db.select(db.cachedStays)
              ..where(
                (r) => r.accountId.equals(account) & r.id.equals('stay_other'),
              ))
            .getSingleOrNull();
        expect(otherStay, isNotNull);

        // C. Verify attendance
        final victimAtt = await (db.select(db.cachedAttendance)
              ..where(
                (r) => r.accountId.equals(account) & r.patientId.equals(victimId),
              ))
            .get();
        expect(victimAtt, isEmpty);

        final otherAtt = await (db.select(db.cachedAttendance)
              ..where(
                (r) => r.accountId.equals(account) & r.patientId.equals(otherId),
              ))
            .get();
        expect(otherAtt, isNotEmpty);

        // D. Verify payments
        final victimPayments = await (db.select(db.cachedPayments)
              ..where(
                (r) => r.accountId.equals(account) & r.patientId.equals(victimId),
              ))
            .get();
        expect(victimPayments, isEmpty);

        final otherPayments = await (db.select(db.cachedPayments)
              ..where(
                (r) => r.accountId.equals(account) & r.patientId.equals(otherId),
              ))
            .get();
        expect(otherPayments, isNotEmpty);

        // E. Verify room bed occupancy update
        final roomRow = await (db.select(db.cachedRooms)
              ..where(
                (r) => r.accountId.equals(account) & r.id.equals('room_1'),
              ))
            .getSingle();
        final roomData = json.decode(roomRow.payload) as Map<String, dynamic>;
        expect(roomData['occupiedBeds'], 1);
        expect(roomData['status'], 'partially_occupied');

        final beds = roomData['beds'] as List;
        final bed1 = beds.firstWhere((b) => b['id'] == 'bed_1');
        final bed2 = beds.firstWhere((b) => b['id'] == 'bed_2');

        // Bed 1 (was assigned to victim) must now be available and clear of patient IDs
        expect(bed1['status'], 'available');
        expect(bed1['currentPatientId'], isNull);
        expect(bed1['currentStayId'], isNull);

        // Bed 2 (assigned to other) must remain occupied
        expect(bed2['status'], 'occupied');
        expect(bed2['currentPatientId'], otherId);
        expect(bed2['currentStayId'], 'stay_other');
      },
    );
  });
}
