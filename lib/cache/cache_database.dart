import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'cache_database.g.dart';

@TableIndex(name: 'patients_status_idx', columns: {#accountId, #status})
@TableIndex(
  name: 'patients_registration_idx',
  columns: {#accountId, #registrationNumber},
)
@TableIndex(name: 'patients_name_idx', columns: {#accountId, #normalizedName})
@TableIndex(name: 'patients_updated_idx', columns: {#accountId, #updatedAt})
class CachedPatients extends Table {
  TextColumn get accountId => text()();
  TextColumn get id => text()();
  TextColumn get status => text().nullable()();
  TextColumn get registrationNumber => text().nullable()();
  TextColumn get normalizedName => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, id};
}

@TableIndex(name: 'stays_patient_idx', columns: {#accountId, #patientId})
@TableIndex(name: 'stays_room_idx', columns: {#accountId, #roomId})
@TableIndex(name: 'stays_status_idx', columns: {#accountId, #status})
@TableIndex(
  name: 'stays_discharge_idx',
  columns: {#accountId, #expectedDischargeDate},
)
@TableIndex(name: 'stays_updated_idx', columns: {#accountId, #updatedAt})
class CachedStays extends Table {
  TextColumn get accountId => text()();
  TextColumn get id => text()();
  TextColumn get patientId => text().nullable()();
  TextColumn get roomId => text().nullable()();
  TextColumn get status => text().nullable()();
  IntColumn get expectedDischargeDate => integer().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, id};
}

@TableIndex(name: 'rooms_status_idx', columns: {#accountId, #status})
@TableIndex(name: 'rooms_updated_idx', columns: {#accountId, #updatedAt})
class CachedRooms extends Table {
  TextColumn get accountId => text()();
  TextColumn get id => text()();
  TextColumn get status => text().nullable()();
  IntColumn get floor => integer().nullable()();
  TextColumn get roomType => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, id};
}

@TableIndex(name: 'attendance_date_idx', columns: {#accountId, #kind, #date})
@TableIndex(name: 'attendance_patient_idx', columns: {#accountId, #patientId})
class CachedAttendance extends Table {
  TextColumn get accountId => text()();
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get date => text()();
  TextColumn get patientId => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, id};
}

@TableIndex(name: 'payments_patient_idx', columns: {#accountId, #patientId})
@TableIndex(name: 'payments_date_idx', columns: {#accountId, #date})
class CachedPayments extends Table {
  TextColumn get accountId => text()();
  TextColumn get id => text()();
  TextColumn get collection => text()();
  TextColumn get patientId => text().nullable()();
  IntColumn get date => integer().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, collection, id};
}

class CachedProfiles extends Table {
  TextColumn get accountId => text()();
  TextColumn get id => text()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, id};
}

class CachedSettings extends Table {
  TextColumn get accountId => text()();
  TextColumn get id => text()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, id};
}

class CachedPhotoMetadata extends Table {
  TextColumn get accountId => text()();
  TextColumn get photoRef => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get contentType => text().nullable()();
  TextColumn get contentHash => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  IntColumn get lastAccessedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {accountId, photoRef};
}

class SyncStates extends Table {
  TextColumn get accountId => text()();
  TextColumn get entity => text()();
  IntColumn get lastSuccessfulSync => integer().nullable()();
  IntColumn get highWaterMark => integer().nullable()();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('idle'))();
  TextColumn get error => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, entity};
}

@DriftDatabase(
  tables: [
    CachedPatients,
    CachedStays,
    CachedRooms,
    CachedAttendance,
    CachedPayments,
    CachedProfiles,
    CachedSettings,
    CachedPhotoMetadata,
    SyncStates,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase(super.executor);

  factory CacheDatabase.open() => CacheDatabase(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
    },
  );

  static Future<File> databaseFile() async {
    final appSupport = await getApplicationSupportDirectory();
    final directory = Directory(p.join(appSupport.path, 'ngo_management'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'persistent_cache.sqlite'));
  }
}

LazyDatabase _openConnection() => LazyDatabase(() async {
  final file = await CacheDatabase.databaseFile();
  return NativeDatabase.createInBackground(file);
});
