class PricingHelper {
  static const int advanceDays = 7;

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

  /// Calendar dates eligible for attendance and its admission estimate.
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
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
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
}
