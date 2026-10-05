import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/patient_service.dart';
import 'package:ngo/services/photo_migration_service.dart';
import 'package:ngo/services/photo_rtdb_service.dart';
import 'package:ngo/widgets/patient_photo.dart';

class MemoryPhotoDb extends FirebaseRTDBRestService {
  MemoryPhotoDb() : super(projectId: 'test');
  final records = <String, dynamic>{};
  final reads = <String, int>{};
  bool failPhotoWrite = false;

  @override
  Stream<dynamic> stream(String path, {Duration? pollInterval}) {
    reads[path] = (reads[path] ?? 0) + 1;
    return Stream.value(records[path]);
  }

  @override
  Future<dynamic> get(String path) async {
    reads[path] = (reads[path] ?? 0) + 1;
    return records[path];
  }

  @override
  Future<void> put(String path, Map<String, dynamic> data) async {
    if (failPhotoWrite && path.startsWith('patientPhotos/')) {
      throw StateError('simulated write failure');
    }
    records[path] = data;
  }

  @override
  Future<void> delete(String path) async {
    records.remove(path);
  }

  @override
  Future<dynamic> getByChildValue(
    String path, {
    required String child,
    required Object value,
  }) async {
    final collection = records[path];
    if (collection is! Map) return null;
    return {
      for (final entry in collection.entries)
        if (entry.value is Map && entry.value[child] == value)
          entry.key.toString(): entry.value,
    };
  }

  @override
  Future<void> patch(String path, Map<String, dynamic> updates) async {
    for (final update in updates.entries) {
      final parts = update.key.split('/');
      if (parts.length == 2) {
        records[update.key] = update.value;
        continue;
      }
      if (parts.length < 3) continue;
      final collection = records[parts[0]] as Map;
      final record = collection[parts[1]] as Map;
      dynamic target = record;
      for (final part in parts.skip(2).take(parts.length - 3)) {
        target = target is List
            ? target[int.parse(part)]
            : (target as Map).putIfAbsent(part, () => <String, dynamic>{});
      }
      if (update.value == null) {
        (target as Map).remove(parts.last);
      } else {
        (target as Map)[parts.last] = update.value;
      }
    }
  }
}

Uint8List testImage({int width = 80, int height = 80}) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: width, height: height)));

