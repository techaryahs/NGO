import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/bed_model.dart';
import '../models/room_model.dart';
import '../models/stay_model.dart';
import '../utils/pricing_helper.dart';
import 'backend_api_service.dart';
import 'firebase_rtdb_rest_service.dart';
import 'service_locator.dart';
import 'payment_service.dart';

part 'room_service_pricing.dart';
part 'room_service_rooms.dart';
part 'room_service_beds.dart';
part 'room_service_stays.dart';
part 'room_service_stats.dart';
part 'room_service_reconciliation.dart';

// ===========================================================================
// RoomService — Core class, fields, and shared utilities.
//
// Domain logic is split across part files for maintainability:
//   room_service_pricing.dart       — Pricing CRUD
//   room_service_rooms.dart         — Room CRUD, streams, status computation
//   room_service_beds.dart          — Bed query & update helpers
//   room_service_stays.dart         — Stay lifecycle (create/extend/complete)
//   room_service_stats.dart         — Aggregated stats & census streams
//   room_service_reconciliation.dart — Data reconciliation & self-healing
// ===========================================================================
class RoomService {
  final FirebaseRTDBRestService? _injectedRtdb;
  final BackendApiService? _injectedBackendApi;

  static const String _roomsPath = 'rooms';
  static const String _staysPath = 'stays';
  static const String _pricingPath = 'admin_settings/pricing';
  static final Random _random = Random();

  static const Map<String, dynamic> defaultPricing = {
    'privateRoomBasePrice': 700,
    'privateRoomIncludedAttendants': 1,
    'privateRoomExtraAttendantFee': 200,
    'privateRoomMaxAttendants': 5,
    'generalRoomBedPrice': 200,
    'generalRoomDefaultBeds': 4,
    'generalRoomIncludedAttendants': 1,
    'generalRoomMaxAttendants': 2,
  };

  RoomService({
    FirebaseRTDBRestService? rtdbService,
    BackendApiService? backendApiService,
  }) : _injectedRtdb = rtdbService,
       _injectedBackendApi = backendApiService;

  // ── Internal accessors for part files ──────────────────────────────────────
  BackendApiService? get backendApi {
    if (_injectedBackendApi != null) return _injectedBackendApi;
    if (_injectedRtdb != null) return null;
    try {
      return ServiceLocator().backendApiService;
    } catch (_) {
      return null;
    }
  }

  bool get isPostgres => backendApi != null || _injectedRtdb == null;

  FirebaseRTDBRestService get rtdb {
    if (_injectedRtdb != null) return _injectedRtdb;
    return ServiceLocator().rtdbService;
  }

  String get roomsPath => _roomsPath;
  String get staysPath => _staysPath;
  String get pricingPath => _pricingPath;

  // ── Shared utility methods ─────────────────────────────────────────────────

