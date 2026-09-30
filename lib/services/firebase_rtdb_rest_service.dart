import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Firebase Realtime Database REST API Service
///
/// Provides CRUD operations and resource-level realtime streams without
/// requiring the native Firebase Database SDK. Works on ALL platforms
/// including Windows desktop.
///
/// Architecture (production fixes):
/// - One shared, reference-counted polling stream per resource path. Every
///   consumer of the same path shares a single network subscription instead
///   of each screen/widget starting its own 10-second timer.
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
  http.Client? _ownedClient;

  http.Client get _client => _injectedClient ?? (_ownedClient ??= http.Client());

  // Polling interval for resource streams (in seconds)
  static const int _pollingInterval = 10;

  // One shared resource stream per path+interval.
  final Map<String, _SharedResource> _resources = {};

  // Keep the latest successful value per path so moving between screens does
  // not flash an empty state while the same Firebase data is downloaded again.
  final Map<String, dynamic> _latestValues = {};

  FirebaseRTDBRestService({
    required this.projectId,
    String? databaseUrl,
    this.getAuthToken,
    http.Client? httpClient,
  })  : _injectedClient = httpClient,
        databaseUrl =
            databaseUrl ?? 'https://$projectId-default-rtdb.firebaseio.com';

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
        if (!path.startsWith('patientPhotos/')) _latestValues[path] = value;
        return value;
      } else {
        throw Exception(
          'GET failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to GET $path: $e');
    }
  }

  /// Value of a snapshot together with its ETag, for conditional writes.
  Future<RtdbValue> getWithEtag(String path) async {
    try {
      final token = await _getIdToken();
      final url = Uri.parse(_buildUrl(path, auth: token));
      final response = await _client.get(
        url,
        headers: {'X-Firebase-ETag': 'true'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception(
          'Request timeout - check your internet connection',
        ),
      );
      if (response.statusCode == 200) {
        final value = response.body == 'null'
            ? null
            : json.decode(response.body);
        _latestValues[path] = value;
        final etag = response.headers['etag'];
        if (etag == null || etag.isEmpty) {
          throw StateError('Firebase did not return an ETag for $path');
        }
        return RtdbValue(value, etag);
      }
      throw Exception(
        'GET failed: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
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
        return response.body == 'null' ? null : json.decode(response.body);
      }
      throw Exception(
        'GET range failed: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
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
        return response.body == 'null' ? null : json.decode(response.body);
      }
      throw Exception(
        'GET filtered data failed: ${response.statusCode} - ${response.body}',
      );
    } catch (e) {
      throw Exception('Failed to GET filtered $path: $e');
    }
  }

  // ===========================================================================
  // WRITE — Write/Replace data
  // ===========================================================================

  /// Write data to a specific path (replaces existing data)
  Future<void> put(String path, Map<String, dynamic> data) async {
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await _client.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'PUT failed: ${response.statusCode} - ${response.body}',
        );
      }
      if (!path.startsWith('patientPhotos/')) _latestValues[path] = data;
      _notifyWritten([path]);
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
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await _client.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updates),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'PATCH failed: ${response.statusCode} - ${response.body}',
        );
      }
      final changed = <String>[];
      for (final entry in updates.entries) {
        final changedPath = path.isEmpty ? entry.key : '$path/${entry.key}';
        changed.add(changedPath);
        _mergeIntoCache(changedPath, entry.value);
      }
      _notifyWritten(changed);
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
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await _client.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'if-match': etag,
        },
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        _latestValues[path] = data;
        _notifyWritten([path]);
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
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await _client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final key = result['name'] as String;
        _notifyWritten(['$path/$key']);
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
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await _client.delete(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception(
          'DELETE failed: ${response.statusCode} - ${response.body}',
        );
      }
      _latestValues.remove(path);
      _notifyWritten([path]);
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
    if (!_latestValues.containsKey(changedPath)) return;
    final current = _latestValues[changedPath];
    if (current is Map && value is Map) {
      _latestValues[changedPath] = {...current, ...value};
    } else {
      _latestValues[changedPath] = value;
    }
  }

  /// Schedules an independent refresh of every shared resource that overlaps
  /// the written paths. Runs after the mutation has already completed, so a
  /// write never blocks on other screens' refetches.
  void _notifyWritten(List<String> changedPaths) {
    for (final resource in _resources.values) {
      if (changedPaths.any((changed) => resource.overlaps(changed))) {
        resource.invalidate();
      }
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
    );
  }

  /// Poll a child-indexed query for several exact values and merge the maps.
  /// This avoids downloading an entire large collection when the UI needs only
  /// a few statuses (for example, active patients on the Payments page).
  Stream<dynamic> queryAnyStream(
    String path, {
    required String orderBy,
    required List<dynamic> equalToAny,
    Duration? pollInterval,
  }) {
    final interval = pollInterval ?? Duration(seconds: _pollingInterval);
    final cacheKey = '$path|$orderBy|${json.encode(equalToAny)}';
    final key = '$cacheKey|${interval.inMilliseconds}';

    Future<dynamic> fetchMerged() async {
      final merged = <String, dynamic>{};
      final results = await Future.wait(
        equalToAny.map(
          (value) => query(path, orderBy: orderBy, equalTo: value),
        ),
      );
      for (final result in results) {
        if (result is Map) {
          result.forEach((key, value) => merged[key.toString()] = value);
        }
      }
      _latestValues[cacheKey] = merged;
      return merged;
    }

    return _resource(
      key,
      path,
      cacheKey,
      interval,
      fetchMerged,
      errorOnInitialFailure: true,
    );
  }

  Stream<dynamic> _resource(
    String key,
    String invalidationPath,
    String cacheKey,
    Duration interval,
    Future<dynamic> Function() fetch, {
    bool errorOnInitialFailure = false,
    String? ssePath,
  }) {
    return _resources.putIfAbsent(
      key,
      () => _SharedResource(
        service: this,
        key: key,
        invalidationPath: invalidationPath,
        cacheKey: cacheKey,
        ssePath: ssePath,
        pollInterval: interval,
        fetch: fetch,
        errorOnInitialFailure: errorOnInitialFailure,
        initialHasValue: _latestValues.containsKey(cacheKey),
        initialValue: _latestValues.containsKey(cacheKey)
            ? _latestValues[cacheKey]
            : null,
      ),
    ).stream;
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
    try {
      final token = await _getIdToken();
      final baseUrl = Uri.parse(_buildUrl(path));

      final params = <String, String>{};
      if (token != null) params['auth'] = token;
      if (orderBy != null) params['orderBy'] = json.encode(orderBy);
      if (equalTo != null) {
        params['equalTo'] = json.encode(equalTo);
      }
      if (startAt != null) {
        params['startAt'] = json.encode(startAt);
      }
      if (endAt != null) {
        params['endAt'] = json.encode(endAt);
      }
      if (limitToFirst != null) params['limitToFirst'] = '$limitToFirst';
      if (limitToLast != null) params['limitToLast'] = '$limitToLast';

      final response = await _client.get(baseUrl.replace(queryParameters: params)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception(
          'Request timeout - check your internet connection',
        ),
      );

      if (response.statusCode == 200) {
        if (response.body == 'null') return null;
        return json.decode(response.body);
      } else {
        throw Exception(
          'Query failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to query $path: $e');
    }
  }

  /// Query stream with polling (shared per exact query).
  Stream<dynamic> queryStream(
    String path, {
    String? orderBy,
    dynamic equalTo,
    Duration? pollInterval,
  }) {
    final interval = pollInterval ?? Duration(seconds: _pollingInterval);
    final cacheKey = '$path|$orderBy|$equalTo';
    final key = '$cacheKey|${interval.inMilliseconds}';
    return _resource(
      key,
      path,
      cacheKey,
      interval,
      () => query(path, orderBy: orderBy, equalTo: equalTo),
      errorOnInitialFailure: true,
    );
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  /// Dispose all shared resource streams
  void dispose() {
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

/// One reference-counted polling subscription shared by all consumers of the
/// same resource path.
class _SharedResource {
  final FirebaseRTDBRestService service;
  final String key;
  final String invalidationPath;
  final String cacheKey;
  final String? ssePath;
  final Duration pollInterval;
  final Future<dynamic> Function() fetch;
  final bool errorOnInitialFailure;

  late StreamController<dynamic> _controller;
  Timer? _timer;
  Timer? _refreshDebounce;
  bool _isFetching = false;
  bool _hasValue = false;
  int _revision = 0;
  dynamic _latest;

  _SharedResource({
    required this.service,
    required this.key,
    required this.invalidationPath,
    required this.cacheKey,
    required this.ssePath,
    required this.pollInterval,
    required this.fetch,
    required this.errorOnInitialFailure,
    required bool initialHasValue,
    required dynamic initialValue,
  }) {
    _hasValue = initialHasValue;
    _latest = initialValue;
    _controller = StreamController<dynamic>.broadcast(
      onListen: () {
        // First subscriber starts the shared subscription (polling plus the
        // SSE realtime channel).
        refreshSoon();
        _timer = Timer.periodic(pollInterval, (_) => refreshSoon());
        if (ssePath != null) _startSse();
      },
      onCancel: () {
        _timer?.cancel();
        _timer = null;
        _refreshDebounce?.cancel();
        _refreshDebounce = null;
        _closeSse();
      },
    );
  }

  /// Attach to the shared controller before replaying its latest value.
  /// This gives every subscriber, including `.first`, a current snapshot.
  Stream<dynamic> get stream {
    return Stream<dynamic>.multi((controller) {
      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      if (_hasValue) controller.add(_latest);
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
    if (_controller.isClosed) return;
    if (_refreshDebounce?.isActive ?? false) return;
    _refreshDebounce = Timer(const Duration(milliseconds: 150), () {
      _refreshDebounce = null;
      _refreshNow();
    });
  }

  void invalidate() {
    _revision++;
    refreshSoon();
  }

  Future<void> _refreshNow() async {
    if (_controller.isClosed || !_controller.hasListener) return;
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
      service._latestValues[cacheKey] = value;
      if (!_hasValue || json.encode(value) != json.encode(_latest)) {
        _hasValue = true;
        _latest = value;
        _controller.add(value);
      }
    } catch (error, stackTrace) {
      if (!_controller.isClosed && !_hasValue && errorOnInitialFailure) {
        _controller.addError(error, stackTrace);
      }
      // Otherwise keep showing the last successful value. A temporary Wi-Fi
      // or Firebase failure must never replace real data with an empty screen.
    } finally {
      _isFetching = false;
      if (revision != _revision && _controller.hasListener) refreshSoon();
    }
  }

  void dispose() {
    _timer?.cancel();
    _refreshDebounce?.cancel();
    _closeSse();
    if (!_controller.isClosed) _controller.close();
  }

  // ── SSE realtime channel ────────────────────────────────────────────────────
  // Firebase RTDB's REST endpoint streams Server-Sent Events for the path.
  // Any data event triggers a debounced refresh, giving sub-second
  // cross-terminal propagation. Polling remains active as the reconciliation
  // fallback while the SSE connection is down or reconnecting.

  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  Timer? _sseRetryTimer;
  bool _sseEnabled = true;
  int _sseFailures = 0;

  void _closeSse() {
    _sseRetryTimer?.cancel();
    _sseRetryTimer = null;
    _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;
  }

  Future<void> _startSse() async {
    if (!_sseEnabled || _controller.isClosed || !_controller.hasListener) return;
    try {
      final token = await service._getIdToken();
      if (token == null) {
        _scheduleSseRetry();
        return;
      }
      final cleanPath = ssePath!.startsWith('/')
          ? ssePath!.substring(1)
          : ssePath!;
      final client = http.Client();
      _sseClient = client;
      final request = http.Request(
        'GET',
        Uri.parse('${service.databaseUrl}/$cleanPath.json?auth=$token'),
      );
      request.headers['Accept'] = 'text/event-stream';
      final response = await client.send(request);
      if (_controller.isClosed || !_controller.hasListener ||
          !identical(_sseClient, client)) {
        client.close();
        return;
      }
      if (response.statusCode != 200) {
        _closeSse();
        _scheduleSseRetry();
        return;
      }
      _sseFailures = 0;
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
            // Any change to this path (put, patch or delete) triggers a
            // debounced refresh.
            refreshSoon();
          }
        },
        onError: (Object _) {
          _closeSse();
          _scheduleSseRetry();
        },
        onDone: () {
          _closeSse();
          _scheduleSseRetry();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _closeSse();
      _scheduleSseRetry();
    }
  }

  void _scheduleSseRetry() {
    if (_controller.isClosed || !_controller.hasListener || !_sseEnabled) return;
    if (_sseRetryTimer?.isActive ?? false) return;
    _sseFailures++;
    final shift = math.min(_sseFailures, 5);
    final delay = Duration(seconds: 2 << shift);
    _sseRetryTimer = Timer(delay, _startSse);
  }
}
