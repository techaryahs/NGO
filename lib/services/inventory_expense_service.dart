import 'dart:async';
import 'backend_api_service.dart';
import 'firebase_rtdb_rest_service.dart';
import '../models/inventory_item_model.dart';
import '../models/vendor_model.dart';
import '../models/purchase_model.dart';
import '../models/expense_entry_model.dart';
import '../models/salary_model.dart';

/// Database Service layer for NGO Inventory and Expenses.
class InventoryExpenseService {
  final FirebaseRTDBRestService? _rtdb;
  final BackendApiService? _backendApi;

  InventoryExpenseService({
    FirebaseRTDBRestService? rtdbService,
    BackendApiService? backendApiService,
  })  : assert(
          rtdbService != null || backendApiService != null,
          'Provide either rtdbService or backendApiService',
        ),
        _rtdb = rtdbService,
        _backendApi = backendApiService;

  bool get isPostgres => _backendApi != null;

  Stream<dynamic> _streamPath(String path) =>
      _backendApi != null ? _backendApi.stream(path) : _rtdb!.stream(path);

  Future<dynamic> _getPath(String path) =>
      _backendApi != null ? _backendApi.get(path) : _rtdb!.get(path);

  Future<String> _pushPath(String path, Map<String, dynamic> data) async {
    final cleanData = Map<String, dynamic>.from(data);
    if (cleanData['id'] != null &&
        (cleanData['id'].toString().trim().isEmpty ||
            cleanData['id'].toString().startsWith('temp_'))) {
      cleanData.remove('id');
    }
    if (_backendApi != null) {
      return _backendApi.push(path, cleanData);
    }
    final id = await _rtdb!.push(path, cleanData);
    await _rtdb.patch('$path/$id', {'id': id});
    return id;
  }

  Future<void> _putPath(String path, Map<String, dynamic> data) =>
      _backendApi != null ? _backendApi.put(path, data) : _rtdb!.put(path, data);

  Future<void> _patchPath(String path, Map<String, dynamic> updates) =>
      _backendApi != null
          ? _backendApi.patch(path, updates)
          : _rtdb!.patch(path, updates);

  Future<void> _deletePath(String path) =>
      _backendApi != null ? _backendApi.delete(path) : _rtdb!.delete(path);

  // ===========================================================================
  // INVENTORY ITEMS
  // ===========================================================================

