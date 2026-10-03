enum PatientCollectionCompleteness {
  uninitialized,
  hydrating,
  complete,
  unknown,
}

/// Internal ordering, independent of Firebase's record timestamps.
class PatientSnapshotTicket {
  const PatientSnapshotTicket(this.revision, this.accountGeneration);
  final int revision;
  final int accountGeneration;
}

class _PatientMutation {
  const _PatientMutation(this.path, this.value, this.isPatch);
  final String path;
  final dynamic value;
  final bool isPatch;
}

/// The only owner allowed to establish or mutate canonical patient memory.
/// Query membership and single-record reads never establish completeness.
class PatientCollectionState {
  int _sequence = 0;
  int _publishedRevision = 0;
  int _mutationRevision = 0;
  int _accountGeneration = -1;
  Map<String, dynamic>? _value;
  final Map<String, List<_PatientMutation>> _acknowledged = {};
  PatientCollectionCompleteness completeness =
      PatientCollectionCompleteness.uninitialized;

  Map<String, dynamic>? get value =>
      completeness == PatientCollectionCompleteness.complete ? _value : null;
  int get revision => _publishedRevision;

  void bindAccount(int generation) {
    if (_accountGeneration == generation) return;
    _accountGeneration = generation;
    _sequence++;
    _publishedRevision = _mutationRevision = _sequence;
    _value = null;
    _acknowledged.clear();
    completeness = PatientCollectionCompleteness.uninitialized;
  }

  PatientSnapshotTicket capture({bool hydrating = false}) {
    if (hydrating && value == null) {
      completeness = PatientCollectionCompleteness.hydrating;
    }
    return PatientSnapshotTicket(++_sequence, _accountGeneration);
  }

  bool isCurrent(PatientSnapshotTicket ticket) =>
      ticket.accountGeneration == _accountGeneration &&
      ticket.revision >= _publishedRevision &&
      ticket.revision >= _mutationRevision;

  static bool isCollection(dynamic data) =>
      data == null ||
      data is Map &&
          data.entries.every(
            (entry) =>
                !entry.key.toString().contains('/') &&
                entry.value is Map &&
                (entry.value as Map)['fullName'] is String,
          );

  /// Rebase acknowledged writes until a server snapshot confirms them. This
  /// protects an add even when a stale snapshot is delivered after its HTTP ACK.
  Map<String, dynamic> reconcile(dynamic data) {
    final result = <String, dynamic>{
      if (data is Map)
        for (final entry in data.entries)
          entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
    };
    for (final entry in _acknowledged.entries) {
      final candidate = <String, dynamic>{
        if (result.containsKey(entry.key)) entry.key: result[entry.key],
      };
      for (final mutation in entry.value) {
        _apply(candidate, mutation);
      }
      final remote = result[entry.key];
      final expected = candidate[entry.key];
      final remoteVersion = remote is Map ? remote['updatedAt'] : null;
      final localVersion = expected is Map ? expected['updatedAt'] : null;
      final confirmed =
          _confirms(remote, expected, entry.value) ||
          remoteVersion is num &&
              localVersion is num &&
              remoteVersion > localVersion;
      if (!confirmed) {
        if (candidate.containsKey(entry.key)) {
          result[entry.key] = candidate[entry.key];
        } else {
          result.remove(entry.key);
        }
      }
    }
    // Payload timestamps only reject older record contents. Publication order
    // itself is always enforced by the internal ticket above.
    for (final entry in (_value ?? <String, dynamic>{}).entries) {
      final remote = result[entry.key];
      final previous = entry.value;
      if (remote is Map &&
          previous is Map &&
          remote['updatedAt'] is num &&
          previous['updatedAt'] is num &&
          (remote['updatedAt'] as num) < (previous['updatedAt'] as num)) {
        result[entry.key] = previous;
      }
    }
    return result;
  }

  bool publish(
    dynamic data,
    PatientSnapshotTicket ticket, {
    required bool complete,
  }) {
    if (!isCurrent(ticket)) return false;
    if (!complete || !isCollection(data)) {
      if (value == null) completeness = PatientCollectionCompleteness.unknown;
      return false;
    }
    final next = reconcile(data);
    // Retire journals only after a successful publication confirms them.
    _acknowledged.removeWhere((id, mutations) {
      final original = data is Map ? data[id] : null;
      final expected = next[id];
      return _confirms(original, expected, mutations) ||
          original is Map &&
              expected is Map &&
              original['updatedAt'] is num &&
              expected['updatedAt'] is num &&
              (original['updatedAt'] as num) > (expected['updatedAt'] as num);
    });
    _value = Map<String, dynamic>.unmodifiable(next);
    _publishedRevision = ticket.revision;
    completeness = PatientCollectionCompleteness.complete;
    return true;
  }

