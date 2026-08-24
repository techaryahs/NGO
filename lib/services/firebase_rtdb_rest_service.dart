import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Firebase Realtime Database REST API Service
///
/// Provides CRUD operations and polling-based "realtime" updates
/// without requiring the native Firebase Database SDK.
///
/// Works on ALL platforms including Windows desktop.
class FirebaseRTDBRestService {
  final String projectId;
  final String databaseUrl;

  // Callback to get auth token
  Future<String?> Function()? getAuthToken;

  // Polling interval for simulating realtime listeners (in seconds)
  static const int _pollingInterval = 10;

  // Active stream controllers for cleanup
  final Map<String, StreamController> _activeControllers = {};

  // Keep the latest successful value per path so moving between screens does
  // not flash an empty state while the same Firebase data is downloaded again.
  final Map<String, dynamic> _latestValues = {};

  FirebaseRTDBRestService({
    required this.projectId,
    String? databaseUrl,
    this.getAuthToken,
  }) : databaseUrl =
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

      final response = await http
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
        _latestValues[path] = value;
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
      final response = await http
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

  // ===========================================================================
  // PUT — Write/Replace data
  // ===========================================================================

  /// Write data to a specific path (replaces existing data)
  Future<void> put(String path, Map<String, dynamic> data) async {
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'PUT failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to PUT $path: $e');
    }
  }

  // ===========================================================================
  // PATCH — Update data
  // ===========================================================================

  /// Update specific fields at a path (merges with existing data)
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    try {
      final token = await _getIdToken();
      final url = _buildUrl(path, auth: token);

      final response = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updates),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'PATCH failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to PATCH $path: $e');
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

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return result['name'] as String; // Firebase returns {"name": "pushKey"}
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

      final response = await http.delete(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception(
          'DELETE failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to DELETE $path: $e');
    }
  }

  // ===========================================================================
  // STREAM — Polling-based realtime updates
  // ===========================================================================

  /// Create a stream that polls the database for changes
  ///
  /// This simulates Firebase's onValue listener by polling every N seconds.
  /// For production, consider using Server-Sent Events (SSE) for true realtime.
  Stream<dynamic> stream(String path, {Duration? pollInterval}) {
    final interval = pollInterval ?? Duration(seconds: _pollingInterval);
    final controllerId = '${path}_${DateTime.now().millisecondsSinceEpoch}';

    late StreamController<dynamic> controller;
    Timer? timer;
    dynamic lastValue;
    var isFetching = false;

    Future<void> fetchLatest() async {
      // Slow connections must not create a queue of overlapping full-database
      // downloads. The next timer tick will retry after this request finishes.
      if (isFetching || controller.isClosed) return;
      isFetching = true;
      try {
        final value = await get(path).timeout(const Duration(seconds: 10));
        if (!controller.isClosed &&
            json.encode(value) != json.encode(lastValue)) {
          lastValue = value;
          controller.add(value);
        }
      } catch (_) {
        // Keep showing the last successful value. A temporary Wi-Fi or
        // Firebase failure must never replace real data with an empty screen.
      } finally {
        isFetching = false;
      }
    }

    controller = StreamController<dynamic>(
      onListen: () {
        // Repaint immediately with the most recently fetched value. The
        // network request below still runs so the UI remains up to date.
        if (_latestValues.containsKey(path)) {
          lastValue = _latestValues[path];
          controller.add(lastValue);
        }

        // Refresh in the background without clearing the cached value.
        fetchLatest();

        // Start polling
        timer = Timer.periodic(interval, (t) {
          fetchLatest();
        });
      },
      onCancel: () {
        timer?.cancel();
        _activeControllers.remove(controllerId);
      },
    );

    _activeControllers[controllerId] = controller;
    return controller.stream;
  }

  // ===========================================================================
  // QUERY — Filtered queries
  // ===========================================================================

  /// Query with orderBy and equalTo filters
  ///
  /// Note: REST API queries are limited compared to SDK.
  /// For complex queries, fetch all data and filter client-side.
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
      final cleanPath = path.startsWith('/') ? path.substring(1) : path;
      var url = '$databaseUrl/$cleanPath.json';

      final params = <String, String>{};
      if (token != null) params['auth'] = token;
      if (orderBy != null) params['orderBy'] = '"$orderBy"';
      if (equalTo != null) {
        params['equalTo'] = equalTo is String ? '"$equalTo"' : '$equalTo';
      }
      if (startAt != null) {
        params['startAt'] = startAt is String ? '"$startAt"' : '$startAt';
      }
      if (endAt != null) {
        params['endAt'] = endAt is String ? '"$endAt"' : '$endAt';
      }
      if (limitToFirst != null) params['limitToFirst'] = '$limitToFirst';
      if (limitToLast != null) params['limitToLast'] = '$limitToLast';

      if (params.isNotEmpty) {
        url += '?' + params.entries.map((e) => '${e.key}=${e.value}').join('&');
      }

      final response = await http.get(Uri.parse(url));

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

  /// Query stream with polling
  Stream<dynamic> queryStream(
    String path, {
    String? orderBy,
    dynamic equalTo,
    Duration? pollInterval,
  }) {
    final interval = pollInterval ?? Duration(seconds: _pollingInterval);
    final controllerId =
        '${path}_query_${DateTime.now().millisecondsSinceEpoch}';

    late StreamController<dynamic> controller;
    Timer? timer;
    dynamic lastValue;

    controller = StreamController<dynamic>(
      onListen: () {
        // Initial fetch
        query(path, orderBy: orderBy, equalTo: equalTo)
            .then((value) {
              if (!controller.isClosed) {
                lastValue = value;
                controller.add(value);
              }
            })
            .catchError((error) {
              if (!controller.isClosed) {
                controller.addError(error);
              }
            });

        // Start polling
        timer = Timer.periodic(interval, (t) {
          query(path, orderBy: orderBy, equalTo: equalTo)
              .then((value) {
                if (!controller.isClosed) {
                  if (json.encode(value) != json.encode(lastValue)) {
                    lastValue = value;
                    controller.add(value);
                  }
                }
              })
              .catchError((error) {
                if (!controller.isClosed) {
                  controller.addError(error);
                }
              });
        });
      },
      onCancel: () {
        timer?.cancel();
        _activeControllers.remove(controllerId);
      },
    );

    _activeControllers[controllerId] = controller;
    return controller.stream;
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
    final controllerId =
        '${cacheKey}_${DateTime.now().millisecondsSinceEpoch}';

    late StreamController<dynamic> controller;
    Timer? timer;
    dynamic lastValue;
    var isFetching = false;

    Future<void> fetchLatest() async {
      if (isFetching || controller.isClosed) return;
      isFetching = true;
      try {
        final merged = <String, dynamic>{};
        try {
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
        } catch (_) {
          // A deployed RTDB may not yet contain the requested `.indexOn`.
          // Fall back to one unfiltered read and apply the exact same filter
          // locally so screens remain usable until the rules are deployed.
          final allValues = await get(path);
          if (allValues is Map) {
            allValues.forEach((key, value) {
              if (value is Map && equalToAny.contains(value[orderBy])) {
                merged[key.toString()] = value;
              }
            });
          }
        }
        _latestValues[cacheKey] = merged;
        if (!controller.isClosed &&
            json.encode(merged) != json.encode(lastValue)) {
          lastValue = merged;
          controller.add(merged);
        }
      } catch (error, stackTrace) {
        // Retain cached data during a temporary failure, but surface an
        // initial failure so screens do not remain on a spinner forever.
        if (!_latestValues.containsKey(cacheKey) && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      } finally {
        isFetching = false;
      }
    }

    controller = StreamController<dynamic>(
      onListen: () {
        if (_latestValues.containsKey(cacheKey)) {
          lastValue = _latestValues[cacheKey];
          controller.add(lastValue);
        }
        fetchLatest();
        timer = Timer.periodic(interval, (_) => fetchLatest());
      },
      onCancel: () {
        timer?.cancel();
        _activeControllers.remove(controllerId);
      },
    );
    _activeControllers[controllerId] = controller;
    return controller.stream;
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  /// Dispose all active stream controllers
  void dispose() {
    for (var controller in _activeControllers.values) {
      controller.close();
    }
    _activeControllers.clear();
  }
}