  int parseIntSafe(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  double parseDoubleSafe(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  String generateStayId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final suffix = (_random.nextInt(900000) + 100000).toString();
    return 'stay_${now}_$suffix';
  }

  Map<String, dynamic> bedsToRtdbMap(List<BedModel> beds) {
    final map = <String, dynamic>{};
    for (final bed in beds) {
      if (bed.id.isNotEmpty) {
        map[bed.id] = bed.toMap();
      }
    }
    return map;
  }

  List<StayModel> parseStaysFromData(dynamic data) {
    final stays = <StayModel>[];
    if (data != null && data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      mapData.forEach((key, value) {
        if (value is Map) {
          stays.add(StayModel.fromMap(key, Map<String, dynamic>.from(value)));
        }
      });
    }
    return stays;
  }

  DateTime? earliestExpectedVacancy(List<StayModel> stays) {
    if (stays.isEmpty) return null;
    stays.sort(
      (a, b) => a.effectiveExpiryDate.compareTo(b.effectiveExpiryDate),
    );
    return stays.first.effectiveExpiryDate;
  }

  /// Reconciles bed occupancy statuses against currently active stays.
  ///
  /// A bed is marked occupied only when a valid active stay occupies it.
  /// Stale, historical, discharged, or cancelled stay references are cleared
  /// to 'available'. Maintenance beds are preserved.
  List<BedModel> reconcileBedsWithActiveStays(
    List<BedModel> beds,
    List<StayModel> activeStays,
  ) {
    if (beds.isEmpty) return beds;

    if (activeStays.isEmpty) {
      return beds.map((bed) {
        if (bed.isMaintenance) return bed;
        if (bed.isOccupied) {
          return bed.copyWith(
            status: 'available',
            clearPatientId: true,
            clearStayId: true,
          );
        }
        return bed;
      }).toList();
    }

    final remainingStays = List<StayModel>.from(activeStays);
    final matchedStayByBedIndex = <int, StayModel>{};

    // Pass 1: match by exact stay ID
    for (var i = 0; i < beds.length; i++) {
      final bed = beds[i];
      if (bed.isMaintenance) continue;
      if (bed.currentStayId != null && bed.currentStayId!.isNotEmpty) {
        final matchIndex =
            remainingStays.indexWhere((s) => s.id == bed.currentStayId);
        if (matchIndex != -1) {
          matchedStayByBedIndex[i] = remainingStays.removeAt(matchIndex);
        }
      }
    }

    // Pass 2: match by bedId
    for (var i = 0; i < beds.length; i++) {
      if (matchedStayByBedIndex.containsKey(i)) continue;
      final bed = beds[i];
      if (bed.isMaintenance) continue;
      final matchIndex = remainingStays.indexWhere((s) => s.bedId == bed.id);
      if (matchIndex != -1) {
        matchedStayByBedIndex[i] = remainingStays.removeAt(matchIndex);
      }
    }

    // Pass 3: match by currentPatientId
    for (var i = 0; i < beds.length; i++) {
      if (matchedStayByBedIndex.containsKey(i)) continue;
      final bed = beds[i];
      if (bed.isMaintenance) continue;
      if (bed.currentPatientId != null && bed.currentPatientId!.isNotEmpty) {
        final matchIndex =
            remainingStays.indexWhere((s) => s.patientId == bed.currentPatientId);
        if (matchIndex != -1) {
          matchedStayByBedIndex[i] = remainingStays.removeAt(matchIndex);
        }
      }
    }

    // Pass 4: match by bedLabel / bedNumber
    for (var i = 0; i < beds.length; i++) {
      if (matchedStayByBedIndex.containsKey(i)) continue;
      final bed = beds[i];
      if (bed.isMaintenance) continue;
      final matchIndex = remainingStays.indexWhere(
        (s) =>
            (s.bedLabel != null && s.bedLabel == bed.bedLabel) ||
            (s.bedNumber != null && s.bedNumber.toString() == bed.bedLabel),
      );
      if (matchIndex != -1) {
        matchedStayByBedIndex[i] = remainingStays.removeAt(matchIndex);
      }
    }

    // Pass 5: if any active stays remain unmatched in this room,
    // match them to any remaining non-maintenance beds
    for (var i = 0; i < beds.length && remainingStays.isNotEmpty; i++) {
      if (matchedStayByBedIndex.containsKey(i)) continue;
      final bed = beds[i];
      if (bed.isMaintenance) continue;
      matchedStayByBedIndex[i] = remainingStays.removeAt(0);
    }

    return List.generate(beds.length, (i) {
      final bed = beds[i];
      if (bed.isMaintenance) return bed;
      final matchedStay = matchedStayByBedIndex[i];
      if (matchedStay != null) {
        return bed.copyWith(
          status: 'occupied',
          currentStayId: matchedStay.id,
          currentPatientId: matchedStay.patientId,
        );
      } else {
        if (bed.isOccupied) {
          return bed.copyWith(
            status: 'available',
            clearPatientId: true,
            clearStayId: true,
          );
        }
        return bed;
      }
    });
  }

  /// Generic stream combiner (used by rooms + stays streams).
  static Stream<T> combineLatest2<A, B, T>(
    Stream<A> streamA,
    Stream<B> streamB,
    T Function(A, B) combiner,
  ) {
    return Stream<T>.multi((controller) {
      A? latestA;
      B? latestB;
      bool hasA = false;
      bool hasB = false;
      bool doneA = false;
      bool doneB = false;

      void checkDone() {
        if (doneA && doneB && !controller.isClosed) {
          controller.close();
        }
      }

      final subA = streamA.listen(
        (a) {
          latestA = a;
          hasA = true;
          if (hasA && hasB) {
            try {
              controller.add(combiner(latestA as A, latestB as B));
            } catch (e, st) {
              controller.addError(e, st);
            }
          }
        },
        onError: (Object e, StackTrace st) {
          controller.addError(e, st);
        },
        onDone: () {
          doneA = true;
          checkDone();
        },
      );

      final subB = streamB.listen(
        (b) {
          latestB = b;
          hasB = true;
          if (hasA && hasB) {
            try {
              controller.add(combiner(latestA as A, latestB as B));
            } catch (e, st) {
              controller.addError(e, st);
            }
          }
        },
        onError: (Object e, StackTrace st) {
          controller.addError(e, st);
        },
        onDone: () {
          doneB = true;
          checkDone();
        },
      );

      controller.onCancel = () {
        subA.cancel();
        subB.cancel();
      };
    });
  }
}

// ── Value objects (used across part files) ────────────────────────────────────

class CostBreakdown {
  final double baseCost;
  final double extraAttendantCost;
  final double totalCost;

  const CostBreakdown({
    required this.baseCost,
    required this.extraAttendantCost,
    required this.totalCost,
  });
}

class RoomStatusMeta {
  final String dbStatus;
  final String uiStatus;
  final DateTime? expectedVacancyDate;

  const RoomStatusMeta({
    required this.dbStatus,
    required this.uiStatus,
    required this.expectedVacancyDate,
  });
}