void main() {
  late MemoryPhotoDb db;
  late PhotoRtdbService photos;
  setUp(() {
    db = MemoryPhotoDb();
    photos = PhotoRtdbService(rtdb: db);
  });

  test('new photo is optimized, separate, and verified', () async {
    final path = PhotoRtdbService.patientPath('p1');
    final result = await photos.uploadPhoto(
      photoPath: path,
      bytes: testImage(width: 1200, height: 800),
    );
    expect(result, path);
    final record = db.records[path] as Map;
    expect(record['contentType'], 'image/jpeg');
    final bytes = base64Decode(record['data'] as String);
    expect(bytes.length, lessThan(PhotoRtdbService.maxEncodedBytes));
    final decoded = img.decodeImage(bytes)!;
    expect(decoded.width, lessThanOrEqualTo(720));
    expect(decoded.height, lessThanOrEqualTo(720));
    expect(db.records['patients'], isNull);
  });

  test('transparent source remains PNG', () {
    final source = img.Image(width: 48, height: 48, numChannels: 4);
    final prepared = PhotoRtdbService.prepare(
      Uint8List.fromList(img.encodePng(source)),
    );
    expect(prepared.contentType, 'image/png');
    expect(img.decodeImage(prepared.bytes), isNotNull);
  });

  test('replacement invalidates cache and removal deletes photo', () async {
    final path = PhotoRtdbService.patientPath('p1');
    await photos.uploadPhoto(photoPath: path, bytes: testImage());
    final first = await photos.downloadPhotoCached(path);
    await photos.uploadPhoto(photoPath: path, bytes: testImage(width: 32));
    final second = await photos.downloadPhotoCached(path);
    expect(second, isNot(equals(first)));
    await photos.deletePhoto(path);
    expect(await photos.downloadPhotoCached(path), isNull);
  });

  test(
    'concurrent widgets share one targeted request and cached hit',
    () async {
      final path = PhotoRtdbService.patientPath('p1');
      db.records[path] = {
        'data': base64Encode(testImage()),
        'contentType': 'image/jpeg',
        'version': 1,
        'updatedAt': 1,
      };
      final responses = await Future.wait([
        photos.downloadPhotoCached(path),
        photos.downloadPhotoCached(path),
        photos.downloadPhotoCached(path),
      ]);
      expect(responses.every((bytes) => bytes != null), isTrue);
      expect(db.reads[path], 1);
      await photos.downloadPhotoCached(path);
      expect(db.reads[path], 1);
    },
  );

  test('failed fetch does not poison cache', () async {
    final path = PhotoRtdbService.patientPath('p1');
    db.records[path] = {'data': '!invalid!'};
    await expectLater(photos.downloadPhotoCached(path), throwsFormatException);
    db.records[path] = {
      'data': base64Encode(testImage()),
      'contentType': 'image/jpeg',
    };
    expect(await photos.downloadPhotoCached(path), isNotNull);
    expect(db.reads[path], 2);
  });

  test('patient list reads metadata without a photo request', () async {
    final path = PhotoRtdbService.patientPath('p1');
    db.records['patients'] = {
      'p1': {
        'fullName': 'A',
        'photoRef': path,
        'attendants': [
          {'name': 'B', 'photoRef': PhotoRtdbService.attendantPath('p1', '0')},
        ],
      },
    };
    final patients = await PatientService(
      rtdbService: db,
    ).getPatientsStream().first;
    expect(patients.length, 1);
    expect(db.reads['patients'], 1);
    expect(db.reads[path], isNull);
    expect(patients.first.toMap().containsKey('photoDataUrl'), isFalse);
    expect(
      patients.first.attendants!.first.toMap().containsKey('photoDataUrl'),
      isFalse,
    );
  });

  Future<String> addTestPatient({String? photoDataUrl}) {
    return PatientService(rtdbService: db, photos: photos).addPatient(
      fullName: 'A Patient',
      dateOfBirth: DateTime(1980),
      gender: 'female',
      contactNumber: '1234567890',
      emergencyContact: '1234567890',
      emergencyContactName: 'Contact',
      medicalCondition: 'None',
      admissionDate: DateTime(2026, 1, 1),
      createdBy: 'tester',
      photoDataUrl: photoDataUrl,
    );
  }

  test('new patient without photo writes metadata only', () async {
    final id = await addTestPatient();
    final patient = db.records['patients/$id'] as Map;
    expect(patient.containsKey('photoDataUrl'), isFalse);
    expect(patient['photoRef'], isNull);
    expect(
      db.records.keys.where((path) => path.startsWith('patientPhotos/')),
      isEmpty,
    );
  });

  test('new patient with photo writes targeted RTDB record first', () async {
    final legacy = 'data:image/jpeg;base64,${base64Encode(testImage())}';
    final id = await addTestPatient(photoDataUrl: legacy);
    final patient = db.records['patients/$id'] as Map;
    expect(patient.containsKey('photoDataUrl'), isFalse);
    final path = PhotoRtdbService.patientPath(id);
    expect(patient['photoRef'], path);
    expect(db.records[path], isA<Map>());
    expect(db.reads[path], 1);
  });

  test('legacy model reads embedded bytes but never serializes them', () {
    final patient = PatientModel.fromMap('old', {
      'photoDataUrl': 'data:image/jpeg;base64,AA==',
      'attendants': [
        {'name': 'A', 'photoDataUrl': 'data:image/jpeg;base64,AA=='},
      ],
    });
    expect(patient.photoDataUrl, isNotNull);
    expect(patient.toMap().containsKey('photoDataUrl'), isFalse);
    expect(
      patient.toMap()['attendants'][0].containsKey('photoDataUrl'),
      isFalse,
    );
  });

  testWidgets('avatar without a photo makes no photo request', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatientPhoto(size: 64, fallbackText: 'AB', photos: photos),
        ),
      ),
    );
    expect(find.text('AB'), findsOneWidget);
    expect(
      db.reads.keys.where((path) => path.startsWith('patientPhotos/')),
      isEmpty,
    );
  });

  testWidgets('avatar fetches one targeted record and shares the cache', (
    tester,
  ) async {
    final path = PhotoRtdbService.patientPath('p1');
    db.records[path] = {
      'data': base64Encode(testImage()),
      'contentType': 'image/jpeg',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              PatientPhoto(size: 64, photoRef: path, photos: photos),
              PatientPhoto(size: 64, photoRef: path, photos: photos),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    expect(db.reads[path], 1);
    expect(db.reads['patients'], isNull);
  });

  testWidgets('avatar falls back on failed record and legacy Base64 works', (
    tester,
  ) async {
    final path = PhotoRtdbService.patientPath('p1');
    db.records[path] = {'data': '!invalid!', 'contentType': 'image/jpeg'};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PatientPhoto(
                size: 64,
                photoRef: path,
                photos: photos,
                fallbackText: 'AB',
              ),
              PatientPhoto(
                size: 64,
                photos: photos,
                legacyDataUrl:
                    'data:image/jpeg;base64,${base64Encode(testImage())}',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('AB'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  test(
    'migration verifies photo before removing patient and stay bytes',
    () async {
      final legacy = 'data:image/jpeg;base64,${base64Encode(testImage())}';
      db.records['patients'] = {
        'p1': {
          'photoDataUrl': legacy,
          'attendants': [
            {'name': 'A', 'photoDataUrl': legacy},
          ],
        },
      };
      db.records['stays'] = {
        's1': {
          'patientId': 'p1',
          'patientSnapshot': {
            'photoDataUrl': legacy,
            'attendants': [
              {'name': 'A', 'photoDataUrl': legacy},
            ],
          },
        },
      };
      final migration = PhotoMigrationService(rtdb: db, photos: photos);
      final report = await migration.migrate();
      expect(report.failed, 0);
      expect(report.uploadedPatientPhotos, 1);
      final patient = (db.records['patients'] as Map)['p1'] as Map;
      final stay = (db.records['stays'] as Map)['s1'] as Map;
      expect(patient.containsKey('photoDataUrl'), isFalse);
      expect(
        (stay['patientSnapshot'] as Map).containsKey('photoDataUrl'),
        isFalse,
      );
      expect(patient['photoRef'], PhotoRtdbService.patientPath('p1'));
      expect((patient['attendants'] as List).first['photoDataUrl'], isNull);
      expect(
        (stay['patientSnapshot']['attendants'] as List).first['photoDataUrl'],
        isNull,
      );
      final retry = await migration.migrate();
      expect(retry.failed, 0);
      expect(retry.uploadedPatientPhotos, 0);
    },
  );

  test('failed migration preserves legacy data and retry succeeds', () async {
    final legacy = 'data:image/jpeg;base64,${base64Encode(testImage())}';
    db.records['patients'] = {
      'p1': {'photoDataUrl': legacy},
    };
    db.records['stays'] = <String, dynamic>{};
    final migration = PhotoMigrationService(rtdb: db, photos: photos);
    db.failPhotoWrite = true;
    final first = await migration.migrate();
    expect(first.failed, 1);
    expect((db.records['patients'] as Map)['p1']['photoDataUrl'], legacy);
    db.failPhotoWrite = false;
    final second = await migration.migrate();
    expect(second.failed, 0);
    expect(
      (db.records['patients'] as Map)['p1'].containsKey('photoDataUrl'),
      isFalse,
    );
  });
}
