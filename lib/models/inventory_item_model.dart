/// Model representing an inventory item.
class InventoryItemModel {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double minStockLevel;
  final double currentStock;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventoryItemModel({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.minStockLevel,
    required this.currentStock,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isLowStock => currentStock <= minStockLevel;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'unit': unit,
      'minStockLevel': minStockLevel,
      'currentStock': currentStock,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory InventoryItemModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return InventoryItemModel(
      id: id,
      name: data['name']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      unit: data['unit']?.toString() ?? 'piece',
      minStockLevel: _parseDouble(data['minStockLevel']),
      currentStock: _parseDouble(data['currentStock']),
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

  InventoryItemModel copyWith({
    String? id,
    String? name,
    String? category,
    String? unit,
    double? minStockLevel,
    double? currentStock,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      currentStock: currentStock ?? this.currentStock,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
