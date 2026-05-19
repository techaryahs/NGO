/// Data model representing a Sponsorship Booking
class SponsorshipModel {
  final String id;
  final DateTime sponsorshipDate;
  final String sponsorPrefix;
  final String sponsorName;
  final String sponsorMobile;
  final String referencePrefix;
  final String referenceName;
  final String referenceMobile;
  final String occasion;
  final String? honoreeName;
  final double amount;
  final String paymentMethod;
  final String paymentStatus;
  final String transactionRef;
  final String notes;
  final String bookingStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  SponsorshipModel({
    required this.id,
    required this.sponsorshipDate,
    required this.sponsorPrefix,
    required this.sponsorName,
    required this.sponsorMobile,
    required this.referencePrefix,
    required this.referenceName,
    required this.referenceMobile,
    required this.occasion,
    this.honoreeName,
    required this.amount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.transactionRef,
    required this.notes,
    required this.bookingStatus,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  /// Map serialized JSON payload from Firebase RTDB to SponsorshipModel
  factory SponsorshipModel.fromMap(String key, Map<dynamic, dynamic> map) {
    return SponsorshipModel(
      id: key,
      sponsorshipDate: DateTime.fromMillisecondsSinceEpoch(
        map['sponsorshipDate'] is int
            ? map['sponsorshipDate']
            : (int.tryParse(map['sponsorshipDate'].toString()) ?? 0),
      ),
      sponsorPrefix: map['sponsorPrefix']?.toString() ?? 'Shri',
      sponsorName: map['sponsorName']?.toString() ?? '',
      sponsorMobile: map['sponsorMobile']?.toString() ?? '',
      referencePrefix: map['referencePrefix']?.toString() ?? 'Shri',
      referenceName: map['referenceName']?.toString() ?? '',
      referenceMobile: map['referenceMobile']?.toString() ?? '',
      occasion: map['occasion']?.toString() ?? 'Birthday',
      honoreeName: map['honoreeName']?.toString(),
      amount: map['amount'] is num
          ? (map['amount'] as num).toDouble()
          : (double.tryParse(map['amount']?.toString() ?? '') ?? 0.0),
      paymentMethod: map['paymentMethod']?.toString() ?? 'Cash',
      paymentStatus: map['paymentStatus']?.toString() ?? 'Pending',
      transactionRef: map['transactionRef']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      bookingStatus: map['bookingStatus']?.toString() ?? 'Booked',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] is int
            ? map['createdAt']
            : (int.tryParse(map['createdAt'].toString()) ?? 0),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updatedAt'] is int
            ? map['updatedAt']
            : (int.tryParse(map['updatedAt'].toString()) ?? 0),
      ),
      createdBy: map['createdBy']?.toString() ?? 'Admin',
      updatedBy: map['updatedBy']?.toString() ?? 'Admin',
    );
  }

  /// Serialize model instance back to JSON-friendly Map for Firebase REST writes
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sponsorshipDate': sponsorshipDate.millisecondsSinceEpoch,
      'sponsorPrefix': sponsorPrefix,
      'sponsorName': sponsorName,
      'sponsorMobile': sponsorMobile,
      'referencePrefix': referencePrefix,
      'referenceName': referenceName,
      'referenceMobile': referenceMobile,
      'occasion': occasion,
      'honoreeName': honoreeName,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'transactionRef': transactionRef,
      'notes': notes,
      'bookingStatus': bookingStatus,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
    };
  }

  /// Helper copy constructor to mutate records easily
  SponsorshipModel copyWith({
    String? id,
    DateTime? sponsorshipDate,
    String? sponsorPrefix,
    String? sponsorName,
    String? sponsorMobile,
    String? referencePrefix,
    String? referenceName,
    String? referenceMobile,
    String? occasion,
    String? honoreeName,
    double? amount,
    String? paymentMethod,
    String? paymentStatus,
    String? transactionRef,
    String? notes,
    String? bookingStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
  }) {
    return SponsorshipModel(
      id: id ?? this.id,
      sponsorshipDate: sponsorshipDate ?? this.sponsorshipDate,
      sponsorPrefix: sponsorPrefix ?? this.sponsorPrefix,
      sponsorName: sponsorName ?? this.sponsorName,
      sponsorMobile: sponsorMobile ?? this.sponsorMobile,
      referencePrefix: referencePrefix ?? this.referencePrefix,
      referenceName: referenceName ?? this.referenceName,
      referenceMobile: referenceMobile ?? this.referenceMobile,
      occasion: occasion ?? this.occasion,
      honoreeName: honoreeName ?? this.honoreeName,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      transactionRef: transactionRef ?? this.transactionRef,
      notes: notes ?? this.notes,
      bookingStatus: bookingStatus ?? this.bookingStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
