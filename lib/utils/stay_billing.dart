import '../models/patient_model.dart';
import '../models/stay_model.dart';
import 'pricing_helper.dart';

class AdmissionBalance {
  final String id;
  final List<StayModel> stays;
  final Map<String, double> charges;
  final Map<String, int> days;
  final double total;
  final double paid;
  final double refunded;
  final List<Map<String, dynamic>> pendingAttendance;
  final Map<String, dynamic>? checkoutAdjustment;
  final bool plannedExitConfirmed;
  final bool provisionalState;
  final int? checkoutAt;
  final int actualPatientPresentDays;
  final int projectedPatientPresentDays;
  final String pricingBasis;
  AdmissionBalance(
    this.id,
    this.stays,
    this.charges,
    this.days,
    this.total,
    this.paid,
    this.refunded, {
    this.pendingAttendance = const [],
    this.checkoutAdjustment,
    this.plannedExitConfirmed = true,
    this.provisionalState = false,
    this.checkoutAt,
    this.actualPatientPresentDays = 0,
    this.projectedPatientPresentDays = 0,
    this.pricingBasis = 'projected_patient_present',
  });
  bool get provisional => pendingAttendance.isNotEmpty || provisionalState;
  double get netPaid => paid - refunded;
  double get due => (total - netPaid).clamp(0.0, double.infinity);
  double get refundDue => (netPaid - total).clamp(0.0, double.infinity);
  String get status => refundDue > 0.005
      ? 'Payment Exceeded'
      : due <= 0.005
      ? 'Paid'
      : netPaid > 0
      ? 'Partially Paid'
      : 'Unpaid';
  Map<String, dynamic> toMap() => {
    'cycleId': id,
    'total': total,
    'paid': paid,
    'refunded': refunded,
    'netPaid': netPaid,
    'due': due,
    'refundDue': refundDue,
    'status': status,
    'segmentCharges': charges,
    'segmentDays': days,
    'provisional': provisional,
    'pendingAttendance': pendingAttendance,
    'plannedExitConfirmed': plannedExitConfirmed,
    if (checkoutAt != null) 'checkoutAt': checkoutAt,
    if (checkoutAdjustment != null) 'checkoutAdjustment': checkoutAdjustment,
    'actualPatientPresentDays': actualPatientPresentDays,
    'projectedPatientPresentDays': projectedPatientPresentDays,
    'pricingBasis': pricingBasis,
  };
}

/// One bill per admission. A transfer day belongs to its last room segment,
/// so changing rooms never charges two full days for the same patient.
class StayBilling {
  static bool eligibleHistoricalAttendant(
    String id,
    DateTime date,
    List<StayModel> stays,
  ) {
    final people = stays
        .expand((stay) {
          final roster = stay.patientSnapshot['attendants'];
          return roster is List ? roster.whereType<Map>() : <Map>[];
        })
        .where((person) => person['id'] == id)
        .toList();
    final key = dateKey(date);
    return people.isEmpty ||
        people.any(
          (person) =>
              (person['startDate'] == null ||
                  key.compareTo(person['startDate'].toString()) >= 0) &&
              (person['endDate'] == null ||
                  key.compareTo(person['endDate'].toString()) <= 0),
        );
  }

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// A calendar carrier for India's civil date, independent of host timezone.
  static DateTime kolkataDay(DateTime instant) {
    final clock = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime(clock.year, clock.month, clock.day);
  }

  static String dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  /// Active admissions remain eligible through today even after a planned exit.
  /// Actual discharge takes precedence for completed admissions.
  static ({String start, String end}) attendanceDateRange(
    PatientModel patient, {
    DateTime? now,
    bool includeElapsed = false,
  }) {
    final start = patient.registrationDate ?? patient.admissionDate;
    final today = kolkataDay(now ?? DateTime.now());
    final planned = patient.exitDate == null
        ? null
        : kolkataDay(patient.exitDate!);
    final end = patient.status.toLowerCase() == 'discharged'
        ? patient.dischargeDate ?? patient.exitDate ?? today
        : !includeElapsed
        ? patient.exitDate ?? today
        : planned != null && planned.isAfter(today)
        ? planned
        : today;
    final period = PricingHelper.attendancePeriod(start, end);
    return (start: dateKey(period.start), end: dateKey(period.end));
  }

