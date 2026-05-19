/// Model representing payment details associated with inventory and expenses.
class PaymentDetailsModel {
  final String paymentMethod; // Cash, Cheque, UPI, NEFT / RTGS / IMPS, Bank Transfer, Credit Card, Debit Card, Other
  final String paymentStatus; // Paid, Pending, Partial
  final DateTime? paymentDate;
  final String? paymentReferenceNumber;
  final String? bankName;
  final String? transactionId; // UTR Number / Transaction ID
  final String? cashVoucherNumber;
  final String? receivedBy;
  final String? chequeNumber;
  final DateTime? chequeDate;
  final String? chequeClearanceStatus; // Clearance Status
  final String? proofUrl;

  PaymentDetailsModel({
    required this.paymentMethod,
    required this.paymentStatus,
    this.paymentDate,
    this.paymentReferenceNumber,
    this.bankName,
    this.transactionId,
    this.cashVoucherNumber,
    this.receivedBy,
    this.chequeNumber,
    this.chequeDate,
    this.chequeClearanceStatus,
    this.proofUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'paymentDate': paymentDate?.millisecondsSinceEpoch,
      'paymentReferenceNumber': paymentReferenceNumber,
      'bankName': bankName,
      'transactionId': transactionId,
      'cashVoucherNumber': cashVoucherNumber,
      'receivedBy': receivedBy,
      'chequeNumber': chequeNumber,
      'chequeDate': chequeDate?.millisecondsSinceEpoch,
      'chequeClearanceStatus': chequeClearanceStatus,
      'proofUrl': proofUrl,
    };
  }

  factory PaymentDetailsModel.fromMap(Map<dynamic, dynamic> data) {
    return PaymentDetailsModel(
      paymentMethod: data['paymentMethod']?.toString() ?? 'Cash',
      paymentStatus: data['paymentStatus']?.toString() ?? 'Pending',
      paymentDate: data['paymentDate'] != null ? _parseDateTime(data['paymentDate']) : null,
      paymentReferenceNumber: data['paymentReferenceNumber']?.toString(),
      bankName: data['bankName']?.toString(),
      transactionId: data['transactionId']?.toString(),
      cashVoucherNumber: data['cashVoucherNumber']?.toString(),
      receivedBy: data['receivedBy']?.toString(),
      chequeNumber: data['chequeNumber']?.toString(),
      chequeDate: data['chequeDate'] != null ? _parseDateTime(data['chequeDate']) : null,
      chequeClearanceStatus: data['chequeClearanceStatus']?.toString(),
      proofUrl: data['proofUrl']?.toString(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final parsed = int.tryParse(value.toString());
    if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
    return null;
  }
}
