class PricingHelper {
  static const int advanceDays = 7;

  static double calculateDailyCharge(bool isPrivate, int attendantsCount) {
    if (isPrivate) {
      // The room charge includes the patient and one attendant. From the
      // second attendant onward, each attendant is charged at ₹200/day.
      return 700.0 +
          (attendantsCount > 1 ? (attendantsCount - 1) * 200.0 : 0.0);
    } else {
      // 1 patient + attendantsCount. Max occupants = 3 is enforced in UI.
      return (1 + attendantsCount) * 200.0;
    }
  }

  static double calculateAdvanceAmount(bool isPrivate, int attendantsCount) {
    return calculateDailyCharge(isPrivate, attendantsCount) * advanceDays;
  }
}