  static String currentCycle(PatientModel patient) =>
      patient.admissionDate.millisecondsSinceEpoch.toString();
  static String cycleFor(StayModel stay, PatientModel patient) {
    if (stay.cycleId != null) return stay.cycleId!;
    final saved = stay.patientSnapshot['admissionDate'];
    if (saved != null) return saved.toString();
    final owners = patient.admissionBalances.entries
        .where((entry) {
          final balance = entry.value;
          return balance is Map &&
              balance['segmentCharges'] is Map &&
              (balance['segmentCharges'] as Map).containsKey(stay.id);
        })
        .map((entry) => entry.key)
        .toList();
    return owners.length == 1 ? owners.single : 'unresolved-stay:${stay.id}';
  }

  static String paymentCycle(
    PaymentModel payment,
    PatientModel patient,
    List<StayModel> stays,
  ) {
    if (payment.cycleId != null) return payment.cycleId!;
    // Historical ownership cannot be established from payment dates or the
    // number of cycles that happen to remain in the database.
    return 'unallocated-payment:${payment.id}';
  }

  static List<AdmissionBalance> calculate({
    required PatientModel patient,
    required List<StayModel> stays,
    required Map<String, dynamic> pricing,
    Map<String, String> attendance = const {},
    Map<String, Map<String, String>> attendantAttendance = const {},
    DateTime? now,
    bool onlyPresent = false,
    // PostgreSQL uses the explicitly agreed calendar-day policy. Keep legacy
    // RTDB/offline historical tooling unchanged unless it opts into that policy.
    bool calendarDayBilling = false,
    DateTime? checkoutAt,
    bool finalize = false,
  }) {
    final currentSaved = patient.admissionBalances[currentCycle(patient)];
    if (checkoutAt == null &&
        patient.status.toLowerCase() != 'discharged' &&
        currentSaved is Map &&
        currentSaved['checkoutAt'] is num) {
      checkoutAt = DateTime.fromMillisecondsSinceEpoch(
        (currentSaved['checkoutAt'] as num).toInt(),
      );
    }
    DateTime billingDay(DateTime value) =>
        calendarDayBilling ? kolkataDay(value) : day(value);
    final groups = <String, List<StayModel>>{};
    for (final stay in stays.where((s) => s.status != 'cancelled')) {
      groups.putIfAbsent(cycleFor(stay, patient), () => []).add(stay);
    }
    groups.putIfAbsent(currentCycle(patient), () => []);
    for (final cycle in patient.admissionBalances.keys) {
      groups.putIfAbsent(cycle, () => []);
    }
    final result = <AdmissionBalance>[];
    for (final group in groups.entries) {
      final segments = [...group.value]
        ..sort((a, b) => a.admissionDate.compareTo(b.admissionDate));
      final charges = <String, double>{for (final s in segments) s.id: 0};
      final days = <String, int>{for (final s in segments) s.id: 0};
      final pending = <Map<String, dynamic>>[];
      Map<String, dynamic>? checkoutAdjustment;
      final isCurrent = group.key == currentCycle(patient);
      final active = isCurrent && patient.status.toLowerCase() != 'discharged';
      var saved = patient.admissionBalances[group.key];
      if (calendarDayBilling &&
          saved is! Map &&
          segments.isNotEmpty &&
          segments.every((s) => s.status == 'completed') &&
          (!isCurrent ||
              patient.status.toLowerCase() == 'discharged' &&
                  checkoutAt == null)) {
        saved = {
          'total': segments.fold<double>(0, (sum, s) => sum + s.totalCost),
          'segmentCharges': {for (final s in segments) s.id: s.totalCost},
          'segmentDays': {
            for (final s in segments) s.id: s.billingSummary['days'] ?? 0,
          },
        };
      }
      final frozen =
          saved is Map &&
          saved['total'] != null &&
          (!isCurrent ||
              saved['finalized'] == true ||
              patient.status.toLowerCase() == 'discharged');
      var actualPatientPresentDays = 0;
      var projectedPatientPresentDays = 0;
      if (segments.isNotEmpty && !frozen) {
        final start = billingDay(segments.first.admissionDate);
        DateTime end;
        bool isActualCheckout = false;
        if (isCurrent && checkoutAt != null) {
          end = checkoutAt;
          isActualCheckout = true;
        } else if (active) {
          if (patient.exitDate != null) {
            end = patient.exitDate!;
          } else {
            final estimateEnd = start.add(
              Duration(
                days: PricingHelper.advanceDays - (calendarDayBilling ? 1 : 0),
              ),
            );
            final activeSegmentEnds = segments
                .where((segment) => segment.isActive)
                .map(
                  (segment) => calendarDayBilling
                      ? segment.expectedDischargeDate.subtract(
                          const Duration(days: 1),
                        )
                      : segment.expectedDischargeDate,
                )
                .where((date) => date.millisecondsSinceEpoch > 0);
            end = activeSegmentEnds.fold<DateTime>(
              estimateEnd,
              (latest, date) => date.isAfter(latest) ? date : latest,
            );
            final todayEnd = billingDay(
              now ?? DateTime.now(),
            ).add(Duration(days: calendarDayBilling ? 0 : 1));
            if (todayEnd.isAfter(end)) end = todayEnd;
            for (final key in {
              ...attendance.keys,
              ...attendantAttendance.keys,
            }) {
              final recorded = DateTime.tryParse(key);
              if (recorded == null) continue;
              final recordedEnd = day(
                recorded,
              ).add(Duration(days: calendarDayBilling ? 0 : 1));
              if (recordedEnd.isAfter(end)) end = recordedEnd;
            }
          }
        } else {
          end =
              patient.dischargeDate ??
              segments
                  .map((s) => s.completedAt ?? s.updatedAt)
                  .reduce((a, b) => a.isAfter(b) ? a : b);
          isActualCheckout = true;
        }

        DateTime exclusiveEnd;
        if (calendarDayBilling) {
          final checkoutDayKey = patient.exitDate != null
              ? dateKey(billingDay(patient.exitDate!))
              : null;
          final hasCheckoutAttendance =
              checkoutDayKey != null &&
              (attendance.containsKey(checkoutDayKey) ||
                  attendantAttendance.containsKey(checkoutDayKey));
          if (isActualCheckout) {
            final late = PricingHelper.afterCheckoutCutoff(end);
            exclusiveEnd = late
                ? billingDay(end).add(const Duration(days: 1))
                : billingDay(end);
          } else if (patient.exitDate != null) {
            final late = PricingHelper.afterCheckoutCutoff(end);
            exclusiveEnd = (late || hasCheckoutAttendance)
                ? billingDay(end).add(const Duration(days: 1))
                : billingDay(end);
          } else {
            exclusiveEnd = billingDay(end).add(const Duration(days: 1));
          }
        } else {
          final late = PricingHelper.afterCheckoutCutoff(end);
          exclusiveEnd = late
              ? billingDay(end).add(const Duration(days: 1))
              : billingDay(end);
        }
        if (!exclusiveEnd.isAfter(start)) {
          exclusiveEnd = start.add(const Duration(days: 1));
        }
        final checkoutExclusiveEnd = exclusiveEnd;
        if (!calendarDayBilling && active && patient.exitDate != null) {
          final period = PricingHelper.attendancePeriod(
            start,
            patient.exitDate,
          );
          if (period.days > 0) {
            exclusiveEnd = DateTime(
              period.end.year,
              period.end.month,
              period.end.day + 1,
            );
          }
        }

        if (isCurrent && checkoutAt != null) {
          final late = PricingHelper.afterCheckoutCutoff(checkoutAt);
          checkoutAdjustment = {
            'day': dateKey(billingDay(checkoutAt)),
            'included': late,
            'includedInTotal': true,
            'amount': 0.0,
            'checkoutAt': checkoutAt.millisecondsSinceEpoch,
          };
        }

        var billableDays = 0;
        for (
          var date = start;
          date.isBefore(exclusiveEnd);
          date = DateTime(date.year, date.month, date.day + 1)
        ) {
          final status = attendance[dateKey(date)];
          if (!const {'Present', 'Absent'}.contains(status)) {
            pending.add({'day': dateKey(date), 'kind': 'attendance'});
          }
          final patientBillable =
              status == 'Present' ||
              ((!finalize && !onlyPresent && status != 'Absent') &&
                  (calendarDayBilling || date.isBefore(checkoutExclusiveEnd)));
          final patientPresentDaysBefore = finalize
              ? actualPatientPresentDays
              : projectedPatientPresentDays;
          final isLongStay =
              patientPresentDaysBefore >= PricingHelper.longStayThresholdDays;
          if (status == 'Present') actualPatientPresentDays++;
          if (patientBillable) projectedPatientPresentDays++;

          final candidates = segments.where((s) {
            if (billingDay(s.admissionDate).isAfter(date)) return false;
            if (s.isActive && (active || checkoutAt != null)) return true;
            final checkout = s.completedAt ?? s.updatedAt;
            final late = PricingHelper.afterCheckoutCutoff(checkout);
            final checkoutEnd = late
                ? billingDay(checkout).add(const Duration(days: 1))
                : billingDay(checkout);
            return date.isBefore(checkoutEnd) ||
                (date == billingDay(s.admissionDate) &&
                    checkout.isAfter(s.admissionDate));
          }).toList();
          if (candidates.isEmpty) continue;

          final explicit = candidates
              .where(
                (s) =>
                    s.patientSnapshot['transferFingerprint'] != null ||
                    s.notes == 'Room transfer' ||
                    s.notes?.trim().toLowerCase().startsWith('shifted from') ==
                        true ||
                    candidates.any(
                      (other) =>
                          other.id != s.id &&
                          other.completedAt != null &&
                          other.completedAt == s.admissionDate,
                    ),
              )
              .toList();
          final owners = explicit.isNotEmpty ? explicit : candidates;
          owners.sort((a, b) {
            if (explicit.isNotEmpty) {
              final dateOrder = b.admissionDate.compareTo(a.admissionDate);
              if (dateOrder != 0) return dateOrder;
            } else {
              final bPricing = b.billingSummary['pricing'] is Map
                  ? Map<String, dynamic>.from(
                      b.billingSummary['pricing'] as Map,
                    )
                  : PricingHelper.approvedPricing(pricing);
              final aPricing = a.billingSummary['pricing'] is Map
                  ? Map<String, dynamic>.from(
                      a.billingSummary['pricing'] as Map,
                    )
                  : PricingHelper.approvedPricing(pricing);
              final bCost = isLongStay
                  ? PricingHelper.calculateLongStayDailyCharge(
                      b.roomType == 'private',
                      0,
                      pricing: bPricing,
                      patientBillable: patientBillable,
                    )
                  : PricingHelper.calculateDailyCharge(
                      b.roomType == 'private',
                      0,
                      pricing: bPricing,
                      patientBillable: patientBillable,
                    );
              final aCost = isLongStay
                  ? PricingHelper.calculateLongStayDailyCharge(
                      a.roomType == 'private',
                      0,
                      pricing: aPricing,
                      patientBillable: patientBillable,
                    )
                  : PricingHelper.calculateDailyCharge(
                      a.roomType == 'private',
                      0,
                      pricing: aPricing,
                      patientBillable: patientBillable,
                    );
              final costDiff = bCost.compareTo(aCost);
              if (costDiff != 0) return costDiff;
            }
            final dateOrder = b.admissionDate.compareTo(a.admissionDate);
            if (dateOrder != 0) return dateOrder;
            if (a.isActive != b.isActive) return b.isActive ? 1 : -1;
            return a.id.compareTo(b.id);
          });
          final segment = owners.first;

          final roster = segment.patientSnapshot['attendants'];
          final people = roster is List
              ? roster
              : (isCurrent
                    ? patient.attendants?.map((a) => a.toMap()).toList()
                    : null);
          final dailyMarks =
              attendantAttendance[dateKey(date)] ?? const <String, String>{};
          final known = <String>{};
          var dailyAttendants = 0;
          if (people is List) {
            for (final person in people.whereType<Map>()) {
              final name = person['name']?.toString();
              final currentPeople =
                  patient.attendants?.where((a) => a.name == name).toList() ??
                  <AttendantModel>[];
              final stableId =
                  person['id'] ??
                  (currentPeople.length == 1 ? currentPeople.single.id : null);
              final identity = (stableId ?? name)?.toString();
              if (identity == null) continue;
              final safeName = name?.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
              known.addAll([
                identity,
                if (name != null) name,
                if (safeName != null) safeName,
              ]);
              final associationStart = person['startDate']?.toString();
              final associationEnd = person['endDate']?.toString();
              if ((associationStart != null &&
                      dateKey(date).compareTo(associationStart) < 0) ||
                  (associationEnd != null &&
                      dateKey(date).compareTo(associationEnd) > 0)) {
                continue;
              }
              final uniqueName =
                  people
                      .whereType<Map>()
                      .where((p) => p['name']?.toString() == name)
                      .length ==
                  1;
              final mark =
                  (stableId != null || uniqueName
                      ? dailyMarks[identity]
                      : null) ??
                  (uniqueName
                      ? dailyMarks[name] ?? dailyMarks[safeName]
                      : null);
              if (mark == 'Present') dailyAttendants++;
              if (!const {'Present', 'Absent'}.contains(mark)) {
                pending.add({
                  'day': dateKey(date),
                  'kind': 'attendant_attendance',
                  'attendantId': identity,
                });
              }
            }
          }
          dailyAttendants += dailyMarks.entries
              .where(
                (entry) =>
                    !known.contains(entry.key) &&
                    eligibleHistoricalAttendant(entry.key, date, segments) &&
                    entry.value == 'Present',
              )
              .length;
          for (final mark in dailyMarks.entries.where(
            (entry) =>
                !known.contains(entry.key) &&
                eligibleHistoricalAttendant(entry.key, date, segments) &&
                !const {'Present', 'Absent'}.contains(entry.value),
          )) {
            pending.add({
              'day': dateKey(date),
              'kind': 'attendant_attendance',
              'attendantId': mark.key,
            });
          }

          final privateReserved = segment.roomType == 'private';
          final exitBoundaryExempt =
              !calendarDayBilling &&
              !date.isBefore(checkoutExclusiveEnd) &&
              status != 'Present' &&
              dailyAttendants == 0;
          if ((!patientBillable && dailyAttendants == 0 && !privateReserved) ||
              exitBoundaryExempt) {
            continue;
          }
          billableDays++;
          final segmentPricing = segment.billingSummary['pricing'] is Map
              ? Map<String, dynamic>.from(
                  segment.billingSummary['pricing'] as Map,
                )
              : PricingHelper.approvedPricing(pricing);
          double rateFor(StayModel segment) {
            final base =
                (segment.dailyRateIsManual ? segment.dailyRate : null) ??
                PricingHelper.calculateDailyCharge(
                  segment.roomType == 'private',
                  dailyAttendants,
                  pricing: segmentPricing,
                  patientBillable: patientBillable,
                );
            final rate = !isLongStay
                ? base
                : segment.longStayDailyRate ??
                      PricingHelper.calculateLongStayDailyCharge(
                        segment.roomType == 'private',
                        dailyAttendants,
                        pricing: segmentPricing,
                        patientBillable: patientBillable,
                        baseRateOverride: base,
                      );
            return rate;
          }

          final dailyRate = rateFor(segment);
          charges[segment.id] = charges[segment.id]! + dailyRate;
          days[segment.id] = days[segment.id]! + 1;

          if (calendarDayBilling &&
              isCurrent &&
              checkoutAt != null &&
              dateKey(date) == dateKey(billingDay(checkoutAt))) {
            final patientBase = PricingHelper.calculateDailyCharge(
              segment.roomType == 'private',
              0,
              pricing: segmentPricing,
              patientBillable: patientBillable,
            );
            final patientAmount = isLongStay
                ? PricingHelper.calculateLongStayDailyCharge(
                    segment.roomType == 'private',
                    0,
                    pricing: segmentPricing,
                    patientBillable: patientBillable,
                    baseRateOverride: patientBase,
                  )
                : patientBase;
            final custom =
                segment.dailyRateIsManual ||
                (isLongStay && segment.longStayDailyRate != null);
            checkoutAdjustment = {
              ...?checkoutAdjustment,
              'stayId': segment.id,
              'billableDay': billableDays,
              'patientPresentDaysBefore': patientPresentDaysBefore,
              'amount': segment.costOverride == null ? dailyRate : 0.0,
              'included': true,
              'includedInTotal': true,
              'includedByOverride': segment.costOverride != null,
              'patientAmount': custom ? null : patientAmount,
              'attendantAmount': custom ? null : (dailyRate - patientAmount),
              'category': segment.roomType,
              'checkoutAt': checkoutAt.millisecondsSinceEpoch,
              'day': dateKey(date),
            };
          }
        }
        for (final segment in segments) {
          if (segment.costOverride != null) {
            charges[segment.id] = segment.costOverride!;
          }
        }
      }
      var total = charges.values.fold<double>(0, (a, b) => a + b);
      if (frozen) {
        total = (saved['total'] as num).toDouble();
        if (saved['pendingAttendance'] is List) {
          pending.addAll(
            (saved['pendingAttendance'] as List).whereType<Map>().map(
              (row) => Map<String, dynamic>.from(row),
            ),
          );
        }
        final savedCharges = saved['segmentCharges'];
        final savedDays = saved['segmentDays'];
        for (final segment in segments) {
          charges[segment.id] =
              savedCharges is Map && savedCharges[segment.id] is num
              ? (savedCharges[segment.id] as num).toDouble()
              : segment.totalCost;
          days[segment.id] = savedDays is Map && savedDays[segment.id] is num
              ? (savedDays[segment.id] as num).toInt()
              : 0;
        }
        if (saved['checkoutAdjustment'] is Map) {
          checkoutAdjustment = Map<String, dynamic>.from(
            saved['checkoutAdjustment'] as Map,
          );
        }
        if (saved['actualPatientPresentDays'] is num) {
          actualPatientPresentDays = (saved['actualPatientPresentDays'] as num)
              .toInt();
        } else if (segments.isNotEmpty &&
            segments.last.billingSummary['actualPatientPresentDays'] is num) {
          actualPatientPresentDays =
              (segments.last.billingSummary['actualPatientPresentDays'] as num)
                  .toInt();
        }
        if (saved['projectedPatientPresentDays'] is num) {
          projectedPatientPresentDays =
              (saved['projectedPatientPresentDays'] as num).toInt();
        } else if (segments.isNotEmpty &&
            segments.last.billingSummary['projectedPatientPresentDays']
                is num) {
          projectedPatientPresentDays =
              (segments.last.billingSummary['projectedPatientPresentDays']
                      as num)
                  .toInt();
        }
      }
      if (segments.isEmpty && !frozen) {
        total = patient.advanceBilledAmount + patient.attendanceCharges;
      }
      // A patient-level override is legacy data from the old admission form.
      // Once stay segments exist, their calculated charges (or an explicit
      // stay costOverride) are authoritative so attendance can adjust totals.
      if (isCurrent &&
          segments.isEmpty &&
          patient.billingAmountOverride != null) {
        total = patient.billingAmountOverride!;
      }
      var paid = 0.0;
      var refunded = 0.0;
      for (final payment in patient.payments ?? <PaymentModel>[]) {
        if (paymentCycle(payment, patient, stays) != group.key) continue;
        if (payment.amount < 0) {
          refunded -= payment.amount;
        } else {
          paid += payment.amount;
        }
      }
      if (patient.payments == null && isCurrent) {
        paid = patient.totalPaidAmount ?? 0;
      }
      if (finalize && isCurrent && pending.isNotEmpty) {
        throw StateError(
          'Resolve ${pending.length} pending attendance record(s) before finalizing billing',
        );
      }
      result.add(
        AdmissionBalance(
          group.key,
          segments,
          charges,
          days,
          total,
          paid,
          refunded,
          pendingAttendance: pending,
          checkoutAdjustment: checkoutAdjustment,
          plannedExitConfirmed: frozen && saved['plannedExitConfirmed'] is bool
              ? saved['plannedExitConfirmed'] as bool
              : patient.exitDate != null,
          provisionalState: frozen
              ? saved['provisional'] == true
              : active && patient.exitDate == null && checkoutAt == null,
          checkoutAt: isCurrent ? checkoutAt?.millisecondsSinceEpoch : null,
          actualPatientPresentDays: actualPatientPresentDays,
          projectedPatientPresentDays: projectedPatientPresentDays,
          pricingBasis: frozen && saved['pricingBasis'] is String
              ? saved['pricingBasis'] as String
              : (finalize
                    ? 'actual_patient_present'
                    : 'projected_patient_present'),
        ),
      );
    }
    return result;
  }
}
