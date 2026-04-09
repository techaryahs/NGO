part of 'room_service.dart';

/// Pricing operations for RoomService.
///
/// Handles CRUD for the admin pricing configuration stored
/// at `admin_settings/pricing` in RTDB.
extension RoomServicePricing on RoomService {
  // --- Pricing ---

  Future<Map<String, dynamic>> getPricing() async {
    try {
      final data = await rtdb.get(pricingPath);
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      await rtdb.put(pricingPath, Map<String, dynamic>.from(RoomService.defaultPricing));
      return Map<String, dynamic>.from(RoomService.defaultPricing);
    } catch (e) {
      throw Exception('Failed to fetch pricing: $e');
    }
  }

  Future<void> updatePricing(Map<String, dynamic> pricing) async {
    try {
      await rtdb.patch(pricingPath, pricing);
    } catch (e) {
      throw Exception('Failed to update pricing: $e');
    }
  }

  Stream<Map<String, dynamic>> getPricingStream() {
    return rtdb.stream(pricingPath).map((data) {
      if (data != null && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return Map<String, dynamic>.from(RoomService.defaultPricing);
    });
  }
}
