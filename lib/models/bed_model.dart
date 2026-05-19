/// BedModel — RTDB-compatible data model for individual bed tracking.
///
/// Supports non-sequential bed labels (e.g., "23", "21", "19").
/// Each bed has its own status and can be linked to a patient/stay.
class BedModel {
  final String id; // Format: roomID_bedLabel (e.g., "room1_23")
  final String bedLabel; // Non-sequential label (e.g., "23", "21", "19")
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

  // ── Computed Properties ──

  bool get isAvailable => status == 'available';
  bool get isOccupied => status == 'occupied';
  bool get isMaintenance => status == 'maintenance';

  // ── Factory Constructors ──

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

  // ── Serialization ──

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

  // ── Deserialization ──

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

  // ── copyWith ──

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
      currentPatientId: clearPatientId ? null : (currentPatientId ?? this.currentPatientId),
      currentStayId: clearStayId ? null : (currentStayId ?? this.currentStayId),
      lastCleaned: clearLastCleaned ? null : (lastCleaned ?? this.lastCleaned),
    );
  }

  // ── Helpers ──

  static String _parseString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    final parsed = int.tryParse(value.toString());
    return DateTime.fromMillisecondsSinceEpoch(parsed ?? 0);
  }

  @override
  String toString() => 'BedModel(id: $id, label: $bedLabel, status: $status)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BedModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}