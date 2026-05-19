import 'dart:async';
import 'firebase_rtdb_rest_service.dart';
import '../models/inventory_item_model.dart';
import '../models/vendor_model.dart';
import '../models/purchase_model.dart';
import '../models/expense_entry_model.dart';
import '../models/salary_model.dart';

/// Database Service layer for NGO Inventory and Expenses.
class InventoryExpenseService {
  final FirebaseRTDBRestService _rtdb;

  InventoryExpenseService({required FirebaseRTDBRestService rtdbService})
      : _rtdb = rtdbService;

  // ===========================================================================
  // INVENTORY ITEMS
  // ===========================================================================

  /// Stream of all inventory items, sorted alphabetically by name.
  Stream<List<InventoryItemModel>> getInventoryItemsStream() {
    return _rtdb.stream('inventory_items').map((data) {
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

    final itemId = await _rtdb.push('inventory_items', item.toMap());
    await _rtdb.patch('inventory_items/$itemId', {'id': itemId});
    return itemId;
  }

  /// Partially update inventory item fields.
  Future<void> updateInventoryItem(String itemId, Map<String, dynamic> updates) async {
    updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _rtdb.patch('inventory_items/$itemId', updates);
  }

  /// Permanently delete an inventory item.
  Future<void> deleteInventoryItem(String itemId) async {
    await _rtdb.delete('inventory_items/$itemId');
  }

  // ===========================================================================
  // VENDORS
  // ===========================================================================

  /// Stream of all vendors, sorted alphabetically by name.
  Stream<List<VendorModel>> getVendorsStream() {
    return _rtdb.stream('vendors').map((data) {
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

    final vendorId = await _rtdb.push('vendors', vendor.toMap());
    await _rtdb.patch('vendors/$vendorId', {'id': vendorId});
    return vendorId;
  }

  /// Partially update vendor fields.
  Future<void> updateVendor(String vendorId, Map<String, dynamic> updates) async {
    updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _rtdb.patch('vendors/$vendorId', updates);
  }

  /// Permanently delete a vendor.
  Future<void> deleteVendor(String vendorId) async {
    await _rtdb.delete('vendors/$vendorId');
  }

  // ===========================================================================
  // PURCHASES
  // ===========================================================================

  /// Stream of all purchases, sorted newest first.
  Stream<List<PurchaseModel>> getPurchasesStream() {
    return _rtdb.stream('purchases').map((data) {
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
    final purchaseId = await _rtdb.push('purchases', purchase.toMap());
    await _rtdb.patch('purchases/$purchaseId', {'id': purchaseId});

    // Auto stock increment logic
    try {
      final itemData = await _rtdb.get('inventory_items/${purchase.itemId}');
      if (itemData != null && itemData is Map) {
        final item = InventoryItemModel.fromMap(purchase.itemId, Map<String, dynamic>.from(itemData));
        final updatedStock = item.currentStock + purchase.quantity;
        await _rtdb.patch('inventory_items/${purchase.itemId}', {'currentStock': updatedStock});
      }
    } catch (_) {}

    return purchaseId;
  }

  /// Update an existing purchase. Adjusts inventory item stock accordingly!
  Future<void> updatePurchase(String purchaseId, PurchaseModel purchase, {double oldQuantity = 0.0}) async {
    await _rtdb.put('purchases/$purchaseId', purchase.toMap());

    // Auto stock adjust logic
    try {
      final itemData = await _rtdb.get('inventory_items/${purchase.itemId}');
      if (itemData != null && itemData is Map) {
        final item = InventoryItemModel.fromMap(purchase.itemId, Map<String, dynamic>.from(itemData));
        final stockDiff = purchase.quantity - oldQuantity;
        final updatedStock = item.currentStock + stockDiff;
        await _rtdb.patch('inventory_items/${purchase.itemId}', {'currentStock': updatedStock});
      }
    } catch (_) {}
  }

  /// Delete a purchase record. Automatically adjusts corresponding item stock down!
  Future<void> deletePurchase(String purchaseId, String itemId, double quantity) async {
    await _rtdb.delete('purchases/$purchaseId');

    // Auto stock decrement logic
    try {
      final itemData = await _rtdb.get('inventory_items/$itemId');
      if (itemData != null && itemData is Map) {
        final item = InventoryItemModel.fromMap(itemId, Map<String, dynamic>.from(itemData));
        final updatedStock = (item.currentStock - quantity).clamp(0.0, double.infinity);
        await _rtdb.patch('inventory_items/$itemId', {'currentStock': updatedStock});
      }
    } catch (_) {}
  }

  // ===========================================================================
  // EXPENSE ENTRIES
  // ===========================================================================

  /// Stream of all operational expenses, sorted newest first.
  Stream<List<ExpenseEntryModel>> getExpenseEntriesStream() {
    return _rtdb.stream('expense_entries').map((data) {
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
    final entryId = await _rtdb.push('expense_entries', entry.toMap());
    await _rtdb.patch('expense_entries/$entryId', {'id': entryId});
    return entryId;
  }

  /// Update an operational expense record.
  Future<void> updateExpenseEntry(String entryId, ExpenseEntryModel entry) async {
    await _rtdb.put('expense_entries/$entryId', entry.toMap());
  }

  /// Delete an operational expense record.
  Future<void> deleteExpenseEntry(String entryId) async {
    await _rtdb.delete('expense_entries/$entryId');
  }

  // ===========================================================================
  // SALARIES
  // ===========================================================================

  /// Stream of all salary payment records, sorted newest first.
  Stream<List<SalaryModel>> getSalariesStream() {
    return _rtdb.stream('salaries').map((data) {
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
    final salaryId = await _rtdb.push('salaries', salary.toMap());
    await _rtdb.patch('salaries/$salaryId', {'id': salaryId});
    return salaryId;
  }

  /// Update a salary record.
  Future<void> updateSalary(String salaryId, SalaryModel salary) async {
    await _rtdb.put('salaries/$salaryId', salary.toMap());
  }

  /// Delete a salary record.
  Future<void> deleteSalary(String salaryId) async {
    await _rtdb.delete('salaries/$salaryId');
  }
}