  void mutate(
    String path,
    dynamic data, {
    required bool isPatch,
    required bool acknowledged,
    int? revision,
  }) {
    if (path == 'patients') {
      // A resource-level notification is a set of child changes, never proof
      // that the supplied map is the full authoritative collection.
      if (data is Map) {
        for (final entry in data.entries) {
          mutate(
            'patients/${entry.key}',
            entry.value,
            isPatch: isPatch,
            acknowledged: acknowledged,
            revision: revision,
          );
        }
      }
      return;
    }
    if (!path.startsWith('patients/')) return;
    final mutation = _PatientMutation(path.substring(9), data, isPatch);
    final id = mutation.path.split('/').first;
    final operationRevision = revision ?? ++_sequence;
    if (operationRevision > _mutationRevision) {
      _mutationRevision = operationRevision;
    }
    if (acknowledged) {
      final journal = _acknowledged.putIfAbsent(id, () => []);
      if (!mutation.path.contains('/') && !isPatch) journal.clear();
      journal.add(mutation);
    }
    if (value == null) {
      completeness = PatientCollectionCompleteness.unknown;
      return;
    }
    final next = Map<String, dynamic>.from(_value!);
    // Rebase pending acknowledgements over server deltas. An echo can update
    // unrelated fields, but cannot undo a field whose ACK is not confirmed.
    if (!acknowledged && _acknowledged.containsKey(id)) {
      final local = next[id];
      if (data is Map &&
          local is Map &&
          data['updatedAt'] is num &&
          local['updatedAt'] is num &&
          ((data['updatedAt'] as num) > (local['updatedAt'] as num) ||
              _confirms(data, local, _acknowledged[id]!))) {
        _acknowledged.remove(id);
      }
    }
    if (_apply(next, mutation)) {
      if (!acknowledged) {
        for (final pending in _acknowledged[id] ?? <_PatientMutation>[]) {
          _apply(next, pending);
        }
      }
      _value = Map<String, dynamic>.unmodifiable(next);
      if (operationRevision > _publishedRevision) {
        _publishedRevision = operationRevision;
      }
    }
  }

  static bool _confirms(
    dynamic remote,
    dynamic expected,
    List<_PatientMutation> mutations,
  ) {
    if (expected == null) return remote == null;
    if (remote is! Map || expected is! Map) return false;
    for (final mutation in mutations) {
      final path = mutation.path.split('/').skip(1).toList();
      if (path.isEmpty) {
        if (mutation.value is! Map) return false;
        final keys = mutation.isPatch
            ? (mutation.value as Map).keys
            : expected.keys;
        for (final key in keys) {
          if (!_equal(remote[key], expected[key])) return false;
        }
      } else if (!_equal(_field(remote, path), _field(expected, path))) {
        return false;
      }
    }
    return true;
  }

  static dynamic _field(dynamic value, List<String> path) {
    for (final part in path) {
      if (value is! Map) return null;
      value = value[part];
    }
    return value;
  }

  static bool _equal(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return {...a.keys, ...b.keys}.every((key) => _equal(a[key], b[key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static bool _apply(
    Map<String, dynamic> collection,
    _PatientMutation mutation,
  ) {
    final parts = mutation.path.split('/');
    final id = parts.first;
    final existing = collection[id];
    if (parts.length == 1) {
      if (mutation.value == null) {
        collection.remove(id);
        return true;
      }
      if (mutation.value is! Map) return false;
      if (existing is Map &&
          mutation.value['updatedAt'] is num &&
          existing['updatedAt'] is num &&
          (mutation.value['updatedAt'] as num) <
              (existing['updatedAt'] as num)) {
        return false;
      }
      final record = mutation.isPatch && existing is Map
          ? {...Map<String, dynamic>.from(existing), ...mutation.value as Map}
          : Map<String, dynamic>.from(mutation.value as Map);
      if (record['fullName'] is! String) return false;
      collection[id] = record;
      return true;
    }
    if (existing is! Map) return false;
    final record = Map<String, dynamic>.from(existing);
    _setField(record, parts.sublist(1), mutation.value);
    collection[id] = record;
    return true;
  }

  static void _setField(
    Map<String, dynamic> record,
    List<String> path,
    dynamic data,
  ) {
    if (path.length == 1) {
      if (data == null) {
        record.remove(path.first);
      } else {
        record[path.first] = data;
      }
      return;
    }
    final old = record[path.first];
    final child = old is Map
        ? Map<String, dynamic>.from(old)
        : <String, dynamic>{};
    _setField(child, path.sublist(1), data);
    record[path.first] = child;
  }
}
