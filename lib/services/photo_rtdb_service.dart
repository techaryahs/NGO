import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../cache/persistent_cache.dart';
import 'firebase_rtdb_rest_service.dart';

/// Targeted RTDB photo records. Patient and stay metadata never contain bytes.
class PhotoRtdbService {
  PhotoRtdbService({
    required FirebaseRTDBRestService rtdb,
    PersistentCache? persistentCache,
  }) : _rtdb = rtdb,
       _persistentCache = persistentCache;

  final FirebaseRTDBRestService _rtdb;
  final PersistentCache? _persistentCache;
  static const maxDimension = 720;
  static const jpegQuality = 78;
  static const maxSourceBytes = 8 * 1024 * 1024;
  static const maxEncodedBytes = 300 * 1024;
  static const maxCachedBytes = 8 * 1024 * 1024;
  static const maxDiskCachedBytes = 128 * 1024 * 1024;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, DateTime> _cachedAt = {};
  final Map<String, Future<Uint8List?>> _pending = {};
  final Map<String, int> _generations = {};
  int _cachedBytes = 0;

  static String patientPath(String patientId) =>
      'patientPhotos/$patientId/patient';
  static String attendantPath(String patientId, String attendantKey) =>
      'patientPhotos/$patientId/attendants/$attendantKey';

  static bool validPath(String path) => RegExp(
    r'^patientPhotos/[^/.#$\[\]]+/(patient|attendants/[^/.#$\[\]]+)$',
  ).hasMatch(path);

