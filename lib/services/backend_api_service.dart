import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../cache/persistent_cache.dart';

/// HTTP failure with optional server message.
class BackendApiException extends HttpException {
  BackendApiException(
    this.statusCode,
    String operation, {
    this.serverMessage,
    this.responseBody,
    this.requestId,
  }) : super(
         serverMessage != null && serverMessage.isNotEmpty
             ? '$operation failed (HTTP $statusCode): $serverMessage'
             : '$operation failed (HTTP $statusCode)',
       );

  final int statusCode;
  final String? serverMessage;
  final String? responseBody;
  final String? requestId;

  static String? extractMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map) {
        if (decoded['message'] != null &&
            decoded['message'].toString().trim().isNotEmpty) {
          return decoded['message'].toString().trim();
        }
        if (decoded['error'] != null &&
            decoded['error'].toString().trim().isNotEmpty) {
          return decoded['error'].toString().trim();
        }
      }
    } catch (_) {}
    return null;
  }
}

class _BackendStreamResource {
  _BackendStreamResource(this.accountGeneration);

  final int? accountGeneration;
  final controller = StreamController<dynamic>.broadcast(sync: true);
  Timer? timer;
  late Future<void> Function() poll;
  dynamic latest;
  bool hasValue = false;
  bool polling = false;
  bool refreshAfterPoll = false;
  int revision = 0;
  int mutationRevision = 0;
  Object? error;
  StackTrace? errorStack;
}

/// BackendApiService — High-performance HTTP client for the Fastify + PostgreSQL backend.
///
/// Implements domain-aware routing, authentication token injection,
/// Drift/SQLite persistent caching, and offline-read fallback.
class BackendApiService {
  final String baseUrl;
  final Future<String?> Function()? getAuthToken;
  final PersistentCache? persistentCache;
  final http.Client _client;

  // Polling streams by path for reactive UI screens
  final Map<String, _BackendStreamResource> _streams = {};
  final Map<String, Future<dynamic>> _targetedRefreshes = {};
  final Map<String, int> _acknowledgedRevisions = {};
  int _mutationGeneration = 0;
  int _readSequence = 0;
  final Map<String, int> _acceptedReads = {};
  bool _disposed = false;

  BackendApiService({
    required this.baseUrl,
    this.getAuthToken,
    this.persistentCache,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Headers with Bearer token authentication
  Future<Map<String, String>> _headers() async {
    if (_disposed) throw StateError('Backend API service has been disposed');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (getAuthToken != null) {
      final token = await getAuthToken!();
      if (token == null || token.trim().isEmpty) {
        throw BackendApiException(401, 'Authentication');
      }
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }

    return headers;
  }

  /// Check server process liveness
  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/health'.replaceAll('/api/health', '/health'),
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Check database connectivity readiness
  Future<bool> checkReady() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/ready'.replaceAll('/api/ready', '/ready'),
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Maps an RTDB-style path to the corresponding Fastify API URL
  String _mapPathToApiUrl(String path, {Map<String, String>? queryParams}) {
    final cleanPath = path.replaceAll('.json', '').replaceAll('//', '/');
    final querySplit = cleanPath.split('?');
    final basePath = querySplit[0];
    final pathQuery = querySplit.length > 1
        ? Uri.splitQueryString(querySplit[1])
        : <String, String>{};
    final segments = basePath.split('/').where((s) => s.isNotEmpty).toList();

    String endpoint = '$baseUrl/$basePath';
    final query = <String, String>{...?queryParams, ...pathQuery};

    if (segments.isEmpty) {
      endpoint = '$baseUrl/';
    } else if (segments[0] == 'patients') {
      if (segments.length == 1) {
        endpoint = '$baseUrl/patients';
        query.putIfAbsent('format', () => 'map');
      } else {
        endpoint = '$baseUrl/patients/${segments[1]}';
      }
    } else if (segments[0] == 'rooms') {
      if (segments.length == 1) {
        endpoint = '$baseUrl/rooms';
        query.putIfAbsent('format', () => 'map');
      } else if (segments.length == 2) {
        endpoint = '$baseUrl/rooms/${segments[1]}';
      } else if (segments.length == 3 && segments[2] == 'beds') {
        endpoint = '$baseUrl/rooms/${segments[1]}/beds';
      } else if (segments.length >= 4 && segments[2] == 'beds') {
        endpoint = '$baseUrl/rooms/${segments[1]}/beds/${segments[3]}';
      }
    } else if (segments[0] == 'stays') {
      if (segments.length == 1) {
        endpoint = '$baseUrl/stays';
        query.putIfAbsent('format', () => 'map');
      } else {
        final stayId = segments.sublist(1).join('/');
        endpoint = '$baseUrl/stays/${Uri.encodeComponent(stayId)}';
      }
    } else if (segments[0] == 'attendance' ||
        segments[0] == 'attendant_attendance') {
      endpoint = '$baseUrl/attendance';
      query['kind'] = segments[0];
      final dateIndex = segments.length >= 2 && segments[1] == 'daily' ? 2 : 1;
      if (segments.length > dateIndex) query['date'] = segments[dateIndex];
      if (segments.length > dateIndex + 1) {
        query['patientId'] = segments[dateIndex + 1];
      }
      query.putIfAbsent('format', () => 'map');
    } else if (segments[0] == 'payments' || segments[0] == 'paymentHistory') {
      if (segments.length == 1) {
        endpoint = '$baseUrl/payments';
        query.putIfAbsent('format', () => 'map');
      } else {
        endpoint = '$baseUrl/payments/${segments[1]}';
      }
    } else if (segments[0] == 'system_counters' || segments[0] == 'counters') {
      final counterName = segments.length >= 2
          ? segments[1]
          : 'registrationNumber';
      endpoint = '$baseUrl/counters/$counterName';
    } else if (segments[0] == 'admin_settings' || segments[0] == 'settings') {
      final category = segments.length >= 2 ? segments[1] : 'pricing';
      if (segments.length >= 3) {
        endpoint = '$baseUrl/settings/$category/${segments[2]}';
      } else {
        endpoint = '$baseUrl/settings/$category';
      }
    } else if (segments[0] == 'patientPhotos' || segments[0] == 'photos') {
      final photoRef = segments[0] == 'patientPhotos'
          ? segments.sublist(1).join('/')
          : segments.join('/');
      endpoint = '$baseUrl/photos/$photoRef';
    } else if (segments[0] == 'users') {
      if (segments.length == 1) {
        endpoint = '$baseUrl/users';
      } else {
        endpoint = '$baseUrl/users/${segments[1]}';
      }
    } else if (segments[0] == 'erp') {
      endpoint = '$baseUrl/erp/${segments.sublist(1).join('/')}';
    } else if (const {
      'inventory_items': 'inventory',
      'vendors': 'vendors',
      'purchases': 'purchases',
      'expenses': 'expenses',
      'expense_entries': 'expenses',
      'salaries': 'salaries',
      'sponsorships': 'sponsorships',
    }.containsKey(segments[0])) {
      final erpMod = const {
        'inventory_items': 'inventory',
        'vendors': 'vendors',
        'purchases': 'purchases',
        'expenses': 'expenses',
        'expense_entries': 'expenses',
        'salaries': 'salaries',
        'sponsorships': 'sponsorships',
      }[segments[0]]!;
      if (segments.length == 1) {
        endpoint = '$baseUrl/erp/$erpMod';
      } else {
        endpoint = '$baseUrl/erp/$erpMod/${segments[1]}';
      }
    }

    final uri = Uri.parse(endpoint);
    if (query.isNotEmpty) {
      final mergedParams = Map<String, String>.from(uri.queryParameters)
        ..addAll(query);
      return uri.replace(queryParameters: mergedParams).toString();
    }
    return endpoint;
  }

  static Map<String, dynamic> _normalizeErpRow(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    void alias(String snake, String camel) {
      if (m.containsKey(snake) && !m.containsKey(camel)) {
        m[camel] = m[snake];
      }
    }

    alias('min_stock_level', 'minStockLevel');
    alias('current_stock', 'currentStock');
    alias('contact_person', 'contactPerson');
    alias('phone', 'mobileNumber');
    alias('vendor_id', 'vendorId');
    alias('vendor_name', 'vendorName');
    alias('item_id', 'itemId');
    alias('item_name', 'itemName');
    alias('unit_price', 'unitPrice');
    alias('total_amount', 'totalAmount');
    alias('amount', 'totalAmount');
    alias('purchase_date', 'purchaseDate');
    alias('invoice_number', 'invoiceNumber');
    alias('payment_method', 'paymentMethod');
    alias('paid_to', 'paidTo');
    alias('paidTo', 'vendorName');
    alias('expense_date', 'expenseDate');
    alias('receipt_url', 'receiptUrl');
    alias('staff_id', 'staffId');
    alias('staff_name', 'staffName');
    alias('staffName', 'employeeName');
    alias('base_salary', 'baseSalary');
    alias('baseSalary', 'grossSalary');
    alias('net_salary', 'netSalary');
    alias('sponsor_name', 'sponsorName');
    alias('patient_id', 'patientId');
    alias('patient_name', 'patientName');
    alias('sponsorship_date', 'sponsorshipDate');
    alias('created_at', 'createdAt');
    alias('updated_at', 'updatedAt');

    for (final dateKey in const [
      'purchaseDate',
      'expenseDate',
      'sponsorshipDate',
      'createdAt',
      'updatedAt',
    ]) {
      final val = m[dateKey];
      if (val is String && val.isNotEmpty && int.tryParse(val) == null) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) {
          m[dateKey] = parsed.millisecondsSinceEpoch;
        }
      }
    }
    return m;
  }

