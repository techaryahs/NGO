import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import 'cache_database.dart';

enum CacheConnectionState { idle, syncing, fresh, offline, degraded }

class CacheStatus {
  const CacheStatus({required this.state, this.lastSynced, this.error});

  final CacheConnectionState state;
  final DateTime? lastSynced;
  final String? error;
}

/// Disposable, account-partitioned persistent cache beneath the RTDB layer.
///
/// Firebase remains authoritative: callers only write here after Firebase has
/// acknowledged a mutation. Rows contain canonical entities once; filtered
/// results are always derived from indexed columns.
class PersistentCache {
  PersistentCache(this.database) : _ownsDatabase = false;

  PersistentCache._owned(this.database) : _ownsDatabase = true;

  factory PersistentCache.open() =>
      PersistentCache._owned(CacheDatabase.open());

  CacheDatabase database;
  final bool _ownsDatabase;
  bool _available = true;
  final StreamController<CacheStatus> _statusController =
      StreamController<CacheStatus>.broadcast();
  String? _accountId;
  CacheStatus _status = const CacheStatus(state: CacheConnectionState.idle);
  DateTime? _lastPrune;

  String? get accountId => _accountId;
  CacheStatus get status => _status;
  Stream<CacheStatus> get statusStream =>
      Stream.value(_status).asyncExpand((initial) async* {
        yield initial;
        yield* _statusController.stream;
      });

  Future<void> initialize() async {
    try {
      await database.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (!_ownsDatabase) {
        _available = false;
        _setStatus(CacheConnectionState.degraded, error: error.toString());
        return;
      }
      try {
        await database.close();
        final file = await CacheDatabase.databaseFile();
        for (final candidate in <File>[
          file,
          File('${file.path}-wal'),
          File('${file.path}-shm'),
        ]) {
          if (await candidate.exists()) await candidate.delete();
        }
        database = CacheDatabase.open();
        await database.customSelect('SELECT 1').getSingle();
        _available = true;
      } catch (recoveryError) {
        _available = false;
        _setStatus(
          CacheConnectionState.degraded,
          error: 'Cache recovery failed: $recoveryError',
        );
      }
    }
  }

  /// Selects the authenticated cache partition and removes data belonging to a
  /// different account. Cached PII is never readable before this method.
  Future<void> activateAccount(String accountId) async {
    if (!_available || accountId.isEmpty) return;
    if (_accountId == accountId) return;
    _accountId = accountId;
    await database.transaction(() async {
      await (database.delete(
        database.cachedPatients,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.cachedStays,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.cachedRooms,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.cachedAttendance,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.cachedPayments,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.cachedProfiles,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.cachedSettings,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.cachedPhotoMetadata,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
      await (database.delete(
        database.syncStates,
      )..where((row) => row.accountId.isNotValue(accountId))).go();
    });
  }

  void deactivateAccount() {
    _accountId = null;
    _setStatus(CacheConnectionState.idle);
  }

  void markDegraded(Object error) {
    _available = false;
    _setStatus(
      CacheConnectionState.degraded,
      lastSynced: _status.lastSynced,
      error: error.toString(),
    );
  }

  void markSyncing() {
    if (_available &&
        _accountId != null &&
        _status.state != CacheConnectionState.syncing) {
      _setStatus(CacheConnectionState.syncing, lastSynced: _status.lastSynced);
    }
  }

  Future<void> markSynced(String entity) async {
    if (!_available) return;
    final account = _accountId;
    if (account == null) return;
    final now = DateTime.now();
    _setStatus(CacheConnectionState.fresh, lastSynced: now);
    await database
        .into(database.syncStates)
        .insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            accountId: account,
            entity: entity,
            lastSuccessfulSync: Value(now.millisecondsSinceEpoch),
            status: const Value('fresh'),
          ),
        );
    await _pruneIfDue();
  }