  /// Decode, apply EXIF orientation, resize, and compress before any write.
  /// PNG is retained for images with alpha; all other images become JPEG.
  static ({Uint8List bytes, String contentType}) prepare(Uint8List source) {
    if (source.length > maxSourceBytes) {
      throw FormatException('Source photo exceeds 8 MB');
    }
    final decoded = img.decodeImage(source);
    if (decoded == null) throw FormatException('Unsupported or invalid image');
    var image = img.bakeOrientation(decoded);
    if (image.width > maxDimension || image.height > maxDimension) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxDimension,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: maxDimension,
              interpolation: img.Interpolation.average,
            );
    }
    final transparent = image.hasAlpha;
    var encoded = transparent
        ? img.encodePng(image, level: 9)
        : img.encodeJpg(image, quality: jpegQuality);
    while (encoded.length > maxEncodedBytes &&
        (image.width > 240 || image.height > 240)) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: math.max(240, (image.width * 0.8).round()),
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: math.max(240, (image.height * 0.8).round()),
              interpolation: img.Interpolation.average,
            );
      encoded = transparent
          ? img.encodePng(image, level: 9)
          : img.encodeJpg(image, quality: jpegQuality);
    }
    if (encoded.length > maxEncodedBytes) {
      throw FormatException('Photo exceeds the 300 KB limit after compression');
    }
    return (
      bytes: Uint8List.fromList(encoded),
      contentType: transparent ? 'image/png' : 'image/jpeg',
    );
  }

  Future<String> uploadPhoto({
    required String photoPath,
    required Uint8List bytes,
  }) async {
    if (!validPath(photoPath))
      throw ArgumentError.value(photoPath, 'photoPath');
    final prepared = await Isolate.run(() => prepare(bytes));
    final version = DateTime.now().microsecondsSinceEpoch;
    final data = base64Encode(prepared.bytes);
    await _rtdb.put(photoPath, {
      'data': data,
      'contentType': prepared.contentType,
      'version': version,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    // Read back the exact targeted record before metadata can point at it.
    final saved = await _rtdb.get(photoPath);
    if (saved is! Map ||
        saved['data'] != data ||
        saved['contentType'] != prepared.contentType ||
        saved['version'] != version) {
      throw StateError('Photo write verification failed');
    }
    invalidate(photoPath);
    _remember(photoPath, prepared.bytes);
    await _bestEffortWriteDisk(
      photoPath,
      prepared.bytes,
      version: version,
      contentType: prepared.contentType,
    );
    return photoPath;
  }

  Future<bool> photoExists(String photoPath) async {
    if (!validPath(photoPath)) return false;
    final value = await _rtdb.get(photoPath);
    if (value is! Map ||
        value['data'] is! String ||
        value['contentType'] is! String)
      return false;
    final bytes = decodeLegacyBase64(value['data'] as String);
    return bytes != null &&
        bytes.isNotEmpty &&
        bytes.length <= maxEncodedBytes &&
        img.decodeImage(bytes) != null;
  }

  Future<Uint8List?> downloadPhoto(String photoPath) async {
    final record = await _downloadPhotoRecord(photoPath);
    return record?.bytes;
  }

  Future<({Uint8List bytes, int version, String contentType})?>
  _downloadPhotoRecord(String photoPath) async {
    if (!validPath(photoPath)) return null;
    final value = await _rtdb.get(photoPath);
    if (value is! Map || value['data'] is! String) return null;
    if (value['contentType'] != 'image/jpeg' &&
        value['contentType'] != 'image/png') {
      throw FormatException('Invalid photo content type');
    }
    final bytes = decodeLegacyBase64(value['data'] as String);
    if (bytes == null || bytes.length > maxEncodedBytes) {
      throw FormatException('Invalid photo record');
    }
    if (img.decodeImage(bytes) == null) {
      throw FormatException('Corrupt photo record');
    }
    return (
      bytes: bytes,
      version: value['version'] is num ? (value['version'] as num).toInt() : 0,
      contentType: value['contentType'].toString(),
    );
  }

  Future<Uint8List?> downloadPhotoCached(String photoPath) {
    final hit = _cache.remove(photoPath);
    if (hit != null) {
      if (DateTime.now().difference(_cachedAt[photoPath]!) <
          const Duration(minutes: 5)) {
        _cache[photoPath] = hit;
        return Future.value(hit);
      }
      _cachedBytes -= hit.length;
      _cachedAt.remove(photoPath);
    }
    return _pending.putIfAbsent(photoPath, () async {
      final generation = _generations[photoPath] ?? 0;
      Uint8List? diskFallback;
      try {
        ({Uint8List bytes, bool isFresh})? disk;
        try {
          disk = await _readDisk(photoPath);
        } catch (_) {
          disk = null;
        }
        diskFallback = disk?.bytes;
        if (disk != null && disk.isFresh) {
          _remember(photoPath, disk.bytes);
          return disk.bytes;
        }
        final record = await _downloadPhotoRecord(photoPath);
        final bytes = record?.bytes;
        if (record != null && (_generations[photoPath] ?? 0) == generation) {
          _remember(photoPath, record.bytes);
          await _bestEffortWriteDisk(
            photoPath,
            record.bytes,
            version: record.version,
            contentType: record.contentType,
          );
        }
        return bytes;
      } catch (_) {
        if (diskFallback != null) {
          _remember(photoPath, diskFallback);
          return diskFallback;
        }
        rethrow;
      } finally {
        if ((_generations[photoPath] ?? 0) == generation) {
          _pending.remove(photoPath);
        }
      }
    });
  }

  void _remember(String path, Uint8List bytes) {
    final previous = _cache.remove(path);
    if (previous != null) _cachedBytes -= previous.length;
    if (bytes.length > maxCachedBytes) return;
    _cache[path] = bytes;
    _cachedAt[path] = DateTime.now();
    _cachedBytes += bytes.length;
    while (_cachedBytes > maxCachedBytes) {
      final oldest = _cache.keys.first;
      _cachedBytes -= _cache.remove(oldest)!.length;
      _cachedAt.remove(oldest);
    }
  }

  void invalidate(String photoPath) {
    _generations[photoPath] = (_generations[photoPath] ?? 0) + 1;
    final bytes = _cache.remove(photoPath);
    if (bytes != null) _cachedBytes -= bytes.length;
    _cachedAt.remove(photoPath);
    _pending.remove(photoPath);
  }

  Future<void> deletePhoto(String photoPath) async {
    if (!validPath(photoPath))
      throw ArgumentError.value(photoPath, 'photoPath');
    await _rtdb.delete(photoPath);
    invalidate(photoPath);
    try {
      await _deleteDisk(photoPath);
    } catch (_) {
      // Remote deletion succeeded; stale local files are disposable.
    }
  }

  Future<Directory?> _accountPhotoDirectory() async {
    final account = _persistentCache?.accountId;
    if (account == null) return null;
    final support = await getApplicationSupportDirectory();
    final safeAccount = sha256.convert(utf8.encode(account)).toString();
    final directory = Directory(
      p.join(support.path, 'ngo_management', 'photo_cache', safeAccount),
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _diskKey(String account, String photoPath, int version) =>
      sha256.convert(utf8.encode('$account|$photoPath|$version')).toString();

  Future<({Uint8List bytes, bool isFresh})?> _readDisk(String photoPath) async {
    final cache = _persistentCache;
    final account = cache?.accountId;
    if (cache == null || account == null) return null;
    final metadata = await cache.photoMetadata(photoPath);
    if (metadata == null || metadata.version == 0) return null;
    final directory = await _accountPhotoDirectory();
    if (directory == null) return null;
    final file = File(
      p.join(
        directory.path,
        '${_diskKey(account, photoPath, metadata.version)}.bin',
      ),
    );
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      if (bytes.isEmpty ||
          bytes.length > maxEncodedBytes ||
          metadata.contentHash != hash ||
          img.decodeImage(bytes) == null) {
        await file.delete();
        return null;
      }
      final modified = await file.lastModified();
      return (
        bytes: bytes,
        isFresh:
            DateTime.now().difference(modified) < const Duration(minutes: 5),
      );
    } catch (_) {
      if (await file.exists()) await file.delete();
      return null;
    }
  }

  Future<void> _writeDisk(
    String photoPath,
    Uint8List bytes, {
    required int version,
    required String contentType,
  }) async {
    final cache = _persistentCache;
    final account = cache?.accountId;
    if (cache == null || account == null || bytes.length > maxEncodedBytes) {
      return;
    }
    final directory = await _accountPhotoDirectory();
    if (directory == null) return;
    final hash = sha256.convert(bytes).toString();
    final file = File(
      p.join(directory.path, '${_diskKey(account, photoPath, version)}.bin'),
    );
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      await cache.updatePhotoMetadata(
        photoRef: photoPath,
        version: version,
        contentType: contentType,
        contentHash: hash,
      );
      await _evictDisk(directory);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _bestEffortWriteDisk(
    String photoPath,
    Uint8List bytes, {
    required int version,
    required String contentType,
  }) async {
    try {
      await _writeDisk(
        photoPath,
        bytes,
        version: version,
        contentType: contentType,
      );
    } catch (_) {
      // A disk-cache failure must not fail a verified RTDB photo operation.
    }
  }

  Future<void> _deleteDisk(String photoPath) async {
    final directory = await _accountPhotoDirectory();
    if (directory == null || !await directory.exists()) return;
    final metadata = await _persistentCache?.photoMetadata(photoPath);
    final account = _persistentCache?.accountId;
    if (metadata == null || account == null) return;
    final file = File(
      p.join(
        directory.path,
        '${_diskKey(account, photoPath, metadata.version)}.bin',
      ),
    );
    if (await file.exists()) await file.delete();
  }

  Future<void> _evictDisk(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.bin'))
        .cast<File>()
        .toList();
    final entries = <({File file, int size, DateTime modified})>[];
    var total = 0;
    for (final file in files) {
      final stat = await file.stat();
      total += stat.size;
      entries.add((file: file, size: stat.size, modified: stat.modified));
    }
    if (total <= maxDiskCachedBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= maxDiskCachedBytes) break;
      await entry.file.delete();
      total -= entry.size;
    }
  }

  static Uint8List? decodeLegacyBase64(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      return base64Decode(
        dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl,
      );
    } catch (_) {
      return null;
    }
  }
}
