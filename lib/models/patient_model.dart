import '../utils/bed_helper.dart';

/// AttendantModel — RTDB-compatible data model for patient attendants.
class AttendantModel {
  final String name;
  final String? age;
  final String? relation;

  AttendantModel({required this.name, this.age, this.relation});

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'age': age,
      'relation': relation,
    };
  }

  factory AttendantModel.fromMap(Map<dynamic, dynamic> data) {
    return AttendantModel(
      name: data['name']?.toString() ?? '',
      age: data['age']?.toString(),
      relation: data['relation']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttendantModel &&
        other.name == name &&
        other.age == age &&
        other.relation == relation;
  }

  @override
  int get hashCode => name.hashCode ^ age.hashCode ^ relation.hashCode;
}

/// PaymentModel — Represents a single payment transaction.
class PaymentModel {
  final String id;
  final double amount;
  final String method; // 'cash', 'check', 'online'
  final DateTime date;
  final String? receiptNumber;
  final String? checkNumber;
  final String? bankName;
  final String? transactionId; // For online payments
  final String? notes;

  // Partial Payment support fields
  final double totalAmount;
  final double paidAmount;
  final double pendingAmount;
  final String paymentStatus;

  PaymentModel({
    required this.id,
    required this.amount, // Keeping for backward compat, representing the transaction amount
    required this.method,
    required this.date,
    this.totalAmount = 0.0,
    this.paidAmount = 0.0,
    this.pendingAmount = 0.0,
    this.paymentStatus = 'Paid',
    this.receiptNumber,
    this.checkNumber,
    this.bankName,
    this.transactionId,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'pendingAmount': pendingAmount,
      'paymentStatus': paymentStatus,
      'method': method,
      'date': date.millisecondsSinceEpoch,
      'receiptNumber': receiptNumber,
      'checkNumber': checkNumber,
      'bankName': bankName,
      'transactionId': transactionId,
      'notes': notes,
    };
  }

