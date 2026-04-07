/// RoomModel — RTDB-compatible data model for Room Management.
///
/// Supports two room types:
/// - `private`: Independent room with attendant-based pricing.
/// - `general`: Bed-based system with individual bed tracking.
///
/// All dates are stored as `millisecondsSinceEpoch` (int) in RTDB.
class RoomModel {
  final String id;
  final String roomNumber;
  final int floor;
  final String roomType; // 'private' or 'general'
  final String status; // 'available', 'occupied', 'maintenance'

  // ── Private Room Fields ──
  final int maxAttendants; // default: 5 for private
  final int currentAttendants;

  // ── General Room Fields ──
  final int totalBeds; // default: 4, admin-editable
  final int occupiedBeds;

  // ── Metadata ──
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  RoomModel({
    required this.id,
    required this.roomNumber,
    required this.floor,
    required this.roomType,
    required this.status,
    this.maxAttendants = 5,
    this.currentAttendants = 0,
    this.totalBeds = 4,
    this.occupiedBeds = 0,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Computed Properties ──

  bool get isPrivate => roomType == 'private';
  bool get isGeneral => roomType == 'general';
  bool get isAvailable => status == 'available';
  bool get isOccupied => status == 'occupied';

  int get availableBeds => isGeneral ? totalBeds - occupiedBeds : 0;
  bool get hasAvailableBeds => isGeneral && availableBeds > 0;
  bool get canAddAttendant => isPrivate && currentAttendants < maxAttendants;

  // ── Dynamic Pricing Calculations ──

  /// Calculate the total cost for a private room stay.
  ///
  /// [days] — number of stay days
  /// [attendants] — number of attendants
  /// [basePrice] — fetched from /admin_settings/pricing
  /// [includedAttendants] — attendants included in base price
  /// [extraAttendantFee] — fee per extra attendant per day
  static double calculatePrivateRoomCost({
    required int days,
    required int attendants,
    required double basePrice,
    required int includedAttendants,
    required double extraAttendantFee,
  }) {
    final baseCost = basePrice * days;
    final extraAttendants =
        attendants > includedAttendants ? attendants - includedAttendants : 0;
    final extraCost = extraAttendants * extraAttendantFee * days;
    return baseCost + extraCost;
  }

  /// Calculate the total cost for a general room bed.
  ///
  /// [days] — number of stay days
  /// [bedPrice] — per-bed per-day rate from admin settings
  /// [attendants] — number of attendants (1 included, max 2)
  static double calculateGeneralRoomCost({
    required int days,
    required double bedPrice,
    required int attendants,
  }) {
    // Only 1 attendant included; 2nd is self-expense (no charge added)
    return bedPrice * days;
  }

  // ── Serialization ──

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'roomNumber': roomNumber,
      'floor': floor,
      'roomType': roomType,
      'status': status,
      'maxAttendants': maxAttendants,
      'currentAttendants': currentAttendants,
      'totalBeds': totalBeds,
      'occupiedBeds': occupiedBeds,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  // ── Deserialization ──

  factory RoomModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return RoomModel(
      id: id,
      roomNumber: _parseString(data['roomNumber']),
      floor: _parseInt(data['floor'], fallback: 1),
      roomType: _parseString(data['roomType'], fallback: 'general'),
      status: _parseString(data['status'], fallback: 'available'),
      maxAttendants: _parseInt(data['maxAttendants'], fallback: 5),
      currentAttendants: _parseInt(data['currentAttendants']),
      totalBeds: _parseInt(data['totalBeds'], fallback: 4),
      occupiedBeds: _parseInt(data['occupiedBeds']),
      notes: data['notes']?.toString(),
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  // ── copyWith ──

  RoomModel copyWith({
    String? id,
    String? roomNumber,
    int? floor,
    String? roomType,
    String? status,
    int? maxAttendants,
    int? currentAttendants,
    int? totalBeds,
    int? occupiedBeds,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoomModel(
      id: id ?? this.id,
      roomNumber: roomNumber ?? this.roomNumber,
      floor: floor ?? this.floor,
      roomType: roomType ?? this.roomType,
      status: status ?? this.status,
      maxAttendants: maxAttendants ?? this.maxAttendants,
      currentAttendants: currentAttendants ?? this.currentAttendants,
      totalBeds: totalBeds ?? this.totalBeds,
      occupiedBeds: occupiedBeds ?? this.occupiedBeds,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Helpers ──

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
  String toString() =>
      'RoomModel(id: $id, room: $roomNumber, type: $roomType, status: $status)';
}
