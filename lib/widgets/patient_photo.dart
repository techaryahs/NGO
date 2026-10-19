import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/patient_model.dart';
import '../services/photo_rtdb_service.dart';
import '../services/service_locator.dart';

/// Shared patient/attendant photo avatar.
///
/// Resolution order:
///   1. legacy Base64 `photoDataUrl` (kept readable during rollout),
///   2. targeted RTDB `photoRef` (downloaded once, cached),
///   3. initials fallback.
class PatientPhoto extends StatelessWidget {
  final PatientModel? patient;
  final AttendantModel? attendant;
  final String? photoRef;
  final String? legacyDataUrl;
  final PhotoRtdbService? photos;
  final double size;
  final Color? backgroundColor;
  final Color? textColor;
  final String? fallbackText;

  const PatientPhoto({
    super.key,
    this.patient,
    this.attendant,
    this.photoRef,
    this.legacyDataUrl,
    this.photos,
    required this.size,
    this.backgroundColor,
    this.textColor,
    this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    final photoDataUrl =
        legacyDataUrl ?? patient?.photoDataUrl ?? attendant?.photoDataUrl;
    final resolvedRef = photoRef ?? patient?.photoRef ?? attendant?.photoRef;

    final initials =
        fallbackText ?? _initials(patient?.fullName ?? attendant?.name ?? '');

    Widget placeholder() => Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: textColor ?? const Color(0xFF3B6D11),
        ),
      ),
    );

    if (photoDataUrl != null && photoDataUrl.isNotEmpty) {
      final bytes = PhotoRtdbService.decodeLegacyBase64(photoDataUrl);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder(),
        );
      }
    }

    if (resolvedRef != null && resolvedRef.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: (photos ?? ServiceLocator().photoRtdbService)
            .downloadPhotoCached(resolvedRef),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null)
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder(),
            );
          if (snapshot.connectionState == ConnectionState.waiting) {
            return placeholder();
          }
          return placeholder();
        },
      );
    }

    return placeholder();
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Decodes a legacy Base64 photo for one-shot renderers.
Uint8List? decodeLegacyPhoto(String? dataUrl) =>
    PhotoRtdbService.decodeLegacyBase64(dataUrl);