  factory PaymentModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return PaymentModel(
      id: id,
      amount: (data['amount'] ?? 0).toDouble(),
      totalAmount: (data['totalAmount'] ?? data['amount'] ?? 0).toDouble(),
      paidAmount: (data['paidAmount'] ?? data['amount'] ?? 0).toDouble(),
      pendingAmount: (data['pendingAmount'] ?? 0).toDouble(),
      paymentStatus: data['paymentStatus']?.toString() ?? 'Paid',
      method: data['method']?.toString() ?? 'cash',
      date: DateTime.fromMillisecondsSinceEpoch(data['date'] ?? 0),
      receiptNumber: data['receiptNumber']?.toString(),
      checkNumber: data['checkNumber']?.toString(),
      bankName: data['bankName']?.toString(),
      transactionId: data['transactionId']?.toString(),
      notes: data['notes']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaymentModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// PatientModel — RTDB-compatible data model.
///
/// All dates are stored as `millisecondsSinceEpoch` (int) in RTDB.
/// The `fromMap` factory accepts `Map<dynamic, dynamic>` because
/// `DataSnapshot.value` returns exactly that type from RTDB.
class PatientModel {
  final String id;
  final String fullName;
  final String searchKey;
  final DateTime dateOfBirth;
  final int age;
  final String gender;
  final String contactNumber;
  final String emergencyContact;
  final String emergencyContactName;
  final String medicalCondition;
  final String? allergies;
  final String? bloodType;
  final DateTime admissionDate;
  final String status; // 'active', 'discharged', 'transferred'
  final DateTime? dischargeDate;
  final String? roomId;
  final String? roomNumber;
  final int? floor;
  final List<String>? bedIds; // Added for explicit bed tracking
  final List<String>? bedLabels; // Added for UI display
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  // ── New administrative / identity fields ──────────────────────────────────
  final String? registrationNumber;
  final DateTime? registrationDate;
  final String? panCardNumber;
  final String? aadhaarCardNumber;
  final String? receiptNumber;
  final String? modeOfPayment;
  final String? utiNumber;
  final bool? paymentPending;
  final String? paymentStatus;
  final double? totalPaidAmount;
  final double? currentDueAmount;
  final DateTime? paymentDueDate;

  // ── Billing / Attendance Metrics ──────────────────────────────────────────
  final bool isAdvancePeriod;
  final double advanceBilledAmount;
  final double attendanceCharges;
  final int totalPresentDays;
  final int totalAbsentDays;

  // ── Structured Attendants ─────────────────────────────────────────────────
  final List<AttendantModel>? attendants;

  // ── Stay & Extensions ─────────────────────────────────────────────────────
  final int maxStayDays;
  final bool extensionApproved;
  final int extensionDays;
  final String? extensionReason;
  final String? approvedBy;
  final DateTime? approvedDate;

  // ── Payment History ───────────────────────────────────────────────────────
  final List<PaymentModel>? payments;

  PatientModel({
    required this.id,
    required this.fullName,
    required this.searchKey,
    required this.dateOfBirth,
    required this.age,
    required this.gender,
    required this.contactNumber,
    required this.emergencyContact,
    required this.emergencyContactName,
    required this.medicalCondition,
    this.allergies,
    this.bloodType,
    required this.admissionDate,
    required this.status,
    this.roomId,
    this.roomNumber,
    this.floor,
    this.bedIds,
    this.bedLabels,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    this.registrationNumber,
    this.registrationDate,
    this.panCardNumber,
    this.aadhaarCardNumber,
    this.receiptNumber,
    this.modeOfPayment,
    this.utiNumber,
    this.paymentPending,
    this.paymentStatus,
    this.totalPaidAmount,
    this.currentDueAmount,
    this.paymentDueDate,
    this.isAdvancePeriod = true,
    this.advanceBilledAmount = 0.0,
    this.attendanceCharges = 0.0,
    this.totalPresentDays = 0,
    this.totalAbsentDays = 0,
    this.attendants,
    this.payments,
    this.dischargeDate,
    this.maxStayDays = 60,
    this.extensionApproved = false,
    this.extensionDays = 0,
    this.extensionReason,
    this.approvedBy,
    this.approvedDate,
  });

  // ---------------------------------------------------------------------------
  // Serialization — Model → RTDB
  // ---------------------------------------------------------------------------

  /// Converts this model into a plain `Map<String, dynamic>` for RTDB `.set()`.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'searchKey': searchKey,
      'dateOfBirth': dateOfBirth.millisecondsSinceEpoch,
      'age': age,
      'gender': gender,
      'contactNumber': contactNumber,
      'emergencyContact': emergencyContact,
      'emergencyContactName': emergencyContactName,
      'medicalCondition': medicalCondition,
      'allergies': allergies,
      'bloodType': bloodType,
      'admissionDate': admissionDate.millisecondsSinceEpoch,
      'status': status,
      'roomId': roomId,
      'roomNumber': roomNumber,
      'floor': floor,
      'bedIds': bedIds,
      'bedLabels': bedLabels,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'registrationNumber': registrationNumber,
      'registrationDate': registrationDate?.millisecondsSinceEpoch,
      'panCardNumber': panCardNumber,
      'aadhaarCardNumber': aadhaarCardNumber,
      'receiptNumber': receiptNumber,
      'modeOfPayment': modeOfPayment,
      'utiNumber': utiNumber,
      'paymentPending': paymentPending,
      'paymentStatus': paymentStatus,
      'totalPaidAmount': totalPaidAmount,
      'currentDueAmount': currentDueAmount,
      'paymentDueDate': paymentDueDate?.millisecondsSinceEpoch,
      'isAdvancePeriod': isAdvancePeriod,
      'advanceBilledAmount': advanceBilledAmount,
      'attendanceCharges': attendanceCharges,
      'totalPresentDays': totalPresentDays,
      'totalAbsentDays': totalAbsentDays,
      'attendants': attendants?.map((a) => a.toMap()).toList(),
      'payments': payments?.map((p) => p.toMap()).toList(),
      'dischargeDate': dischargeDate?.millisecondsSinceEpoch,
      'maxStayDays': maxStayDays,
      'extensionApproved': extensionApproved,
      'extensionDays': extensionDays,
      'extensionReason': extensionReason,
      'approvedBy': approvedBy,
      'approvedDate': approvedDate?.millisecondsSinceEpoch,
    };
  }

  /// Alias for `toMap()` — matches JSON convention naming.
  Map<String, dynamic> toJson() => toMap();

