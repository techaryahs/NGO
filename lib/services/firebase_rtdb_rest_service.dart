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
  static const int _pollingInterval = 2;
  
  // Active stream controllers for cleanup
  final Map<String, StreamController> _activeControllers = {};

  FirebaseRTDBRestService({
    required this.projectId,
    String? databaseUrl,
    this.getAuthToken,
  }) : databaseUrl = databaseUrl ?? 'https://$projectId-default-rtdb.firebaseio.com';

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
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout - check your internet connection');
        },
      );
      
      if (response.statusCode == 200) {
        if (response.body == 'null') return null;
        return json.decode(response.body);
      } else {
        throw Exception('GET failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to GET $path: $e');
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
        throw Exception('PUT failed: ${response.statusCode} - ${response.body}');
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
        throw Exception('PATCH failed: ${response.statusCode} - ${response.body}');
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
        throw Exception('POST failed: ${response.statusCode} - ${response.body}');
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
        throw Exception('DELETE failed: ${response.statusCode} - ${response.body}');
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

    controller = StreamController<dynamic>(
      onListen: () {
        // Initial fetch with timeout
        get(path).timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        ).then((value) {
          if (!controller.isClosed) {
            lastValue = value;
            controller.add(value);
          }
        }).catchError((error) {
          if (!controller.isClosed) {
            // Emit null to show empty state instead of error
            controller.add(null);
          }
        });

        // Start polling
        timer = Timer.periodic(interval, (t) {
          get(path).then((value) {
            if (!controller.isClosed) {
              // Only emit if value changed
              if (json.encode(value) != json.encode(lastValue)) {
                lastValue = value;
                controller.add(value);
              }
            }
          }).catchError((error) {
            if (!controller.isClosed) {
              // Don't emit error, just skip this poll cycle
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
        throw Exception('Query failed: ${response.statusCode} - ${response.body}');
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
    final controllerId = '${path}_query_${DateTime.now().millisecondsSinceEpoch}';
    
    late StreamController<dynamic> controller;
    Timer? timer;
    dynamic lastValue;

    controller = StreamController<dynamic>(
      onListen: () {
        // Initial fetch
        query(path, orderBy: orderBy, equalTo: equalTo).then((value) {
          if (!controller.isClosed) {
            lastValue = value;
            controller.add(value);
          }
        }).catchError((error) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        });

        // Start polling
        timer = Timer.periodic(interval, (t) {
          query(path, orderBy: orderBy, equalTo: equalTo).then((value) {
            if (!controller.isClosed) {
              if (json.encode(value) != json.encode(lastValue)) {
                lastValue = value;
                controller.add(value);
              }
            }
          }).catchError((error) {
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
