import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/inventory_item_model.dart';

/// Sub-tab to view, filter, and CRUD warehouse inventory items
class InventoryItemsTab extends StatefulWidget {
  const InventoryItemsTab({super.key});

  @override
  State<InventoryItemsTab> createState() => _InventoryItemsTabState();
}

class _InventoryItemsTabState extends State<InventoryItemsTab> {
  final _service = ServiceLocator().inventoryExpenseService;
  final _searchController = TextEditingController();

  List<InventoryItemModel> _items = [];
  StreamSubscription? _subscription;
  bool _loading = true;

  // Filters and sorting
  String _searchQuery = "";
  String _selectedCategory = "All";
  bool _showOnlyLowStock = false;
  String _sortBy = "Name"; // Name, Stock (Asc), Stock (Desc)

  final List<String> _categories = [
    "All", "Fruits", "Vegetables", "Groceries", "Drinking Water",
    "Water Tanker", "Laundry", "Canteen", "Housekeeping", "Cleaning Material", "Maintenance"
  ];

  @override
  void initState() {
    super.initState();
    _subscription = _service.getInventoryItemsStream().listen((data) {
      if (mounted) {
        setState(() {
          _items = data;
          _loading = false;
        });
      }
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11)));
    }

    // Apply filters
    var filteredItems = _items.where((item) {
      final matchesSearch = item.name.toLowerCase().contains(_searchQuery) ||
                            item.category.toLowerCase().contains(_searchQuery);
      final matchesCategory = _selectedCategory == "All" || item.category == _selectedCategory;
      final matchesLowStock = !_showOnlyLowStock || item.isLowStock;
      return matchesSearch && matchesCategory && matchesLowStock;
    }).toList();

    // Apply sorting
    if (_sortBy == "Name") {
      filteredItems.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortBy == "Stock (Asc)") {
      filteredItems.sort((a, b) => a.currentStock.compareTo(b.currentStock));
    } else if (_sortBy == "Stock (Desc)") {
      filteredItems.sort((a, b) => b.currentStock.compareTo(a.currentStock));
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter and Actions Bar
          _buildFilterBar(context),
          const SizedBox(height: 15),
          // Items Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFDF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: filteredItems.isEmpty
                    ? const Center(child: Text("No inventory items found", style: TextStyle(color: Color(0xFF639922))))
                    : ListView(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F9F0)),
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 48,
                              columns: const [
                                DataColumn(label: Text("Item Name", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Category", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Unit", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Min Stock Level", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Current Stock", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                                DataColumn(label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              ],
                              rows: filteredItems.map((item) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    DataCell(Text(item.category)),
                                    DataCell(Text(item.unit)),
                                    DataCell(Text("${item.minStockLevel} ${item.unit}")),
                                    DataCell(Text(
                                      "${item.currentStock} ${item.unit}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: item.isLowStock ? const Color(0xFFC62828) : const Color(0xFF27500A),
                                      ),
                                    )),
                                    DataCell(_buildStatusBadge(item)),
                                    DataCell(_buildActionButtons(item)),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFDF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Row(
        children: [
          // Search box
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search item name...",
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF639922), size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                fillColor: const Color(0xFFF4F9F0),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3B6D11), width: 1.0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          
          // Category dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: "Category",
                labelStyle: TextStyle(color: Color(0xFF3B6D11), fontSize: 12),
                contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              ),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
          ),
          const SizedBox(width: 15),

          // Sorting dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _sortBy,
              decoration: const InputDecoration(
                labelText: "Sort By",
                labelStyle: TextStyle(color: Color(0xFF3B6D11), fontSize: 12),
                contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              ),
              items: const [
                DropdownMenuItem(value: "Name", child: Text("Name")),
                DropdownMenuItem(value: "Stock (Asc)", child: Text("Stock (Low to High)")),
                DropdownMenuItem(value: "Stock (Desc)", child: Text("Stock (High to Low)")),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _sortBy = val);
              },
            ),
          ),
          const SizedBox(width: 15),

          // Low Stock Toggle
          Row(
            children: [
              const Text("Low Stock Only", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF27500A))),
              Switch(
                value: _showOnlyLowStock,
                activeColor: const Color(0xFF3B6D11),
                activeTrackColor: const Color(0xFFD4EABD),
                onChanged: (val) => setState(() => _showOnlyLowStock = val),
              ),
            ],
          ),
          const Spacer(),

          // Add Button
          ElevatedButton.icon(
            onPressed: () => _showFormDialog(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("Add Item"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B6D11),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(InventoryItemModel item) {
    if (item.isLowStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFFB300), width: 0.5),
        ),
        child: const Text(
          "Low Stock",
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF57F17)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF81C784), width: 0.5),
      ),
      child: const Text(
        "Optimal",
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
      ),
    );
  }

  Widget _buildActionButtons(InventoryItemModel item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: Color(0xFF639922), size: 18),
          tooltip: "Edit Item",
          onPressed: () => _showFormDialog(context, item: item),
        ),
        IconButton(
          icon: const Icon(Icons.delete_rounded, color: Color(0xFFC62828), size: 18),
          tooltip: "Delete Item",
          onPressed: () => _confirmDelete(item),
        ),
      ],
    );
  }

  void _confirmDelete(InventoryItemModel item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Inventory Item"),
        content: Text("Are you sure you want to permanently delete '${item.name}'? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.deleteInventoryItem(item.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Item successfully deleted'), backgroundColor: Color(0xFF3B6D11)),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC62828), foregroundColor: Colors.white),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showFormDialog(BuildContext context, {InventoryItemModel? item}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: item?.name ?? "");
    final minCtrl = TextEditingController(text: item?.minStockLevel.toString() ?? "");
    final currentCtrl = TextEditingController(text: item?.currentStock.toString() ?? "");

    String selectedCategory = item?.category ?? _categories.where((c) => c != "All").first;
    String selectedUnit = item?.unit ?? "piece";

    final List<String> units = ["piece", "kg", "liter", "packet", "month", "other"];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? "Add Inventory Item" : "Edit Inventory Item"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Item Name"),
                validator: (val) => val == null || val.isEmpty ? "Enter a valid name" : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(labelText: "Category"),
                items: _categories
                    .where((c) => c != "All")
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) selectedCategory = val;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: minCtrl,
                      decoration: const InputDecoration(labelText: "Min Stock"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) => val == null || double.tryParse(val) == null ? "Enter a number" : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: currentCtrl,
                      decoration: const InputDecoration(labelText: "Current Stock"),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) => val == null || double.tryParse(val) == null ? "Enter a number" : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      decoration: const InputDecoration(labelText: "Unit"),
                      items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                      onChanged: (val) {
                        if (val != null) selectedUnit = val;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final double minVal = double.parse(minCtrl.text.trim());
                final double curVal = double.parse(currentCtrl.text.trim());

                if (item == null) {
                  await _service.addInventoryItem(
                    name: nameCtrl.text.trim(),
                    category: selectedCategory,
                    unit: selectedUnit,
                    minStockLevel: minVal,
                    currentStock: curVal,
                    createdBy: "Admin",
                  );
                } else {
                  await _service.updateInventoryItem(item.id, {
                    'name': nameCtrl.text.trim(),
                    'category': selectedCategory,
                    'unit': selectedUnit,
                    'minStockLevel': minVal,
                    'currentStock': curVal,
                    'updatedBy': "Admin",
                  });
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(item == null ? 'Item successfully added' : 'Item successfully updated'),
                      backgroundColor: const Color(0xFF3B6D11),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
