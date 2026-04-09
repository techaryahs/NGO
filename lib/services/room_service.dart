import 'dart:async';
import 'dart:math';
import '../models/bed_model.dart';
import '../models/room_model.dart';
import '../models/stay_model.dart';
import 'firebase_rtdb_rest_service.dart';

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
  final FirebaseRTDBRestService _rtdb;

  static const String _roomsPath = 'rooms';
  static const String _staysPath = 'stays';
  static const String _pricingPath = 'admin_settings/pricing';
  static final Random _random = Random();

  static const Map<String, dynamic> defaultPricing = {
    'privateRoomBasePrice': 600,
    'privateRoomIncludedAttendants': 2,
    'privateRoomExtraAttendantFee': 200,
    'privateRoomMaxAttendants': 5,
    'generalRoomBedPrice': 150,
    'generalRoomDefaultBeds': 4,
    'generalRoomIncludedAttendants': 1,
    'generalRoomMaxAttendants': 2,
  };

  RoomService({required FirebaseRTDBRestService rtdbService})
    : _rtdb = rtdbService;

  // ── Internal accessors for part files ──────────────────────────────────────
  FirebaseRTDBRestService get rtdb => _rtdb;
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
    stays.sort((a, b) => a.effectiveExpiryDate.compareTo(b.effectiveExpiryDate));
    return stays.first.effectiveExpiryDate;
  }

  /// Generic stream combiner (used by rooms + stays streams).
  static Stream<T> combineLatest2<A, B, T>(
    Stream<A> streamA,
    Stream<B> streamB,
    T Function(A, B) combiner,
  ) {
    A? latestA;
    B? latestB;
    bool hasA = false;
    bool hasB = false;

    late StreamController<T> controller;
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;

    controller = StreamController<T>(
      onListen: () {
        subA = streamA.listen((a) {
          latestA = a;
          hasA = true;
          if (hasA && hasB) {
            controller.add(combiner(latestA as A, latestB as B));
          }
        });
        subB = streamB.listen((b) {
          latestB = b;
          hasB = true;
          if (hasA && hasB) {
            controller.add(combiner(latestA as A, latestB as B));
          }
        });
      },
      onCancel: () {
        subA?.cancel();
        subB?.cancel();
      },
    );

    return controller.stream;
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
