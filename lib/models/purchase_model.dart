import 'payment_details_model.dart';

/// Model representing a stock purchase entry.
class PurchaseModel {
  final String id;
  final DateTime purchaseDate;
  final String vendorId;
  final String vendorName;
  final String itemId;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final String invoiceNumber;
  final PaymentDetailsModel paymentDetails;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchaseModel({
    required this.id,
    required this.purchaseDate,
    required this.vendorId,
    required this.vendorName,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.invoiceNumber,
    required this.paymentDetails,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'purchaseDate': purchaseDate.millisecondsSinceEpoch,
      'vendorId': vendorId,
      'vendorName': vendorName,
      'itemId': itemId,
      'itemName': itemName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalAmount': totalAmount,
      'invoiceNumber': invoiceNumber,
      'paymentDetails': paymentDetails.toMap(),
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PurchaseModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return PurchaseModel(
      id: id,
      purchaseDate: _parseDateTime(data['purchaseDate']),
      vendorId: data['vendorId']?.toString() ?? '',
      vendorName: data['vendorName']?.toString() ?? '',
      itemId: data['itemId']?.toString() ?? '',
      itemName: data['itemName']?.toString() ?? '',
      quantity: _parseDouble(data['quantity']),
      unitPrice: _parseDouble(data['unitPrice']),
      totalAmount: _parseDouble(data['totalAmount']),
      invoiceNumber: data['invoiceNumber']?.toString() ?? '',
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

  PurchaseModel copyWith({
    String? id,
    DateTime? purchaseDate,
    String? vendorId,
    String? vendorName,
    String? itemId,
    String? itemName,
    double? quantity,
    double? unitPrice,
    double? totalAmount,
    String? invoiceNumber,
    PaymentDetailsModel? paymentDetails,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseModel(
      id: id ?? this.id,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalAmount: totalAmount ?? this.totalAmount,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      paymentDetails: paymentDetails ?? this.paymentDetails,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
