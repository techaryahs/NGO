class PricingHelper {
  static const int advanceDays = 7;

  static double calculateDailyCharge(bool isPrivate, int attendantsCount) {
    if (isPrivate) {
      return 700.0 + (attendantsCount * 200.0);
    } else {
      // 1 patient + attendantsCount. Max occupants = 3 is enforced in UI.
      return (1 + attendantsCount) * 200.0;
    }
  }

  static double calculateAdvanceAmount(bool isPrivate, int attendantsCount) {
    return calculateDailyCharge(isPrivate, attendantsCount) * advanceDays;
  }
}
