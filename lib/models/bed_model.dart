/// BedModel — RTDB-compatible data model for individual bed tracking.
///
/// Supports public/general room grouped bed labels:
/// - bed1 => Bed 1/2
/// - bed2 => Bed 3/4
/// - bed3 => Bed 5/6
/// - bed4 => Bed 7/8
/// - bed5 => Bed 9/10
/// - bed6 => Bed 11/12
///
/// Also supports private room labels such as:
/// - 1A, 1B, 1C, 1D, 2A, etc.
class BedModel {
  final String id; // Format: roomID_bedLabel (e.g. "room1_bed1")
  final String bedLabel; // Stored value (e.g. "bed1", "bed2", "1A")
  final String status; // 'available', 'occupied', 'maintenance'
  final String? currentPatientId;
  final String? currentStayId;
  final DateTime? lastCleaned;

  BedModel({
    required this.id,
    required this.bedLabel,
    required this.status,
    this.currentPatientId,
    this.currentStayId,
    this.lastCleaned,
  });

  // ─────────────────────────────────────────────────────────────
  // Computed Properties
  // ─────────────────────────────────────────────────────────────

  bool get isAvailable => status == 'available';
  bool get isOccupied => status == 'occupied';
  bool get isMaintenance => status == 'maintenance';

  // ─────────────────────────────────────────────────────────────
  // Factory Constructors
  // ─────────────────────────────────────────────────────────────

  /// Generate a unique bed ID from room ID and bed label
  static String generateId(String roomId, String bedLabel) {
    return '${roomId}_$bedLabel';
  }

  /// Create a new available bed
  factory BedModel.create({
    required String roomId,
    required String bedLabel,
  }) {
    return BedModel(
      id: generateId(roomId, bedLabel),
      bedLabel: bedLabel,
      status: 'available',
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Serialization
  // ─────────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bedLabel': bedLabel,
      'status': status,
      'currentPatientId': currentPatientId,
      'currentStayId': currentStayId,
      'lastCleaned': lastCleaned?.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  // ─────────────────────────────────────────────────────────────
  // Deserialization
  // ─────────────────────────────────────────────────────────────

  factory BedModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return BedModel(
      id: id,
      bedLabel: _parseString(data['bedLabel']),
      status: _parseString(data['status'], fallback: 'available'),
      currentPatientId: data['currentPatientId']?.toString(),
      currentStayId: data['currentStayId']?.toString(),
      lastCleaned: data['lastCleaned'] != null
          ? _parseDateTime(data['lastCleaned'])
          : null,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // copyWith
  // ─────────────────────────────────────────────────────────────

  BedModel copyWith({
    String? id,
    String? bedLabel,
    String? status,
    String? currentPatientId,
    String? currentStayId,
    DateTime? lastCleaned,
    bool clearPatientId = false,
    bool clearStayId = false,
    bool clearLastCleaned = false,
  }) {
    return BedModel(
      id: id ?? this.id,
      bedLabel: bedLabel ?? this.bedLabel,
      status: status ?? this.status,
      currentPatientId:
      clearPatientId ? null : (currentPatientId ?? this.currentPatientId),
      currentStayId:
      clearStayId ? null : (currentStayId ?? this.currentStayId),
      lastCleaned:
      clearLastCleaned ? null : (lastCleaned ?? this.lastCleaned),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  /// Converts stored bed IDs into user-friendly labels.
  ///
  /// Public/General room mappings:
  /// - bed1 => Bed 1/2
  /// - bed2 => Bed 3/4
  /// - bed3 => Bed 5/6
  /// - bed4 => Bed 7/8
  /// - bed5 => Bed 9/10
  /// - bed6 => Bed 11/12
  ///
  /// Private room labels are returned unchanged.
  ///
  /// Supports backward compatibility:
  /// - "1" => Bed 1/2
  /// - "2" => Bed 3/4
  /// - "3" => Bed 5/6
  /// - etc.
  static String formatBedLabel(String rawLabel, String roomType) {
    // Only convert labels for public/general rooms.
    if (roomType != 'general' && roomType != 'public') {
      return rawLabel;
    }

    const publicBedLabels = {
      'bed1': 'Bed 1/2',
      'bed2': 'Bed 3/4',
      'bed3': 'Bed 5/6',
      'bed4': 'Bed 7/8',
      'bed5': 'Bed 9/10',
      'bed6': 'Bed 11/12',
    };

    // Preferred storage format: bed1, bed2, bed3...
    if (publicBedLabels.containsKey(rawLabel)) {
      return publicBedLabels[rawLabel]!;
    }

    // Backward compatibility: if database contains "1", "2", "3"...
    final value = int.tryParse(rawLabel);
    if (value != null && value >= 1 && value <= 6) {
      return publicBedLabels['bed$value']!;
    }

    // If no mapping is found, return original label.
    return rawLabel;
  }

  static String _parseString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (value is double) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    final parsed = int.tryParse(value.toString());
    return DateTime.fromMillisecondsSinceEpoch(parsed ?? 0);
  }

  // ─────────────────────────────────────────────────────────────
  // Overrides
  // ─────────────────────────────────────────────────────────────

  @override
  String toString() {
    return 'BedModel(id: $id, label: $bedLabel, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BedModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}