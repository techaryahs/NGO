import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'firebase_rtdb_rest_service.dart';

/// Targeted RTDB photo records. Patient and stay metadata never contain bytes.
class PhotoRtdbService {
  PhotoRtdbService({required FirebaseRTDBRestService rtdb}) : _rtdb = rtdb;

  final FirebaseRTDBRestService _rtdb;
  static const maxDimension = 720;
  static const jpegQuality = 78;
  static const maxSourceBytes = 8 * 1024 * 1024;
  static const maxEncodedBytes = 300 * 1024;
  static const maxCachedBytes = 8 * 1024 * 1024;

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
    return bytes;
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
      try {
        final bytes = await downloadPhoto(photoPath);
        if (bytes != null && (_generations[photoPath] ?? 0) == generation) {
          _remember(photoPath, bytes);
        }
        return bytes;
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