  dynamic _readRepresentation(String path, dynamic decoded) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isNotEmpty &&
        const {
          'inventory_items',
          'vendors',
          'purchases',
          'expenses',
          'expense_entries',
          'salaries',
          'sponsorships',
          'erp',
        }.contains(parts.first)) {
      if (decoded is List) {
        final map = <String, dynamic>{};
        for (final item in decoded) {
          if (item is Map && item['id'] != null) {
            map[item['id'].toString()] = _normalizeErpRow(item);
          }
        }
        return map;
      } else if (decoded is Map) {
        return _normalizeErpRow(decoded);
      }
    }
    if (parts.isEmpty ||
        parts.first != 'attendance' && parts.first != 'attendant_attendance') {
      return decoded;
    }
    if (parts.length == 1) return {'daily': decoded};
    final dateIndex = parts[1] == 'daily' ? 2 : 1;
    // Date-filtered API maps are keyed by patient; a targeted RTDB path
    // expects the patient payload (or the nested attendant payload).
    for (final key in parts.skip(dateIndex + 1)) {
      if (decoded is! Map) return null;
      decoded = decoded[key];
    }
    return decoded;
  }

  static const _collectionPageSize = 500;

  bool _needsCompleteCollection(String path, Uri uri) {
    final parts = path
        .split('?')
        .first
        .replaceAll('.json', '')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.length == 1 &&
        const {
          'patients',
          'payments',
          'paymentHistory',
        }.contains(parts.first) &&
        !const {
          'limit',
          'offset',
          'cursor',
        }.any(uri.queryParameters.containsKey);
  }

  /// Aggregate before reconciling SQLite: a later failed page must never erase
  /// records that were absent from an earlier, partial page.
  Future<dynamic> _readCompleteCollection(
    Uri uri,
    http.Response response,
    Map<String, String> headers,
    bool Function() currentAccount,
  ) async {
    dynamic page = json.decode(response.body);
    // Retain the legacy authoritative-null representation.
    if (page == null) return null;
    final asMap = page is Map;
    final mergedMap = <String, dynamic>{};
    final mergedList = <dynamic>[];
    final seen = <String>{};
    final cursors = <String>{};
    var cursorMode = response.headers['x-pagination-mode'] == 'cursor';
    var requestedLimit = _collectionPageSize;
    String? overlapId;

    while (true) {
      if (!currentAccount()) throw StateError('Account changed during request');
      final entries = <MapEntry<String, dynamic>>[];
      if (asMap && page is Map) {
        entries.addAll(
          page.entries.map(
            (entry) => MapEntry(entry.key.toString(), entry.value),
          ),
        );
      } else if (!asMap && page is List) {
        for (final item in page) {
          if (item is! Map || item['id'] == null) {
            throw const FormatException('Collection row must have an id');
          }
          entries.add(MapEntry(item['id'].toString(), item));
        }
      } else {
        throw const FormatException(
          'Collection response must be a map or list',
        );
      }
      if (entries.length > requestedLimit) {
        throw const FormatException('Collection page exceeds requested limit');
      }
      final pageLength = entries.length;
      if (overlapId != null) {
        // Older servers support only offsets. Verify an overlapping boundary
        // so a deletion, insertion or ignored offset cannot silently skip rows.
        if (entries.isEmpty || entries.first.key != overlapId) {
          throw StateError('Collection changed during pagination; retry read');
        }
        entries.removeAt(0);
      }
      for (final entry in entries) {
        if (!seen.add(entry.key)) {
          throw StateError('Collection pagination repeated a record');
        }
        if (asMap) {
          mergedMap[entry.key] = entry.value;
        } else {
          mergedList.add(entry.value);
        }
      }

      final nextCursor = response.headers['x-next-cursor'];
      cursorMode = cursorMode || nextCursor != null;
      final query = Map<String, String>.from(uri.queryParameters);
      if (cursorMode) {
        if (nextCursor == null || nextCursor.isEmpty) {
          return asMap ? mergedMap : mergedList;
        }
        if (entries.isEmpty || !cursors.add(nextCursor)) {
          throw StateError('Collection pagination did not advance');
        }
        query.remove('offset');
        query['cursor'] = nextCursor;
        requestedLimit = _collectionPageSize;
        overlapId = null;
      } else {
        if (pageLength < requestedLimit) {
          return asMap ? mergedMap : mergedList;
        }
        overlapId = entries.last.key;
        query['offset'] = (seen.length - 1).toString();
        requestedLimit = _collectionPageSize + 1;
      }
      query['limit'] = requestedLimit.toString();
      if (!currentAccount()) throw StateError('Account changed during request');
      response = await _client
          .get(uri.replace(queryParameters: query), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (!currentAccount()) throw StateError('Account changed during request');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BackendApiException(response.statusCode, 'GET collection page');
      }
      page = json.decode(response.body);
    }
  }

  /// GET request with SQLite persistent cache fallback
  bool _overlappingReads(Uri left, Uri right) {
    if (left.path.endsWith('/attendance') && right.path == left.path) {
      final a = left.queryParameters;
      final b = right.queryParameters;
      if (a['kind'] != b['kind']) return false;
      if (a['patientId'] != null &&
          b['patientId'] != null &&
          a['patientId'] != b['patientId']) {
        return false;
      }
      final aStart = a['date'] ?? a['startDate'] ?? '';
      final aEnd = a['date'] ?? a['endDate'] ?? '9999-12-31';
      final bStart = b['date'] ?? b['startDate'] ?? '';
      final bEnd = b['date'] ?? b['endDate'] ?? '9999-12-31';
      return aStart.compareTo(bEnd) <= 0 && bStart.compareTo(aEnd) <= 0;
    }
    return left == right;
  }

  bool _readCurrent(Uri uri, int sequence) => !_acceptedReads.entries.any(
    (entry) =>
        entry.value > sequence && _overlappingReads(uri, Uri.parse(entry.key)),
  );

  Future<dynamic> get(String path, {bool allowCacheFallback = true}) async {
    var uri = Uri.parse(_mapPathToApiUrl(path));
    final completeCollection = _needsCompleteCollection(path, uri);
    if (completeCollection) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'limit': _collectionPageSize.toString(),
          'offset': '0',
        },
      );
    }
    final accountGeneration = persistentCache?.accountGeneration;
    final mutationGeneration = _mutationGeneration;
    final sequence = ++_readSequence;
    bool currentAccount() =>
        !_disposed && accountGeneration == persistentCache?.accountGeneration;
    // Token refresh failures are authentication failures, not offline reads.
    final headers = await _headers();
    if (!currentAccount()) throw StateError('Account changed during request');

    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (!currentAccount()) throw StateError('Account changed during request');

      if (!_readCurrent(uri, sequence)) {
        return get(path, allowCacheFallback: allowCacheFallback);
      }
      if (mutationGeneration != _mutationGeneration) {
        final scope = _recordScope(path);
        if (persistentCache != null &&
            _acknowledgedRevisions.entries.any(
              (entry) =>
                  entry.value > mutationGeneration &&
                  (entry.key == scope || entry.key.startsWith('$scope/')),
            )) {
          final cached = await persistentCache!.read(path);
          if (!currentAccount()) {
            throw StateError('Account changed during request');
          }
          return cached;
        }
        return get(path, allowCacheFallback: allowCacheFallback);
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = _readRepresentation(
          path,
          completeCollection
              ? await _readCompleteCollection(
                  uri,
                  response,
                  headers,
                  currentAccount,
                )
              : json.decode(response.body),
        );

        // System counter unwrap
        if (path.startsWith('system_counters') &&
            decoded is Map &&
            decoded.containsKey('currentValue')) {
          final countVal = decoded['currentValue'];
          return countVal;
        }

        if (!_readCurrent(uri, sequence) ||
            mutationGeneration != _mutationGeneration) {
          return get(path, allowCacheFallback: allowCacheFallback);
        }
        _acceptedReads[uri.toString()] = sequence;
        // Cache successful response in Drift/SQLite
        try {
          await persistentCache?.replaceSnapshot(
            path,
            decoded,
            isCurrent: () =>
                currentAccount() &&
                mutationGeneration == _mutationGeneration &&
                _readCurrent(uri, sequence),
          );
        } catch (_) {}

        if (!currentAccount()) {
          throw StateError('Account changed during request');
        }
        if (!_readCurrent(uri, sequence) ||
            mutationGeneration != _mutationGeneration) {
          return get(path, allowCacheFallback: allowCacheFallback);
        }
        return decoded;
      } else if (response.statusCode == 404) {
        _acceptedReads[uri.toString()] = sequence;
        try {
          await persistentCache?.replaceSnapshot(
            path,
            null,
            isCurrent: () =>
                currentAccount() &&
                mutationGeneration == _mutationGeneration &&
                _readCurrent(uri, sequence),
          );
        } catch (_) {}
        if (!currentAccount()) {
          throw StateError('Account changed during request');
        }
        if (!_readCurrent(uri, sequence) ||
            mutationGeneration != _mutationGeneration) {
          return get(path, allowCacheFallback: allowCacheFallback);
        }
        return null;
      } else {
        throw BackendApiException(response.statusCode, 'GET');
      }
    } catch (e) {
      final transient =
          e is SocketException ||
          e is http.ClientException ||
          e is TimeoutException ||
          e is BackendApiException && e.statusCode >= 500;
      if (!allowCacheFallback || !transient || !currentAccount()) rethrow;
      try {
        final cached = await persistentCache?.read(path);
        if (cached != null && currentAccount()) return cached;
      } catch (_) {}
      rethrow;
    }
  }

  /// The server representation owns the cache. An empty acknowledgement
  /// invalidates the record so its next read must refresh from the server.
  Future<void> _cacheAcknowledged(
    String path,
    http.Response response,
    int? accountGeneration, {
    Map<String, dynamic>? relatedRecord,
  }) async {
    if (_disposed) return;
    final mutationGeneration = ++_mutationGeneration;
    if (accountGeneration != persistentCache?.accountGeneration) return;
    dynamic saved;
    if (response.body.trim().isNotEmpty) {
      saved = json.decode(response.body);
    }
    await _acceptSnapshot(path, saved, accountGeneration, mutationGeneration);
    if (!_currentAccount(accountGeneration)) return;

    // Placement/payment responses identify the exact related records whose
    // server state changed. Refresh those records only when a screen uses them.
    final parts = path.split('/');
    final related = <String>{};
    final relationship = saved is Map ? saved : relatedRecord;
    if (relationship is Map &&
        (parts.first == 'stays' || parts.first == 'payments')) {
      if (relationship['patientId'] != null) {
        related.add('patients/${relationship['patientId']}');
      }
      if (parts.first == 'stays' && relationship['roomId'] != null) {
        related.add('rooms/${relationship['roomId']}');
      }
    }
    if (parts.length >= 3 && parts.first == 'rooms' && parts[2] == 'beds') {
      related.add('rooms/${parts[1]}');
    }
    if (parts.first == 'patients' && (saved == null || saved == 'null')) {
      related.add('stays');
      related.add('rooms');
      if (relationship is Map && relationship['roomId'] != null) {
        related.add('rooms/${relationship['roomId']}');
      }
    }
    await _refreshWatchedRecords(
      related,
      accountGeneration,
      mutationGeneration,
    );
  }

  bool _currentAccount(int? generation) =>
      !_disposed && generation == persistentCache?.accountGeneration;

  String _recordScope(String path) {
    final parts = path.split('?').first.split('/');
    final depth =
        parts.first == 'attendance' || parts.first == 'attendant_attendance'
        ? 4
        : 2;
    return parts.take(depth).join('/');
  }

  Future<void> _acceptSnapshot(
    String path,
    dynamic saved,
    int? accountGeneration,
    int mutationGeneration,
  ) async {
    if (!_currentAccount(accountGeneration)) return;
    final scope = _recordScope(path);
    if ((_acknowledgedRevisions[scope] ?? -1) > mutationGeneration) return;
    _acknowledgedRevisions[scope] = mutationGeneration;
    bool current() =>
        _currentAccount(accountGeneration) &&
        _acknowledgedRevisions[scope] == mutationGeneration;
    try {
      await persistentCache?.replaceSnapshot(path, saved, isCurrent: current);
    } catch (_) {
      // SQLite failure must not turn an acknowledged server write into a retry.
    }
    if (current()) {
      _publishSnapshot(path, saved, accountGeneration);
    }
  }

  dynamic _replaceNested(dynamic current, List<String> keys, dynamic value) {
    if (keys.isEmpty) return value;
    final updated = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};
    final key = keys.first;
    if (keys.length == 1 && value == null) {
      updated.remove(key);
    } else {
      updated[key] = _replaceNested(updated[key], keys.skip(1).toList(), value);
    }
    return updated;
  }

  void _emit(
    _BackendStreamResource resource,
    dynamic value, {
    bool mutation = false,
  }) {
    if (resource.controller.isClosed ||
        !_currentAccount(resource.accountGeneration)) {
      return;
    }
    resource.latest = value;
    resource.hasValue = true;
    resource.error = null;
    resource.errorStack = null;
    resource.revision++;
    if (mutation) resource.mutationRevision++;
    resource.controller.add(value);
  }

  void _publishSnapshot(String path, dynamic saved, int? accountGeneration) {
    for (final entry in _streams.entries.toList()) {
      final resource = entry.value;
      if (resource.accountGeneration != accountGeneration ||
          resource.controller.isClosed) {
        continue;
      }
      final watched = entry.key;
      if (_publishFilteredStaySnapshot(watched, path, saved, resource)) {
        continue;
      } else if (watched == path) {
        _emit(resource, saved, mutation: true);
      } else if (!watched.contains('?') &&
          path.startsWith('$watched/') &&
          resource.hasValue &&
          !RegExp(r'^rooms/[^/]+/beds/').hasMatch(path)) {
        final suffix = path.substring(watched.length + 1).split('/');
        _emit(
          resource,
          _replaceNested(resource.latest, suffix, saved),
          mutation: true,
        );
      } else if (!watched.contains('?') && watched.startsWith('$path/')) {
        dynamic selected = saved;
        for (final key in watched.substring(path.length + 1).split('/')) {
          selected = selected is Map ? selected[key] : null;
        }
        _emit(resource, selected, mutation: true);
      }
    }
  }

  bool _publishFilteredStaySnapshot(
    String watched,
    String path,
    dynamic saved,
    _BackendStreamResource resource,
  ) {
    if (!watched.contains('?')) return false;
    final uri = Uri.tryParse(watched);
    final changed = path.split('/');
    if (uri == null ||
        uri.path != 'stays' ||
        changed.length < 2 ||
        changed.first != 'stays') {
      return false;
    }
    final changedId = Uri.decodeComponent(changed.skip(1).join('/'));
    final query = uri.queryParameters;
    if (query.keys.any(
          (key) =>
              !const {'status', 'patientId', 'roomId', 'format'}.contains(key),
        ) ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        query['format'] != null && query['format'] != 'map') {
      return false;
    }
    // Only a complete authoritative stay can establish query membership.
    if (saved != null && (saved is! Map || saved['id'] != changedId)) {
      return false;
    }
    if (saved is Map &&
        const ['status', 'patientId', 'roomId'].any(
          (field) =>
              (query[field]?.isNotEmpty ?? false) && !saved.containsKey(field),
        )) {
      return false;
    }
    if (!resource.hasValue || resource.latest is! Map) {
      // There is no complete list to amend yet. Fence the old initial poll and
      // request a fresh filtered list as soon as that poll settles.
      resource.revision++;
      resource.mutationRevision++;
      resource.refreshAfterPoll = true;
      if (!resource.polling) {
        resource.refreshAfterPoll = false;
        unawaited(resource.poll());
      }
      return true;
    }
    var matches = saved != null;
    for (final field in const ['status', 'patientId', 'roomId']) {
      final expected = query[field];
      if (expected != null &&
          expected.isNotEmpty &&
          saved?[field] != expected) {
        matches = false;
      }
    }
    final updated = Map<String, dynamic>.from(resource.latest as Map);
    if (matches) {
      updated[changedId] = saved;
    } else {
      updated.remove(changedId);
    }
    _emit(resource, updated, mutation: true);
    final revision = resource.revision;
    unawaited(
      persistentCache
          ?.replaceSnapshot(
            watched,
            updated,
            isCurrent: () =>
                _currentAccount(resource.accountGeneration) &&
                resource.revision == revision,
          )
          .catchError((_) {}),
    );
    return true;
  }

  bool _isWatched(String path) => _streams.keys.any(
    (watched) =>
        watched == path ||
        path.startsWith('$watched/') ||
        watched.startsWith('$path/'),
  );

  Future<void> _refreshWatchedRecords(
    Set<String> paths,
    int? accountGeneration,
    int mutationGeneration,
  ) async {
    await Future.wait(
      paths.where(_isWatched).map((path) async {
        if (!_currentAccount(accountGeneration)) return;
        final scope = _recordScope(path);
        if ((_acknowledgedRevisions[scope] ?? -1) < mutationGeneration) {
          _acknowledgedRevisions[scope] = mutationGeneration;
        }
        try {
          await refresh(path);
        } catch (_) {
          // The mutation already succeeded; its regular stream poll can retry a
          // failed related read without causing staff to submit the write twice.
          debugPrint('[BackendApiService] Related record refresh failed');
        }
      }),
    );
  }

  /// Fetches one authoritative record and publishes it to matching active views.
  /// Concurrent callers share the request; collection refreshes are unnecessary.
  Future<dynamic> refresh(String path) {
    if (_disposed) throw StateError('Backend API service has been disposed');
    final accountGeneration = persistentCache?.accountGeneration;
    final scope = _recordScope(path);
    final generation = _acknowledgedRevisions[scope] ?? 0;
    final key = '$accountGeneration:$generation:$path';
    return _targetedRefreshes.putIfAbsent(key, () async {
      try {
        final value = await get(path, allowCacheFallback: false);
        if (!_currentAccount(accountGeneration)) {
          throw StateError('Account changed during request');
        }
        if (generation == (_acknowledgedRevisions[scope] ?? 0)) {
          await _acceptSnapshot(path, value, accountGeneration, generation);
        }
        return value;
      } finally {
        _targetedRefreshes.remove(key);
      }
    });
  }

  /// PUT request (full entity replacement or upsert)
  Future<void> put(String path, Map<String, dynamic> data) async {
    final url = _mapPathToApiUrl(path);
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _cacheAcknowledged(path, response, accountGeneration);
    } else {
      throw BackendApiException(
        response.statusCode,
        'PUT',
        serverMessage: BackendApiException.extractMessage(response.body),
        responseBody: response.body,
      );
    }
  }

  /// PATCH request (partial update)
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    final url = _mapPathToApiUrl(path);
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(updates))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _cacheAcknowledged(path, response, accountGeneration);
    } else {
      throw BackendApiException(
        response.statusCode,
        'PATCH',
        serverMessage: BackendApiException.extractMessage(response.body),
        responseBody: response.body,
      );
    }
  }

  /// POST / PUSH request (creates new record)
  Future<String> push(String path, Map<String, dynamic> data) async {
    final url = _mapPathToApiUrl(path);
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .post(Uri.parse(url), headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      if (decoded is! Map ||
          decoded['id'] is! String ||
          (decoded['id'] as String).isEmpty) {
        throw const FormatException(
          'Create response must contain the record ID',
        );
      }
      final id = decoded['id'] as String;
      await _cacheAcknowledged('$path/$id', response, accountGeneration);
      return id;
    } else {
      throw BackendApiException(
        response.statusCode,
        'POST',
        serverMessage: BackendApiException.extractMessage(response.body),
        responseBody: response.body,
      );
    }
  }

  /// DELETE request
  Future<void> delete(String path) async {
    final url = _mapPathToApiUrl(path);
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    dynamic previous = _streams[path]?.latest;
    if (previous == null && path.startsWith('stays/')) {
      final id = path.substring('stays/'.length);
      for (final entry in _streams.entries) {
        if (entry.key.split('?').first == 'stays' &&
            entry.value.accountGeneration == accountGeneration &&
            entry.value.latest is Map) {
          final record = (entry.value.latest as Map)[id];
          if (record is Map && record['id'] == id) {
            previous = record;
            break;
          }
        }
      }
    }
    if (previous == null) {
      try {
        previous = await persistentCache?.read(path);
      } catch (_) {}
    }

    final response = await _client
        .delete(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300 ||
        response.statusCode == 404) {
      await _cacheAcknowledged(
        path,
        http.Response('null', 200),
        accountGeneration,
        relatedRecord: previous is Map
            ? Map<String, dynamic>.from(previous)
            : null,
      );
    } else {
      throw BackendApiException(
        response.statusCode,
        'DELETE',
        serverMessage: BackendApiException.extractMessage(response.body),
        responseBody: response.body,
      );
    }
  }

  /// POST request returning the decoded Map representation
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data, {
    String? requestId,
  }) async {
    final url = _mapPathToApiUrl(path);
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (requestId != null) headers['X-Request-Id'] = requestId;
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .post(Uri.parse(url), headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 10));

    if (requestId != null) {
      debugPrint(
        '[Payment] requestId=$requestId phase=response status=${response.statusCode}',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final id = map['id']?.toString() ?? data['id']?.toString();
      if (id != null && id.isNotEmpty) {
        await _cacheAcknowledged('$path/$id', response, accountGeneration);
      }
      return map;
    } else {
      throw BackendApiException(
        response.statusCode,
        'POST',
        serverMessage: BackendApiException.extractMessage(response.body),
        responseBody: response.body,
        requestId: response.headers['x-request-id'] ?? requestId,
      );
    }
  }

  // ── Attendance Operations ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> postAttendance({
    required String date,
    required String patientId,
    String kind = 'attendance',
    required Map<String, dynamic> payload,
  }) async {
    final url = '$baseUrl/attendance';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .post(
          Uri.parse(url),
          headers: headers,
          body: json.encode({
            'date': date,
            'kind': kind,
            'patientId': patientId,
            'payload': payload,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final savedPayload = map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : payload;
      await _acceptSnapshot(
        '$kind/daily/$date/$patientId',
        savedPayload,
        accountGeneration,
        ++_mutationGeneration,
      );
      return map;
    } else {
      throw BackendApiException(response.statusCode, 'postAttendance');
    }
  }

  Future<void> postAttendanceBulk({
    required String date,
    String kind = 'attendance',
    required Map<String, dynamic> records,
  }) async {
    final url = '$baseUrl/attendance/bulk';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .post(
          Uri.parse(url),
          headers: headers,
          body: json.encode({'date': date, 'kind': kind, 'records': records}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final generation = ++_mutationGeneration;
      for (final entry in records.entries) {
        final path = '$kind/daily/$date/${entry.key}';
        if (kind == 'attendant_attendance' && entry.value is Map) {
          for (final attEntry in (entry.value as Map).entries) {
            await _acceptSnapshot(
              '$path/${attEntry.key}',
              attEntry.value,
              accountGeneration,
              generation,
            );
          }
        } else {
          await _acceptSnapshot(
            path,
            entry.value,
            accountGeneration,
            generation,
          );
        }
      }
    } else {
      throw BackendApiException(response.statusCode, 'postAttendanceBulk');
    }
  }

  Future<Map<String, dynamic>> getAttendanceRange({
    required String kind,
    required String startKey,
    required String endKey,
    String? patientId,
    bool allowCacheFallback = true,
  }) async {
    final uri = Uri.parse('$baseUrl/attendance').replace(
      queryParameters: {
        'kind': kind,
        'startDate': startKey,
        'endDate': endKey,
        'format': 'map',
        if (patientId != null) 'patientId': patientId,
      },
    );
    Map<String, dynamic> selectWindow(Map values) {
      final result = <String, dynamic>{};
      for (final entry in values.entries) {
        final date = entry.key.toString();
        if (date.compareTo(startKey) < 0 || date.compareTo(endKey) > 0) {
          continue;
        }
        final day = entry.value;
        if (patientId == null) {
          result[date] = day;
        } else if (day is Map && day.containsKey(patientId)) {
          result[date] = {patientId: day[patientId]};
        }
      }
      return result;
    }

    final accountGeneration = persistentCache?.accountGeneration;
    final mutationGeneration = _mutationGeneration;
    final sequence = ++_readSequence;
    Future<Map<String, dynamic>> reload() => getAttendanceRange(
      kind: kind,
      startKey: startKey,
      endKey: endKey,
      patientId: patientId,
      allowCacheFallback: allowCacheFallback,
    );
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (!_currentAccount(accountGeneration)) {
        throw StateError('Account changed during request');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = json.decode(response.body);
        if (decoded is Map) {
          if (!_readCurrent(uri, sequence) ||
              mutationGeneration != _mutationGeneration) {
            return reload();
          }
          _acceptedReads[uri.toString()] = sequence;
          final result = selectWindow(decoded);
          if (persistentCache != null) {
            // An omitted date in a successful range is authoritatively empty.
            // Clear that date only; preserve attendance outside this window.
            final previous = await persistentCache!.readKeyRange(
              '$kind/daily',
              startKey: startKey,
              endKey: endKey,
              patientId: patientId,
            );
            final dates = <String>{
              ...result.keys,
              if (previous is Map)
                ...previous.keys.map((key) => key.toString()),
            };
            for (final date in dates) {
              if (!_currentAccount(accountGeneration)) {
                throw StateError('Account changed during request');
              }
              try {
                await persistentCache!.replaceSnapshot(
                  '$kind/daily/$date${patientId == null ? '' : '/$patientId'}',
                  patientId == null
                      ? result[date] ?? <String, dynamic>{}
                      : (result[date] as Map?)?[patientId],
                  isCurrent: () =>
                      _currentAccount(accountGeneration) &&
                      mutationGeneration == _mutationGeneration &&
                      _readCurrent(uri, sequence),
                );
              } catch (_) {}
            }
          }
          if (!_currentAccount(accountGeneration)) {
            throw StateError('Account changed during request');
          }
          if (!_readCurrent(uri, sequence) ||
              mutationGeneration != _mutationGeneration) {
            return reload();
          }
          return result;
        }
        throw const FormatException('Attendance range response must be a map');
      } else {
        throw BackendApiException(response.statusCode, 'getAttendanceRange');
      }
    } catch (e) {
      final transient =
          e is SocketException ||
          e is http.ClientException ||
          e is TimeoutException ||
          e is BackendApiException && e.statusCode >= 500;
      if (!allowCacheFallback ||
          !transient ||
          !_currentAccount(accountGeneration)) {
        rethrow;
      }
      if (persistentCache != null) {
        try {
          final cached = await persistentCache!.readKeyRange(
            '$kind/daily',
            startKey: startKey,
            endKey: endKey,
            patientId: patientId,
          );
          if (!_currentAccount(accountGeneration)) {
            throw StateError('Account changed during request');
          }
          if (cached is Map) {
            return selectWindow(cached);
          }
        } catch (_) {}
      }
      rethrow;
    }
  }

  // ── Counters ───────────────────────────────────────────────────────────────

  Future<int> allocateNextCounter(String name) async {
    final url = '$baseUrl/counters/$name/next';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .post(Uri.parse(url), headers: headers, body: '{}')
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      if (decoded is Map) {
        final rawVal =
            decoded['allocatedValue'] ??
            decoded['nextValue'] ??
            decoded['currentValue'];
        if (rawVal is num) {
          return rawVal.toInt();
        }
        if (rawVal != null) {
          final parsed = int.tryParse(rawVal.toString());
          if (parsed != null) return parsed;
        }
      }
      throw const FormatException('Invalid counter allocation response');
    } else {
      throw BackendApiException(response.statusCode, 'allocateNextCounter');
    }
  }

  Future<int?> getCounter(String name) async {
    final url = '$baseUrl/counters/$name';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['currentValue'] is num) {
        return (decoded['currentValue'] as num).toInt();
      }
      return null;
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw BackendApiException(response.statusCode, 'getCounter');
    }
  }

  // ── Rooms & Beds ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> addBed(
    String roomId,
    Map<String, dynamic> bedData,
  ) async {
    final res = await post('rooms/$roomId/beds', bedData);
    return res;
  }

  Future<Map<String, dynamic>> updateBed(
    String roomId,
    String bedId,
    Map<String, dynamic> updates,
  ) async {
    final url = '$baseUrl/rooms/$roomId/beds/$bedId';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(updates))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      await _cacheAcknowledged(
        'rooms/$roomId/beds/$bedId',
        response,
        accountGeneration,
      );
      return map;
    } else {
      throw BackendApiException(response.statusCode, 'updateBed');
    }
  }

  // ── Stays ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createStay(Map<String, dynamic> stayData) async {
    return post('stays', stayData);
  }

  Future<List<String>> createStaysBatch(
    List<Map<String, dynamic>> staysList,
  ) async {
    final url = '$baseUrl/stays/batch';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .post(
          Uri.parse(url),
          headers: headers,
          body: json.encode({'stays': staysList}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['stays'] is List) {
        final createdList = decoded['stays'] as List;
        final ids = <String>[];
        final related = <String>{};
        final generation = ++_mutationGeneration;
        for (final item in createdList) {
          if (item is Map && item['id'] != null) {
            final id = item['id'].toString();
            ids.add(id);
            await _acceptSnapshot(
              'stays/$id',
              Map<String, dynamic>.from(item),
              accountGeneration,
              generation,
            );
            if (item['patientId'] != null) {
              related.add('patients/${item['patientId']}');
            }
            if (item['roomId'] != null) related.add('rooms/${item['roomId']}');
          }
        }
        await _refreshWatchedRecords(related, accountGeneration, generation);
        return ids;
      }
      return staysList.map((s) => s['id']?.toString() ?? '').toList();
    } else {
      throw BackendApiException(response.statusCode, 'createStaysBatch');
    }
  }

  Future<Map<String, dynamic>> updateStay(
    String stayId,
    Map<String, dynamic> updates,
  ) async {
    final encodedStayId = Uri.encodeComponent(stayId);
    final url = '$baseUrl/stays/$encodedStayId';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(updates))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      await _cacheAcknowledged('stays/$stayId', response, accountGeneration);
      return map;
    } else {
      final serverMessage = BackendApiException.extractMessage(response.body);
      throw BackendApiException(
        response.statusCode,
        'updateStay',
        serverMessage: serverMessage,
        responseBody: response.body,
      );
    }
  }

  Future<void> deleteStay(String stayId) async {
    final encodedStayId = Uri.encodeComponent(stayId);
    return delete('stays/$encodedStayId');
  }

  // ── Patients ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createPatient(
    Map<String, dynamic> patientData,
  ) async {
    return post('patients', patientData);
  }

  /// Atomically registers a patient along with attendants, initial stays,
  /// bed reservations inside a single PostgreSQL
  /// transaction (`POST /api/patients/register`).
  Future<Map<String, dynamic>> registerPatient(
    Map<String, dynamic> registrationPayload,
  ) => _postAdmission('patients/register', registrationPayload);

  Future<Map<String, dynamic>> financialSnapshot(
    String patientId, {
    DateTime? checkoutAt,
  }) async {
    // This is a coherent server projection, not a nested patient field in the
    // legacy path adapter. Never cache it as a partially replaced patient.
    final account = persistentCache?.accountGeneration;
    final response = await _client
        .get(
          Uri.parse(
            '$baseUrl/patients/${Uri.encodeComponent(patientId)}/financials${checkoutAt == null ? '' : '?checkoutAt=${checkoutAt.millisecondsSinceEpoch}'}',
          ),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (_disposed || account != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }
    if (response.statusCode != 200) {
      throw BackendApiException(
        response.statusCode,
        'financialSnapshot',
        serverMessage: BackendApiException.extractMessage(response.body),
      );
    }
    return Map<String, dynamic>.from(json.decode(response.body) as Map);
  }

  Future<Map<String, dynamic>> recalculateBilling(
    String patientId, {
    DateTime? checkoutAt,
  }) => _postAdmission(
    'patients/${Uri.encodeComponent(patientId)}/recalculate-billing',
    {if (checkoutAt != null) 'checkoutAt': checkoutAt.millisecondsSinceEpoch},
  );

  Future<Map<String, dynamic>> correctBilling(
    String patientId, {
    required String reason,
    required List<Map<String, dynamic>> dates,
  }) => _postAdmission(
    'patients/${Uri.encodeComponent(patientId)}/billing-corrections',
    {'reason': reason, 'dates': dates},
  );

  Future<Map<String, dynamic>> revertBillingCorrection(
    String patientId, {
    required String day,
    required String reason,
  }) => _postAdmission(
    'patients/${Uri.encodeComponent(patientId)}/billing-corrections/revert',
    {'day': day, 'reason': reason},
  );

  Future<Map<String, dynamic>> dischargePatient(
    String patientId, {
    DateTime? checkoutAt,
  }) => _postAdmission('patients/${Uri.encodeComponent(patientId)}/discharge', {
    if (checkoutAt != null) 'checkoutAt': checkoutAt.millisecondsSinceEpoch,
  });

  Future<Map<String, dynamic>> rejoinPatient(
    String patientId,
    Map<String, dynamic> payload,
  ) => _postAdmission(
    'patients/${Uri.encodeComponent(patientId)}/rejoin',
    payload,
  );

  Future<Map<String, dynamic>> transferPatient(
    String patientId,
    Map<String, dynamic> payload,
  ) => _postAdmission(
    'patients/${Uri.encodeComponent(patientId)}/transfer',
    payload,
  );

  Future<Map<String, dynamic>> _postAdmission(
    String endpoint,
    Map<String, dynamic> registrationPayload,
  ) async {
    final url = '$baseUrl/$endpoint';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .post(
          Uri.parse(url),
          headers: headers,
          body: json.encode(registrationPayload),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};

      final patientMap = map['patient'] is Map
          ? Map<String, dynamic>.from(map['patient'] as Map)
          : map;
      final patientId = patientMap['id']?.toString();
      final generation = ++_mutationGeneration;
      if (patientId != null && patientId.isNotEmpty) {
        await _acceptSnapshot(
          'patients/$patientId',
          patientMap,
          accountGeneration,
          generation,
        );
      }

      final relatedRooms = <String>{};
      if (map['stays'] is List) {
        for (final item in map['stays'] as List) {
          if (item is Map && item['id'] != null) {
            final stayId = item['id'].toString();
            await _acceptSnapshot(
              'stays/$stayId',
              Map<String, dynamic>.from(item),
              accountGeneration,
              generation,
            );
            if (item['roomId'] != null) {
              relatedRooms.add('rooms/${item['roomId']}');
            }
          }
        }
      }
      await _refreshWatchedRecords(relatedRooms, accountGeneration, generation);

      return map;
    } else {
      // Validation diagnostics contain schema paths, never the submitted
      // patient payload or authentication headers.
      if (response.statusCode == 400) {
        try {
          final failure = json.decode(response.body);
          final message = failure is Map ? failure['message'] : null;
          if (message is String && message.startsWith('Invalid request: ')) {
            debugPrint(
              '[BackendApiService] registerPatient rejected: $message',
            );
          }
        } catch (_) {}
      }
      throw BackendApiException(
        response.statusCode,
        endpoint,
        serverMessage: BackendApiException.extractMessage(response.body),
      );
    }
  }

  Future<Map<String, dynamic>> updatePatient(
    String patientId,
    Map<String, dynamic> updates,
  ) async {
    final url = '$baseUrl/patients/$patientId';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(updates))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      await _cacheAcknowledged(
        'patients/$patientId',
        response,
        accountGeneration,
      );
      return map;
    } else {
      throw BackendApiException(response.statusCode, 'updatePatient');
    }
  }

  Future<void> deletePatient(String patientId) async {
    return delete('patients/$patientId');
  }

  // ── Payments ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createPayment(
    Map<String, dynamic> paymentData, {
    String? requestId,
  }) async {
    return post('payments', paymentData, requestId: requestId);
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSettingsCategory(String category) async {
    final url = '$baseUrl/settings/$category';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    } else if (response.statusCode == 404) {
      return {};
    } else {
      throw BackendApiException(response.statusCode, 'getSettingsCategory');
    }
  }

  Future<dynamic> getSettingsKey(String category, String key) async {
    final url = '$baseUrl/settings/$category/$key';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw BackendApiException(response.statusCode, 'getSettingsKey');
    }
  }

  Future<void> updateSettingsCategory(
    String category,
    Map<String, dynamic> values,
  ) async {
    final url = '$baseUrl/settings/$category';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(values))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _cacheAcknowledged(
        'admin_settings/$category',
        response,
        accountGeneration,
      );
    } else {
      throw BackendApiException(response.statusCode, 'updateSettingsCategory');
    }
  }

  Future<void> updateSettingsKey(
    String category,
    String key,
    dynamic value,
  ) async {
    final url = '$baseUrl/settings/$category/$key';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(value))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _cacheAcknowledged(
        'admin_settings/$category/$key',
        response,
        accountGeneration,
      );
    } else {
      throw BackendApiException(response.statusCode, 'updateSettingsKey');
    }
  }

  // ── Photos ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> putPhoto(
    String photoPath, {
    required String data,
    required String contentType,
    required int version,
    String? patientId,
  }) async {
    final cleanPath = photoPath.startsWith('patientPhotos/')
        ? photoPath
        : 'patientPhotos/$photoPath';
    final url = '$baseUrl/photos/$cleanPath';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final body = <String, dynamic>{
      'data': data,
      'contentType': contentType,
      'version': version,
      if (patientId != null) 'patientId': patientId,
    };

    final response = await _client
        .put(Uri.parse(url), headers: headers, body: json.encode(body))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      await _cacheAcknowledged(cleanPath, response, accountGeneration);
      return map;
    } else {
      throw BackendApiException(response.statusCode, 'putPhoto');
    }
  }

  Future<Map<String, dynamic>?> getPhoto(String photoPath) async {
    final cleanPath = photoPath.startsWith('patientPhotos/')
        ? photoPath
        : 'patientPhotos/$photoPath';
    final url = '$baseUrl/photos/$cleanPath';
    final accountGeneration = persistentCache?.accountGeneration;
    final headers = await _headers();
    if (_disposed || accountGeneration != persistentCache?.accountGeneration) {
      throw StateError('Account changed during request');
    }

    final response = await _client
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw BackendApiException(response.statusCode, 'getPhoto');
    }
  }

  Stream<dynamic> _streamView(_BackendStreamResource resource) {
    return Stream<dynamic>.multi((listener) {
      if (resource.controller.isClosed ||
          !_currentAccount(resource.accountGeneration)) {
        listener.close();
        return;
      }
      final subscription = resource.controller.stream.listen(
        (value) {
          if (_currentAccount(resource.accountGeneration)) listener.add(value);
        },
        onError: (Object error, StackTrace stack) {
          if (_currentAccount(resource.accountGeneration)) {
            listener.addError(error, stack);
          }
        },
        onDone: listener.close,
      );
      // A broadcast controller does not replay: a dialog opened between polls
      // otherwise waits ten seconds despite a completed millisecond API read.
      if (resource.error != null) {
        listener.addError(resource.error!, resource.errorStack);
      } else if (resource.hasValue) {
        listener.add(resource.latest);
      }
      listener.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  /// Shared polling with account-scoped replay for every new subscriber.
  Stream<dynamic> stream(String path, {Duration? pollInterval}) {
    if (_disposed) throw StateError('Backend API service has been disposed');
    final interval = pollInterval ?? const Duration(seconds: 10);
    final accountGeneration = persistentCache?.accountGeneration;
    final existing = _streams[path];
    if (existing != null && !existing.controller.isClosed) {
      if (existing.accountGeneration == accountGeneration) {
        return _streamView(existing);
      }
      existing.timer?.cancel();
      unawaited(existing.controller.close());
      _streams.remove(path);
    }

    final resource = _BackendStreamResource(accountGeneration);
    final controller = resource.controller;
    _streams[path] = resource;
    var freshReceived = false;
    final hydrationRevision = resource.revision;

    // Hydration must never arrive after a newer poll or acknowledged mutation.
    persistentCache
        ?.read(path)
        .then((cached) {
          if (cached != null &&
              !(cached is Map && cached.isEmpty) &&
              !controller.isClosed &&
              !freshReceived &&
              resource.revision == hydrationRevision &&
              _currentAccount(accountGeneration)) {
            _emit(resource, cached);
          }
        })
        .catchError((_) {});

    resource.poll = () async {
      if (controller.isClosed ||
          resource.polling ||
          !_currentAccount(accountGeneration)) {
        return;
      }
      resource.polling = true;
      final revision = resource.mutationRevision;
      try {
        final data = await get(path);
        if (!controller.isClosed &&
            _currentAccount(accountGeneration) &&
            revision == resource.mutationRevision) {
          freshReceived = true;
          _emit(resource, data);
        }
      } catch (error, stack) {
        if (!controller.isClosed && _currentAccount(accountGeneration)) {
          resource.error = error;
          resource.errorStack = stack;
          controller.addError(error, stack);
        }
        debugPrint('[BackendApiService] Stream poll failed');
      } finally {
        resource.polling = false;
        if (resource.refreshAfterPoll &&
            !controller.isClosed &&
            _currentAccount(accountGeneration)) {
          resource.refreshAfterPoll = false;
          unawaited(resource.poll());
        }
      }
    };

    unawaited(resource.poll());
    resource.timer = Timer.periodic(interval, (_) => resource.poll());

    controller.onCancel = () {
      resource.timer?.cancel();
      if (identical(_streams[path], resource)) _streams.remove(path);
      unawaited(controller.close());
    };

    return _streamView(resource);
  }

  /// Refreshes all active streams immediately.
  void retryAll() {
    if (_disposed) return;
    for (final resource in _streams.values.toList()) {
      unawaited(resource.poll());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final resource in _streams.values.toList()) {
      resource.timer?.cancel();
      resource.controller.close();
    }
    _streams.clear();
    _targetedRefreshes.clear();
    _acknowledgedRevisions.clear();
    _client.close();
  }
}
