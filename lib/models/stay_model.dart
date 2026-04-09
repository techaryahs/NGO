/// StayModel - RTDB-compatible data model for Stay Management.
///
/// Tracks a patient's stay in a room, including:
/// - Duration and expected discharge date
/// - Stay extensions
/// - Attendant tracking
/// - Pricing breakdown
///
/// All dates are stored as millisecondsSinceEpoch in RTDB.
class StayModel {
  final String id;
  final String patientId;
  final String patientName;
  final String roomId;
  final String roomNumber;
  final String roomType; // 'private' or 'general'

  // Duration
  final DateTime admissionDate;
  final int durationDays;
  final DateTime expectedDischargeDate;
  final DateTime expiryDate; // kept for backward compatibility
  final int totalExtendedDays;

  // Attendants
  final int attendantCount;

  // Pricing
  final double totalCost;
  final double baseCost;
  final double extraAttendantCost;

  // Extensions history
  final List<StayExtension> extensions;

  // Status
  final String status; // 'active', 'completed', 'cancelled'

  // Bed (for general rooms)
  final int? bedNumber;
  final String? bedId;

  // Metadata
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  StayModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.roomId,
    required this.roomNumber,
    required this.roomType,
    required this.admissionDate,
    required this.durationDays,
    required this.expectedDischargeDate,
    required this.expiryDate,
    this.totalExtendedDays = 0,
    this.attendantCount = 0,
    this.totalCost = 0,
    this.baseCost = 0,
    this.extraAttendantCost = 0,
    this.extensions = const [],
    required this.status,
    this.bedNumber,
    this.bedId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  bool get isActive => status == 'active';

  /// Uses expected discharge date plus extensions to determine effective expiry.
  DateTime get effectiveExpiryDate {
    return expectedDischargeDate.add(Duration(days: totalExtendedDays));
  }

  bool get isExpired => DateTime.now().isAfter(effectiveExpiryDate);

  int get totalDays => durationDays + totalExtendedDays;

  int get daysRemaining => effectiveExpiryDate.difference(DateTime.now()).inDays;

