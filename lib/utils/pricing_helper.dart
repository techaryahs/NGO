class PricingHelper {
  static const int advanceDays = 7;

  /// One shared stay-duration rule for forms, billing, overview, and stays.
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

  static double calculateDailyCharge(
    bool isPrivate,
    int attendantsCount, {
    Map<String, dynamic>? pricing,
    int bedsCount = 1,
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
          (1 + attendantsCount) *
          rate('generalRoomBedPrice', 150);
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
