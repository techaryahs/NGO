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
          return PricingHelper.approvedPricing({
            ...RoomService.defaultPricing,
            ...data,
          });
        }
        return PricingHelper.approvedPricing(RoomService.defaultPricing);
      }

      final data = await rtdb.get(pricingPath);
      if (data != null && data is Map) {
        return PricingHelper.approvedPricing({
          ...RoomService.defaultPricing,
          ...Map<String, dynamic>.from(data),
        });
      }
      return PricingHelper.approvedPricing(RoomService.defaultPricing);
    } catch (e) {
      throw Exception('Failed to fetch pricing: $e');
    }
  }

  Future<void> updatePricing(Map<String, dynamic> pricing) async {
    try {
      pricing = PricingHelper.approvedPricing(pricing);
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
          return PricingHelper.approvedPricing({
            ...RoomService.defaultPricing,
            ...Map<String, dynamic>.from(data),
          });
        }
        return PricingHelper.approvedPricing(RoomService.defaultPricing);
      });
    }

    return rtdb.stream(pricingPath).map((data) {
      if (data != null && data is Map) {
        return PricingHelper.approvedPricing({
          ...RoomService.defaultPricing,
          ...Map<String, dynamic>.from(data),
        });
      }
      return PricingHelper.approvedPricing(RoomService.defaultPricing);
    });
  }
}
