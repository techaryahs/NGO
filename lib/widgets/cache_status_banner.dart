import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../cache/persistent_cache.dart';
import '../services/service_locator.dart';

/// Compact freshness indicator for data rendered from the persistent cache.
class CacheStatusBanner extends StatelessWidget {
  const CacheStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CacheStatus>(
      stream: ServiceLocator().persistentCache.statusStream,
      initialData: ServiceLocator().persistentCache.status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null || status.state == CacheConnectionState.idle) {
          return const SizedBox.shrink();
        }
        final offline = status.state == CacheConnectionState.offline;
        final degraded = status.state == CacheConnectionState.degraded;
        final syncing = status.state == CacheConnectionState.syncing;
        final lastSynced = status.lastSynced;
        final text = offline
            ? 'Offline — showing cached data${_lastSynced(lastSynced)}'
            : degraded
            ? 'Local cache unavailable — using server data'
            : syncing
            ? 'Syncing…${_lastSynced(lastSynced)}'
            : 'Last synced${_lastSynced(lastSynced, prefix: ': ')}';
        final color = offline || degraded
            ? const Color(0xFFFFF3CD)
            : const Color(0xFFEAF3DE);
        return Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Color(0xFF4A5D23)),
          ),
        );
      },
    );
  }

  static String _lastSynced(
    DateTime? value, {
    String prefix = ' — last synced ',
  }) {
    if (value == null) return '';
    return '$prefix${DateFormat('dd MMM, HH:mm').format(value.toLocal())}';
  }
}
