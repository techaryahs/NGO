import 'dart:developer' as developer;

import 'firebase_rtdb_rest_service.dart';
import 'photo_rtdb_service.dart';

class PhotoMigrationReport {
  final int scannedPatients, uploadedPatientPhotos, uploadedAttendantPhotos;
  final int alreadyMigrated, skippedNoPhoto, failed;
  final List<String> errors;
  const PhotoMigrationReport({
    required this.scannedPatients,
    required this.uploadedPatientPhotos,
    required this.uploadedAttendantPhotos,
    required this.alreadyMigrated,
    required this.skippedNoPhoto,
    required this.failed,
    required this.errors,
  });
  bool get allDone => failed == 0;
}

/// Restartable migration. Legacy bytes are removed only after a targeted
/// RTDB write has been read back and verified.
class PhotoMigrationService {
  PhotoMigrationService({
    required FirebaseRTDBRestService rtdb,
    required PhotoRtdbService photos,
  }) : _rtdb = rtdb,
       _photos = photos;

  final FirebaseRTDBRestService _rtdb;
  final PhotoRtdbService _photos;

  Future<PhotoMigrationReport> migrate() async {
    var scanned = 0, patientCount = 0, attendantCount = 0;
    var already = 0, skipped = 0, failed = 0;
    final errors = <String>[];
    final rawPatients = await _rtdb.get('patients');
    if (rawPatients is! Map) {
      return const PhotoMigrationReport(
        scannedPatients: 0,
        uploadedPatientPhotos: 0,
        uploadedAttendantPhotos: 0,
        alreadyMigrated: 0,
        skippedNoPhoto: 0,
        failed: 0,
        errors: [],
      );
    }
    for (final entry in rawPatients.entries) {
      if (entry.value is! Map) continue;
      final id = entry.key.toString();
      final patient = Map<String, dynamic>.from(entry.value as Map);
      scanned++;
      final updates = <String, dynamic>{};
      try {
        final rawStays = await _rtdb.getByChildValue(
          'stays',
          child: 'patientId',
          value: id,
        );
        final stays = rawStays is Map ? rawStays : <String, dynamic>{};
        final target = PhotoRtdbService.patientPath(id);
        var verified = await _photos.photoExists(target);
        String? source = patient['photoDataUrl']?.toString();
        if ((source == null || source.isEmpty) && !verified) {
          for (final stay in stays.values) {
            if (stay is Map && stay['patientSnapshot'] is Map) {
              final legacy = (stay['patientSnapshot'] as Map)['photoDataUrl'];
              if (legacy is String && legacy.isNotEmpty) {
                source = legacy;
                break;
              }
            }
          }
        }
        try {
          if (!verified && source != null && source.isNotEmpty) {
            final bytes = PhotoRtdbService.decodeLegacyBase64(source);
            if (bytes == null) throw FormatException('Invalid patient photo');
            await _photos.uploadPhoto(photoPath: target, bytes: bytes);
            verified = await _photos.photoExists(target);
            if (!verified)
              throw StateError('Patient photo could not be verified');
            patientCount++;
          } else if (verified) {
            already++;
          } else if (patient['photoRef'] != null ||
              patient['photoStorageRef'] != null) {
            throw StateError(
              'Photo reference has no RTDB photo or legacy bytes',
            );
          } else {
            skipped++;
          }
          if (verified) {
            updates['patients/$id/photoRef'] = target;
            updates['patients/$id/photoDataUrl'] = null;
            updates['patients/$id/photoStorageRef'] = null;
          }
        } catch (e) {
          failed++;
          errors.add('$id patient photo: $e');
          developer.log(
            'Patient photo migration failed: $id: $e',
            name: 'photo_migration',
          );
        }

        final rawAttendants = patient['attendants'];
        if (rawAttendants is List) {
          for (var i = 0; i < rawAttendants.length; i++) {
            if (rawAttendants[i] is! Map) continue;
            final attendant = Map<String, dynamic>.from(rawAttendants[i]);
            final path = PhotoRtdbService.attendantPath(id, '$i');
            try {
              var valid = await _photos.photoExists(path);
              final legacy = attendant['photoDataUrl']?.toString();
              if (!valid && legacy != null && legacy.isNotEmpty) {
                final bytes = PhotoRtdbService.decodeLegacyBase64(legacy);
                if (bytes == null)
                  throw FormatException('Invalid attendant photo');
                await _photos.uploadPhoto(photoPath: path, bytes: bytes);
                valid = await _photos.photoExists(path);
                if (!valid)
                  throw StateError('Attendant photo verification failed');
                attendantCount++;
              }
              if (!valid &&
                  (attendant['photoRef'] != null ||
                      attendant['photoStorageRef'] != null)) {
                throw StateError(
                  'Attendant reference has no RTDB photo or legacy bytes',
                );
              }
              if (valid) {
                updates['patients/$id/attendants/$i/photoRef'] = path;
                updates['patients/$id/attendants/$i/photoDataUrl'] = null;
                updates['patients/$id/attendants/$i/photoStorageRef'] = null;
              }
            } catch (e) {
              failed++;
              errors.add('$id attendant $i: $e');
              developer.log(
                'Attendant photo migration failed: $id/$i: $e',
                name: 'photo_migration',
              );
            }
          }
        }

        for (final stayEntry in stays.entries) {
          final stay = stayEntry.value;
          if (stay is! Map || stay['patientSnapshot'] is! Map) continue;
          final snapshot = Map<String, dynamic>.from(stay['patientSnapshot']);
          if (verified) {
            updates['stays/${stayEntry.key}/patientSnapshot/photoDataUrl'] =
                null;
            updates['stays/${stayEntry.key}/patientSnapshot/photoStorageRef'] =
                null;
            updates['stays/${stayEntry.key}/patientSnapshot/photoRef'] = target;
          }
          final rawHistorical = snapshot['attendants'];
          if (rawHistorical is List) {
            for (var i = 0; i < rawHistorical.length; i++) {
              if (rawHistorical[i] is! Map) continue;
              final attendant = Map<String, dynamic>.from(rawHistorical[i]);
              final legacy = attendant['photoDataUrl']?.toString();
              if (legacy == null || legacy.isEmpty) {
                if (attendant['photoStorageRef'] != null) {
                  failed++;
                  errors.add(
                    '$id stay ${stayEntry.key} attendant $i: '
                    'Storage-only photo has no legacy bytes',
                  );
                }
                continue;
              }
              final path = PhotoRtdbService.attendantPath(
                id,
                'stay_${stayEntry.key}_$i',
              );
              try {
                if (!await _photos.photoExists(path)) {
                  final bytes = PhotoRtdbService.decodeLegacyBase64(legacy);
                  if (bytes == null)
                    throw FormatException('Invalid historical photo');
                  await _photos.uploadPhoto(photoPath: path, bytes: bytes);
                  attendantCount++;
                }
                if (!await _photos.photoExists(path)) {
                  throw StateError('Historical photo verification failed');
                }
                updates['stays/${stayEntry.key}/patientSnapshot/attendants/$i/photoRef'] =
                    path;
                updates['stays/${stayEntry.key}/patientSnapshot/attendants/$i/photoDataUrl'] =
                    null;
                updates['stays/${stayEntry.key}/patientSnapshot/attendants/$i/photoStorageRef'] =
                    null;
              } catch (e) {
                failed++;
                errors.add('$id stay ${stayEntry.key} attendant $i: $e');
                developer.log(
                  'Historical photo migration failed: '
                  '$id/${stayEntry.key}/$i: $e',
                  name: 'photo_migration',
                );
              }
            }
          }
        }
        if (updates.isNotEmpty) await _rtdb.patch('', updates);
      } catch (e) {
        failed++;
        errors.add('$id: $e');
        developer.log(
          'Patient photo migration failed: $id: $e',
          name: 'photo_migration',
        );
      }
    }
    return PhotoMigrationReport(
      scannedPatients: scanned,
      uploadedPatientPhotos: patientCount,
      uploadedAttendantPhotos: attendantCount,
      alreadyMigrated: already,
      skippedNoPhoto: skipped,
      failed: failed,
      errors: errors,
    );
  }
}
