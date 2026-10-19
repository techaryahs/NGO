part of 'room_service.dart';

/// Pricing operations for RoomService.
///
/// Handles CRUD for the admin pricing configuration stored
/// at `admin_settings/pricing` in RTDB.
extension RoomServicePricing on RoomService {
  // --- Pricing ---

  Future<Map<String, dynamic>> getPricing() async {
    try {
      if (isPostgres) {
        final data = await backendApi!.getSettingsCategory('pricing');
        if (data.isNotEmpty) {
          final pricing = Map<String, dynamic>.from(data);
          final generalRate = (pricing['generalRoomBedPrice'] as num?)?.toDouble();
          if (generalRate == null || generalRate == 150) {
            pricing['generalRoomBedPrice'] = 200;
            await backendApi!.updateSettingsKey('pricing', 'generalRoomBedPrice', 200);
          }
          return pricing;
        }
        await backendApi!.updateSettingsCategory(
          'pricing',
          Map<String, dynamic>.from(RoomService.defaultPricing),
        );
        return Map<String, dynamic>.from(RoomService.defaultPricing);
      }

      final data = await rtdb.get(pricingPath);
      if (data != null && data is Map) {
        final pricing = Map<String, dynamic>.from(data);
        // ₹150 was the application's old built-in fallback. The configured
        // General Room and Lobby base rate is now ₹200.
        final generalRate = (pricing['generalRoomBedPrice'] as num?)?.toDouble();
        if (generalRate == null || generalRate == 150) {
          pricing['generalRoomBedPrice'] = 200;
          await rtdb.patch(pricingPath, {'generalRoomBedPrice': 200});
        }
        return pricing;
      }
      await rtdb.put(
        pricingPath,
        Map<String, dynamic>.from(RoomService.defaultPricing),
      );
      return Map<String, dynamic>.from(RoomService.defaultPricing);
    } catch (e) {
      throw Exception('Failed to fetch pricing: $e');
    }
  }

  Future<void> updatePricing(Map<String, dynamic> pricing) async {
    try {
      if (isPostgres) {
        await backendApi!.updateSettingsCategory('pricing', pricing);
        return;
      }

      await rtdb.patch(pricingPath, pricing);
      final privateMaxAttendants = parseIntSafe(
        pricing['privateRoomMaxAttendants'],
        5,
      );
      final generalMaxAttendants = parseIntSafe(
        pricing['generalRoomMaxAttendants'],
        2,
      );
      final rooms = await getRoomsStream().first;
      final updates = <String, dynamic>{};
      for (final room in rooms.where((room) => !room.hasCustomAttendantLimit)) {
        updates['rooms/${room.id}/maxAttendants'] = room.isPrivate
            ? privateMaxAttendants
            : generalMaxAttendants;
        updates['rooms/${room.id}/updatedAt'] =
            DateTime.now().millisecondsSinceEpoch;
      }
      if (updates.isNotEmpty) await rtdb.patch('', updates);
    } catch (e) {
      throw Exception('Failed to update pricing: $e');
    }
  }

  Stream<Map<String, dynamic>> getPricingStream() {
    if (isPostgres) {
      return backendApi!.stream('settings/pricing').map((data) {
        if (data != null && data is Map) {
          return Map<String, dynamic>.from(data);
        }
        return Map<String, dynamic>.from(RoomService.defaultPricing);
      });
    }

    return rtdb.stream(pricingPath).map((data) {
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return Map<String, dynamic>.from(RoomService.defaultPricing);
    });
  }
}
