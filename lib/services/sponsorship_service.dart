import 'backend_api_service.dart';
import 'firebase_rtdb_rest_service.dart';
import '../models/sponsorship_model.dart';

/// Business logic service for Sponsorships, managing streams and REST CRUD actions
class SponsorshipService {
  final FirebaseRTDBRestService? _rtdbService;
  final BackendApiService? _backendApi;

  SponsorshipService({
    FirebaseRTDBRestService? rtdbService,
    BackendApiService? backendApiService,
  })  : assert(
          rtdbService != null || backendApiService != null,
          'Provide either rtdbService or backendApiService',
        ),
        _rtdbService = rtdbService,
        _backendApi = backendApiService;

  bool get isPostgres => _backendApi != null;

  /// Fetch a real-time reactive stream of all sponsorships
  Stream<List<SponsorshipModel>> getSponsorshipsStream() {
    final stream = _backendApi != null
        ? _backendApi.stream('sponsorships')
        : _rtdbService!.stream('sponsorships');
    return stream.map((data) {
      if (data == null || data is! Map) return [];
      final list = <SponsorshipModel>[];
      data.forEach((key, value) {
        if (value is Map) {
          list.add(
            SponsorshipModel.fromMap(
              key.toString(),
              Map<String, dynamic>.from(value),
            ),
          );
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

    if (_backendApi != null) {
      await _backendApi.push('sponsorships', data);
      return;
    }

    final String key = await _rtdbService!.push('sponsorships', data);
    if (key.isNotEmpty) {
      // Patch the id field inside the node
      await _rtdbService.patch('sponsorships/$key', {'id': key});
    }
  }

  /// Update an existing sponsorship record
  Future<void> updateSponsorship(String id, SponsorshipModel sponsorship) async {
    final Map<String, dynamic> data = sponsorship.toMap();
    if (_backendApi != null) {
      await _backendApi.put('sponsorships/$id', data);
    } else {
      await _rtdbService!.put('sponsorships/$id', data);
    }
  }

  /// Delete a sponsorship record permanently
  Future<void> deleteSponsorship(String id) async {
    if (_backendApi != null) {
      await _backendApi.delete('sponsorships/$id');
    } else {
      await _rtdbService!.delete('sponsorships/$id');
    }
  }
}
