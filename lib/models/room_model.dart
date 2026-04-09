import 'bed_model.dart';

/// RoomModel - RTDB-compatible data model for Room Management.
///
/// Supports two room types:
/// - private: independent room with attendant-based pricing
/// - general: bed-based room with individual bed tracking
class RoomModel {
  final String id;
  final String roomNumber;
  final String roomIdentifier;
  final int floor;
  final String roomType; // 'private' or 'general'
  final String status; // 'available', 'occupied', 'pending_discharge', 'maintenance', 'unavailable'

  // Private room fields
  final int maxAttendants;
  final int currentAttendants;

  // Bed fields
  final List<BedModel> beds;
  final int totalBeds;
  final int occupiedBeds;

  // Availability metadata
  final DateTime? expectedVacancyDate;
  final DateTime? lastUpdated;

  // Generic metadata
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
    this.expectedVacancyDate,
    this.lastUpdated,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPrivate => roomType == 'private';
  bool get isGeneral => roomType == 'general';
  bool get isAvailable => status == 'available';
  bool get isOccupied => status == 'occupied';
  bool get isPendingDischarge => status == 'pending_discharge';

  int get actualTotalBeds => beds.isNotEmpty ? beds.length : totalBeds;
  int get actualOccupiedBeds => beds.where((b) => b.isOccupied).length;
  int get actualAvailableBeds => beds.where((b) => b.isAvailable).length;

  // Compatibility aliases used by UI/business logic.
  int get occupiedCount => actualOccupiedBeds;
  DateTime? get nextExpectedVacancyDate => expectedVacancyDate;
  int get availableBeds => actualAvailableBeds;
  bool get hasAvailableBeds => actualAvailableBeds > 0;
  bool get canAddAttendant => isPrivate && currentAttendants < maxAttendants;
  bool get isFull => actualOccupiedBeds >= actualTotalBeds;

  /// Derived occupancy from bed states with pending-discharge precedence.
  String get derivedOccupancyStatus {
    if (status == 'maintenance') return 'maintenance';
    if (status == 'pending_discharge') return 'pending_discharge';

    final occupied = actualOccupiedBeds;
    final total = actualTotalBeds;

    if (occupied == 0) return 'available';
    if (isPrivate) return 'occupied';
    if (occupied >= total) return 'occupied';
    return 'partially_occupied';
  }

  bool get isPartiallyOccupied => derivedOccupancyStatus == 'partially_occupied';
  bool get isDerivedAvailable => derivedOccupancyStatus == 'available';
  bool get isDerivedOccupied => derivedOccupancyStatus == 'occupied';

  static const List<String> privateRoomIdentifiers = ['1A', '2A', '2B'];
  static const List<String> generalWardIdentifiers = ['1B', '1C', '1D', '2C', '2D', '2E'];
  static const List<String> floor1Rooms = ['1A', '1B', '1C', '1D'];
  static const List<String> floor2Rooms = ['2A', '2B', '2C', '2D', '2E'];

  static bool isPrivateRoomIdentifier(String identifier) {
    return privateRoomIdentifiers.contains(identifier.toUpperCase());
  }

  static String getRoomTypeFromIdentifier(String identifier) {
    return isPrivateRoomIdentifier(identifier) ? 'private' : 'general';
  }

  static int getFloorFromIdentifier(String identifier) {
    final upper = identifier.toUpperCase();
    if (floor1Rooms.contains(upper)) return 1;
    if (floor2Rooms.contains(upper)) return 2;
    if (upper.startsWith('1')) return 1;
    if (upper.startsWith('2')) return 2;
    return 1;
  }

  static bool validateIdentifierForFloor(String identifier, int floor) {
    final upper = identifier.toUpperCase();
    if (floor == 1) {
      return upper.startsWith('1') && floor1Rooms.contains(upper);
    } else if (floor == 2) {
      return upper.startsWith('2') && floor2Rooms.contains(upper);
    }
    return false;
  }

  static List<String> getValidIdentifiersForFloor(int floor) {
    if (floor == 1) return List.from(floor1Rooms);
    if (floor == 2) return List.from(floor2Rooms);
    return [];
  }

  static double calculatePrivateRoomCost({
    required int days,
    required int attendants,
    required double basePrice,
    required int includedAttendants,
    required double extraAttendantFee,
  }) {
    final baseCost = basePrice * days;
    final extraAttendants = attendants > includedAttendants ? attendants - includedAttendants : 0;
    final extraCost = extraAttendants * extraAttendantFee * days;
    return baseCost + extraCost;
  }

  static double calculateGeneralRoomCost({
    required int days,
    required double bedPrice,
    required int attendants,
  }) {
    return bedPrice * days;
  }

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
      'expectedVacancyDate': expectedVacancyDate?.millisecondsSinceEpoch,
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory RoomModel.fromMap(String id, Map<dynamic, dynamic> data) {
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
            bedsList.add(BedModel.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
      }
    }

    return RoomModel(
      id: id,
      roomNumber: _parseString(data['roomNumber']),
      roomIdentifier: _parseString(
        data['roomIdentifier'],
        fallback: data['roomNumber']?.toString() ?? '',
      ),
      floor: _parseInt(data['floor'], fallback: 1),
      roomType: _parseString(data['roomType'], fallback: 'general'),
      status: _parseString(data['status'], fallback: 'available'),
      maxAttendants: _parseInt(data['maxAttendants'], fallback: 5),
      currentAttendants: _parseInt(data['currentAttendants']),
      beds: bedsList,
      totalBeds: _parseInt(data['totalBeds'], fallback: 4),
      occupiedBeds: _parseInt(data['occupiedBeds']),
      expectedVacancyDate: data['expectedVacancyDate'] != null
          ? _parseDateTime(data['expectedVacancyDate'])
          : null,
      lastUpdated: data['lastUpdated'] != null
          ? _parseDateTime(data['lastUpdated'])
          : null,
      notes: data['notes']?.toString(),
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

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
    DateTime? expectedVacancyDate,
    DateTime? lastUpdated,
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
      expectedVacancyDate: expectedVacancyDate ?? this.expectedVacancyDate,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final parsed = int.tryParse(value.toString());
    return DateTime.fromMillisecondsSinceEpoch(parsed ?? 0);
  }

  @override
  String toString() {
    return 'RoomModel(id: $id, room: $roomNumber, identifier: $roomIdentifier, type: $roomType, status: $status)';
  }
}
