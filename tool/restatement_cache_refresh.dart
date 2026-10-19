import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ngo/cache/cache_database.dart';

/// Refresh only existing affected rows after RTDB verification. Other account
/// partitions, records, attendance, ledger tables and synchronization markers
/// remain intact. There is no cache-to-server write path in this utility.
Future<Map<String, int>> refreshVerifiedCache(
  CacheDatabase database,
  String account,
  Map<String, dynamic> verified,
  Map<String, dynamic> changes,
) async {
  final ids = <String, Set<String>>{'patients': {}, 'stays': {}};
  for (final path in changes.keys) {
    final parts = path.split('/');
    ids[parts.first]?.add(parts[1]);
  }
  var patients = 0;
  var stays = 0;
  await database.transaction(() async {
    for (final id in ids['patients']!) {
      final rows =
          await (database.select(database.cachedPatients)..where(
                (row) => row.accountId.equals(account) & row.id.equals(id),
              ))
              .get();
      if (rows.isEmpty) continue;
      final payload = Map<String, dynamic>.from(
        verified['patients'][id] as Map,
      );
      await (database.update(database.cachedPatients)
            ..where((row) => row.accountId.equals(account) & row.id.equals(id)))
          .write(
            CachedPatientsCompanion(
              status: Value(payload['status']?.toString()),
              registrationNumber: Value(
                payload['registrationNumber']?.toString(),
              ),
              normalizedName: Value(
                (payload['searchKey'] ?? payload['fullName'])
                    ?.toString()
                    .toLowerCase(),
              ),
              updatedAt: Value((payload['updatedAt'] as num?)?.toInt() ?? 0),
              payload: Value(jsonEncode(payload)),
            ),
          );
      final refreshed =
          await (database.select(database.cachedPatients)..where(
                (row) => row.accountId.equals(account) & row.id.equals(id),
              ))
              .getSingle();
      expect(jsonDecode(refreshed.payload), payload);
      patients++;
    }
    for (final id in ids['stays']!) {
      final rows =
          await (database.select(database.cachedStays)..where(
                (row) => row.accountId.equals(account) & row.id.equals(id),
              ))
              .get();
      if (rows.isEmpty) continue;
      final payload = Map<String, dynamic>.from(verified['stays'][id] as Map);
      await (database.update(database.cachedStays)
            ..where((row) => row.accountId.equals(account) & row.id.equals(id)))
          .write(
            CachedStaysCompanion(
              patientId: Value(payload['patientId']?.toString()),
              roomId: Value(payload['roomId']?.toString()),
              status: Value(payload['status']?.toString()),
              expectedDischargeDate: Value(
                ((payload['expectedDischargeDate'] ?? payload['expiryDate'])
                        as num?)
                    ?.toInt(),
              ),
              updatedAt: Value((payload['updatedAt'] as num?)?.toInt() ?? 0),
              payload: Value(jsonEncode(payload)),
            ),
          );
      final refreshed =
          await (database.select(database.cachedStays)..where(
                (row) => row.accountId.equals(account) & row.id.equals(id),
              ))
              .getSingle();
      expect(jsonDecode(refreshed.payload), payload);
      stays++;
    }
  });
  return {'patientRowsRefreshed': patients, 'stayRowsRefreshed': stays};
}

void main() {
  test('refresh only the verified production billing cache rows', () async {
    final environment = Platform.environment;
    final directory = Directory(environment['NGO_RESTATEMENT_DIRECTORY']!);
    final verification =
        jsonDecode(
              File('${directory.path}/verification.json').readAsStringSync(),
            )
            as Map;
    expect(verification['status'], 'verified');
    expect(verification['secondReconciliationChangedFields'], 0);
    final verified = Map<String, dynamic>.from(
      jsonDecode(
            File('${directory.path}/post_snapshot.json').readAsStringSync(),
          )
          as Map,
    );
    final plan =
        jsonDecode(File('${directory.path}/dry_run.json').readAsStringSync())
            as Map;
    final database = CacheDatabase(
      NativeDatabase(File(environment['NGO_RESTATEMENT_CACHE_FILE']!)),
    );
    try {
      final results = await refreshVerifiedCache(
        database,
        environment['NGO_RESTATEMENT_CACHE_ACCOUNT']!,
        verified,
        Map<String, dynamic>.from(plan['updates'] as Map),
      );
      final output = File('${directory.path}/cache_verification.json');
      if (output.existsSync()) throw StateError('Cache result already exists');
      output.writeAsStringSync(
        jsonEncode({
          'status': 'verified',
          ...results,
          'otherAccountPartitionsPreserved': true,
          'cacheTablesNotWiped': true,
          'noCacheToServerWrites': true,
        }),
        flush: true,
      );
    } finally {
      await database.close();
    }
  });
}
