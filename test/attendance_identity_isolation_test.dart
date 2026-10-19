import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/attendance/attendance_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Attendance Identity Isolation & Duplicate Name Collision Tests', () {
    late CacheDatabase cacheDb;
    late PersistentCache persistentCache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cacheDb = CacheDatabase(NativeDatabase.memory());
      persistentCache = PersistentCache(cacheDb);
      await persistentCache.initialize();
      await persistentCache.activateAccount('test_account');
    });

    tearDown(() async {
      await cacheDb.close();
    });

    test(
      'Synthetic scenario: two patients named "test" maintain strictly isolated attendance and summaries',
      () async {
        const patientName = 'test';
        const patientIdA = 'patient_A';
        const regNoA = '101';
        final admissionA = DateTime(2026, 10, 10);
        final exitA = DateTime(2026, 10, 20); // 11 days (Oct 10 - Oct 20)
        final cycleIdA = admissionA.millisecondsSinceEpoch.toString();

        const patientIdB = 'patient_B';
        const regNoB = '102';
        final admissionB = DateTime(2026, 10, 15);
        final exitB = DateTime(2026, 10, 25); // 11 days (Oct 15 - Oct 25)
        final cycleIdB = admissionB.millisecondsSinceEpoch.toString();

        // 1. Generate initial registration attendance for Patient A
        final initialA = PatientService.initialAdmissionAttendance(
          patientId: patientIdA,
          patientName: patientName,
          start: admissionA,
          exit: exitA,
          cycleId: cycleIdA,
          attendants: const [],
        );
        expect(initialA, isEmpty);
        await persistentCache.applyServerMutation(initialA, isPatch: true);

        // 2. Mark selected dates for Patient A (Oct 12 Absent, Oct 15 Absent)
        final editKeyA1 = 'attendance/daily/2026-10-12/$patientIdA';
        final editKeyA2 = 'attendance/daily/2026-10-15/$patientIdA';
        await persistentCache.applyServerMutation({
          editKeyA1: {
            'patientId': patientIdA,
            'patientName': patientName,
            'date': '2026-10-12',
            'status': 'Absent',
            'source': 'manual',
            'cycleId': cycleIdA,
          },
          editKeyA2: {
            'patientId': patientIdA,
            'patientName': patientName,
            'date': '2026-10-15',
            'status': 'Absent',
            'source': 'manual',
            'cycleId': cycleIdA,
          },
        }, isPatch: true);

        // Verify Patient A in cache directly using read
        final cachedRecA1 = await persistentCache.read(editKeyA1);
        expect(cachedRecA1['status'], 'Absent');
        expect(cachedRecA1['patientId'], patientIdA);

        final cachedRecA2 = await persistentCache.read(editKeyA2);
        expect(cachedRecA2['status'], 'Absent');
        expect(cachedRecA2['patientId'], patientIdA);

        // 3. Register Patient B with the same name "test"
        final initialB = PatientService.initialAdmissionAttendance(
          patientId: patientIdB,
          patientName: patientName,
          start: admissionB,
          exit: exitB,
          cycleId: cycleIdB,
          attendants: const [],
        );
        expect(initialB, isEmpty);
        await persistentCache.applyServerMutation(initialB, isPatch: true);

        // 4. Retrieve each patient's attendance separately from cache
        // Check dates before admission for Patient B (e.g. 2026-10-12)
        final beforeAdmissionB = await persistentCache.read(
          'attendance/daily/2026-10-12/$patientIdB',
        );
        expect(
          beforeAdmissionB,
          isNull,
          reason: 'Patient B must have no records before its admission date',
        );

        // Check 2026-10-15: Patient A is Absent, Patient B is Present (automatic)
        final recAOct15 = await persistentCache.read(
          'attendance/daily/2026-10-15/$patientIdA',
        );
        final recBOct15 = await persistentCache.read(
          'attendance/daily/2026-10-15/$patientIdB',
        );
        expect(recAOct15['status'], 'Absent');
        expect(recAOct15['source'], 'manual');
        expect(recBOct15, isNull);

        // 5. Build Monthly Attendance for October 2026
        final patientModelA = PatientModel.fromMap(patientIdA, {
          'fullName': patientName,
          'registrationNumber': regNoA,
          'admissionDate': admissionA.millisecondsSinceEpoch,
          'exitDate': exitA.millisecondsSinceEpoch,
          'status': 'active',
        });
        final patientModelB = PatientModel.fromMap(patientIdB, {
          'fullName': patientName,
          'registrationNumber': regNoB,
          'admissionDate': admissionB.millisecondsSinceEpoch,
          'exitDate': exitB.millisecondsSinceEpoch,
          'status': 'active',
        });

        final staysA = [
          StayModel.fromMap('stay_A', {
            'patientId': patientIdA,
            'roomId': 'room_101',
            'roomNumber': '101',
            'admissionDate': admissionA.millisecondsSinceEpoch,
            'expectedDischargeDate': exitA.millisecondsSinceEpoch,
            'durationDays': 11,
            'status': 'active',
            'createdAt': admissionA.millisecondsSinceEpoch,
            'updatedAt': admissionA.millisecondsSinceEpoch,
          }),
        ];
        final staysB = [
          StayModel.fromMap('stay_B', {
            'patientId': patientIdB,
            'roomId': 'room_102',
            'roomNumber': '102',
            'admissionDate': admissionB.millisecondsSinceEpoch,
            'expectedDischargeDate': exitB.millisecondsSinceEpoch,
            'durationDays': 11,
            'status': 'active',
            'createdAt': admissionB.millisecondsSinceEpoch,
            'updatedAt': admissionB.millisecondsSinceEpoch,
          }),
        ];

        // Hydrate records map from cache for October
        final octRecords = <String, Map<String, dynamic>>{};
        for (var day = 1; day <= 31; day++) {
          final dateKey = '2026-10-${day.toString().padLeft(2, '0')}';
          final aRec = await persistentCache.read(
            'attendance/daily/$dateKey/$patientIdA',
          );
          if (aRec is Map) {
            octRecords['attendance/daily/$dateKey/$patientIdA'] =
                Map<String, dynamic>.from(aRec);
          }
          final bRec = await persistentCache.read(
            'attendance/daily/$dateKey/$patientIdB',
          );
          if (bRec is Map) {
            octRecords['attendance/daily/$dateKey/$patientIdB'] =
                Map<String, dynamic>.from(bRec);
          }
        }

        final monthlyData = MonthlyAttendanceData(
          DateTime(2026, 10, 1),
          octRecords,
        );
        final rows = monthlyData.rows(
          [patientModelA, patientModelB],
          [...staysA, ...staysB],
        );

        expect(rows.length, 2);
        // Verify rows are disambiguated by registrationNumber
        expect(rows[0].displayName, 'test (#101)');
        expect(rows[0].patientId, patientIdA);
        expect(rows[1].displayName, 'test (#102)');
        expect(rows[1].patientId, patientIdB);

        // Verify editor cell statuses
        final editor = MonthlyAttendanceEditor(monthlyData);
        // Patient A on Oct 12 & 15 is Absent; on Oct 10 is Present; on Oct 25 outside stay
        expect(editor.status(rows[0], DateTime(2026, 10, 10)), 'Unmarked');
        expect(editor.status(rows[0], DateTime(2026, 10, 12)), 'Absent');
        expect(editor.status(rows[0], DateTime(2026, 10, 15)), 'Absent');
        expect(rows[0].enabled(DateTime(2026, 10, 25)), isFalse);

        // Patient B on Oct 12 outside stay; on Oct 15 is Present; on Oct 25 is Present
        expect(rows[1].enabled(DateTime(2026, 10, 12)), isFalse);
        expect(editor.status(rows[1], DateTime(2026, 10, 15)), 'Unmarked');
        expect(editor.status(rows[1], DateTime(2026, 10, 25)), 'Unmarked');

        // 6. Test editing Patient B and verifying Patient A is completely unaffected
        editor.edit(rows[1], DateTime(2026, 10, 18), 'Absent');
        expect(editor.status(rows[1], DateTime(2026, 10, 18)), 'Absent');
        expect(
          editor.status(rows[0], DateTime(2026, 10, 18)),
          'Unmarked',
        ); // Patient A unchanged!
        expect(editor.dirty.keys, ['attendance/daily/2026-10-18/$patientIdB']);

        // 7. Verify summaries isolation
        // Patient A has 11 days (Oct 10-20), 2 Absent (Oct 12, 15), 9 Present
        final summaryAPresent = octRecords.entries
            .where(
              (e) =>
                  e.key.endsWith('/$patientIdA') &&
                  e.value['status'] == 'Present',
            )
            .length;
        final summaryAAbsent = octRecords.entries
            .where(
              (e) =>
                  e.key.endsWith('/$patientIdA') &&
                  e.value['status'] == 'Absent',
            )
            .length;
        expect(summaryAPresent, 0);
        expect(summaryAAbsent, 2);
        expect(summaryAPresent + summaryAAbsent, 2);

        // Patient B has 11 days (Oct 15-25), 0 Absent in saved records, 11 Present
        final summaryBPresent = octRecords.entries
            .where(
              (e) =>
                  e.key.endsWith('/$patientIdB') &&
                  e.value['status'] == 'Present',
            )
            .length;
        final summaryBAbsent = octRecords.entries
            .where(
              (e) =>
                  e.key.endsWith('/$patientIdB') &&
                  e.value['status'] == 'Absent',
            )
            .length;
        expect(summaryBPresent, 0);
        expect(summaryBAbsent, 0);

        // 8. Close and reopen cache to verify persistence and isolation across re-instantiation
        await persistentCache.database.close();
        final newCacheDb = CacheDatabase(NativeDatabase.memory());
        final newPersistentCache = PersistentCache(newCacheDb);
        await newPersistentCache.initialize();
        await newPersistentCache.activateAccount('test_account');

        // Populate new cache with saved records
        await newPersistentCache.applyServerMutation(octRecords, isPatch: true);

        final directA_15 = await newPersistentCache.read(
          'attendance/daily/2026-10-15/$patientIdA',
        );
        final directB_15 = await newPersistentCache.read(
          'attendance/daily/2026-10-15/$patientIdB',
        );
        expect(directA_15['status'], 'Absent');
        expect(directB_15, isNull);

        await newCacheDb.close();
      },
    );
  });
}
