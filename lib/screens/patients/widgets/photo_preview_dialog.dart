import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> showPhotoPreview(
  BuildContext context, {
  required Uint8List photoBytes,
  required String title,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (dialogContext) {
      final viewport = MediaQuery.sizeOf(dialogContext);
      final portraitSize = math.min(
        680.0,
        math.min(viewport.width - 64, viewport.height - 150),
      );

      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(32),
        child: SizedBox(
          width: portraitSize,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _OverlayPill(child: Text(title))),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.black.withValues(alpha: .58),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: portraitSize,
                height: portraitSize,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .75),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 36,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    clipBehavior: Clip.hardEdge,
                    child: Image.memory(
                      photoBytes,
                      width: portraitSize,
                      height: portraitSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFF172014),
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _OverlayPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.zoom_in_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text('Scroll or pinch to zoom'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _OverlayPill extends StatelessWidget {
  final Widget child;
  const _OverlayPill({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .58),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .18)),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: child,
    ),
  );
}
