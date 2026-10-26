import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'backend_api_service.dart';
import 'firebase_rtdb_rest_service.dart';
import 'service_locator.dart';

/// Allocator lifecycle states for one-time bootstrap protection.
enum AllocatorState {
  uninitialized,
  initializing,
  ready,
  failed,
}

/// Result of analyzing patient registration sequence continuity and outliers.
class SequenceAnalysisResult {
  final int establishedTail;
  final int nextNumber;
  final List<int> outliers;
  final Set<int> allReservedNumbers;
  final int totalExamined;
  final int numericCount;
  final int nonNumericCount;
  final int missingCount;
  final int minNumber;
  final int maxNumber;
  final Map<int, int> duplicateCounts;

  const SequenceAnalysisResult({
    required this.establishedTail,
    required this.nextNumber,
    required this.outliers,
    required this.allReservedNumbers,
    required this.totalExamined,
    required this.numericCount,
    required this.nonNumericCount,
    required this.missingCount,
    required this.minNumber,
    required this.maxNumber,
    required this.duplicateCounts,
  });
}

/// Production-grade, lightweight, concurrency-safe, idempotent registration number allocator.
///
/// Non-functional guarantees:
/// 1. ZERO polling (no Timer.periodic or Future.delayed polling loops).
/// 2. ZERO repeated /patients scans (at most one during bootstrap if counter is uninitialized).
/// 3. ZERO per-widget Firebase streams (exactly ONE shared SSE counter stream for the service singleton).
/// 4. ZERO network requests on preview peeks and widget rebuilds (served directly from in-memory state).
/// 5. Atomic CAS allocation via RTDB ETag without scanning /patients on 412 conflicts.
class RegistrationNumberService {
  static const String defaultCounterPath = 'system_counters/registrationNumber';
  static const int maxCasRetries = 10;

  final FirebaseRTDBRestService? _injectedRtdb;
  final BackendApiService? _injectedBackendApi;
  final String _activePath;
  final Random _random = Random();

  AllocatorState _state = AllocatorState.uninitialized;
  Future<void>? _bootstrapFuture;
  int? _lastAllocatedRegistrationNumber;
  int? _knownDbMax;
  Set<int>? _reservedNumbersCache;
  final Map<String, String> _idempotencyCache = {};

  // Single shared SSE stream resources
  StreamSubscription<dynamic>? _sharedSseSubscription;
  final StreamController<String> _sharedStreamController =
      StreamController<String>.broadcast();

  // Metrics for observability and testing
  int _bootstrapPatientsScanCount = 0;
  int _counterReadsCount = 0;
  int _counterWritesCount = 0;

  RegistrationNumberService({
    FirebaseRTDBRestService? rtdbService,
    BackendApiService? backendApiService,
    String? counterPath,
  })  : _injectedRtdb = rtdbService,
        _injectedBackendApi = backendApiService,
        _activePath = counterPath ?? defaultCounterPath;

  BackendApiService? get _backendApi {
    if (_injectedBackendApi != null) return _injectedBackendApi;
    if (_injectedRtdb != null) return null;
    try {
      return ServiceLocator().backendApiService;
    } catch (_) {
      return null;
    }
  }

  bool get isPostgres => _backendApi != null || _injectedRtdb == null;

  FirebaseRTDBRestService get _rtdb =>
      _injectedRtdb ?? ServiceLocator().rtdbService;

  String get activeCounterPath => _activePath;
  AllocatorState get state => _state;
  int? get cachedHighestAllocatedNumber => _lastAllocatedRegistrationNumber;
  int get bootstrapPatientsScanCount => _bootstrapPatientsScanCount;
  int get counterReadsCount => _counterReadsCount;
  int get counterWritesCount => _counterWritesCount;
  int get activeSseStreamsCount => _sharedSseSubscription != null ? 1 : 0;

  @visibleForTesting
  void clearIdempotencyCache() {
    _idempotencyCache.clear();
  }

  @visibleForTesting
  void clearReservedCache() {
    _reservedNumbersCache = null;
  }

