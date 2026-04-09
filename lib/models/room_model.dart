import 'bed_model.dart';

/// RoomModel — RTDB-compatible data model for Room Management.
///
/// Supports two room types:
/// - `private`: Independent room with attendant-based pricing.
/// - `general`: Bed-based system with individual bed tracking.
///
/// Room Classification Reference:
/// - Private: 1A, 2A, 2B (Pricing: Attendant-based)
/// - General: 1B, 1C, 1D, 2C, 2D, 2E (Pricing: Bed-based)
///
/// All dates are stored as `millisecondsSinceEpoch` (int) in RTDB.
class RoomModel {
  final String id;
  final String roomNumber;
  final String roomIdentifier; // e.g., "1D", "1A", "2C" (alphanumeric)
  final int floor;
  final String roomType; // 'private' or 'general'
  final String status; // 'available', 'occupied', 'maintenance'

  // ── Private Room Fields ──
  final int maxAttendants; // default: 5 for private
  final int currentAttendants;

  // ── General Room Fields (Hierarchical Bed System) ──
  final List<BedModel> beds; // Individual bed tracking
  final int totalBeds; // Legacy: default: 4, admin-editable
  final int occupiedBeds; // Legacy: computed from beds

  // ── Metadata ──
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  RoomModel({
    required this.id,
    required this.roomNumber,
    required this.roomIdentifier,
    required this.floor,
    required this.roomType,
    required this.status,
    this.maxAttendants = 5,
    this.currentAttendants = 0,
    this.beds = const [],
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

  // Hierarchical bed properties
  int get actualTotalBeds => beds.isNotEmpty ? beds.length : totalBeds;
  int get actualOccupiedBeds => beds.where((b) => b.isOccupied).length;
  int get actualAvailableBeds => beds.where((b) => b.isAvailable).length;
  
  // Legacy compatibility
  int get availableBeds => isGeneral ? actualTotalBeds - actualOccupiedBeds : 0;
  bool get hasAvailableBeds => isGeneral && actualAvailableBeds > 0;
  bool get canAddAttendant => isPrivate && currentAttendants < maxAttendants;
  bool get isFull => actualOccupiedBeds >= actualTotalBeds;

  // ── Room Classification ──

  /// Private room identifiers
  static const List<String> privateRoomIdentifiers = ['1A', '2A', '2B'];

  /// General ward identifiers
  static const List<String> generalWardIdentifiers = ['1B', '1C', '1D', '2C', '2D', '2E'];

  /// Floor 1 rooms (Ground Floor)
  static const List<String> floor1Rooms = ['1A', '1B', '1C', '1D'];

  /// Floor 2 rooms (First Floor)
  static const List<String> floor2Rooms = ['2A', '2B', '2C', '2D', '2E'];

  /// Check if room identifier matches private room pattern
  static bool isPrivateRoomIdentifier(String identifier) {
    return privateRoomIdentifiers.contains(identifier.toUpperCase());
  }

  /// Get room type from identifier
  static String getRoomTypeFromIdentifier(String identifier) {
    return isPrivateRoomIdentifier(identifier) ? 'private' : 'general';
  }

  /// Get floor from room identifier
  static int getFloorFromIdentifier(String identifier) {
    final upper = identifier.toUpperCase();
    if (floor1Rooms.contains(upper)) return 1;
    if (floor2Rooms.contains(upper)) return 2;
    // Fallback: check first character
    if (upper.startsWith('1')) return 1;
    if (upper.startsWith('2')) return 2;
    return 1; // Default to floor 1
  }

  /// Validate room identifier for a specific floor
  static bool validateIdentifierForFloor(String identifier, int floor) {
    final upper = identifier.toUpperCase();
    if (floor == 1) {
      return upper.startsWith('1') && floor1Rooms.contains(upper);
    } else if (floor == 2) {
      return upper.startsWith('2') && floor2Rooms.contains(upper);
    }
    return false;
  }

  /// Get valid room identifiers for a floor
  static List<String> getValidIdentifiersForFloor(int floor) {
    if (floor == 1) return List.from(floor1Rooms);
    if (floor == 2) return List.from(floor2Rooms);
    return [];
  }

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
      'roomIdentifier': roomIdentifier,
      'floor': floor,
      'roomType': roomType,
      'status': status,
      'maxAttendants': maxAttendants,
      'currentAttendants': currentAttendants,
      'beds': beds.map((b) => b.toMap()).toList(),
      'totalBeds': totalBeds,
      'occupiedBeds': actualOccupiedBeds,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  // ── Deserialization ──

  factory RoomModel.fromMap(String id, Map<dynamic, dynamic> data) {
    // Parse beds list
    final List<BedModel> bedsList = [];
    if (data['beds'] != null) {
      if (data['beds'] is List) {
        for (var bed in data['beds']) {
          if (bed is Map) {
            bedsList.add(
              BedModel.fromMap(
                bed['id']?.toString() ?? '',
                Map<String, dynamic>.from(bed),
              ),
            );
          }
        }
      } else if (data['beds'] is Map) {
        final bedsMap = Map<String, dynamic>.from(data['beds']);
        bedsMap.forEach((key, value) {
          if (value is Map) {
            bedsList.add(
              BedModel.fromMap(key, Map<String, dynamic>.from(value)),
            );
          }
        });
      }
    }

    return RoomModel(
      id: id,
      roomNumber: _parseString(data['roomNumber']),
      roomIdentifier: _parseString(data['roomIdentifier'], fallback: data['roomNumber']?.toString() ?? ''),
      floor: _parseInt(data['floor'], fallback: 1),
      roomType: _parseString(data['roomType'], fallback: 'general'),
      status: _parseString(data['status'], fallback: 'available'),
      maxAttendants: _parseInt(data['maxAttendants'], fallback: 5),
      currentAttendants: _parseInt(data['currentAttendants']),
      beds: bedsList,
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
    String? roomIdentifier,
    int? floor,
    String? roomType,
    String? status,
    int? maxAttendants,
    int? currentAttendants,
    List<BedModel>? beds,
    int? totalBeds,
    int? occupiedBeds,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoomModel(
      id: id ?? this.id,
      roomNumber: roomNumber ?? this.roomNumber,
      roomIdentifier: roomIdentifier ?? this.roomIdentifier,
      floor: floor ?? this.floor,
      roomType: roomType ?? this.roomType,
      status: status ?? this.status,
      maxAttendants: maxAttendants ?? this.maxAttendants,
      currentAttendants: currentAttendants ?? this.currentAttendants,
      beds: beds ?? this.beds,
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
      'RoomModel(id: $id, room: $roomNumber, identifier: $roomIdentifier, type: $roomType, status: $status)';
}