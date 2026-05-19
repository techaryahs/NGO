/// Model representing a supplier vendor.
class VendorModel {
  final String id;
  final String name;
  final String contactPerson;
  final String mobileNumber;
  final String email;
  final String gstNumber;
  final String address;
  final String notes;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  VendorModel({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.mobileNumber,
    required this.email,
    required this.gstNumber,
    required this.address,
    required this.notes,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'contactPerson': contactPerson,
      'mobileNumber': mobileNumber,
      'email': email,
      'gstNumber': gstNumber,
      'address': address,
      'notes': notes,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory VendorModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return VendorModel(
      id: id,
      name: data['name']?.toString() ?? '',
      contactPerson: data['contactPerson']?.toString() ?? '',
      mobileNumber: data['mobileNumber']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      gstNumber: data['gstNumber']?.toString() ?? '',
      address: data['address']?.toString() ?? '',
      notes: data['notes']?.toString() ?? '',
      createdBy: data['createdBy']?.toString() ?? '',
      updatedBy: data['updatedBy']?.toString() ?? '',
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final parsed = int.tryParse(value.toString());
    return DateTime.fromMillisecondsSinceEpoch(parsed ?? DateTime.now().millisecondsSinceEpoch);
  }

  VendorModel copyWith({
    String? id,
    String? name,
    String? contactPerson,
    String? mobileNumber,
    String? email,
    String? gstNumber,
    String? address,
    String? notes,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VendorModel(
      id: id ?? this.id,
      name: name ?? this.name,
      contactPerson: contactPerson ?? this.contactPerson,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      email: email ?? this.email,
      gstNumber: gstNumber ?? this.gstNumber,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