  // ---------------------------------------------------------------------------
  // Deserialization — RTDB → Model
  // ---------------------------------------------------------------------------

  /// Creates a [PatientModel] from a Realtime Database snapshot map.
  ///
  /// [id] is the RTDB push-key (e.g. `-NxA1b2C3d4E5f6G7h8I`).
  /// [data] is `DataSnapshot.value` cast as `Map<dynamic, dynamic>`.
  factory PatientModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return PatientModel(
      id: id,
      fullName: _parseString(data['fullName']),
      searchKey: _parseString(data['searchKey']),
      dateOfBirth: _parseDateTime(data['dateOfBirth']),
      age: _parseInt(data['age']),
      gender: _parseString(data['gender']),
      contactNumber: _parseString(data['contactNumber']),
      emergencyContact: _parseString(data['emergencyContact']),
      emergencyContactName: _parseString(data['emergencyContactName']),
      medicalCondition: _parseString(data['medicalCondition']),
      allergies: data['allergies']?.toString(),
      bloodType: data['bloodType']?.toString(),
      admissionDate: _parseDateTime(data['admissionDate']),
      status: _parseString(data['status'], fallback: 'active'),
      roomId: data['roomId']?.toString(),
      roomNumber: data['roomNumber']?.toString(),
      floor: data['floor'] != null ? _parseInt(data['floor']) : null,
      bedIds: data['bedIds'] != null 
          ? List<String>.from(data['bedIds'])
          : null,
      bedLabels: data['bedLabels'] != null 
          ? List<String>.from(data['bedLabels'])
          : null,
      notes: data['notes']?.toString(),
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      createdBy: _parseString(data['createdBy']),
      registrationNumber: data['registrationNumber']?.toString(),
      registrationDate: data['registrationDate'] != null
          ? _parseDateTime(data['registrationDate'])
          : null,
      panCardNumber: data['panCardNumber']?.toString(),
      aadhaarCardNumber: data['aadhaarCardNumber']?.toString(),
      receiptNumber: data['receiptNumber']?.toString(),
      modeOfPayment: data['modeOfPayment']?.toString(),
      utiNumber: data['utiNumber']?.toString(),
      paymentPending: data['paymentPending'] as bool? ?? false,
      paymentStatus: data['paymentStatus']?.toString(),
      totalPaidAmount: (data['totalPaidAmount'] ?? 0).toDouble(),
      currentDueAmount: (data['currentDueAmount'] ?? 0).toDouble(),
      paymentDueDate: data['paymentDueDate'] != null
          ? _parseDateTime(data['paymentDueDate'])
          : null,
      isAdvancePeriod: data['isAdvancePeriod'] as bool? ?? true,
      advanceBilledAmount: (data['advanceBilledAmount'] ?? 0).toDouble(),
      attendanceCharges: (data['attendanceCharges'] ?? 0).toDouble(),
      totalPresentDays: _parseInt(data['totalPresentDays']),
      totalAbsentDays: _parseInt(data['totalAbsentDays']),
      attendants: data['attendants'] != null
          ? _parseList(data['attendants'], (item) => AttendantModel.fromMap(Map<String, dynamic>.from(item as Map)))
          : null,
      payments: data['payments'] != null
          ? _parseList(data['payments'], (item) {
              final p = item as Map;
              return PaymentModel.fromMap(
                p['id']?.toString() ?? '',
                Map<String, dynamic>.from(p),
              );
            })
          : null,
      dischargeDate: data['dischargeDate'] != null
          ? _parseDateTime(data['dischargeDate'])
          : null,
      maxStayDays: data['maxStayDays'] != null ? _parseInt(data['maxStayDays']) : 60,
      extensionApproved: data['extensionApproved'] as bool? ?? false,
      extensionDays: _parseInt(data['extensionDays']),
      extensionReason: data['extensionReason']?.toString(),
      approvedBy: data['approvedBy']?.toString(),
      approvedDate: data['approvedDate'] != null
          ? _parseDateTime(data['approvedDate'])
          : null,
    );
  }

  /// Helper to parse potentially List or Map structures from RTDB
  static List<T> _parseList<T>(dynamic data, T Function(dynamic) mapper) {
    if (data == null) return [];
    if (data is List) {
      return data.where((e) => e != null).map((e) => mapper(e)).toList();
    }
    if (data is Map) {
      return data.values.where((e) => e != null).map((e) => mapper(e)).toList();
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Safely parse a string from a dynamic RTDB value.
  static String _parseString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  /// Safely parse an int from a dynamic RTDB value.
  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  /// Safely parse a DateTime from a millisecondsSinceEpoch value.
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final parsed = int.tryParse(value.toString());
    return DateTime.fromMillisecondsSinceEpoch(parsed ?? 0);
  }

  /// Calculate age from a date of birth.
  static int calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  PatientModel copyWith({
    String? id,
    String? fullName,
    String? searchKey,
    DateTime? dateOfBirth,
    int? age,
    String? gender,
    String? contactNumber,
    String? emergencyContact,
    String? emergencyContactName,
    String? medicalCondition,
    String? allergies,
    String? bloodType,
    DateTime? admissionDate,
    String? status,
    String? roomId,
    String? roomNumber,
    int? floor,
    List<String>? bedIds,
    List<String>? bedLabels,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? registrationNumber,
    DateTime? registrationDate,
    String? panCardNumber,
    String? aadhaarCardNumber,
    String? receiptNumber,
    String? modeOfPayment,
    String? utiNumber,
    bool? paymentPending,
    String? paymentStatus,
    double? totalPaidAmount,
    double? currentDueAmount,
    DateTime? paymentDueDate,
    bool? isAdvancePeriod,
    double? advanceBilledAmount,
    double? attendanceCharges,
    int? totalPresentDays,
    int? totalAbsentDays,
    List<AttendantModel>? attendants,
    List<PaymentModel>? payments,
    DateTime? dischargeDate,
    int? maxStayDays,
    bool? extensionApproved,
    int? extensionDays,
    String? extensionReason,
    String? approvedBy,
    DateTime? approvedDate,
  }) {
    return PatientModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      searchKey: searchKey ?? this.searchKey,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      contactNumber: contactNumber ?? this.contactNumber,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      medicalCondition: medicalCondition ?? this.medicalCondition,
      allergies: allergies ?? this.allergies,
      bloodType: bloodType ?? this.bloodType,
      admissionDate: admissionDate ?? this.admissionDate,
      status: status ?? this.status,
      roomId: roomId ?? this.roomId,
      roomNumber: roomNumber ?? this.roomNumber,
      floor: floor ?? this.floor,
      bedIds: bedIds ?? this.bedIds,
      bedLabels: bedLabels ?? this.bedLabels,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      registrationDate: registrationDate ?? this.registrationDate,
      panCardNumber: panCardNumber ?? this.panCardNumber,
      aadhaarCardNumber: aadhaarCardNumber ?? this.aadhaarCardNumber,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      modeOfPayment: modeOfPayment ?? this.modeOfPayment,
      utiNumber: utiNumber ?? this.utiNumber,
      paymentPending: paymentPending ?? this.paymentPending,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      totalPaidAmount: totalPaidAmount ?? this.totalPaidAmount,
      currentDueAmount: currentDueAmount ?? this.currentDueAmount,
      paymentDueDate: paymentDueDate ?? this.paymentDueDate,
      isAdvancePeriod: isAdvancePeriod ?? this.isAdvancePeriod,
      advanceBilledAmount: advanceBilledAmount ?? this.advanceBilledAmount,
      attendanceCharges: attendanceCharges ?? this.attendanceCharges,
      totalPresentDays: totalPresentDays ?? this.totalPresentDays,
      totalAbsentDays: totalAbsentDays ?? this.totalAbsentDays,
      attendants: attendants ?? this.attendants,
      payments: payments ?? this.payments,
      dischargeDate: dischargeDate ?? this.dischargeDate,
      maxStayDays: maxStayDays ?? this.maxStayDays,
      extensionApproved: extensionApproved ?? this.extensionApproved,
      extensionDays: extensionDays ?? this.extensionDays,
      extensionReason: extensionReason ?? this.extensionReason,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedDate: approvedDate ?? this.approvedDate,
    );
  }

  @override
  String toString() => 'PatientModel(id: $id, fullName: $fullName, status: $status)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatientModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
