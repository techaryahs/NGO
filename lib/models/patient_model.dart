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

  // ── Structured Attendants ─────────────────────────────────────────────────
  final List<AttendantModel>? attendants;

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
    this.attendants,
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
      'attendants': attendants?.map((a) => a.toMap()).toList(),
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
      bedIds: data['bedIds'] != null ? List<String>.from(data['bedIds']) : null,
      bedLabels: data['bedLabels'] != null ? List<String>.from(data['bedLabels']) : null,
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
      attendants: data['attendants'] != null
          ? (data['attendants'] as List)
              .map((a) => AttendantModel.fromMap(Map<String, dynamic>.from(a as Map)))
              .toList()
          : null,
    );
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
    List<AttendantModel>? attendants,
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
      attendants: attendants ?? this.attendants,
    );
  }

  @override
  String toString() => 'PatientModel(id: $id, fullName: $fullName, status: $status)';
}
