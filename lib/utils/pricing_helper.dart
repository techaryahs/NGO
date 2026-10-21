class PricingHelper {
  static const int advanceDays = 7;
  static const int longStayThresholdDays = 60;

  /// Physical stay duration, distinct from inclusive attendance dates.
  /// Checkout is at 9:00 AM; leaving after that time adds a billable day.
  static int calculateStayDays(DateTime start, DateTime? exit) {
    if (exit == null) return advanceDays;
    final billingStart = DateTime(start.year, start.month, start.day);
    var days = exit.difference(billingStart).inDays;
    if (exit.hour > 9 || (exit.hour == 9 && exit.minute > 0)) {
      days++;
    }
    return days.clamp(1, 3650);
  }

  /// Billable calendar days include both admission and checkout, at any time.
  /// Physical bed-allocation duration remains separate from this invoice rule.
  static int calculateBillingDays(DateTime start, DateTime? exit) =>
      attendancePeriod(start, exit).days.clamp(1, 3650);

  /// Calendar dates eligible for attendance and a separate admission estimate.
  /// This range must never be used to generate actual attendance.
  /// A planned exit is inclusive regardless of its physical checkout time.
  /// Without a planned exit, preserve the existing advance estimate.
  static ({DateTime start, DateTime end, int days}) attendancePeriod(
    DateTime start,
    DateTime? exit,
  ) {
    final first = DateTime(start.year, start.month, start.day);
    final last = exit == null
        ? DateTime(first.year, first.month, first.day + advanceDays - 1)
        : DateTime(exit.year, exit.month, exit.day);
    final days =
        DateTime.utc(
          last.year,
          last.month,
          last.day,
        ).difference(DateTime.utc(first.year, first.month, first.day)).inDays +
        1;
    return (start: first, end: last, days: days < 0 ? 0 : days);
  }

  static double calculateDailyCharge(
    bool isPrivate,
    int attendantsCount, {
    Map<String, dynamic>? pricing,
    int bedsCount = 1,
    bool patientBillable = true,
  }) {
    double rate(String key, double fallback) {
      final value = pricing?[key];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? fallback;
      // ₹150 was the legacy built-in General/Lobby fallback. Pricing service
      // reads migrate it to ₹200; keep pure billing calculations consistent
      // when they receive an older raw settings map.
      return key == 'generalRoomBedPrice' && parsed == 150 ? 200 : parsed;
    }

    int count(String key, int fallback) {
      final value = pricing?[key];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    if (isPrivate) {
      final base = rate('privateRoomBasePrice', 700);
      final included = count('privateRoomIncludedAttendants', 1);
      final extraFee = rate('privateRoomExtraAttendantFee', 200);
      return base +
          (attendantsCount > included
              ? (attendantsCount - included) * extraFee
              : 0.0);
    } else {
      return bedsCount *
          ((patientBillable ? 1 : 0) + attendantsCount) *
          rate('generalRoomBedPrice', 200);
    }
  }

  /// Daily rate used after the 60th billable day.
  ///
  /// The historical billing engine treats this as the long-stay/approved
  /// extension rate: General and Lobby add ₹50 for every billable person,
  /// while Private adds ₹200 plus ₹100 for each attendant above the
  /// configured included allowance.  [baseRateOverride] preserves a manual
  /// stay rate while applying the same historical long-stay surcharge.
  static double calculateLongStayDailyCharge(
    bool isPrivate,
    int attendantsCount, {
    Map<String, dynamic>? pricing,
    bool patientBillable = true,
    double? baseRateOverride,
    int bedsCount = 1,
  }) {
    final effectiveBeds = bedsCount < 1 ? 1 : bedsCount;
    final base =
        baseRateOverride ??
        calculateDailyCharge(
          isPrivate,
          attendantsCount,
          pricing: pricing,
          bedsCount: effectiveBeds,
          patientBillable: patientBillable,
        );
    if (isPrivate) {
      final included = _count(pricing, 'privateRoomIncludedAttendants', 1);
      return base + 200.0 + (attendantsCount - included).clamp(0, 100) * 100.0;
    }
    return base +
        effectiveBeds * ((patientBillable ? 1 : 0) + attendantsCount) * 50.0;
  }

  /// Calculates a planned stay estimate using the same daily rates as the
  /// attendance-aware billing engine. The planned period is projected as
  /// billable because no attendance rows exist yet; finalized billing can
  /// still reduce the total for explicit absences.
  ///
  /// [dailyRateOverride] is the historical per-stay manual daily rate. When
  /// present, it is used through the first 60 billable days and the normal
  /// long-stay surcharge is applied afterwards unless
  /// [longStayRateOverride] supplies an explicit long-stay rate.
  static double calculateProjectedStayCost(
    bool isPrivate,
    int attendantsCount,
    int projectedBillableDays, {
    Map<String, dynamic>? pricing,
    int bedsCount = 1,
    bool patientBillable = true,
    double? dailyRateOverride,
    double? longStayRateOverride,
  }) {
    if (projectedBillableDays <= 0) return 0;
    final effectiveBeds = bedsCount < 1 ? 1 : bedsCount;
    final baseRate =
        dailyRateOverride ??
        calculateDailyCharge(
          isPrivate,
          attendantsCount,
          pricing: pricing,
          bedsCount: effectiveBeds,
          patientBillable: patientBillable,
        );
    final longStayRate =
        longStayRateOverride ??
        calculateLongStayDailyCharge(
          isPrivate,
          attendantsCount,
          pricing: pricing,
          bedsCount: effectiveBeds,
          patientBillable: patientBillable,
          baseRateOverride: dailyRateOverride,
        );

    final baseDays = projectedBillableDays < longStayThresholdDays
        ? projectedBillableDays
        : longStayThresholdDays;
    final longStayDays = projectedBillableDays - baseDays;
    return baseDays * baseRate + longStayDays * longStayRate;
  }

  /// Estimates an extension using the same 60-day threshold as billing.
  ///
  /// This is metadata/UI estimation only; final totals still come from the
  /// admission billing calculation, which can use dated attendance records.
  static double calculateExtensionCost(
    bool isPrivate,
    int attendantsCount,
    int additionalDays, {
    Map<String, dynamic>? pricing,
    int priorBillableDays = 0,
    double? longStayRateOverride,
  }) {
    if (additionalDays <= 0) return 0;
    var total = 0.0;
    for (var offset = 1; offset <= additionalDays; offset++) {
      final billableDay = priorBillableDays + offset;
      total += billableDay <= longStayThresholdDays
          ? calculateDailyCharge(isPrivate, attendantsCount, pricing: pricing)
          : longStayRateOverride ??
                calculateLongStayDailyCharge(
                  isPrivate,
                  attendantsCount,
                  pricing: pricing,
                );
    }
    return total;
  }

  static double calculateAdvanceAmount(
    bool isPrivate,
    int attendantsCount, {
    Map<String, dynamic>? pricing,
    int bedsCount = 1,
  }) {
    return calculateDailyCharge(
          isPrivate,
          attendantsCount,
          pricing: pricing,
          bedsCount: bedsCount,
        ) *
        advanceDays;
  }

  static int _count(Map<String, dynamic>? pricing, String key, int fallback) {
    final value = pricing?[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