  /// Stream of all inventory items, sorted alphabetically by name.
  Stream<List<InventoryItemModel>> getInventoryItemsStream() {
    return _streamPath('inventory_items').map((data) {
      final List<InventoryItemModel> items = [];
      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        mapData.forEach((key, value) {
          if (value is Map) {
            items.add(InventoryItemModel.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
        items.sort((a, b) => a.name.compareTo(b.name));
      }
      return items;
    }).asBroadcastStream();
  }

  /// Create a new inventory item.
  Future<String> addInventoryItem({
    required String name,
    required String category,
    required String unit,
    required double minStockLevel,
    required double currentStock,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final tempId = 'temp_${now.millisecondsSinceEpoch}';
    final item = InventoryItemModel(
      id: tempId,
      name: name,
      category: category,
      unit: unit,
      minStockLevel: minStockLevel,
      currentStock: currentStock,
      createdBy: createdBy,
      updatedBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );

    return _pushPath('inventory_items', item.toMap());
  }

  /// Partially update inventory item fields.
  Future<void> updateInventoryItem(String itemId, Map<String, dynamic> updates) async {
    updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _patchPath('inventory_items/$itemId', updates);
  }

  /// Permanently delete an inventory item.
  Future<void> deleteInventoryItem(String itemId) async {
    await _deletePath('inventory_items/$itemId');
  }

  // ===========================================================================
  // VENDORS
  // ===========================================================================

  /// Stream of all vendors, sorted alphabetically by name.
  Stream<List<VendorModel>> getVendorsStream() {
    return _streamPath('vendors').map((data) {
      final List<VendorModel> vendors = [];
      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        mapData.forEach((key, value) {
          if (value is Map) {
            vendors.add(VendorModel.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
        vendors.sort((a, b) => a.name.compareTo(b.name));
      }
      return vendors;
    }).asBroadcastStream();
  }

  /// Create a new vendor.
  Future<String> addVendor({
    required String name,
    required String contactPerson,
    required String mobileNumber,
    required String email,
    required String gstNumber,
    required String address,
    required String notes,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final tempId = 'temp_${now.millisecondsSinceEpoch}';
    final vendor = VendorModel(
      id: tempId,
      name: name,
      contactPerson: contactPerson,
      mobileNumber: mobileNumber,
      email: email,
      gstNumber: gstNumber,
      address: address,
      notes: notes,
      createdBy: createdBy,
      updatedBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );

    final map = vendor.toMap();
    map['phone'] = mobileNumber;
    return _pushPath('vendors', map);
  }

  /// Partially update vendor fields.
  Future<void> updateVendor(String vendorId, Map<String, dynamic> updates) async {
    updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    if (updates.containsKey('mobileNumber') && !updates.containsKey('phone')) {
      updates['phone'] = updates['mobileNumber'];
    }
    await _patchPath('vendors/$vendorId', updates);
  }

  /// Permanently delete a vendor.
  Future<void> deleteVendor(String vendorId) async {
    await _deletePath('vendors/$vendorId');
  }

  // ===========================================================================
  // PURCHASES
  // ===========================================================================

  /// Stream of all purchases, sorted newest first.
  Stream<List<PurchaseModel>> getPurchasesStream() {
    return _streamPath('purchases').map((data) {
      final List<PurchaseModel> purchases = [];
      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        mapData.forEach((key, value) {
          if (value is Map) {
            purchases.add(PurchaseModel.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
        purchases.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      }
      return purchases;
    }).asBroadcastStream();
  }

  /// Record a purchase of inventory items. Automatically increments corresponding item stock!
  Future<String> addPurchase(PurchaseModel purchase) async {
    final purchaseId = await _pushPath('purchases', purchase.toMap());
    if (isPostgres) return purchaseId;

    // Auto stock increment logic
    try {
      final itemData = await _getPath('inventory_items/${purchase.itemId}');
      if (itemData != null && itemData is Map) {
        final item = InventoryItemModel.fromMap(purchase.itemId, Map<String, dynamic>.from(itemData));
        final updatedStock = item.currentStock + purchase.quantity;
        await _patchPath('inventory_items/${purchase.itemId}', {'currentStock': updatedStock});
      }
    } catch (_) {}

    return purchaseId;
  }

  /// Update an existing purchase. Adjusts inventory item stock accordingly!
  Future<void> updatePurchase(String purchaseId, PurchaseModel purchase, {double oldQuantity = 0.0}) async {
    await _putPath('purchases/$purchaseId', purchase.toMap());
    if (isPostgres) return;

    // Auto stock adjust logic
    try {
      final itemData = await _getPath('inventory_items/${purchase.itemId}');
      if (itemData != null && itemData is Map) {
        final item = InventoryItemModel.fromMap(purchase.itemId, Map<String, dynamic>.from(itemData));
        final stockDiff = purchase.quantity - oldQuantity;
        final updatedStock = item.currentStock + stockDiff;
        await _patchPath('inventory_items/${purchase.itemId}', {'currentStock': updatedStock});
      }
    } catch (_) {}
  }

  /// Delete a purchase record. Automatically adjusts corresponding item stock down!
  Future<void> deletePurchase(String purchaseId, String itemId, double quantity) async {
    await _deletePath('purchases/$purchaseId');
    if (isPostgres) return;

    // Auto stock decrement logic
    try {
      final itemData = await _getPath('inventory_items/$itemId');
      if (itemData != null && itemData is Map) {
        final item = InventoryItemModel.fromMap(itemId, Map<String, dynamic>.from(itemData));
        final updatedStock = (item.currentStock - quantity).clamp(0.0, double.infinity);
        await _patchPath('inventory_items/$itemId', {'currentStock': updatedStock});
      }
    } catch (_) {}
  }

  // ===========================================================================
  // EXPENSE ENTRIES
  // ===========================================================================

  /// Stream of all operational expenses, sorted newest first.
  Stream<List<ExpenseEntryModel>> getExpenseEntriesStream() {
    return _streamPath('expense_entries').map((data) {
      final List<ExpenseEntryModel> entries = [];
      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        mapData.forEach((key, value) {
          if (value is Map) {
            entries.add(ExpenseEntryModel.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
        entries.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
      }
      return entries;
    }).asBroadcastStream();
  }

  /// Add a general operational expense record.
  Future<String> addExpenseEntry(ExpenseEntryModel entry) async {
    final map = entry.toMap();
    map['amount'] = entry.totalAmount;
    map['paymentMethod'] = entry.paymentDetails.paymentMethod;
    map['paidTo'] = entry.vendorName ?? '';
    return _pushPath('expense_entries', map);
  }

  /// Update an operational expense record.
  Future<void> updateExpenseEntry(String entryId, ExpenseEntryModel entry) async {
    final map = entry.toMap();
    map['amount'] = entry.totalAmount;
    map['paymentMethod'] = entry.paymentDetails.paymentMethod;
    map['paidTo'] = entry.vendorName ?? '';
    await _putPath('expense_entries/$entryId', map);
  }

  /// Delete an operational expense record.
  Future<void> deleteExpenseEntry(String entryId) async {
    await _deletePath('expense_entries/$entryId');
  }

  // ===========================================================================
  // SALARIES
  // ===========================================================================

  /// Stream of all salary payment records, sorted newest first.
  Stream<List<SalaryModel>> getSalariesStream() {
    return _streamPath('salaries').map((data) {
      final List<SalaryModel> salaries = [];
      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        mapData.forEach((key, value) {
          if (value is Map) {
            salaries.add(SalaryModel.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
        salaries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      return salaries;
    }).asBroadcastStream();
  }

  /// Record a salary payment.
  Future<String> addSalary(SalaryModel salary) async {
    return _pushPath('salaries', salary.toMap());
  }

  /// Update a salary record.
  Future<void> updateSalary(String salaryId, SalaryModel salary) async {
    await _putPath('salaries/$salaryId', salary.toMap());
  }

  /// Delete a salary record.
  Future<void> deleteSalary(String salaryId) async {
    await _deletePath('salaries/$salaryId');
  }
}
