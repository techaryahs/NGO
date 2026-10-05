import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import '../cache/persistent_cache.dart';
import 'patient_collection_state.dart';

/// Firebase Realtime Database REST API Service
///
/// Provides CRUD operations and resource-level realtime streams without
/// requiring the native Firebase Database SDK. Works on ALL platforms
/// including Windows desktop.
///
/// Architecture (production fixes):
/// - One shared, reference-counted SSE stream per resource/query. Filtered
///   resources hydrate from SQLite and never run a 10-second GET loop.
/// - Writes complete as soon as Firebase acknowledges the mutation. Cache
///   invalidation happens independently: after a successful write, the
///   affected shared resources are refreshed (debounced), so a mutation never
///   waits for every active screen to refetch large collections.
/// - Conditional writes via `If-Match`/ETag provide server-enforced
///   compare-and-swap for concurrency-sensitive paths (room bed allocation).
class FirebaseRTDBRestService {
  final String projectId;
  final String databaseUrl;

  // Callback to get auth token
  Future<String?> Function()? getAuthToken;

  // Injectable HTTP client (used by tests). When null, an owned client is
  // created lazily.
  final http.Client? _injectedClient;
  final http.Client Function()? _sseClientFactory;
  final PersistentCache? persistentCache;
  http.Client? _ownedClient;

  http.Client get _client =>
      _injectedClient ?? (_ownedClient ??= http.Client());

  // Polling interval for resource streams (in seconds)
  static const int _pollingInterval = 10;

  // One shared resource stream per path+interval.
  final Map<String, _SharedResource> _resources = {};

  // Keep the latest successful value per path so moving between screens does
  // not flash an empty state while the same Firebase data is downloaded again.
  final Map<String, dynamic> _latestValues = {};
  final PatientCollectionState _patients = PatientCollectionState();
  int _memoryAccountGeneration = -1;
  StreamSubscription<int>? _accountSubscription;

  int _bindAccount() {
    final generation = persistentCache?.accountGeneration ?? 0;
    if (_memoryAccountGeneration != generation) {
      _memoryAccountGeneration = generation;
      _patients.bindAccount(generation);
      _latestValues.clear();
      for (final resource in _resources.values.toList()) {
        resource.resetAccount();
      }
    }
    return generation;
  }

  @visibleForTesting
  PatientCollectionCompleteness get patientsCompleteness =>
      _patients.completeness;

  @visibleForTesting
  void seedCanonicalPatientsForTesting(Map<String, dynamic> value) {
    _bindAccount();
    _patients.publish(value, _patients.capture(), complete: true);
    _publishPatients();
  }

  @visibleForTesting
  Future<void> rehydratePatientsForTesting() async {
    for (final resource in _resources.values.toList()) {
      if (resource._isCanonicalPatients) await resource.rehydratePersistent();
    }
  }

  void _publishPatients() {
    final value = _patients.value;
    if (value == null) {
      _latestValues.remove('patients');
      return;
    }
    _latestValues['patients'] = value;
    for (final resource in _resources.values) {
      if (resource._isCanonicalPatients) resource.emitCachedValue(value);
    }
  }

  void _beginMutation(
    Map<String, dynamic> changes, {
    required bool isPatch,
    bool acknowledged = true,
    PatientSnapshotTicket? ticket,
  }) {
    _bindAccount();
    for (final entry in changes.entries) {
      _patients.mutate(
        entry.key,
        entry.value,
        isPatch: isPatch,
        acknowledged: acknowledged,
        revision: ticket?.revision,
      );
    }
    final value = _patients.value;
    if (value != null) _latestValues['patients'] = value;
    for (final resource in _resources.values) {
      if (changes.keys.any(resource.overlaps)) resource._revision++;
    }
  }

  Future<void> _acceptPatientsSnapshot(
    dynamic data,
    PatientSnapshotTicket ticket, {
    bool Function()? connectionCurrent,
  }) async {
    if (_bindAccount() == ticket.accountGeneration &&
        _patients.value == null &&
        !_patients.isCurrent(ticket) &&
        (connectionCurrent?.call() ?? true)) {
      // Establish the first complete base by rebasing deferred acknowledgements;
      // the obsolete raw publication is never emitted.
      ticket = _patients.capture();
    }
    bool current() =>
        _bindAccount() == ticket.accountGeneration &&
        _patients.isCurrent(ticket) &&
        (connectionCurrent?.call() ?? true);
    if (!current() || !PatientCollectionState.isCollection(data)) return;
    final reconciled = _patients.reconcile(data);
    await _cacheAction(
      () => persistentCache?.replaceSnapshot(
        'patients',
        reconciled,
        isCurrent: current,
      ),
    );
    if (!current()) return;
    if (_patients.publish(data, ticket, complete: true)) _publishPatients();
    await _cacheAction(() => persistentCache?.markSynced('patients'));
  }

  @visibleForTesting
  Map<String, dynamic> get latestValuesForTesting => _latestValues;

  @visibleForTesting
  Map<String, dynamic> prepareWriteForTesting(
    String path,
    Map<String, dynamic> input, {
    required bool isPatch,
  }) => _prepareWrite(path, input, isPatch: isPatch);

  @visibleForTesting
  void notifyWrittenForTesting(
    List<String> changedPaths, {
    Map<String, dynamic>? explicitValues,
    bool isPatch = false,
  }) => _notifyWritten(
    changedPaths,
    explicitValues: explicitValues,
    isPatch: isPatch,
  );

  FirebaseRTDBRestService({
    required this.projectId,
    String? databaseUrl,
    this.getAuthToken,
    http.Client? httpClient,
    http.Client Function()? sseClientFactory,
    this.persistentCache,
  }) : _injectedClient = httpClient,
       _sseClientFactory = sseClientFactory,
       databaseUrl =
           databaseUrl ?? 'https://$projectId-default-rtdb.firebaseio.com' {
    _bindAccount();
    _accountSubscription = persistentCache?.accountChanges.listen(
      (_) => _bindAccount(),
    );
  }

  http.Client _createSseClient() => _sseClientFactory?.call() ?? http.Client();

  /// Get the current user's ID token for authenticated requests
  Future<String?> _getIdToken() async {
    if (getAuthToken != null) {
      return await getAuthToken!();
    }
    return null;
  }

