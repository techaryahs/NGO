import 'payment_details_model.dart';

/// Model representing a general operational expense entry.
class ExpenseEntryModel {
  final String id;
  final DateTime expenseDate;
  final String category;
  final String? subcategory;
  final String? itemName;
  final String? vendorId;
  final String? vendorName;
  final String description;
  final double? quantity;
  final String? unit;
  final double? unitPrice;
  final double totalAmount;
  final PaymentDetailsModel paymentDetails;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  ExpenseEntryModel({
    required this.id,
    required this.expenseDate,
    required this.category,
    this.subcategory,
    this.itemName,
    this.vendorId,
    this.vendorName,
    required this.description,
    this.quantity,
    this.unit,
    this.unitPrice,
    required this.totalAmount,
    required this.paymentDetails,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expenseDate': expenseDate.millisecondsSinceEpoch,
      'category': category,
      'subcategory': subcategory,
      'itemName': itemName,
      'vendorId': vendorId,
      'vendorName': vendorName,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'totalAmount': totalAmount,
      'paymentDetails': paymentDetails.toMap(),
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ExpenseEntryModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return ExpenseEntryModel(
      id: id,
      expenseDate: _parseDateTime(data['expenseDate']),
      category: data['category']?.toString() ?? '',
      subcategory: data['subcategory']?.toString(),
      itemName: data['itemName']?.toString(),
      vendorId: data['vendorId']?.toString(),
      vendorName: data['vendorName']?.toString(),
      description: data['description']?.toString() ?? '',
      quantity: data['quantity'] != null ? _parseDouble(data['quantity']) : null,
      unit: data['unit']?.toString(),
      unitPrice: data['unitPrice'] != null ? _parseDouble(data['unitPrice']) : null,
      totalAmount: _parseDouble(data['totalAmount']),
      paymentDetails: PaymentDetailsModel.fromMap(
        Map<dynamic, dynamic>.from(data['paymentDetails'] ?? {}),
      ),
      createdBy: data['createdBy']?.toString() ?? '',
      updatedBy: data['updatedBy']?.toString() ?? '',
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final parsed = int.tryParse(value.toString());
    return DateTime.fromMillisecondsSinceEpoch(parsed ?? DateTime.now().millisecondsSinceEpoch);
  }

  ExpenseEntryModel copyWith({
    String? id,
    DateTime? expenseDate,
    String? category,
    String? subcategory,
    String? itemName,
    String? vendorId,
    String? vendorName,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? totalAmount,
    PaymentDetailsModel? paymentDetails,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseEntryModel(
      id: id ?? this.id,
      expenseDate: expenseDate ?? this.expenseDate,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      itemName: itemName ?? this.itemName,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentDetails: paymentDetails ?? this.paymentDetails,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
