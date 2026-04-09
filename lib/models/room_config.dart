import 'dart:convert';
import 'package:flutter/services.dart';

/// Room Configuration Model - Loads from room_config.json
/// 
/// Defines the hospital's room structure:
/// - Floor 1 (Ground): 1A (Private), 1B-D (General)
/// - Floor 2 (First): 2A-B (Private), 2C-E (General)
class RoomConfig {
  final List<FloorConfig> floors;
  final Map<String, int> defaultBedCounts;

  RoomConfig({
    required this.floors,
    required this.defaultBedCounts,
  });

  /// Load room configuration from JSON asset
  static Future<RoomConfig> load() async {
    try {
      final jsonString = await rootBundle.loadString('lib/data/room_config.json');
      final jsonData = json.decode(jsonString);
      return RoomConfig.fromJson(jsonData);
    } catch (e) {
      throw Exception('Failed to load room configuration: $e');
    }
  }

  factory RoomConfig.fromJson(Map<String, dynamic> json) {
    final floors = (json['floors'] as List)
        .map((f) => FloorConfig.fromJson(f))
        .toList();

    final bedCounts = Map<String, int>.from(json['default_bed_counts']);

    return RoomConfig(
      floors: floors,
      defaultBedCounts: bedCounts,
    );
  }

  /// Get floor configuration by floor number
  FloorConfig? getFloor(int floorNumber) {
    try {
      return floors.firstWhere((f) => f.floorNumber == floorNumber);
    } catch (e) {
      return null;
    }
  }

  /// Get available room identifiers for a floor and room type
  List<String> getAvailableRooms({
    required int floor,
    required String roomType,
  }) {
    final floorConfig = getFloor(floor);
    if (floorConfig == null) return [];

    if (roomType == 'private') {
      return floorConfig.privateRooms;
    } else {
      return floorConfig.generalWards;
    }
  }

  /// Get default bed count for a room identifier
  int getDefaultBedCount(String roomIdentifier) {
    return defaultBedCounts[roomIdentifier] ?? 4;
  }

  /// Validate if a room identifier is valid for the given floor and type
  bool isValidRoom({
    required String roomIdentifier,
    required int floor,
    required String roomType,
  }) {
    final availableRooms = getAvailableRooms(floor: floor, roomType: roomType);
    return availableRooms.contains(roomIdentifier);
  }

  /// Get all room identifiers
  List<String> getAllRoomIdentifiers() {
    return defaultBedCounts.keys.toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'floors': floors.map((f) => f.toJson()).toList(),
      'default_bed_counts': defaultBedCounts,
    };
  }
}

/// Floor Configuration
class FloorConfig {
  final int floorNumber;
  final List<String> privateRooms;
  final List<String> generalWards;

  FloorConfig({
    required this.floorNumber,
    required this.privateRooms,
    required this.generalWards,
  });

  factory FloorConfig.fromJson(Map<String, dynamic> json) {
    return FloorConfig(
      floorNumber: json['floor_number'] as int,
      privateRooms: List<String>.from(json['private_rooms']),
      generalWards: List<String>.from(json['general_wards']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'floor_number': floorNumber,
      'private_rooms': privateRooms,
      'general_wards': generalWards,
    };
  }

  /// Get all rooms for this floor
  List<String> getAllRooms() {
    return [...privateRooms, ...generalWards];
  }

  /// Get rooms by type
  List<String> getRoomsByType(String roomType) {
    if (roomType == 'private') {
      return privateRooms;
    } else {
      return generalWards;
    }
  }
}