  /// Build URL with auth token
  String _buildUrl(String path, {String? auth}) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final url = '$databaseUrl/$cleanPath.json';
    if (auth != null) {
      return '$url?auth=$auth';
    }
    return url;
  }

  // ===========================================================================
  // GET — Read data
  // ===========================================================================

  /// Fetch data from a specific path
  Future<dynamic> get(String path) async {
    final account = _bindAccount();
    final patientTicket = path == 'patients' ? _patients.capture() : null;
    persistentCache?.markSyncing();
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await _client
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception(
                'Request timeout - check your internet connection',
              );
            },
          );

      if (response.statusCode == 200) {
        final value = response.body == 'null'
            ? null
            : json.decode(response.body);
        if (_bindAccount() != account) return value;
        if (patientTicket != null) {
          await _acceptPatientsSnapshot(value, patientTicket);
          return _patients.value ??
              (throw StateError('Canonical patients unavailable'));
        }
        if (!path.startsWith('patientPhotos/')) _latestValues[path] = value;
        await _cacheAction(() async {
          await persistentCache?.replaceSnapshot(path, value);
          await persistentCache?.markSynced(path.split('/').first);
        });
        return value;
      } else {
        throw Exception(
          'GET failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      await _cacheAction(
        () => persistentCache?.markOffline(path.split('/').first, e),
      );
      if (_bindAccount() != account) rethrow;
      final canonical = path == 'patients'
          ? await _cacheValue(() => persistentCache?.readCanonicalPatients())
          : null;
      final cached = path == 'patients'
          ? (canonical is CanonicalPatientCacheSnapshot && canonical.complete
                ? canonical.value
                : null)
          : await _cacheValue(() => persistentCache?.read(path));
      if (cached != null) return cached;
      throw Exception('Failed to GET $path: $e');
    }
  }

  /// Value of a snapshot together with its ETag, for conditional writes.
  Future<RtdbValue> getWithEtag(String path) async {
    final account = _bindAccount();
    final patientTicket = path == 'patients' ? _patients.capture() : null;
    try {
      final token = await _getIdToken();
      final url = Uri.parse(_buildUrl(path, auth: token));
      final response = await _client
          .get(url, headers: {'X-Firebase-ETag': 'true'})
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Request timeout - check your internet connection',
            ),
          );
      if (response.statusCode == 200) {
        final value = response.body == 'null'
            ? null
            : json.decode(response.body);
        if (_bindAccount() == account && patientTicket != null) {
          await _acceptPatientsSnapshot(value, patientTicket);
        } else if (_bindAccount() == account) {
          _latestValues[path] = value;
          await _cacheAction(() async {
            await persistentCache?.replaceSnapshot(path, value);
            await persistentCache?.markSynced(path.split('/').first);
          });
        }
        final etag = response.headers['etag'];
        if (etag == null || etag.isEmpty) {
          throw StateError('Firebase did not return an ETag for $path');
        }
        return RtdbValue(value, etag);
      }
      throw Exception('GET failed: ${response.statusCode} - ${response.body}');
    } catch (e) {
      await _cacheAction(
        () => persistentCache?.markOffline(path.split('/').first, e),
      );
      throw Exception('Failed to GET (etag) $path: $e');
    }
  }

  /// Fetch children whose RTDB keys fall within an inclusive range.
  ///
  /// This is useful for date-keyed collections and avoids downloading the
  /// collection's complete history when only one admission period is needed.
  Future<dynamic> getByKeyRange(
    String path, {
    required String startKey,
    required String endKey,
  }) async {
    try {
      final token = await _getIdToken();
      final baseUrl = Uri.parse(_buildUrl(path));
      final query = <String, String>{
        'orderBy': json.encode(r'$key'),
        'startAt': json.encode(startKey),
        'endAt': json.encode(endKey),
        if (token != null) 'auth': token,
      };
      final response = await _client
          .get(baseUrl.replace(queryParameters: query))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Request timeout - check your internet connection',
            ),
          );

      if (response.statusCode == 200) {
        final value = response.body == 'null'
            ? null
            : json.decode(response.body);
        await _cacheAction(() async {
          await persistentCache?.mergeKeyRangeSnapshot(path, value);
          await persistentCache?.markSynced(path.split('/').first);
        });
        return value;
      }
      throw Exception(
        'GET range failed: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
      await _cacheAction(
        () => persistentCache?.markOffline(path.split('/').first, e),
      );
      final cached = await _cacheValue(
        () => persistentCache?.readKeyRange(
          path,
          startKey: startKey,
          endKey: endKey,
        ),
      );
      if (cached is Map && cached.isNotEmpty) return cached;
      throw Exception('Failed to GET range $path: $e');
    }
  }

  /// Fetch children whose indexed child property equals [value].
  Future<dynamic> getByChildValue(
    String path, {
    required String child,
    required Object value,
  }) async {
    try {
      final token = await _getIdToken();
      final baseUrl = Uri.parse(_buildUrl(path));
      final query = <String, String>{
        'orderBy': json.encode(child),
        'equalTo': json.encode(value),
        if (token != null) 'auth': token,
      };
      final response = await _client
          .get(baseUrl.replace(queryParameters: query))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Request timeout - check your internet connection',
            ),
          );
      if (response.statusCode == 200) {
        final remoteValue = response.body == 'null'
            ? null
            : json.decode(response.body);
        await _cacheAction(() async {
          await persistentCache?.mergeQuerySnapshot(path, remoteValue);
          await persistentCache?.markSynced(path.split('/').first);
        });
        return remoteValue;
      }
      throw Exception(
        'GET filtered data failed: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
      await _cacheAction(
        () => persistentCache?.markOffline(path.split('/').first, e),
      );
      final cached = await _cacheValue(
        () => persistentCache?.read(path, orderBy: child, equalTo: value),
      );
      if (cached is Map && cached.isNotEmpty) return cached;
      throw Exception('Failed to GET filtered $path: $e');
    }
  }

  // ===========================================================================
  // WRITE — Write/Replace data
  // ===========================================================================

  /// Write data to a specific path (replaces existing data)
  Future<void> put(String path, Map<String, dynamic> data) async {
    final account = _bindAccount();
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final prepared = _prepareWrite(path, data, isPatch: false);
      final response = await _client.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(prepared),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'PUT failed: ${response.statusCode} - ${response.body}',
        );
      }
      final resolved = _decodeWriteResponse(response.body, prepared);
      if (_bindAccount() != account) return;
      if (path != 'patients' && !path.startsWith('patientPhotos/')) {
        _latestValues[path] = resolved;
      }
      _beginMutation({path: resolved}, isPatch: false);
      await _cacheAction(
        () => persistentCache?.applyServerMutation({
          path: resolved,
        }, isPatch: false),
      );
      if (_bindAccount() != account) return;
      _notifyWritten(
        [path],
        explicitValues: {path: resolved},
        isPatch: false,
        recorded: true,
      );
    } catch (e) {
      throw Exception('Failed to PUT $path: $e');
    }
  }

  // ===========================================================================
  // PATCH — Update data
  // ===========================================================================

  /// Update specific fields at a path (merges with existing data).
  ///
  /// Completes as soon as Firebase acknowledges the write. The affected
  /// shared streams are refreshed independently and never block the caller.
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    final account = _bindAccount();
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final prepared = _prepareWrite(path, updates, isPatch: true);
      final response = await _client.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(prepared),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'PATCH failed: ${response.statusCode} - ${response.body}',
        );
      }
      final changed = <String>[];
      final changedValues = <String, dynamic>{};
      final resolved = _decodeWriteResponse(response.body, prepared);
      if (_bindAccount() != account) return;
      for (final entry in resolved.entries) {
        final changedPath = path.isEmpty ? entry.key : '$path/${entry.key}';
        changed.add(changedPath);
        changedValues[changedPath] = entry.value;
        _mergeIntoCache(changedPath, entry.value);
      }
      _beginMutation(changedValues, isPatch: true);
      await _cacheAction(
        () =>
            persistentCache?.applyServerMutation(changedValues, isPatch: true),
      );
      if (_bindAccount() != account) return;
      _notifyWritten(
        changed,
        explicitValues: changedValues,
        isPatch: true,
        recorded: true,
      );
    } catch (e) {
      throw Exception('Failed to PATCH $path: $e');
    }
  }

  /// Conditional replacement: applies only while the node matches [etag].
  ///
  /// Returns `false` when the server rejects the write because the node was
  /// changed by another terminal (HTTP 412 Precondition Failed). Used for
  /// concurrency-safe bed allocation.
  Future<bool> putIfMatch(
    String path,
    Map<String, dynamic> data,
    String etag,
  ) async {
    final account = _bindAccount();
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final prepared = _prepareWrite(path, data, isPatch: false);
      final response = await _client.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'if-match': etag},
        body: json.encode(prepared),
      );

      if (response.statusCode == 200) {
        final resolved = _decodeWriteResponse(response.body, prepared);
        if (_bindAccount() != account) return true;
        if (path != 'patients') _latestValues[path] = resolved;
        _beginMutation({path: resolved}, isPatch: false);
        await _cacheAction(
          () => persistentCache?.applyServerMutation({
            path: resolved,
          }, isPatch: false),
        );
        if (_bindAccount() != account) return true;
        _notifyWritten(
          [path],
          explicitValues: {path: resolved},
          isPatch: false,
          recorded: true,
        );
        return true;
      }
      if (response.statusCode == 412) return false;
      throw Exception(
        'Conditional PUT failed: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
      throw Exception('Failed conditional PUT $path: $e');
    }
  }

  // ===========================================================================
  // POST — Push new data (generates unique key)
  // ===========================================================================

  /// Push new data to a path (generates a unique push key)
  /// Returns the generated key
  Future<String> push(String path, Map<String, dynamic> data) async {
    final account = _bindAccount();
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final prepared = _prepareWrite(path, data, isPatch: false);
      final response = await _client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(prepared),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final key = result['name'] as String;
        final newPath = '$path/$key';
        // Firebase POST returns only the generated key. A targeted read obtains
        // the resolved server timestamp without downloading the collection.
        final stored = await get(newPath);
        final resolved = stored is Map
            ? Map<String, dynamic>.from(stored)
            : prepared;
        if (_bindAccount() != account) return key;
        _latestValues[newPath] = resolved;
        _beginMutation({newPath: resolved}, isPatch: false);
        await _cacheAction(
          () => persistentCache?.applyServerMutation({
            newPath: resolved,
          }, isPatch: false),
        );
        if (_bindAccount() != account) return key;
        _notifyWritten(
          [newPath],
          explicitValues: {newPath: resolved},
          isPatch: false,
          recorded: true,
        );
        return key; // Firebase returns {"name": "pushKey"}
      } else {
        throw Exception(
          'POST failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to POST $path: $e');
    }
  }

  // ===========================================================================
  // DELETE — Remove data
  // ===========================================================================

  /// Delete data at a specific path
  Future<void> delete(String path) async {
    final account = _bindAccount();
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await _client.delete(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception(
          'DELETE failed: ${response.statusCode} - ${response.body}',
        );
      }
      if (_bindAccount() != account) return;
      if (path != 'patients') _latestValues.remove(path);
      _beginMutation({path: null}, isPatch: false);
      await _cacheAction(
        () =>
            persistentCache?.applyServerMutation({path: null}, isPatch: false),
      );
      if (_bindAccount() != account) return;
      _notifyWritten(
        [path],
        explicitValues: {path: null},
        isPatch: false,
        recorded: true,
      );
    } catch (e) {
      throw Exception('Failed to DELETE $path: $e');
    }
  }

  // ===========================================================================
  // WRITE INVALIDATION — independent of mutation completion
  // ===========================================================================

  /// Updates the cached value for an exact path after a local write, so the
  /// UI never flashes stale data while the shared resource refreshes.
  void _mergeIntoCache(String changedPath, dynamic value) {
    if (changedPath == 'patients') return;
    if (!_latestValues.containsKey(changedPath)) return;
    final current = _latestValues[changedPath];
    if (current is Map && value is Map) {
      _latestValues[changedPath] = {...current, ...value};
    } else {
      _latestValues[changedPath] = value;
    }
  }

  /// Recursively sets a nested field in a map, creating intermediate maps as
  /// needed. Used for field-level cache merging.
  void _setNestedField(
    Map<String, dynamic> map,
    List<String> path,
    dynamic value,
  ) {
    if (path.length == 1) {
      if (value == null) {
        map.remove(path[0]);
      } else {
        map[path[0]] = value;
      }
      return;
    }
    final existing = map[path[0]];
    final nested = existing is Map
        ? Map<String, dynamic>.from(existing)
        : existing is List
        ? {
            for (final entry in existing.asMap().entries)
              entry.key.toString(): entry.value,
          }
        : <String, dynamic>{};
    _setNestedField(nested, path.sublist(1), value);
    map[path[0]] = nested;
  }

  /// Schedules an independent refresh of every shared resource that overlaps
  /// the written paths. Runs after the mutation has already completed, so a
  /// write never blocks on other screens' refetches.
  ///
  /// For single-record writes against a collection (e.g. `patients/abc`), the
  /// change is merged directly into the cached collection and emitted to
  /// listeners without downloading the entire collection again. The next
  /// natural polling cycle will reconcile with the server.
  void _notifyWritten(
    List<String> changedPaths, {
    Map<String, dynamic>? explicitValues,
    bool isPatch = false,
    bool recorded = false,
  }) {
    _bindAccount();
    if (!recorded) {
      _beginMutation({
        for (final path in changedPaths)
          path: explicitValues != null && explicitValues.containsKey(path)
              ? explicitValues[path]
              : _latestValues[path],
      }, isPatch: isPatch);
    }
    _publishPatients();
    for (final resource in _resources.values) {
      if (resource._isCanonicalPatients) {
        if (_patients.value == null && changedPaths.any(resource.overlaps)) {
          unawaited(resource.rehydratePersistent());
        }
        continue;
      }
      if (changedPaths.any((changed) => resource.overlaps(changed))) {
        final relevantPaths = changedPaths
            .where((changed) => resource.overlaps(changed))
            .toList();
        var allMerged = true;
        for (final changed in relevantPaths) {
          final val =
              explicitValues != null && explicitValues.containsKey(changed)
              ? explicitValues[changed]
              : _latestValues[changed];
          final ok = resource.applyChildMutation(
            changed,
            val,
            isPatch: isPatch,
          );
          if (!ok) {
            allMerged = false;
            break;
          }
        }
        if (!allMerged) {
          // The acknowledged mutation is already in SQLite. Rehydrate the
          // affected local view instead of invalidating a whole collection.
          unawaited(resource.rehydratePersistent());
        }
      }
    }
  }

  static const Map<String, String> _serverTimestamp = {'.sv': 'timestamp'};

  /// Adds authoritative Firebase server timestamps to synchronized entities.
  /// This is applied centrally so root multi-path writes cannot accidentally
  /// omit the synchronization contract.
  Map<String, dynamic> _prepareWrite(
    String path,
    Map<String, dynamic> input, {
    required bool isPatch,
  }) {
    final data = Map<String, dynamic>.from(input);
    final clean = path.replaceFirst(RegExp(r'^/+'), '');
    if (clean.isEmpty && isPatch) {
      final timestampPaths = <String, String>{};
      final parentKeys = data.keys.toSet();
      for (final entry in data.entries) {
        if (entry.value == null) continue;
        final record = _synchronizedRecordPath(entry.key);
        if (record != null && !entry.key.endsWith('/updatedAt')) {
          timestampPaths[record] = '$record/updatedAt';
        }
      }
      for (final entry in timestampPaths.entries) {
        final record = entry.key;
        final tsPath = entry.value;
        // BUG #4 FIX: If the parent record path is already in the payload
        // as a full object, embed updatedAt inside it instead of creating a
        // separate child path that would cause Firebase to reject the
        // overlapping multi-path PATCH with HTTP 400.
        if (parentKeys.contains(record) && data[record] is Map) {
          final parentMap = Map<String, dynamic>.from(data[record] as Map);
          parentMap['updatedAt'] = _serverTimestamp;
          data[record] = parentMap;
        } else {
          data[tsPath] = _serverTimestamp;
        }
      }
      return data;
    }

    final record = _synchronizedRecordPath(clean);
    if (record == null) return data;
    final parts = clean.split('/');
    final recordParts = record.split('/');
    if (parts.length == recordParts.length) {
      data['updatedAt'] = _serverTimestamp;
    }
    return data;
  }

  String? _synchronizedRecordPath(String path) {
    final clean = path.replaceFirst(RegExp(r'^/+'), '');
    final parts = clean.split('/');
    if (parts.isEmpty) return null;
    if (const {
          'patients',
          'stays',
          'rooms',
          'payments',
          'paymentHistory',
          'users',
        }.contains(parts.first) &&
        parts.length >= 2) {
      return '${parts[0]}/${parts[1]}';
    }
    if ((parts.first == 'attendance' ||
            parts.first == 'attendant_attendance') &&
        parts.length >= 4 &&
        parts[1] == 'daily') {
      final length = parts.first == 'attendance'
          ? 4
          : math.min(5, parts.length);
      return parts.take(length).join('/');
    }
    if (parts.first == 'patientPhotos' && parts.length >= 3) {
      final length = parts.length >= 4 && parts[2] == 'attendants' ? 4 : 3;
      return parts.take(length).join('/');
    }
    return null;
  }

  Map<String, dynamic> _decodeWriteResponse(
    String body,
    Map<String, dynamic> fallback,
  ) {
    if (body.isEmpty || body == 'null') return fallback;
    try {
      final value = json.decode(body);
      if (value is Map) {
        return {...fallback, ...Map<String, dynamic>.from(value)};
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// A local cache failure must not turn an acknowledged Firebase operation
  /// into an application-level server failure. SQLite is disposable and will
  /// be rebuilt from RTDB after recovery.
  Future<void> _cacheAction(Future<void>? Function() action) async {
    try {
      await action();
    } catch (error) {
      persistentCache?.markDegraded(error);
      // Disk full, corruption, and migration failures degrade cache only.
    }
  }

  Future<dynamic> _cacheValue(Future<dynamic>? Function() read) async {
    try {
      return await read();
    } catch (error) {
      persistentCache?.markDegraded(error);
      return null;
    }
  }

  // ===========================================================================
  // STREAM — shared resource-level realtime updates
  // ===========================================================================

  /// Returns a shared stream for [path]. Every consumer of the same path
  /// shares ONE polling subscription; the latest known value is replayed to
  /// new subscribers immediately so `.first`-style callers never hang.
  Stream<dynamic> stream(String path, {Duration? pollInterval}) {
    final interval = pollInterval ?? Duration(seconds: _pollingInterval);
    final key = '$path|${interval.inMilliseconds}';
    return _resource(
      key,
      path,
      path,
      interval,
      () => get(path),
      ssePath: path,
      hydrate: persistentCache == null
          ? null
          : () => persistentCache!.read(path),
    );
  }

  /// Subscribe to several exact indexed values and merge their bounded maps.
  /// Each exact query uses one shared SSE connection, so this never falls back
  /// to a 10-second multi-megabyte collection polling loop.
  Stream<dynamic> queryAnyStream(
    String path, {
    required String orderBy,
    required List<dynamic> equalToAny,
    Duration? pollInterval,
  }) {
    final values = equalToAny.toSet().toList(growable: false);
    if (values.isEmpty) return Stream<dynamic>.value(<String, dynamic>{});
    return Stream<dynamic>.multi((controller) {
      final latest = <dynamic, Map<String, dynamic>>{};
      final subscriptions = <StreamSubscription<dynamic>>[];

      void emitIfReady() {
        if (latest.length != values.length) return;
        final merged = <String, dynamic>{};
        for (final value in values) {
          merged.addAll(latest[value]!);
        }
        controller.add(merged);
      }

      for (final value in values) {
        final subscription =
            queryStream(
              path,
              orderBy: orderBy,
              equalTo: value,
              pollInterval: pollInterval,
            ).listen((snapshot) {
              latest[value] = snapshot is Map
                  ? Map<String, dynamic>.from(snapshot)
                  : <String, dynamic>{};
              emitIfReady();
            }, onError: controller.addError);
        subscriptions.add(subscription);
      }
      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  Stream<dynamic> _resource(
    String key,
    String invalidationPath,
    String cacheKey,
    Duration interval,
    Future<dynamic> Function() fetch, {
    bool errorOnInitialFailure = false,
    String? ssePath,
    String? queryOrderBy,
    dynamic queryEqualTo,
    Map<String, String>? sseQueryParameters,
    Future<dynamic> Function()? hydrate,
  }) {
    _bindAccount();
    return _resources
        .putIfAbsent(
          key,
          () => _SharedResource(
            service: this,
            key: key,
            invalidationPath: invalidationPath,
            cacheKey: cacheKey,
            ssePath: ssePath,
            queryOrderBy: queryOrderBy,
            queryEqualTo: queryEqualTo,
            sseQueryParameters: sseQueryParameters,
            pollInterval: interval,
            fetch: fetch,
            hydrate: hydrate,
            errorOnInitialFailure: errorOnInitialFailure,
            initialHasValue:
                _latestValues.containsKey(cacheKey) &&
                (cacheKey != 'patients' || _patients.value != null),
            initialValue: _latestValues.containsKey(cacheKey)
                ? _latestValues[cacheKey]
                : null,
          ),
        )
        .stream;
  }

  // ===========================================================================
  // QUERY — Filtered queries
  // ===========================================================================

  /// Query with orderBy and equalTo filters
  Future<dynamic> query(
    String path, {
    String? orderBy,
    dynamic equalTo,
    dynamic startAt,
    dynamic endAt,
    int? limitToFirst,
    int? limitToLast,
  }) async {
    final bounds = _boundedExpectedDischargeQuery(
      path: path,
      orderBy: orderBy,
      equalTo: equalTo,
      startAt: startAt,
      endAt: endAt,
      limitToFirst: limitToFirst,
      limitToLast: limitToLast,
    );
    try {
      final token = await _getIdToken();
      final baseUrl = Uri.parse(_buildUrl(path));

      final params = <String, String>{};
      if (token != null) params['auth'] = token;
      if (orderBy != null) params['orderBy'] = json.encode(orderBy);
      if (equalTo != null) {
        params['equalTo'] = json.encode(equalTo);
      }
      if (bounds.startAt != null) {
        params['startAt'] = json.encode(bounds.startAt);
      }
      if (bounds.endAt != null) {
        params['endAt'] = json.encode(bounds.endAt);
      }
      if (bounds.limitToFirst != null) {
        params['limitToFirst'] = '${bounds.limitToFirst}';
      }
      if (bounds.limitToLast != null) {
        params['limitToLast'] = '${bounds.limitToLast}';
      }

      final response = await _client
          .get(baseUrl.replace(queryParameters: params))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Request timeout - check your internet connection',
            ),
          );

      if (response.statusCode == 200) {
        final value = response.body == 'null'
            ? null
            : json.decode(response.body);
        await _cacheAction(() async {
          await persistentCache?.mergeQuerySnapshot(path, value);
          await persistentCache?.markSynced(path.split('/').first);
        });
        return value;
      } else {
        throw Exception(
          'Query failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      await _cacheAction(
        () => persistentCache?.markOffline(path.split('/').first, e),
      );
      var cached = await _cacheValue(
        () => persistentCache?.read(path, orderBy: orderBy, equalTo: equalTo),
      );
      cached = _applyQueryBounds(
        cached,
        orderBy: orderBy,
        startAt: bounds.startAt,
        endAt: bounds.endAt,
        limitToFirst: bounds.limitToFirst,
        limitToLast: bounds.limitToLast,
      );
      if (cached is Map && cached.isNotEmpty) return cached;
      throw Exception('Failed to query $path: $e');
    }
  }

  /// Shared filtered SSE query. SQLite is hydrated first; the SSE snapshot is
  /// authoritative. REST is used once only when SSE cannot be established.
  Stream<dynamic> queryStream(
    String path, {
    String? orderBy,
    dynamic equalTo,
    int? limitToFirst,
    int? limitToLast,
    Duration? pollInterval,
  }) {
    final bounds = _boundedExpectedDischargeQuery(
      path: path,
      orderBy: orderBy,
      equalTo: equalTo,
      startAt: null,
      endAt: null,
      limitToFirst: limitToFirst,
      limitToLast: limitToLast,
    );
    final interval = pollInterval ?? Duration(seconds: _pollingInterval);
    final queryParameters = <String, String>{
      if (orderBy != null) 'orderBy': json.encode(orderBy),
      if (equalTo != null) 'equalTo': json.encode(equalTo),
      if (bounds.startAt != null) 'startAt': json.encode(bounds.startAt),
      if (bounds.endAt != null) 'endAt': json.encode(bounds.endAt),
      if (bounds.limitToFirst != null) 'limitToFirst': '${bounds.limitToFirst}',
      if (bounds.limitToLast != null) 'limitToLast': '${bounds.limitToLast}',
    };
    final cacheKey = '$path|${json.encode(queryParameters)}';
    final key = '$cacheKey|${interval.inMilliseconds}';
    return _resource(
      key,
      path,
      cacheKey,
      interval,
      () => query(
        path,
        orderBy: orderBy,
        equalTo: equalTo,
        startAt: bounds.startAt,
        endAt: bounds.endAt,
        limitToFirst: bounds.limitToFirst,
        limitToLast: bounds.limitToLast,
      ),
      errorOnInitialFailure: true,
      ssePath: path,
      queryOrderBy: orderBy,
      queryEqualTo: equalTo,
      sseQueryParameters: queryParameters,
      hydrate: persistentCache == null
          ? null
          : () async => _applyQueryBounds(
              await persistentCache!.read(
                path,
                orderBy: orderBy,
                equalTo: equalTo,
              ),
              orderBy: orderBy,
              startAt: bounds.startAt,
              endAt: bounds.endAt,
              limitToFirst: bounds.limitToFirst,
              limitToLast: bounds.limitToLast,
            ),
    );
  }

  _QueryBounds _boundedExpectedDischargeQuery({
    required String path,
    required String? orderBy,
    required dynamic equalTo,
    required dynamic startAt,
    required dynamic endAt,
    required int? limitToFirst,
    required int? limitToLast,
  }) {
    if (path == 'stays' &&
        orderBy == 'expectedDischargeDate' &&
        equalTo == null &&
        startAt == null &&
        endAt == null &&
        limitToFirst == null &&
        limitToLast == null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return _QueryBounds(
        startAt: today.millisecondsSinceEpoch,
        endAt: today.add(const Duration(days: 90)).millisecondsSinceEpoch,
        limitToFirst: 200,
      );
    }
    return _QueryBounds(
      startAt: startAt,
      endAt: endAt,
      limitToFirst: limitToFirst,
      limitToLast: limitToLast,
    );
  }

  dynamic _applyQueryBounds(
    dynamic value, {
    required String? orderBy,
    required dynamic startAt,
    required dynamic endAt,
    required int? limitToFirst,
    required int? limitToLast,
  }) {
    if (value is! Map || orderBy == null) return value;
    final entries = value.entries.where((entry) {
      final record = entry.value;
      if (record is! Map) return false;
      final indexed = record[orderBy];
      if (startAt != null && indexed is Comparable) {
        if (indexed.compareTo(startAt) < 0) return false;
      }
      if (endAt != null && indexed is Comparable) {
        if (indexed.compareTo(endAt) > 0) return false;
      }
      return true;
    }).toList();
    entries.sort((a, b) {
      final left = a.value is Map ? (a.value as Map)[orderBy] : null;
      final right = b.value is Map ? (b.value as Map)[orderBy] : null;
      if (left is Comparable && right != null) return left.compareTo(right);
      return 0;
    });
    Iterable<MapEntry<dynamic, dynamic>> selected = entries;
    if (limitToFirst != null) selected = selected.take(limitToFirst);
    if (limitToLast != null) {
      selected = entries.skip(math.max(0, entries.length - limitToLast));
    }
    return <String, dynamic>{
      for (final entry in selected) entry.key.toString(): entry.value,
    };
  }

  // ===========================================================================
  // RETRY & CLEANUP
  // ===========================================================================

  /// Retry all active resources (resets backoff and resumes suspended queries)
  void retryAll() {
    for (final resource in _resources.values) {
      resource.retry();
    }
  }

  /// Retry resources matching a specific path
  void retryPath(String path) {
    for (final entry in _resources.entries) {
      if (entry.value.invalidationPath == path ||
          entry.key.startsWith('$path|')) {
        entry.value.retry();
      }
    }
  }

  void _removeResource(String key) {
    _resources.remove(key);
  }

  /// Dispose all shared resource streams
  void dispose() {
    _accountSubscription?.cancel();
    for (final resource in _resources.values) {
      resource.dispose();
    }
    _resources.clear();
    _ownedClient?.close();
    _ownedClient = null;
  }
}

/// Value + ETag pair returned by [FirebaseRTDBRestService.getWithEtag].
class RtdbValue {
  final dynamic value;
  final String? etag;
  RtdbValue(this.value, this.etag);
}

class _QueryBounds {
  final dynamic startAt;
  final dynamic endAt;
  final int? limitToFirst;
  final int? limitToLast;

  const _QueryBounds({
    this.startAt,
    this.endAt,
    this.limitToFirst,
    this.limitToLast,
  });
}

/// One reference-counted polling subscription shared by all consumers of the
/// same resource path.
class _QueuedSseEvent {
  const _QueuedSseEvent(
    this.type,
    this.path,
    this.data,
    this.connectionGeneration,
    this.accountGeneration,
    this.patientTicket,
  );
  final String type;
  final String path;
  final dynamic data;
  final int connectionGeneration;
  final int accountGeneration;
  final PatientSnapshotTicket? patientTicket;
}

class _SharedResource {
  final FirebaseRTDBRestService service;
  final String key;
  final String invalidationPath;
  final String cacheKey;
  final String? ssePath;
  final String? queryOrderBy;
  final dynamic queryEqualTo;
  final Map<String, String> sseQueryParameters;
  final Duration pollInterval;
  final Future<dynamic> Function() fetch;
  final Future<dynamic> Function()? hydrate;
  final bool errorOnInitialFailure;

  late StreamController<dynamic> _controller;
  Timer? _timer;
  Timer? _refreshDebounce;
  Timer? _evictionTimer;
  bool _isFetching = false;
  bool _hasValue = false;
  int _revision = 0;
  dynamic _latest;

  bool _isSuspended = false;
  int _failureCount = 0;
  dynamic _lastError;
  StackTrace? _lastStackTrace;
  bool _sseConnected = false;
  bool _fallbackReconciled = false;

  bool get _isFilteredQuery => queryOrderBy != null;
  bool get _isCanonicalPatients =>
      invalidationPath == 'patients' &&
      !_isFilteredQuery &&
      sseQueryParameters.isEmpty;
  int _resourceGeneration = 0;

  void resetAccount() {
    _resourceGeneration++;
    _revision++;
    _hasValue = false;
    _latest = null;
    _rehydrateFuture = null;
    _closeSse();
    if (_controller.hasListener) {
      unawaited(rehydratePersistent());
      unawaited(_startSse());
    }
  }

  bool get isSuspended => _isSuspended;
  dynamic get lastError => _lastError;
  StackTrace? get lastStackTrace => _lastStackTrace;

  _SharedResource({
    required this.service,
    required this.key,
    required this.invalidationPath,
    required this.cacheKey,
    required this.ssePath,
    required this.queryOrderBy,
    required this.queryEqualTo,
    required Map<String, String>? sseQueryParameters,
    required this.pollInterval,
    required this.fetch,
    required this.hydrate,
    required this.errorOnInitialFailure,
    required bool initialHasValue,
    required dynamic initialValue,
  }) : sseQueryParameters = sseQueryParameters ?? const {} {
    _hasValue = initialHasValue;
    _latest = initialValue;
    _controller = StreamController<dynamic>.broadcast(
      onListen: () {
        _cancelEviction();
        if (!_isSuspended) {
          if (ssePath != null) {
            _startSse();
          } else {
            refreshSoon();
            _startPollingTimer();
          }
        }
      },
      onCancel: () {
        _stopPollingTimer();
        _refreshDebounce?.cancel();
        _refreshDebounce = null;
        _closeSse();
        _scheduleEviction();
      },
    );
    _hydratePersistent();
  }

  Future<void> _hydratePersistent() => rehydratePersistent();

  Future<void>? _rehydrateFuture;

  Future<void> rehydratePersistent() async {
    final loader = hydrate;
    if (loader == null || _controller.isClosed) return;
    if (_rehydrateFuture != null) return _rehydrateFuture!;
    final account = service._bindAccount();
    final generation = _resourceGeneration;
    final revision = _revision;
    final ticket = _isCanonicalPatients
        ? service._patients.capture(hydrating: true)
        : null;
    var retry = false;
    final future = () async {
      try {
        final value = _isCanonicalPatients
            ? await service.persistentCache?.readCanonicalPatients()
            : await loader();
        if (_controller.isClosed ||
            service._bindAccount() != account ||
            generation != _resourceGeneration) {
          return;
        }
        if (ticket != null) {
          if (value is! CanonicalPatientCacheSnapshot ||
              value.accountGeneration != account) {
            return;
          }
          if (!service._patients.isCurrent(ticket)) {
            retry = value.complete && service._patients.value == null;
            return;
          }
          if (service._patients.publish(
            value.value,
            ticket,
            complete: value.complete,
          )) {
            service._publishPatients();
          }
        } else if (value != null && revision == _revision) {
          emitCachedValue(value);
        }
      } catch (_) {
        // The next authoritative SSE event remains the recovery path.
      } finally {
        if (generation == _resourceGeneration) {
          _rehydrateFuture = null;
          if (retry) unawaited(rehydratePersistent());
        }
      }
    }();
    _rehydrateFuture = future;
    return future;
  }

  void _startPollingTimer([Duration? customInterval]) {
    if (_isFilteredQuery) return;
    _stopPollingTimer();
    final interval = customInterval ?? pollInterval;
    _timer = Timer.periodic(interval, (_) => refreshSoon());
  }

  void _stopPollingTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleEviction() {
    _evictionTimer?.cancel();
    _evictionTimer = Timer(const Duration(seconds: 15), () {
      if (!_controller.hasListener) {
        service._removeResource(key);
        dispose();
      }
    });
  }

  void _cancelEviction() {
    _evictionTimer?.cancel();
    _evictionTimer = null;
  }

  static bool _isNonTransientError(dynamic error) {
    final str = error.toString().toLowerCase();
    return str.contains('index not defined') ||
        str.contains('400') ||
        str.contains('bad request') ||
        str.contains('permission denied') ||
        str.contains('401') ||
        str.contains('403') ||
        str.contains('unauthorized');
  }

  /// Attach to the shared controller before replaying its latest value.
  /// This gives every subscriber, including `.first`, a current snapshot.
  /// When suspended after a non-transient error, replaying the stored error
  /// prevents late `.first` subscribers from hanging until timeout.
  Stream<dynamic> get stream {
    return Stream<dynamic>.multi((controller) {
      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      if (_hasValue) controller.add(_latest);
      if (_isSuspended && _lastError != null) {
        controller.addError(_lastError, _lastStackTrace);
      }
      controller.onCancel = subscription.cancel;
    });
  }

  /// True when [changedPath] touches this resource's data.
  bool overlaps(String changedPath) {
    if (changedPath == invalidationPath) return true;
    if (changedPath.startsWith('$invalidationPath/')) return true;
    if (invalidationPath.startsWith('$changedPath/')) return true;
    return false;
  }

  /// Debounced refresh: multiple writes in one batch trigger one fetch.
  void refreshSoon() {
    if (_controller.isClosed || _isSuspended) return;
    if (_refreshDebounce?.isActive ?? false) return;
    _refreshDebounce = Timer(const Duration(milliseconds: 50), () {
      _refreshDebounce = null;
      _refreshNow();
    });
  }

  void invalidate() {
    _revision++;
    if (_isSuspended) {
      _isSuspended = false;
      _failureCount = 0;
      if (!_isFilteredQuery) _startPollingTimer();
    }
    if (_isFilteredQuery) {
      unawaited(rehydratePersistent());
    } else {
      refreshSoon();
    }
  }

  /// Applies a child mutation directly into this resource's cache and emits
  /// the updated snapshot to listeners without a network round-trip.
  ///
  /// Returns `true` if the mutation was successfully applied locally.
  bool applyChildMutation(
    String childPath,
    dynamic value, {
    bool isPatch = false,
  }) {
    if (_controller.isClosed) return true;
    if (_isCanonicalPatients) {
      service._patients.mutate(
        childPath,
        value,
        isPatch: isPatch,
        acknowledged: false,
      );
      service._publishPatients();
      if (service._patients.value == null) unawaited(rehydratePersistent());
      return true;
    }
    if (childPath == invalidationPath) {
      if ((isPatch || _isFilteredQuery) && value is Map) {
        for (final entry in value.entries) {
          applyChildMutation(
            '$childPath/${entry.key}',
            entry.value,
            isPatch: isPatch,
          );
        }
        return true;
      }
      if (_isFilteredQuery) {
        unawaited(rehydratePersistent());
        return true;
      }
      emitCachedValue(value);
      return true;
    }
    if (!childPath.startsWith('$invalidationPath/')) return false;

    final suffix = childPath.substring(invalidationPath.length + 1);
    final cached = service._latestValues[cacheKey];
    final parts = suffix.split('/');
    final recordKey = parts[0];

    // BUG #1 FIX: When the in-memory cache has been evicted (cached is null),
    // we must NOT fabricate an empty map — that would collapse the entire
    // collection to just the one mutated record. Instead, schedule a full
    // rehydration from SQLite (which still has the complete dataset) and
    // skip the optimistic local merge for this event.
    if (cached is! Map) {
      unawaited(rehydratePersistent());
      return true;
    }
    final updatedMap = Map<String, dynamic>.from(cached);

    if (_isFilteredQuery) {
      dynamic existing = updatedMap[recordKey];
      if (existing is! Map) {
        final canonical = service._latestValues[invalidationPath];
        if (canonical is Map && canonical[recordKey] is Map) {
          existing = Map<String, dynamic>.from(canonical[recordKey] as Map);
        }
      }
      Map<String, dynamic>? candidate;
      if (parts.length == 1) {
        if (value is Map) {
          candidate = isPatch && existing is Map
              ? {...Map<String, dynamic>.from(existing), ...value}
              : Map<String, dynamic>.from(value);
        }
      } else if (existing is Map) {
        candidate = Map<String, dynamic>.from(existing);
        service._setNestedField(candidate, parts.sublist(1), value);
      }

      if (candidate != null && candidate[queryOrderBy] == queryEqualTo) {
        updatedMap[recordKey] = candidate;
      } else {
        updatedMap.remove(recordKey);
        if (candidate == null && value != null) {
          unawaited(rehydratePersistent());
        }
      }
      emitCachedValue(updatedMap);
      return true;
    }

    if (parts.length == 1) {
      if (value == null) {
        // DELETE
        updatedMap.remove(recordKey);
      } else if (isPatch) {
        // PATCH: merge changed fields
        final existing = updatedMap[recordKey];
        if (existing is Map && value is Map) {
          updatedMap[recordKey] = {
            ...Map<String, dynamic>.from(existing),
            ...value,
          };
        } else {
          updatedMap[recordKey] = value;
        }
      } else {
        // PUT / PUSH: replace affected record
        updatedMap[recordKey] = value;
      }
    } else {
      // Field-level write (e.g. patients/abc/status)
      final existingRecord = updatedMap[recordKey];
      if (existingRecord is! Map) {
        unawaited(rehydratePersistent());
        return true;
      }
      final updatedRecord = Map<String, dynamic>.from(existingRecord);
      service._setNestedField(updatedRecord, parts.sublist(1), value);
      updatedMap[recordKey] = updatedRecord;
    }

    service._latestValues[cacheKey] = updatedMap;
    emitCachedValue(updatedMap);
    return true;
  }

  /// Emits a locally-merged value to listeners without a network round-trip.
  /// The cache and latest snapshot are updated immediately.
  void emitCachedValue(dynamic value) {
    if (_controller.isClosed) return;
    if (_isCanonicalPatients) {
      value = service._patients.value;
      if (value == null) return;
    }
    service._latestValues[cacheKey] = value;
    if (!_hasValue || json.encode(value) != json.encode(_latest)) {
      _hasValue = true;
      _latest = value;
      _controller.add(value);
    }
  }

  void retry() {
    _isSuspended = false;
    _failureCount = 0;
    _lastError = null;
    _lastStackTrace = null;
    _fallbackReconciled = false;
    if (ssePath != null && _sseClient == null) {
      _startSse();
    } else if (ssePath == null) {
      _startPollingTimer();
      refreshSoon();
    }
  }

  Future<void> _refreshNow() async {
    if (_controller.isClosed || !_controller.hasListener || _isSuspended) {
      return;
    }
    if (_isFetching) {
      _revision++;
      return;
    }
    _isFetching = true;
    final revision = _revision;
    try {
      final value = await fetch();
      if (_controller.isClosed) return;
      if (revision != _revision) return;
      _failureCount = 0;
      _lastError = null;
      _lastStackTrace = null;
      _isSuspended = false;
      if (!_isFilteredQuery && !_sseConnected && _timer != null) {
        _startPollingTimer(pollInterval);
      }
      emitCachedValue(value);
    } catch (error, stackTrace) {
      _lastError = error;
      _lastStackTrace = stackTrace;
      if (_isNonTransientError(error)) {
        _isSuspended = true;
        _stopPollingTimer();
        _closeSse();
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      } else {
        _failureCount++;
        final backoffSeconds = math.min(
          pollInterval.inSeconds * (1 << math.min(_failureCount, 3)),
          60,
        );
        if (!_isFilteredQuery &&
            !_sseConnected &&
            !_controller.isClosed &&
            _controller.hasListener) {
          _startPollingTimer(Duration(seconds: backoffSeconds));
        }
        if (!_controller.isClosed && !_hasValue && errorOnInitialFailure) {
          _controller.addError(error, stackTrace);
        }
      }
    } finally {
      _isFetching = false;
      if (ssePath == null &&
          revision != _revision &&
          _controller.hasListener &&
          !_isSuspended) {
        refreshSoon();
      }
    }
  }

  void dispose() {
    _resourceGeneration++;
    _cancelEviction();
    _stopPollingTimer();
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _closeSse();
    if (!_controller.isClosed) _controller.close();
  }

  // ── SSE realtime channel ────────────────────────────────────────────────────
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  Timer? _sseRetryTimer;
  Future<void> _sseEventQueue = Future<void>.value();
  final bool _sseEnabled = true;
  int _sseFailures = 0;
  int _connectionGeneration = 0;
  bool _sseStarting = false;

  void _closeSse() {
    _connectionGeneration++;
    _sseStarting = false;
    _sseConnected = false;
    _sseRetryTimer?.cancel();
    _sseRetryTimer = null;
    _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;
  }

  Future<void> _startSse() async {
    if (!_sseEnabled ||
        _controller.isClosed ||
        !_controller.hasListener ||
        _isSuspended ||
        _sseStarting ||
        _sseClient != null) {
      return;
    }
    final account = service._bindAccount();
    final connection = ++_connectionGeneration;
    _sseStarting = true;
    try {
      final token = await service._getIdToken();
      if (connection != _connectionGeneration ||
          service._bindAccount() != account) {
        return;
      }
      if (token == null) {
        _scheduleSseRetry();
        return;
      }
      final cleanPath = ssePath!.startsWith('/')
          ? ssePath!.substring(1)
          : ssePath!;
      final client = service._createSseClient();
      _sseClient = client;
      final query = <String, String>{...sseQueryParameters, 'auth': token};
      final request = http.Request(
        'GET',
        Uri.parse(
          '${service.databaseUrl}/$cleanPath.json',
        ).replace(queryParameters: query),
      );
      request.headers['Accept'] = 'text/event-stream';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      if (_controller.isClosed ||
          !_controller.hasListener ||
          !identical(_sseClient, client)) {
        client.close();
        return;
      }
      if (response.statusCode != 200) {
        _closeSse();
        _scheduleSseRetry();
        return;
      }
      _sseConnected = true;
      _sseFailures = 0;
      _fallbackReconciled = false;
      // Pause redundant polling while SSE is healthy
      _stopPollingTimer();

      String? lastEvent;
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      _sseSub = lines.listen(
        (line) {
          if (line.isEmpty) return;
          if (line.startsWith('event: ')) {
            lastEvent = line.substring(7).trim();
            if (lastEvent == 'auth_revoked' || lastEvent == 'cancel') {
              _closeSse();
              _scheduleSseRetry();
            }
            return;
          }
          if (line.startsWith('data: ')) {
            if (lastEvent == 'keep-alive') return;
            final jsonPayload = line.substring(6).trim();
            try {
              final decoded = json.decode(jsonPayload);
              final type = lastEvent;
              if (decoded is Map &&
                  decoded.containsKey('data') &&
                  (type == 'put' || type == 'patch')) {
                final queued = _QueuedSseEvent(
                  type!,
                  decoded['path']?.toString() ?? '/',
                  decoded['data'],
                  connection,
                  account,
                  _isCanonicalPatients ? service._patients.capture() : null,
                );
                _sseEventQueue = _sseEventQueue
                    .then((_) => _applySseEvent(queued))
                    .catchError((_) {});
              }
            } catch (_) {}
          }
        },
        onError: (Object _) {
          if (connection != _connectionGeneration) return;
          _closeSse();
          _scheduleSseRetry();
        },
        onDone: () {
          if (connection != _connectionGeneration) return;
          _closeSse();
          _scheduleSseRetry();
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (connection != _connectionGeneration) return;
      _closeSse();
      _scheduleSseRetry();
    } finally {
      if (connection == _connectionGeneration) _sseStarting = false;
    }
  }

  void _scheduleSseRetry() {
    _sseConnected = false;
    // A failed connection gets one REST reconciliation. Filtered resources do
    // not start a periodic GET loop; exponential SSE reconnect remains active.
    if (!_isSuspended && !_controller.isClosed && _controller.hasListener) {
      if (!_fallbackReconciled) {
        _fallbackReconciled = true;
        refreshSoon();
      }
      if (!_isFilteredQuery) _startPollingTimer();
    }
    if (_controller.isClosed ||
        !_controller.hasListener ||
        !_sseEnabled ||
        _isSuspended) {
      return;
    }
    if (_sseRetryTimer?.isActive ?? false) return;
    _sseFailures++;
    final shift = math.min(_sseFailures, 5);
    final delay = Duration(seconds: 2 << shift);
    _sseRetryTimer = Timer(delay, _startSse);
  }

  Future<void> _applySseEvent(_QueuedSseEvent queued) async {
    bool current() =>
        !_controller.isClosed &&
        queued.connectionGeneration == _connectionGeneration &&
        queued.accountGeneration == service._bindAccount();
    if (!current()) return;
    final relativePath = queued.path;
    final data = queued.data;
    final isPatch = queued.type == 'patch';

    if (relativePath == '/' && !isPatch) {
      if (_isCanonicalPatients) {
        await service._acceptPatientsSnapshot(
          data,
          queued.patientTicket!,
          connectionCurrent: current,
        );
        return;
      }
      final revision = ++_revision;
      await service._cacheAction(() async {
        if (_isFilteredQuery) {
          await service.persistentCache?.mergeQuerySnapshot(ssePath!, data);
        } else {
          await service.persistentCache?.replaceSnapshot(
            ssePath!,
            data,
            isCurrent: () => current() && revision == _revision,
          );
        }
        await service.persistentCache?.markSynced(ssePath!.split('/').first);
      });
      if (current() && revision == _revision) emitCachedValue(data);
      return;
    }

    if (relativePath == '/' && isPatch && data is Map) {
      for (final entry in data.entries) {
        await _applySseMutation(
          '$ssePath/${entry.key}',
          entry.value,
          isPatch: true,
          isCurrent: current,
          ticket: queued.patientTicket,
        );
      }
      return;
    }

    final suffix = relativePath.replaceFirst(RegExp(r'^/+'), '');
    final changedPath = suffix.isEmpty ? ssePath! : '$ssePath/$suffix';
    await _applySseMutation(
      changedPath,
      data,
      isPatch: isPatch,
      isCurrent: current,
      ticket: queued.patientTicket,
    );
  }

  Future<void> _applySseMutation(
    String changedPath,
    dynamic value, {
    required bool isPatch,
    required bool Function() isCurrent,
    PatientSnapshotTicket? ticket,
  }) async {
    if (!isCurrent()) return;
    // A null child in a filtered RTDB stream can mean "left the query", not
    // deletion from the canonical collection. Remove it only from this view.
    if (_isFilteredQuery && value == null) {
      applyChildMutation(changedPath, null, isPatch: false);
      return;
    }

    service._beginMutation(
      {changedPath: value},
      isPatch: isPatch,
      acknowledged: false,
      ticket: ticket,
    );
    var cacheChanges = <String, dynamic>{changedPath: value};
    var cachePatch = isPatch;
    final canonical = service._patients.value;
    if (canonical != null && changedPath.startsWith('patients/')) {
      // Persist the same one-record reconciliation as memory, including any
      // still-unconfirmed ACK fields, rather than an obsolete server echo.
      final id = changedPath.split('/')[1];
      cacheChanges = {'patients/$id': canonical[id]};
      cachePatch = false;
    }
    await service._cacheAction(
      () => service.persistentCache?.applyServerMutation(
        cacheChanges,
        isPatch: cachePatch,
      ),
    );
    if (!isCurrent()) return;
    service._notifyWritten(
      [changedPath],
      explicitValues: {changedPath: value},
      isPatch: isPatch,
      recorded: true,
    );
  }
}
