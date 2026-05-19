import 'firebase_rtdb_rest_service.dart';
import '../models/sponsorship_model.dart';

/// Business logic service for Sponsorships, managing streams and REST CRUD actions
class SponsorshipService {
  final FirebaseRTDBRestService _rtdbService;

  SponsorshipService({required FirebaseRTDBRestService rtdbService}) : _rtdbService = rtdbService;

  /// Fetch a real-time reactive stream of all sponsorships
  Stream<List<SponsorshipModel>> getSponsorshipsStream() {
    return _rtdbService.stream('sponsorships').map((data) {
      if (data == null) return [];
      final list = <SponsorshipModel>[];
      data.forEach((key, value) {
        if (value is Map) {
          list.add(SponsorshipModel.fromMap(key, value));
        }
      });
      
      // Sort sponsorships chronologically by default
      list.sort((a, b) => b.sponsorshipDate.compareTo(a.sponsorshipDate));
      return list;
    });
  }

  /// Record a new sponsorship and patch its auto-generated key ID
  Future<void> addSponsorship(SponsorshipModel sponsorship) async {
    final Map<String, dynamic> data = sponsorship.toMap();
    data.remove('id'); // Remove id placeholder before push
    
    final String key = await _rtdbService.push('sponsorships', data);
    if (key.isNotEmpty) {
      // Patch the id field inside the node
      await _rtdbService.patch('sponsorships/$key', {'id': key});
    }
  }

  /// Update an existing sponsorship record
  Future<void> updateSponsorship(String id, SponsorshipModel sponsorship) async {
    final Map<String, dynamic> data = sponsorship.toMap();
    await _rtdbService.put('sponsorships/$id', data);
  }

  /// Delete a sponsorship record permanently
  Future<void> deleteSponsorship(String id) async {
    await _rtdbService.delete('sponsorships/$id');
  }
}
