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
  AdmissionBalance(
    this.id,
    this.stays,
    this.charges,
    this.days,
    this.total,
    this.paid,
    this.refunded,
  );
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
  };
}

/// One bill per admission. A transfer day belongs to its last room segment,
/// so changing rooms never charges two full days for the same patient.
class StayBilling {
  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static String dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String currentCycle(PatientModel patient) =>
      patient.admissionDate.millisecondsSinceEpoch.toString();
  static String cycleFor(StayModel stay, PatientModel patient) {
    if (stay.cycleId != null) return stay.cycleId!;
    final saved = stay.patientSnapshot['admissionDate'];
    if (saved != null) return saved.toString();
    if (!stay.createdAt.isBefore(
          patient.admissionDate.subtract(const Duration(minutes: 1)),
        ) ||
        stay.admissionDate ==
            (patient.registrationDate ?? patient.admissionDate)) {
      return currentCycle(patient);
    }
    return stay.admissionDate.millisecondsSinceEpoch.toString();
  }

  static String paymentCycle(
    PaymentModel payment,
    PatientModel patient,
    List<StayModel> stays,
  ) {
    if (payment.cycleId != null) return payment.cycleId!;
    final boundaries = <int>{patient.admissionDate.millisecondsSinceEpoch};
    for (final stay in stays) {
      final timestamp = int.tryParse(cycleFor(stay, patient));
      if (timestamp != null) boundaries.add(timestamp);
    }
    final sorted = boundaries.toList()..sort();
    // Older receipts do not have a cycleId and may have been entered earlier
    // on the admission date than the recorded registration time. Match those
    // receipts by calendar day so a valid same-day payment is not discarded.
    final paymentDay = day(payment.date);
    final before = sorted.where((value) {
      final boundaryDay = day(DateTime.fromMillisecondsSinceEpoch(value));
      return !boundaryDay.isAfter(paymentDay);
    });
    return before.isEmpty ? 'before-${sorted.first}' : before.last.toString();
  }

  static List<AdmissionBalance> calculate({
    required PatientModel patient,
    required List<StayModel> stays,
    required Map<String, dynamic> pricing,
    Map<String, String> attendance = const {},
    Map<String, Map<String, String>> attendantAttendance = const {},
    DateTime? now,
    bool onlyPresent = false,
  }) {
    final groups = <String, List<StayModel>>{};
    for (final stay in stays.where((s) => s.status != 'cancelled')) {
      groups.putIfAbsent(cycleFor(stay, patient), () => []).add(stay);
    }
    groups.putIfAbsent(currentCycle(patient), () => []);
    final result = <AdmissionBalance>[];
    for (final group in groups.entries) {
      final segments = [...group.value]
        ..sort((a, b) => a.admissionDate.compareTo(b.admissionDate));
      final charges = <String, double>{for (final s in segments) s.id: 0};
      final days = <String, int>{for (final s in segments) s.id: 0};
      final isCurrent = group.key == currentCycle(patient);
      final active = isCurrent && patient.status.toLowerCase() != 'discharged';
      if (segments.isNotEmpty) {
        final start = day(segments.first.admissionDate);
        DateTime end;
        if (active) {
          // A recorded exit date is the billing boundary even while the
          // patient is still awaiting formal discharge. Without an exit date,
          // retain the seven-day estimate and grow it through the current day.
          if (patient.exitDate != null) {
            end = patient.exitDate!;
          } else {
            end = start.add(const Duration(days: PricingHelper.advanceDays));
            final today = day(
              now ?? DateTime.now(),
            ).add(const Duration(days: 1));
            if (end.isBefore(today)) end = today;
          }
        } else {
          end = segments
              .map((s) => s.completedAt ?? s.updatedAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);
        }
        var exclusiveEnd = day(end);
        if (end.hour > 9 || (end.hour == 9 && end.minute > 0)) {
          exclusiveEnd = exclusiveEnd.add(const Duration(days: 1));
        }
        if (!exclusiveEnd.isAfter(start))
          exclusiveEnd = start.add(const Duration(days: 1));
        var billableDays = 0;
        for (
          var date = start;
          date.isBefore(exclusiveEnd);
          date = DateTime(date.year, date.month, date.day + 1)
        ) {
          final status = attendance[dateKey(date)];
          if (status == 'Absent' || (onlyPresent && status != 'Present'))
            continue;
          final candidates = segments.where((s) {
            if (day(s.admissionDate).isAfter(date)) return false;
            if (s.isActive && active) return true;
            final checkout = s.completedAt ?? s.updatedAt;
            var checkoutEnd = day(checkout);
            if (checkout.hour > 9 ||
                (checkout.hour == 9 && checkout.minute > 0)) {
              checkoutEnd = checkoutEnd.add(const Duration(days: 1));
            }
            return date.isBefore(checkoutEnd) ||
                (date == day(s.admissionDate) &&
                    checkout.isAfter(s.admissionDate));
          }).toList();
          if (candidates.isEmpty) continue;
          billableDays++;
          int attendantsFor(StayModel segment) {
            final daily = attendantAttendance[dateKey(date)];
            if (daily == null) return 0;
            return daily.values.where((status) => status == 'Present').length;
          }

          double rateFor(StayModel segment) {
            final dailyAttendants = attendantsFor(segment);
            final base =
                (segment.dailyRateIsManual ? segment.dailyRate : null) ??
                PricingHelper.calculateDailyCharge(
                  segment.roomType == 'private',
                  dailyAttendants,
                  pricing: pricing,
                );
            final extra = segment.roomType == 'private'
                ? 200.0 +
                      (dailyAttendants -
                                  ((pricing['privateRoomIncludedAttendants']
                                              as num?)
                                          ?.toInt() ??
                                      1))
                              .clamp(0, 100) *
                          100.0
                : (1 + dailyAttendants) * 50.0;
            final rate = billableDays <= 60
                ? base
                : segment.longStayDailyRate ?? (base + extra);
            return rate;
          }

          // A transfer date is charged exactly once. When more than one room
          // segment touches that date, use the highest applicable room rate,
          // matching common inpatient transfer billing practice. Payments
          // remain admission-level credits and never decide which room owns
          // the day.
          candidates.sort((a, b) {
            final rateOrder = rateFor(b).compareTo(rateFor(a));
            if (rateOrder != 0) return rateOrder;
            return b.admissionDate.compareTo(a.admissionDate);
          });
          final segment = candidates.first;
          charges[segment.id] = charges[segment.id]! + rateFor(segment);
          days[segment.id] = days[segment.id]! + 1;
        }
        for (final segment in segments) {
          if (segment.costOverride != null)
            charges[segment.id] = segment.costOverride!;
        }
      }
      var total = charges.values.fold<double>(0, (a, b) => a + b);
      if (segments.isEmpty)
        total = patient.advanceBilledAmount + patient.attendanceCharges;
      // A patient-level override is legacy data from the old admission form.
      // Once stay segments exist, their calculated charges (or an explicit
      // stay costOverride) are authoritative so attendance can adjust totals.
      if (isCurrent && segments.isEmpty && patient.billingAmountOverride != null)
        total = patient.billingAmountOverride!;
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
      if (patient.payments == null && isCurrent)
        paid = patient.totalPaidAmount ?? 0;
      result.add(
        AdmissionBalance(
          group.key,
          segments,
          charges,
          days,
          total,
          paid,
          refunded,
        ),
      );
    }
    return result;
  }
}