  static DateTime calculateExpiryDate(DateTime admissionDate, int days) {
    return admissionDate.add(Duration(days: days));
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'roomId': roomId,
      'roomNumber': roomNumber,
      'roomType': roomType,
      'admissionDate': admissionDate.millisecondsSinceEpoch,
      'durationDays': durationDays,
      'expectedDischargeDate': expectedDischargeDate.millisecondsSinceEpoch,
      // Keep legacy field while transitioning existing UI/logic.
      'expiryDate': expiryDate.millisecondsSinceEpoch,
      'totalExtendedDays': totalExtendedDays,
      'attendantCount': attendantCount,
      'totalCost': totalCost,
      'baseCost': baseCost,
      'extraAttendantCost': extraAttendantCost,
      'extensions': extensions.map((e) => e.toMap()).toList(),
      'status': status,
      'bedNumber': bedNumber,
      'bedId': bedId,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory StayModel.fromMap(String id, Map<dynamic, dynamic> data) {
    final List<StayExtension> extensionsList = [];
    if (data['extensions'] != null) {
      if (data['extensions'] is List) {
        for (var ext in data['extensions']) {
          if (ext is Map) {
            extensionsList.add(StayExtension.fromMap(Map<String, dynamic>.from(ext)));
          }
        }
      } else if (data['extensions'] is Map) {
        final extMap = Map<String, dynamic>.from(data['extensions']);
        extMap.forEach((_, value) {
          if (value is Map) {
            extensionsList.add(StayExtension.fromMap(Map<String, dynamic>.from(value)));
          }
        });
      }
    }

    final expectedDischarge = _parseDateTime(
      data['expectedDischargeDate'] ?? data['expiryDate'],
    );

    return StayModel(
      id: id,
      patientId: _parseString(data['patientId']),
      patientName: _parseString(data['patientName']),
      roomId: _parseString(data['roomId']),
      roomNumber: _parseString(data['roomNumber']),
      roomType: _parseString(data['roomType'], fallback: 'general'),
      admissionDate: _parseDateTime(data['admissionDate']),
      durationDays: _parseInt(data['durationDays']),
      expectedDischargeDate: expectedDischarge,
      expiryDate: _parseDateTime(data['expiryDate'] ?? data['expectedDischargeDate']),
      totalExtendedDays: _parseInt(data['totalExtendedDays']),
      attendantCount: _parseInt(data['attendantCount']),
      totalCost: _parseDouble(data['totalCost']),
      baseCost: _parseDouble(data['baseCost']),
      extraAttendantCost: _parseDouble(data['extraAttendantCost']),
      extensions: extensionsList,
      status: _parseString(data['status'], fallback: 'active'),
      bedNumber: data['bedNumber'] != null ? _parseInt(data['bedNumber']) : null,
      bedId: data['bedId']?.toString(),
      notes: data['notes']?.toString(),
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      createdBy: _parseString(data['createdBy']),
    );
  }

  StayModel copyWith({
    String? id,
    String? patientId,
    String? patientName,
    String? roomId,
    String? roomNumber,
    String? roomType,
    DateTime? admissionDate,
    int? durationDays,
    DateTime? expectedDischargeDate,
    DateTime? expiryDate,
    int? totalExtendedDays,
    int? attendantCount,
    double? totalCost,
    double? baseCost,
    double? extraAttendantCost,
    List<StayExtension>? extensions,
    String? status,
    int? bedNumber,
    String? bedId,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return StayModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      roomId: roomId ?? this.roomId,
      roomNumber: roomNumber ?? this.roomNumber,
      roomType: roomType ?? this.roomType,
      admissionDate: admissionDate ?? this.admissionDate,
      durationDays: durationDays ?? this.durationDays,
      expectedDischargeDate: expectedDischargeDate ?? this.expectedDischargeDate,
      expiryDate: expiryDate ?? this.expiryDate,
      totalExtendedDays: totalExtendedDays ?? this.totalExtendedDays,
      attendantCount: attendantCount ?? this.attendantCount,
      totalCost: totalCost ?? this.totalCost,
      baseCost: baseCost ?? this.baseCost,
      extraAttendantCost: extraAttendantCost ?? this.extraAttendantCost,
      extensions: extensions ?? this.extensions,
      status: status ?? this.status,
      bedNumber: bedNumber ?? this.bedNumber,
      bedId: bedId ?? this.bedId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  static String _parseString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double _parseDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final parsed = int.tryParse(value.toString());
    return DateTime.fromMillisecondsSinceEpoch(parsed ?? 0);
  }

  @override
  String toString() {
    return 'StayModel(id: $id, patient: $patientName, room: $roomNumber, status: $status, daysLeft: $daysRemaining)';
  }
}

/// Extension record for tracking stay extensions.
class StayExtension {
  final int additionalDays;
  final DateTime extendedOn;
  final String reason;
  final double additionalCost;

  StayExtension({
    required this.additionalDays,
    required this.extendedOn,
    this.reason = '',
    this.additionalCost = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'additionalDays': additionalDays,
      'extendedOn': extendedOn.millisecondsSinceEpoch,
      'reason': reason,
      'additionalCost': additionalCost,
    };
  }

  factory StayExtension.fromMap(Map<String, dynamic> data) {
    return StayExtension(
      additionalDays: data['additionalDays'] is int
          ? data['additionalDays']
          : int.tryParse(data['additionalDays']?.toString() ?? '0') ?? 0,
      extendedOn: data['extendedOn'] is int
          ? DateTime.fromMillisecondsSinceEpoch(data['extendedOn'])
          : DateTime.now(),
      reason: data['reason']?.toString() ?? '',
      additionalCost: data['additionalCost'] is double
          ? data['additionalCost']
          : (data['additionalCost'] is int
              ? (data['additionalCost'] as int).toDouble()
              : double.tryParse(data['additionalCost']?.toString() ?? '0') ?? 0),
    );
  }
}
