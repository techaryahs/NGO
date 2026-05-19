import 'payment_details_model.dart';

/// Model representing an employee salary payment entry.
class SalaryModel {
  final String id;
  final String employeeName;
  final String role;
  final String salaryMonth;
  final double grossSalary;
  final double deductions;
  final double netSalary;
  final PaymentDetailsModel paymentDetails;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  SalaryModel({
    required this.id,
    required this.employeeName,
    required this.role,
    required this.salaryMonth,
    required this.grossSalary,
    required this.deductions,
    required this.netSalary,
    required this.paymentDetails,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeName': employeeName,
      'role': role,
      'salaryMonth': salaryMonth,
      'grossSalary': grossSalary,
      'deductions': deductions,
      'netSalary': netSalary,
      'paymentDetails': paymentDetails.toMap(),
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SalaryModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return SalaryModel(
      id: id,
      employeeName: data['employeeName']?.toString() ?? '',
      role: data['role']?.toString() ?? '',
      salaryMonth: data['salaryMonth']?.toString() ?? '',
      grossSalary: _parseDouble(data['grossSalary']),
      deductions: _parseDouble(data['deductions']),
      netSalary: _parseDouble(data['netSalary']),
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

  SalaryModel copyWith({
    String? id,
    String? employeeName,
    String? role,
    String? salaryMonth,
    double? grossSalary,
    double? deductions,
    double? netSalary,
    PaymentDetailsModel? paymentDetails,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SalaryModel(
      id: id ?? this.id,
      employeeName: employeeName ?? this.employeeName,
      role: role ?? this.role,
      salaryMonth: salaryMonth ?? this.salaryMonth,
      grossSalary: grossSalary ?? this.grossSalary,
      deductions: deductions ?? this.deductions,
      netSalary: netSalary ?? this.netSalary,
      paymentDetails: paymentDetails ?? this.paymentDetails,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