  @visibleForTesting
  void resetForTesting() {
    _state = AllocatorState.uninitialized;
    _bootstrapFuture = null;
    _lastAllocatedRegistrationNumber = null;
    _knownDbMax = null;
    _reservedNumbersCache = null;
    _idempotencyCache.clear();
    _bootstrapPatientsScanCount = 0;
    _counterReadsCount = 0;
    _counterWritesCount = 0;
    _sharedSseSubscription?.cancel();
    _sharedSseSubscription = null;
  }

  /// Parses a stored counter or registration number into an integer.
  static int? parseNumeric(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is Map) {
      final inner = val['current'] ??
          val['value'] ??
          val['counter'] ??
          val['registrationNumber'];
      if (inner != null) return parseNumeric(inner);
    }
    final str = val.toString().trim();
    if (str.isEmpty) return null;
    return int.tryParse(str);
  }

  /// Analyzes a map of patients data to determine sequence continuity,
  /// the canonical established sequence tail, and isolated historical outliers.
  static SequenceAnalysisResult analyzeSequence(
    Map<dynamic, dynamic>? patientsData,
  ) {
    if (patientsData == null || patientsData.isEmpty) {
      return const SequenceAnalysisResult(
        establishedTail: 0,
        nextNumber: 1,
        outliers: [],
        allReservedNumbers: {},
        totalExamined: 0,
        numericCount: 0,
        nonNumericCount: 0,
        missingCount: 0,
        minNumber: 0,
        maxNumber: 0,
        duplicateCounts: {},
      );
    }

    int totalExamined = 0;
    final List<int> validNumbers = [];
    int nonNumericCount = 0;
    int missingCount = 0;
    final Map<int, int> counts = {};

    for (final entry in patientsData.entries) {
      final patient = entry.value;
      if (patient is! Map) continue;
      totalExamined++;

      final reg = patient['registrationNumber'];
      if (reg == null) {
        missingCount++;
        continue;
      }
      final str = reg.toString().trim();
      if (str.isEmpty) {
        missingCount++;
        continue;
      }

      final parsed = int.tryParse(str);
      if (parsed == null || parsed <= 0) {
        nonNumericCount++;
        continue;
      }

      validNumbers.add(parsed);
      counts[parsed] = (counts[parsed] ?? 0) + 1;
    }

    if (validNumbers.isEmpty) {
      return SequenceAnalysisResult(
        establishedTail: 0,
        nextNumber: 1,
        outliers: const [],
        allReservedNumbers: const {},
        totalExamined: totalExamined,
        numericCount: 0,
        nonNumericCount: nonNumericCount,
        missingCount: missingCount,
        minNumber: 0,
        maxNumber: 0,
        duplicateCounts: const {},
      );
    }

    final uniqueSorted = validNumbers.toSet().toList()..sort();
    final minNumber = uniqueSorted.first;
    final maxNumber = uniqueSorted.last;
    final duplicateCounts = Map<int, int>.fromEntries(
      counts.entries.where((e) => e.value > 1),
    );

    // Identify isolated outliers:
    // Walk from highest number downward. If gap to previous number is > 300,
    // and elements above gap is an isolated cohort (<= max(1, min(5, 10% of total))),
    // those high numbers are isolated historical outliers (e.g. Lata 8959).
    final List<int> outliers = [];
    int establishedTail = uniqueSorted.last;

    final maxOutlierCohort = (uniqueSorted.length <= 3)
        ? 0
        : max(1, min(5, (uniqueSorted.length * 0.1).ceil()));

    for (int i = uniqueSorted.length - 1; i > 0; i--) {
      final curr = uniqueSorted[i];
      final prev = uniqueSorted[i - 1];
      final gap = curr - prev;
      final elementsAbove = uniqueSorted.length - i;

      if (gap > 300 && elementsAbove <= maxOutlierCohort) {
        outliers.addAll(uniqueSorted.sublist(i));
        establishedTail = prev;
        break;
      }
    }

    outliers.sort();
    final allReservedNumbers = validNumbers.toSet();

    int candidate = establishedTail + 1;
    while (allReservedNumbers.contains(candidate)) {
      candidate++;
    }

    return SequenceAnalysisResult(
      establishedTail: establishedTail,
      nextNumber: candidate,
      outliers: outliers,
      allReservedNumbers: allReservedNumbers,
      totalExamined: totalExamined,
      numericCount: validNumbers.length,
      nonNumericCount: nonNumericCount,
      missingCount: missingCount,
      minNumber: minNumber,
      maxNumber: maxNumber,
      duplicateCounts: duplicateCounts,
    );
  }

  /// Scans the authoritative RTDB `patients` collection and returns a full
  /// sequence analysis, caching the set of reserved numbers.
  Future<SequenceAnalysisResult> analyzeDatabase() async {
    final patientsMap = await _obtainAuthoritativePatientsData();
    final result = analyzeSequence(patientsMap);
    _reservedNumbersCache = Set<int>.from(result.allReservedNumbers);
    return result;
  }

  Future<int> computeEstablishedSequenceTail() async {
    final analysis = await analyzeDatabase();
    return analysis.establishedTail;
  }

  Future<Set<int>> getReservedRegistrationNumbers() async {
    if (_reservedNumbersCache != null) {
      return _reservedNumbersCache!;
    }
    final analysis = await analyzeDatabase();
    return analysis.allReservedNumbers;
  }

  /// Ensures the allocator has completed its one-time bootstrap.
  /// Concurrent callers share the exact same in-flight Future.
  Future<void> ensureInitialized() async {
    if (_state == AllocatorState.ready) return;
    if (_state == AllocatorState.initializing && _bootstrapFuture != null) {
      return _bootstrapFuture!;
    }
    _state = AllocatorState.initializing;
    _bootstrapFuture = _bootstrapInternal();
    try {
      await _bootstrapFuture!;
      _state = AllocatorState.ready;
    } catch (e) {
      _state = AllocatorState.failed;
      rethrow;
    } finally {
      _bootstrapFuture = null;
    }
  }

  Future<void> _bootstrapInternal() async {
    debugPrint('[RegistrationNumberService] bootstrap started');

    if (isPostgres) {
      try {
        final counter = await _backendApi!.getCounter('registrationNumber');
        final currentVal = parseNumeric(counter);
        if (currentVal != null && currentVal > 0) {
          _lastAllocatedRegistrationNumber = currentVal;
          _knownDbMax = currentVal;
        } else {
          _lastAllocatedRegistrationNumber = 0;
          _knownDbMax = 0;
        }
      } catch (e) {
        debugPrint('[RegistrationNumberService] bootstrap error via backend API: $e');
        _lastAllocatedRegistrationNumber = 0;
      }
      return;
    }

    // 1. Check persistent counter on RTDB
    RtdbValue snapshot;
    try {
      _counterReadsCount++;
      snapshot = await _rtdb.getWithEtag(_activePath);
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('401') || errorStr.contains('permission denied')) {
        debugPrint(
          '[RegistrationNumberService] Access denied to $_activePath: Permission denied (HTTP 401). '
          'Manual action required: Deploy system_counters security rules in Firebase Console.',
        );
        throw StateError(
          'Firebase RTDB permission denied on $_activePath. '
          'Please deploy the system_counters security rules in Firebase Console.',
        );
      }
      rethrow;
    }

    final currentVal = parseNumeric(snapshot.value);
    if (currentVal != null && currentVal > 0) {
      // Check if currentVal is an isolated outlier baseline (e.g. 8960 from prior naive max run)
      if (currentVal > 7000) {
        final patientsMap = await _obtainAuthoritativePatientsData();
        if (patientsMap != null) {
          final analysis = analyzeSequence(patientsMap);
          _reservedNumbersCache = Set<int>.from(analysis.allReservedNumbers);
          if (analysis.outliers.isNotEmpty &&
              (analysis.outliers.contains(currentVal) ||
                  analysis.outliers.contains(currentVal - 1) ||
                  currentVal > analysis.establishedTail + 300)) {
            final healed = analysis.establishedTail;
            debugPrint('[RegistrationNumberService] Healing outlier counter $currentVal to $healed');
            await _putCounterConditional(healed, snapshot.etag ?? '');
            _lastAllocatedRegistrationNumber = healed;
            _knownDbMax = healed;
            _reservedNumbersCache = Set<int>.from(analysis.allReservedNumbers);
            _startSharedStream();
            debugPrint('[RegistrationNumberService] bootstrap completed: counter healed to $healed');
            return;
          }
        }
      }

      _lastAllocatedRegistrationNumber = currentVal;
      _startSharedStream();
      debugPrint('[RegistrationNumberService] bootstrap completed: persistent counter found: $currentVal');
      return;
    }

    // 2. Counter is genuinely uninitialized: obtain sequence from DB
    debugPrint('[RegistrationNumberService] bootstrap source: persistent counter uninitialized');
    final patientsMap = await _obtainAuthoritativePatientsData();
    final analysis = analyzeSequence(patientsMap);
    final tail = analysis.establishedTail;
    _lastAllocatedRegistrationNumber = tail;
    _knownDbMax = tail;
    _reservedNumbersCache = Set<int>.from(analysis.allReservedNumbers);

    // Initialize persistent counter
    await _putCounterConditional(tail, snapshot.etag ?? '');
    _startSharedStream();
    debugPrint('[RegistrationNumberService] bootstrap completed: counter initialized to $tail');
  }

  Future<Map<dynamic, dynamic>?> _obtainAuthoritativePatientsData() async {
    // 1. Check in-memory cached state first
    try {
      final cached = _rtdb.cachedPatientsData;
      if (cached != null) {
        debugPrint('[RegistrationNumberService] bootstrap source: in-memory cached patients');
        return cached;
      }
    } catch (_) {}

    // 2. Check persistent SQLite cache next
    if (_rtdb.persistentCache != null) {
      try {
        final snap = await _rtdb.persistentCache!.readCanonicalPatients();
        if (snap != null && snap.value.isNotEmpty) {
          debugPrint('[RegistrationNumberService] bootstrap source: persistent cache patients');
          return snap.value;
        }
      } catch (_) {}
    }

    // 3. Only if neither memory nor SQLite has patients, perform ONE network read:
    debugPrint('[RegistrationNumberService] bootstrap source: one-time /patients read');
    _bootstrapPatientsScanCount++;
    final dynamic data = await _rtdb.get('patients');
    return (data is Map) ? data : null;
  }

  Future<bool> _putCounterConditional(dynamic value, String etag) async {
    final payload = (value is Map)
        ? value
        : <String, dynamic>{
            'current': value,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            'source': 'patients_database_sequence',
          };

    _counterWritesCount++;
    return await _rtdb.putValueIfMatch(_activePath, payload, etag);
  }

  /// Returns the next expected registration number synchronously from in-memory state.
  /// Performs ZERO network requests and ZERO async delay.
  String peekNextRegistrationNumberSync() {
    final last = _lastAllocatedRegistrationNumber;
    if (last == null) return '...';
    var candidate = last + 1;
    final reserved = _reservedNumbersCache;
    if (reserved != null) {
      while (reserved.contains(candidate)) {
        candidate++;
      }
    }
    return candidate.toString();
  }

  /// Peeks at the next registration number.
  /// After one-time initialization, reads purely from in-memory state with ZERO Firebase calls.
  Future<String> peekNextRegistrationNumber() async {
    if (_state != AllocatorState.ready) {
      await ensureInitialized();
    }
    return peekNextRegistrationNumberSync();
  }

  /// Streams real-time updates of the next registration number.
  ///
  /// Uses EXACTLY ONE shared SSE connection to RTDB at the service singleton level.
  /// Multiple dialogs/screens listen to the shared in-memory broadcast controller.
  /// Dialog rebuilds and navigation do NOT reconnect or create multiple streams.
  Stream<String> watchNextRegistrationNumber() {
    _startSharedStream();

    final controller = StreamController<String>();

    if (_state == AllocatorState.ready && _lastAllocatedRegistrationNumber != null) {
      controller.add(peekNextRegistrationNumberSync());
    } else {
      ensureInitialized().then((_) {
        if (!controller.isClosed) {
          controller.add(peekNextRegistrationNumberSync());
        }
      }).catchError((_) {});
    }

    final sub = _sharedStreamController.stream.listen(
      (nextVal) {
        if (!controller.isClosed) controller.add(nextVal);
      },
      onError: (e) {
        if (!controller.isClosed) controller.addError(e);
      },
    );

    controller.onCancel = () {
      sub.cancel();
    };

    return controller.stream;
  }

  void _startSharedStream() {
    if (isPostgres || _sharedSseSubscription != null) return;
    try {
      _sharedSseSubscription = _rtdb.stream(_activePath).listen((event) {
        final val = parseNumeric(event);
        if (val != null && val > (_lastAllocatedRegistrationNumber ?? 0)) {
          _lastAllocatedRegistrationNumber = val;
          _sharedStreamController.add(peekNextRegistrationNumberSync());
        }
      }, onError: (e) {
        debugPrint('[RegistrationNumberService] shared counter stream error: $e');
      });
    } catch (e) {
      debugPrint('[RegistrationNumberService] failed to start shared counter stream: $e');
    }
  }

  /// Allocates the next monotonic numeric registration number.
  ///
  /// Concurrency-safe via RTDB optimistic CAS (ETag).
  /// Idempotent when [idempotencyKey] is provided.
  /// Monotonic: numbers are never recycled or rolled back.
  /// Collision-safe: skips any already-used historical registrations (e.g. 8959).
  Future<String> allocateNextRegistrationNumber({String? idempotencyKey}) async {
    if (idempotencyKey != null &&
        idempotencyKey.trim().isNotEmpty &&
        _idempotencyCache.containsKey(idempotencyKey)) {
      return _idempotencyCache[idempotencyKey]!;
    }

    if (isPostgres) {
      await ensureInitialized();
      final allocatedInt = await _backendApi!.allocateNextCounter('registrationNumber');
      final allocated = allocatedInt.toString();
      _lastAllocatedRegistrationNumber = allocatedInt;
      _sharedStreamController.add(peekNextRegistrationNumberSync());
      if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty) {
        _idempotencyCache[idempotencyKey] = allocated;
      }
      debugPrint('[RegistrationNumberService] postgres allocated=$allocated');
      return allocated;
    }

    await ensureInitialized();

    for (var attempt = 0; attempt < maxCasRetries; attempt++) {
      debugPrint('[RegistrationNumberService] allocation attempt=${attempt + 1}');
      _counterReadsCount++;
      final snapshot = await _rtdb.getWithEtag(_activePath);
      var currentVal = parseNumeric(snapshot.value) ?? _lastAllocatedRegistrationNumber ?? 0;
      var currentEtag = snapshot.etag ?? '';

      var base = max(currentVal, max(_lastAllocatedRegistrationNumber ?? 0, _knownDbMax ?? 0));
      var candidate = base + 1;

      final reserved = _reservedNumbersCache;
      if (reserved != null) {
        while (reserved.contains(candidate)) {
          candidate++;
        }
      }

      final success = await _putCounterConditional(candidate, currentEtag);
      if (success) {
        final allocated = candidate.toString();
        _lastAllocatedRegistrationNumber = candidate;
        _reservedNumbersCache?.add(candidate);
        _sharedStreamController.add(peekNextRegistrationNumberSync());

        if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty) {
          _idempotencyCache[idempotencyKey] = allocated;
        }
        debugPrint('[RegistrationNumberService] allocated=$allocated');
        return allocated;
      }

      // CAS conflict on HTTP 412:
      debugPrint('[RegistrationNumberService] CAS retry=${attempt + 1}');
      await Future<void>.delayed(
        Duration(milliseconds: 30 * (attempt + 1) + _random.nextInt(25)),
      );
    }

    debugPrint('[RegistrationNumberService] allocation failure');
    throw StateError(
      'Failed to allocate registration number after $maxCasRetries attempts due to concurrent writes.',
    );
  }

  void dispose() {
    _sharedSseSubscription?.cancel();
    _sharedStreamController.close();
  }
}