  Future<void> markOffline(String entity, Object error) async {
    if (!_available) return;
    final account = _accountId;
    if (account == null) return;
    _setStatus(
      CacheConnectionState.offline,
      lastSynced: _status.lastSynced,
      error: error.toString(),
    );
    await database
        .into(database.syncStates)
        .insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            accountId: account,
            entity: entity,
            lastSuccessfulSync: Value(
              _status.lastSynced?.millisecondsSinceEpoch,
            ),
            status: const Value('offline'),
            error: Value(error.toString()),
          ),
        );
  }

  void _setStatus(
    CacheConnectionState state, {
    DateTime? lastSynced,
    String? error,
  }) {
    _status = CacheStatus(state: state, lastSynced: lastSynced, error: error);
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  Future<dynamic> read(
    String path, {
    String? orderBy,
    dynamic equalTo,
    List<dynamic>? equalToAny,
  }) async {
    if (!_available) return null;
    final account = _accountId;
    if (account == null) return null;
    final clean = _cleanPath(path);
    final parts = clean.split('/');
    switch (parts.first) {
      case 'patients':
        return _readPatients(account, parts, orderBy, equalTo, equalToAny);
      case 'stays':
        return _readStays(account, parts, orderBy, equalTo, equalToAny);
      case 'rooms':
        return _readRooms(account, parts, orderBy, equalTo, equalToAny);
      case 'payments':
      case 'paymentHistory':
        return _readPayments(account, parts.first, parts, orderBy, equalTo);
      case 'users':
        return _readProfiles(account, parts);
      case 'attendance':
      case 'attendant_attendance':
        return _readAttendance(account, parts);
      default:
        final row =
            await (database.select(database.cachedSettings)..where(
                  (item) =>
                      item.accountId.equals(account) & item.id.equals(clean),
                ))
                .getSingleOrNull();
        return row == null ? null : jsonDecode(row.payload);
    }
  }

  Future<dynamic> readKeyRange(
    String path, {
    required String startKey,
    required String endKey,
  }) async {
    if (!_available) return null;
    final account = _accountId;
    final clean = _cleanPath(path);
    if (account == null ||
        (clean != 'attendance/daily' &&
            clean != 'attendant_attendance/daily')) {
      return null;
    }
    final kind = clean.split('/').first;
    final rows =
        await (database.select(database.cachedAttendance)..where(
              (row) =>
                  row.accountId.equals(account) &
                  row.kind.equals(kind) &
                  row.date.isBiggerOrEqualValue(startKey) &
                  row.date.isSmallerOrEqualValue(endKey),
            ))
            .get();
    final result = <String, dynamic>{};
    for (final row in rows) {
      final dateMap =
          result.putIfAbsent(row.date, () => <String, dynamic>{})
              as Map<String, dynamic>;
      final suffix = row.id.split('/').skip(2).toList();
      _setNested(dateMap, suffix, jsonDecode(row.payload));
    }
    return result;
  }

  Future<void> mergeKeyRangeSnapshot(String path, dynamic value) async {
    if (!_available || value is! Map) return;
    for (final entry in value.entries) {
      await replaceSnapshot('$path/${entry.key}', entry.value);
    }
  }

  Stream<dynamic> watch(String path, {String? orderBy, dynamic equalTo}) {
    if (!_available) return const Stream<dynamic>.empty();
    final account = _accountId;
    final clean = _cleanPath(path);
    if (account == null) return const Stream<dynamic>.empty();
    if (clean == 'patients') {
      final query = database.select(database.cachedPatients)
        ..where((row) {
          var predicate = row.accountId.equals(account);
          if (orderBy == 'status' && equalTo != null) {
            predicate = predicate & row.status.equals(equalTo.toString());
          }
          return predicate;
        });
      return query.watch().map(_patientRowsToMap);
    }
    if (clean == 'stays') {
      final query = database.select(database.cachedStays)
        ..where((row) {
          var predicate = row.accountId.equals(account);
          if (orderBy == 'status' && equalTo != null) {
            predicate = predicate & row.status.equals(equalTo.toString());
          } else if (orderBy == 'roomId' && equalTo != null) {
            predicate = predicate & row.roomId.equals(equalTo.toString());
          } else if (orderBy == 'patientId' && equalTo != null) {
            predicate = predicate & row.patientId.equals(equalTo.toString());
          }
          return predicate;
        });
      return query.watch().map(_stayRowsToMap);
    }
    return Stream.fromFuture(read(clean, orderBy: orderBy, equalTo: equalTo));
  }

  Future<void> replaceSnapshot(String path, dynamic value) async {
    if (!_available) return;
    final account = _accountId;
    if (account == null) return;
    final clean = _cleanPath(path);
    final parts = clean.split('/');
    await database.transaction(() async {
      if (parts.length == 1 && value is Map) {
        await _replaceCollection(account, parts.first, value);
      } else {
        await _applyPath(account, clean, value, isPatch: false);
      }
    });
  }

  Future<void> mergeQuerySnapshot(String path, dynamic value) async {
    if (!_available) return;
    final account = _accountId;
    if (account == null || value is! Map) return;
    final collection = _cleanPath(path).split('/').first;
    await database.transaction(() async {
      for (final entry in value.entries) {
        await _applyPath(
          account,
          '$collection/${entry.key}',
          entry.value,
          isPatch: false,
        );
      }
    });
  }

  Future<void> applyServerMutation(
    Map<String, dynamic> changedValues, {
    required bool isPatch,
  }) async {
    if (!_available) return;
    final account = _accountId;
    if (account == null) return;
    await database.transaction(() async {
      for (final entry in changedValues.entries) {
        await _applyPath(
          account,
          _cleanPath(entry.key),
          entry.value,
          isPatch: isPatch,
        );
      }
    });
  }

  Future<void> _replaceCollection(
    String account,
    String collection,
    Map<dynamic, dynamic> values,
  ) async {
    switch (collection) {
      case 'patients':
        await (database.delete(
          database.cachedPatients,
        )..where((row) => row.accountId.equals(account))).go();
        break;
      case 'stays':
        await (database.delete(
          database.cachedStays,
        )..where((row) => row.accountId.equals(account))).go();
        break;
      case 'rooms':
        await (database.delete(
          database.cachedRooms,
        )..where((row) => row.accountId.equals(account))).go();
        break;
      case 'payments':
      case 'paymentHistory':
        await (database.delete(database.cachedPayments)..where(
              (row) =>
                  row.accountId.equals(account) &
                  row.collection.equals(collection),
            ))
            .go();
        break;
      case 'users':
        await (database.delete(
          database.cachedProfiles,
        )..where((row) => row.accountId.equals(account))).go();
        break;
    }
    for (final entry in values.entries) {
      await _applyPath(
        account,
        '$collection/${entry.key}',
        entry.value,
        isPatch: false,
      );
    }
  }

  Future<void> _applyPath(
    String account,
    String path,
    dynamic value, {
    required bool isPatch,
  }) async {
    if (path.isEmpty) return;
    final parts = path.split('/');
    final collection = parts.first;
    if (collection == 'patientPhotos') {
      if (value is Map) {
        await _upsertPhotoMetadata(account, path, value);
      } else if (value == null) {
        await (database.delete(database.cachedPhotoMetadata)..where(
              (row) =>
                  row.accountId.equals(account) & row.photoRef.equals(path),
            ))
            .go();
      }
      return;
    }
    if (collection == 'attendance' || collection == 'attendant_attendance') {
      await _applyAttendance(account, parts, value, isPatch: isPatch);
      return;
    }
    if (parts.length < 2 ||
        !const {
          'patients',
          'stays',
          'rooms',
          'payments',
          'paymentHistory',
          'users',
        }.contains(collection)) {
      await _applySetting(account, path, value, isPatch: isPatch);
      return;
    }

    final id = parts[1];
    if (parts.length == 2 && value == null) {
      await _deleteEntity(account, collection, id);
      return;
    }
    Map<String, dynamic> payload;
    if (parts.length == 2 && value is Map && !isPatch) {
      payload = _sanitize(Map<String, dynamic>.from(value), collection);
    } else {
      payload =
          await _existingEntity(account, collection, id) ?? <String, dynamic>{};
      if (parts.length == 2 && value is Map) {
        payload.addAll(_sanitize(Map<String, dynamic>.from(value), collection));
      } else if (parts.length > 2) {
        _setNested(payload, parts.sublist(2), value);
      }
    }
    await _upsertEntity(account, collection, id, payload);
  }

  Future<void> _upsertEntity(
    String account,
    String collection,
    String id,
    Map<String, dynamic> payload,
  ) async {
    final encoded = jsonEncode(payload);
    final updatedAt = _asInt(payload['updatedAt']);
    switch (collection) {
      case 'patients':
        await database
            .into(database.cachedPatients)
            .insertOnConflictUpdate(
              CachedPatientsCompanion.insert(
                accountId: account,
                id: id,
                status: Value(_asString(payload['status'])),
                registrationNumber: Value(
                  _asString(payload['registrationNumber']),
                ),
                normalizedName: Value(
                  _asString(
                    payload['searchKey'] ?? payload['fullName'],
                  )?.toLowerCase(),
                ),
                updatedAt: Value(updatedAt),
                payload: encoded,
              ),
            );
        break;
      case 'stays':
        await database
            .into(database.cachedStays)
            .insertOnConflictUpdate(
              CachedStaysCompanion.insert(
                accountId: account,
                id: id,
                patientId: Value(_asString(payload['patientId'])),
                roomId: Value(_asString(payload['roomId'])),
                status: Value(_asString(payload['status'])),
                expectedDischargeDate: Value(
                  _asNullableInt(
                    payload['expectedDischargeDate'] ?? payload['expiryDate'],
                  ),
                ),
                updatedAt: Value(updatedAt),
                payload: encoded,
              ),
            );
        break;
      case 'rooms':
        await database
            .into(database.cachedRooms)
            .insertOnConflictUpdate(
              CachedRoomsCompanion.insert(
                accountId: account,
                id: id,
                status: Value(_asString(payload['status'])),
                floor: Value(_asNullableInt(payload['floor'])),
                roomType: Value(_asString(payload['roomType'])),
                updatedAt: Value(updatedAt),
                payload: encoded,
              ),
            );
        break;
      case 'payments':
      case 'paymentHistory':
        await database
            .into(database.cachedPayments)
            .insertOnConflictUpdate(
              CachedPaymentsCompanion.insert(
                accountId: account,
                id: id,
                collection: collection,
                patientId: Value(_asString(payload['patientId'])),
                date: Value(
                  _asNullableInt(payload['date'] ?? payload['timestamp']),
                ),
                updatedAt: Value(updatedAt),
                payload: encoded,
              ),
            );
        break;
      case 'users':
        await database
            .into(database.cachedProfiles)
            .insertOnConflictUpdate(
              CachedProfilesCompanion.insert(
                accountId: account,
                id: id,
                updatedAt: Value(updatedAt),
                payload: encoded,
              ),
            );
        break;
    }
  }

  Future<void> _deleteEntity(
    String account,
    String collection,
    String id,
  ) async {
    switch (collection) {
      case 'patients':
        await (database.delete(database.cachedPatients)..where(
              (row) => row.accountId.equals(account) & row.id.equals(id),
            ))
            .go();
        break;
      case 'stays':
        await (database.delete(database.cachedStays)..where(
              (row) => row.accountId.equals(account) & row.id.equals(id),
            ))
            .go();
        break;
      case 'rooms':
        await (database.delete(database.cachedRooms)..where(
              (row) => row.accountId.equals(account) & row.id.equals(id),
            ))
            .go();
        break;
      case 'payments':
      case 'paymentHistory':
        await (database.delete(database.cachedPayments)..where(
              (row) =>
                  row.accountId.equals(account) &
                  row.collection.equals(collection) &
                  row.id.equals(id),
            ))
            .go();
        break;
      case 'users':
        await (database.delete(database.cachedProfiles)..where(
              (row) => row.accountId.equals(account) & row.id.equals(id),
            ))
            .go();
        break;
    }
  }

  Future<Map<String, dynamic>?> _existingEntity(
    String account,
    String collection,
    String id,
  ) async {
    dynamic row;
    switch (collection) {
      case 'patients':
        row =
            await (database.select(database.cachedPatients)..where(
                  (item) => item.accountId.equals(account) & item.id.equals(id),
                ))
                .getSingleOrNull();
        break;
      case 'stays':
        row =
            await (database.select(database.cachedStays)..where(
                  (item) => item.accountId.equals(account) & item.id.equals(id),
                ))
                .getSingleOrNull();
        break;
      case 'rooms':
        row =
            await (database.select(database.cachedRooms)..where(
                  (item) => item.accountId.equals(account) & item.id.equals(id),
                ))
                .getSingleOrNull();
        break;
      case 'payments':
      case 'paymentHistory':
        row =
            await (database.select(database.cachedPayments)..where(
                  (item) =>
                      item.accountId.equals(account) &
                      item.collection.equals(collection) &
                      item.id.equals(id),
                ))
                .getSingleOrNull();
        break;
      case 'users':
        row =
            await (database.select(database.cachedProfiles)..where(
                  (item) => item.accountId.equals(account) & item.id.equals(id),
                ))
                .getSingleOrNull();
        break;
    }
    return row == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(row.payload) as Map);
  }

  Future<dynamic> _readPatients(
    String account,
    List<String> parts,
    String? orderBy,
    dynamic equalTo,
    List<dynamic>? equalToAny,
  ) async {
    if (parts.length > 1) {
      return _existingEntity(account, 'patients', parts[1]);
    }
    final query = database.select(database.cachedPatients)
      ..where((row) {
        var predicate = row.accountId.equals(account);
        if (orderBy == 'status' && equalTo != null) {
          predicate = predicate & row.status.equals(equalTo.toString());
        } else if (orderBy == 'status' && equalToAny != null) {
          predicate =
              predicate & row.status.isIn(equalToAny.map((e) => e.toString()));
        } else if (orderBy == 'registrationNumber' && equalTo != null) {
          predicate =
              predicate & row.registrationNumber.equals(equalTo.toString());
        }
        return predicate;
      });
    return _patientRowsToMap(await query.get());
  }

  Future<dynamic> _readStays(
    String account,
    List<String> parts,
    String? orderBy,
    dynamic equalTo,
    List<dynamic>? equalToAny,
  ) async {
    if (parts.length > 1) return _existingEntity(account, 'stays', parts[1]);
    final query = database.select(database.cachedStays)
      ..where((row) {
        var predicate = row.accountId.equals(account);
        if (orderBy == 'status' && equalTo != null) {
          predicate = predicate & row.status.equals(equalTo.toString());
        } else if (orderBy == 'roomId' && equalTo != null) {
          predicate = predicate & row.roomId.equals(equalTo.toString());
        } else if (orderBy == 'patientId' && equalTo != null) {
          predicate = predicate & row.patientId.equals(equalTo.toString());
        }
        return predicate;
      });
    return _stayRowsToMap(await query.get());
  }

  Future<dynamic> _readRooms(
    String account,
    List<String> parts,
    String? orderBy,
    dynamic equalTo,
    List<dynamic>? equalToAny,
  ) async {
    if (parts.length > 1) return _existingEntity(account, 'rooms', parts[1]);
    final query = database.select(database.cachedRooms)
      ..where((row) {
        var predicate = row.accountId.equals(account);
        if (orderBy == 'status' && equalTo != null) {
          predicate = predicate & row.status.equals(equalTo.toString());
        }
        return predicate;
      });
    final rows = await query.get();
    return {for (final row in rows) row.id: jsonDecode(row.payload)};
  }

  Future<dynamic> _readPayments(
    String account,
    String collection,
    List<String> parts,
    String? orderBy,
    dynamic equalTo,
  ) async {
    if (parts.length > 1) {
      return _existingEntity(account, collection, parts[1]);
    }
    final query = database.select(database.cachedPayments)
      ..where((row) {
        var predicate =
            row.accountId.equals(account) & row.collection.equals(collection);
        if (orderBy == 'patientId' && equalTo != null) {
          predicate = predicate & row.patientId.equals(equalTo.toString());
        }
        return predicate;
      });
    final rows = await query.get();
    return {for (final row in rows) row.id: jsonDecode(row.payload)};
  }

  Future<dynamic> _readProfiles(String account, List<String> parts) async {
    if (parts.length > 1) return _existingEntity(account, 'users', parts[1]);
    final rows = await (database.select(
      database.cachedProfiles,
    )..where((row) => row.accountId.equals(account))).get();
    return {for (final row in rows) row.id: jsonDecode(row.payload)};
  }

  Map<String, dynamic> _patientRowsToMap(List<CachedPatient> rows) => {
    for (final row in rows) row.id: jsonDecode(row.payload),
  };

  Map<String, dynamic> _stayRowsToMap(List<CachedStay> rows) => {
    for (final row in rows) row.id: jsonDecode(row.payload),
  };

  Future<void> _applyAttendance(
    String account,
    List<String> parts,
    dynamic value, {
    required bool isPatch,
  }) async {
    if (parts.length < 3 || parts[1] != 'daily') return;
    final kind = parts.first;
    final date = parts[2];
    if (parts.length == 3 && value is Map) {
      await (database.delete(database.cachedAttendance)..where(
            (row) =>
                row.accountId.equals(account) &
                row.kind.equals(kind) &
                row.date.equals(date),
          ))
          .go();
      for (final entry in value.entries) {
        await _applyAttendance(
          account,
          [...parts, entry.key.toString()],
          entry.value,
          isPatch: false,
        );
      }
      return;
    }
    if (parts.length < 4) return;
    final suffix = parts.sublist(3).join('/');
    final id = '$kind/$date/$suffix';
    if (value == null) {
      await (database.delete(database.cachedAttendance)
            ..where((row) => row.accountId.equals(account) & row.id.equals(id)))
          .go();
      return;
    }
    final payload = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{'value': value};
    await database
        .into(database.cachedAttendance)
        .insertOnConflictUpdate(
          CachedAttendanceCompanion.insert(
            accountId: account,
            id: id,
            kind: kind,
            date: date,
            patientId: Value(parts[3]),
            updatedAt: Value(_asInt(payload['updatedAt'])),
            payload: jsonEncode(payload),
          ),
        );
  }

  Future<dynamic> _readAttendance(String account, List<String> parts) async {
    if (parts.length < 3 || parts[1] != 'daily') return null;
    final kind = parts.first;
    final date = parts[2];
    final query = database.select(database.cachedAttendance)
      ..where(
        (row) =>
            row.accountId.equals(account) &
            row.kind.equals(kind) &
            row.date.equals(date),
      );
    final rows = await query.get();
    final result = <String, dynamic>{};
    for (final row in rows) {
      final suffix = row.id.split('/').skip(2).toList();
      _setNested(result, suffix, jsonDecode(row.payload));
    }
    return result;
  }

  Future<void> _upsertSetting(
    String account,
    String path,
    dynamic value,
  ) async {
    if (value == null) {
      await (database.delete(database.cachedSettings)..where(
            (row) => row.accountId.equals(account) & row.id.equals(path),
          ))
          .go();
      return;
    }
    await database
        .into(database.cachedSettings)
        .insertOnConflictUpdate(
          CachedSettingsCompanion.insert(
            accountId: account,
            id: path,
            updatedAt: Value(value is Map ? _asInt(value['updatedAt']) : 0),
            payload: jsonEncode(value),
          ),
        );
  }

  Future<void> _applySetting(
    String account,
    String path,
    dynamic value, {
    required bool isPatch,
  }) async {
    final candidates = await (database.select(
      database.cachedSettings,
    )..where((row) => row.accountId.equals(account))).get();
    candidates.sort((a, b) => b.id.length.compareTo(a.id.length));
    CachedSetting? ancestor;
    for (final row in candidates) {
      if (path == row.id || path.startsWith('${row.id}/')) {
        ancestor = row;
        break;
      }
    }
    if (ancestor == null || value == null && path == ancestor.id) {
      await _upsertSetting(account, path, value);
      return;
    }
    dynamic payload = jsonDecode(ancestor.payload);
    if (path == ancestor.id) {
      if (isPatch && payload is Map && value is Map) {
        payload = {
          ...Map<String, dynamic>.from(payload),
          ...Map<String, dynamic>.from(value),
        };
      } else {
        payload = value;
      }
    } else if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      _setNested(map, path.substring(ancestor.id.length + 1).split('/'), value);
      payload = map;
    }
    await _upsertSetting(account, ancestor.id, payload);
  }

  Future<void> _upsertPhotoMetadata(
    String account,
    String path,
    Map<dynamic, dynamic> value,
  ) async {
    await database
        .into(database.cachedPhotoMetadata)
        .insertOnConflictUpdate(
          CachedPhotoMetadataCompanion.insert(
            accountId: account,
            photoRef: path,
            version: Value(_asInt(value['version'])),
            contentType: Value(_asString(value['contentType'])),
            updatedAt: Value(_asInt(value['updatedAt'])),
            lastAccessedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<void> updatePhotoMetadata({
    required String photoRef,
    required int version,
    required String contentType,
    required String contentHash,
  }) async {
    if (!_available) return;
    final account = _accountId;
    if (account == null) return;
    await database
        .into(database.cachedPhotoMetadata)
        .insertOnConflictUpdate(
          CachedPhotoMetadataCompanion.insert(
            accountId: account,
            photoRef: photoRef,
            version: Value(version),
            contentType: Value(contentType),
            contentHash: Value(contentHash),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
            lastAccessedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<CachedPhotoMetadataData?> photoMetadata(String photoRef) async {
    if (!_available) return null;
    final account = _accountId;
    if (account == null) return null;
    return (database.select(database.cachedPhotoMetadata)..where(
          (row) =>
              row.accountId.equals(account) & row.photoRef.equals(photoRef),
        ))
        .getSingleOrNull();
  }

  Future<void> _pruneIfDue() async {
    final now = DateTime.now();
    if (_lastPrune != null &&
        now.difference(_lastPrune!) < const Duration(days: 1)) {
      return;
    }
    _lastPrune = now;
    final account = _accountId;
    if (account == null) return;
    final attendanceCutoff = now.subtract(const Duration(days: 120));
    final historyCutoff = now
        .subtract(const Duration(days: 730))
        .millisecondsSinceEpoch;
    final attendanceDate = attendanceCutoff.toIso8601String().substring(0, 10);
    await database.transaction(() async {
      await (database.delete(database.cachedAttendance)..where(
            (row) =>
                row.accountId.equals(account) &
                row.date.isSmallerThanValue(attendanceDate),
          ))
          .go();
      await (database.delete(database.cachedPayments)..where(
            (row) =>
                row.accountId.equals(account) &
                row.date.isSmallerThanValue(historyCutoff),
          ))
          .go();
      await (database.delete(database.cachedStays)..where(
            (row) =>
                row.accountId.equals(account) &
                row.status.equals('completed') &
                row.updatedAt.isSmallerThanValue(historyCutoff),
          ))
          .go();
    });
  }

  Future<void> close() async {
    await _statusController.close();
    await database.close();
  }

  static String _cleanPath(String path) =>
      path.replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'/+$'), '');

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    return _asInt(value);
  }

  static String? _asString(dynamic value) => value?.toString();

  static void _setNested(
    Map<String, dynamic> target,
    List<String> parts,
    dynamic value,
  ) {
    if (parts.isEmpty) return;
    if (parts.length == 1) {
      if (value == null) {
        target.remove(parts.first);
      } else {
        target[parts.first] = value;
      }
      return;
    }
    final child = target[parts.first] is Map
        ? Map<String, dynamic>.from(target[parts.first] as Map)
        : <String, dynamic>{};
    _setNested(child, parts.sublist(1), value);
    target[parts.first] = child;
  }

  static Map<String, dynamic> _sanitize(
    Map<String, dynamic> payload,
    String collection,
  ) {
    if (collection != 'patients' && collection != 'stays') return payload;
    dynamic strip(dynamic value) {
      if (value is List) return value.map(strip).toList();
      if (value is Map) {
        final result = <String, dynamic>{};
        value.forEach((key, child) {
          if (key.toString() != 'photoDataUrl') {
            result[key.toString()] = strip(child);
          }
        });
        return result;
      }
      return value;
    }

    return Map<String, dynamic>.from(strip(payload) as Map);
  }
}
