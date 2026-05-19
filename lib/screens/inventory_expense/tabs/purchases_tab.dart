import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/purchase_model.dart';
import '../../../models/inventory_item_model.dart';
import '../../../models/vendor_model.dart';
import '../../../models/payment_details_model.dart';

/// Sub-tab to record and review inventory purchases with automated stock updating
class PurchasesTab extends StatefulWidget {
  const PurchasesTab({super.key});

  @override
  State<PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends State<PurchasesTab> {
  final _service = ServiceLocator().inventoryExpenseService;
  final _searchController = TextEditingController();

  List<PurchaseModel> _purchases = [];
  List<InventoryItemModel> _items = [];
  List<VendorModel> _vendors = [];

  StreamSubscription? _purchasesSub;
  StreamSubscription? _itemsSub;
  StreamSubscription? _vendorsSub;

  bool _loading = true;
  String _searchQuery = "";
  String _statusFilter = "All";

  @override
  void initState() {
    super.initState();
    _subscribeAll();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  void _subscribeAll() {
    _purchasesSub = _service.getPurchasesStream().listen((data) {
      if (mounted) setState(() { _purchases = data; _checkLoading(); });
    });
    _itemsSub = _service.getInventoryItemsStream().listen((data) {
      if (mounted) setState(() { _items = data; _checkLoading(); });
    });
    _vendorsSub = _service.getVendorsStream().listen((data) {
      if (mounted) setState(() { _vendors = data; _checkLoading(); });
    });
  }

  void _checkLoading() {
    if (_purchasesSub != null && _itemsSub != null && _vendorsSub != null) {
      setState(() { _loading = false; });
    }
  }

  @override
  void dispose() {
    _purchasesSub?.cancel();
    _itemsSub?.cancel();
    _vendorsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11)));
    }

    final filteredPurchases = _purchases.where((p) {
      final matchesSearch = p.invoiceNumber.toLowerCase().contains(_searchQuery) ||
                            p.itemName.toLowerCase().contains(_searchQuery) ||
                            p.vendorName.toLowerCase().contains(_searchQuery);
      final matchesStatus = _statusFilter == "All" || p.paymentDetails.paymentStatus == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter Bar
          _buildFilterBar(context),
          const SizedBox(height: 15),
          
          // Purchases Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFDF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: filteredPurchases.isEmpty
                    ? const Center(child: Text("No stock purchases recorded", style: TextStyle(color: Color(0xFF639922))))
                    : ListView(
                        children: [
                          DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F9F0)),
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 48,
                            columns: const [
                              DataColumn(label: Text("Date", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              DataColumn(label: Text("Invoice No", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              DataColumn(label: Text("Vendor", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              DataColumn(label: Text("Item", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              DataColumn(label: Text("Qty", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              DataColumn(label: Text("Total Amount", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              DataColumn(label: Text("Payment Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                              DataColumn(label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A)))),
                            ],
                            rows: filteredPurchases.map((purchase) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(_formatDate(purchase.purchaseDate))),
                                  DataCell(Text(purchase.invoiceNumber.isNotEmpty ? purchase.invoiceNumber : "N/A")),
                                  DataCell(Text(purchase.vendorName)),
                                  DataCell(Text(purchase.itemName)),
                                  DataCell(Text("${purchase.quantity}")),
                                  DataCell(Text("₹${purchase.totalAmount.toStringAsFixed(2)}")),
                                  DataCell(_buildStatusBadge(purchase.paymentDetails.paymentStatus)),
                                  DataCell(_buildActionButtons(purchase)),
                                ],
                              );
                            }).toList(),
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
                hintText: "Search invoice, item, or vendor...",
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
          
          // Status filter dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              decoration: const InputDecoration(
                labelText: "Payment Status",
                labelStyle: TextStyle(color: Color(0xFF3B6D11), fontSize: 12),
                contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              ),
              items: const [
                DropdownMenuItem(value: "All", child: Text("All Statuses")),
                DropdownMenuItem(value: "Paid", child: Text("Paid")),
                DropdownMenuItem(value: "Pending", child: Text("Pending")),
                DropdownMenuItem(value: "Partial", child: Text("Partial")),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _statusFilter = val);
              },
            ),
          ),
          const Spacer(),

          // Add Button
          ElevatedButton.icon(
            onPressed: () => _showFormDialog(context),
            icon: const Icon(Icons.shopping_cart_rounded, size: 18),
            label: const Text("Record Purchase"),
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

  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFFFF8E1);
    Color fg = const Color(0xFFF57F17);
    Color border = const Color(0xFFFFB300);

    if (status == 'Paid') {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      border = const Color(0xFF81C784);
    } else if (status == 'Pending') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      border = const Color(0xFFE57373);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildActionButtons(PurchaseModel purchase) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.visibility_outlined, color: Color(0xFF3B6D11), size: 18),
          tooltip: "View Details",
          onPressed: () => _viewPurchaseDetails(purchase),
        ),
        IconButton(
          icon: const Icon(Icons.edit_rounded, color: Color(0xFF639922), size: 18),
          tooltip: "Edit Record",
          onPressed: () => _showFormDialog(context, purchase: purchase),
        ),
        IconButton(
          icon: const Icon(Icons.delete_rounded, color: Color(0xFFC62828), size: 18),
          tooltip: "Delete Record",
          onPressed: () => _confirmDelete(purchase),
        ),
      ],
    );
  }

  void _confirmDelete(PurchaseModel purchase) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Purchase Record"),
        content: Text(
          "Are you sure you want to delete this purchase for '${purchase.itemName}'?\n\n"
          "WARNING: The inventory current stock for '${purchase.itemName}' will be automatically decremented by ${purchase.quantity}!"
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.deletePurchase(purchase.id, purchase.itemId, purchase.quantity);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Purchase record successfully deleted. Stock updated.'), backgroundColor: Color(0xFF3B6D11)),
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

  void _viewPurchaseDetails(PurchaseModel purchase) {
    final pd = purchase.paymentDetails;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2_rounded, color: Color(0xFF3B6D11)),
            SizedBox(width: 10),
            Text("Purchase & Invoice Details"),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow("Invoice Number", purchase.invoiceNumber.isNotEmpty ? purchase.invoiceNumber : "N/A"),
                _buildDetailRow("Purchase Date", _formatDate(purchase.purchaseDate)),
                _buildDetailRow("Supplier Vendor", purchase.vendorName),
                _buildDetailRow("Inventory Item", purchase.itemName),
                _buildDetailRow("Quantity", "${purchase.quantity}"),
                _buildDetailRow("Unit Price", "₹${purchase.unitPrice.toStringAsFixed(2)}"),
                _buildDetailRow("Total Paid Amount", "₹${purchase.totalAmount.toStringAsFixed(2)}"),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFFC0DD97)),
                ),
                const Text("Payment Information", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A), fontSize: 13.5)),
                const SizedBox(height: 8),
                
                _buildDetailRow("Payment Method", pd.paymentMethod),
                _buildDetailRow("Payment Status", pd.paymentStatus),
                if (pd.paymentDate != null) _buildDetailRow("Payment Date", _formatDate(pd.paymentDate!)),
                if (pd.bankName != null && pd.bankName!.isNotEmpty) _buildDetailRow("Bank Name", pd.bankName!),
                if (pd.transactionId != null && pd.transactionId!.isNotEmpty) _buildDetailRow("UTR / Transaction ID", pd.transactionId!),
                if (pd.cashVoucherNumber != null && pd.cashVoucherNumber!.isNotEmpty) _buildDetailRow("Cash Voucher No", pd.cashVoucherNumber!),
                if (pd.receivedBy != null && pd.receivedBy!.isNotEmpty) _buildDetailRow("Cash Received By", pd.receivedBy!),
                if (pd.chequeNumber != null && pd.chequeNumber!.isNotEmpty) _buildDetailRow("Cheque Number", pd.chequeNumber!),
                if (pd.chequeDate != null) _buildDetailRow("Cheque Date", _formatDate(pd.chequeDate!)),
                if (pd.chequeClearanceStatus != null && pd.chequeClearanceStatus!.isNotEmpty) _buildDetailRow("Clearance Status", pd.chequeClearanceStatus!),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B6D11), foregroundColor: Colors.white),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF639922), fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  void _showFormDialog(BuildContext context, {PurchaseModel? purchase}) {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one Inventory Item first!'), backgroundColor: Color(0xFFC62828)),
      );
      return;
    }
    if (_vendors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please register at least one Supplier Vendor first!'), backgroundColor: Color(0xFFC62828)),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final invoiceCtrl = TextEditingController(text: purchase?.invoiceNumber ?? "");
    final qtyCtrl = TextEditingController(text: purchase?.quantity.toString() ?? "");
    final priceCtrl = TextEditingController(text: purchase?.unitPrice.toString() ?? "");
    final totalCtrl = TextEditingController(text: purchase?.totalAmount.toString() ?? "0.0");

    // Payment fields
    final bankCtrl = TextEditingController(text: purchase?.paymentDetails.bankName ?? "");
    final transactionCtrl = TextEditingController(text: purchase?.paymentDetails.transactionId ?? "");
    final voucherCtrl = TextEditingController(text: purchase?.paymentDetails.cashVoucherNumber ?? "");
    final receivedByCtrl = TextEditingController(text: purchase?.paymentDetails.receivedBy ?? "");
    final chequeNumCtrl = TextEditingController(text: purchase?.paymentDetails.chequeNumber ?? "");

    DateTime purchaseDate = purchase?.purchaseDate ?? DateTime.now();
    DateTime? chequeDate = purchase?.paymentDetails.chequeDate;

    InventoryItemModel selectedItem = _items.firstWhere(
      (item) => item.id == purchase?.itemId,
      orElse: () => _items.first,
    );
    VendorModel selectedVendor = _vendors.firstWhere(
      (v) => v.id == purchase?.vendorId,
      orElse: () => _vendors.first,
    );

    String paymentMethod = purchase?.paymentDetails.paymentMethod ?? "Cash";
    String paymentStatus = purchase?.paymentDetails.paymentStatus ?? "Paid";
    String chequeStatus = purchase?.paymentDetails.chequeClearanceStatus ?? "Pending";

    void recalculateTotal() {
      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
      final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
      totalCtrl.text = (qty * price).toStringAsFixed(2);
    }

    qtyCtrl.addListener(recalculateTotal);
    priceCtrl.addListener(recalculateTotal);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(purchase == null ? "Record Stock Purchase" : "Edit Purchase Record"),
              content: SizedBox(
                width: 580,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic Purchase details
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: invoiceCtrl,
                                decoration: const InputDecoration(labelText: "Invoice/Bill Number"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final selected = await showDatePicker(
                                    context: context,
                                    initialDate: purchaseDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (selected != null) {
                                    setDialogState(() => purchaseDate = selected);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(labelText: "Purchase Date"),
                                  child: Text(_formatDate(purchaseDate)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<InventoryItemModel>(
                                value: selectedItem,
                                decoration: const InputDecoration(labelText: "Select Item"),
                                items: _items.map((item) {
                                  return DropdownMenuItem(value: item, child: Text("${item.name} (${item.category})"));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedItem = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<VendorModel>(
                                value: selectedVendor,
                                decoration: const InputDecoration(labelText: "Select Vendor"),
                                items: _vendors.map((v) {
                                  return DropdownMenuItem(value: v, child: Text(v.name));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedVendor = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: qtyCtrl,
                                decoration: InputDecoration(labelText: "Quantity (Unit: ${selectedItem.unit})"),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (val) => val == null || double.tryParse(val) == null ? "Enter number" : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: priceCtrl,
                                decoration: const InputDecoration(labelText: "Unit Price (₹)"),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: (val) => val == null || double.tryParse(val) == null ? "Enter price" : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: totalCtrl,
                                decoration: const InputDecoration(labelText: "Total Amount (₹)"),
                                readOnly: true,
                              ),
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(color: Color(0xFFC0DD97)),
                        ),
                        
                        const Text("Payment Credentials", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27500A), fontSize: 13)),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: paymentMethod,
                                decoration: const InputDecoration(labelText: "Payment Method"),
                                items: ["Cash", "Cheque", "UPI", "NEFT / RTGS / IMPS", "Bank Transfer", "Credit Card", "Debit Card", "Other"]
                                    .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => paymentMethod = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: paymentStatus,
                                decoration: const InputDecoration(labelText: "Payment Status"),
                                items: ["Paid", "Pending", "Partial"]
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => paymentStatus = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Conditional forms based on payment method
                        if (paymentMethod == "Cheque") ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: chequeNumCtrl,
                                  decoration: const InputDecoration(labelText: "Cheque Number"),
                                  validator: (val) => val == null || val.isEmpty ? "Enter cheque no" : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final selected = await showDatePicker(
                                      context: context,
                                      initialDate: chequeDate ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2030),
                                    );
                                    if (selected != null) {
                                      setDialogState(() => chequeDate = selected);
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(labelText: "Cheque Date"),
                                    child: Text(chequeDate != null ? _formatDate(chequeDate!) : "Select Date"),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: chequeStatus,
                            decoration: const InputDecoration(labelText: "Cheque Clearance Status"),
                            items: ["Pending", "Cleared", "Bounced"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => chequeStatus = val);
                              }
                            },
                          ),
                        ] else if (paymentMethod == "Cash") ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: voucherCtrl,
                                  decoration: const InputDecoration(labelText: "Cash Voucher Number"),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: receivedByCtrl,
                                  decoration: const InputDecoration(labelText: "Received By"),
                                ),
                              ),
                            ],
                          ),
                        ] else if (paymentMethod == "UPI" || paymentMethod.contains("Bank") || paymentMethod.contains("NEFT")) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: bankCtrl,
                                  decoration: const InputDecoration(labelText: "Bank Name"),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: transactionCtrl,
                                  decoration: const InputDecoration(labelText: "UTR / Transaction ID"),
                                  validator: (val) => val == null || val.isEmpty ? "Enter transaction id" : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final double qty = double.parse(qtyCtrl.text.trim());
                      final double price = double.parse(priceCtrl.text.trim());
                      final double total = qty * price;

                      final paymentDetails = PaymentDetailsModel(
                        paymentMethod: paymentMethod,
                        paymentStatus: paymentStatus,
                        paymentDate: purchaseDate,
                        bankName: bankCtrl.text.trim(),
                        transactionId: transactionCtrl.text.trim(),
                        cashVoucherNumber: voucherCtrl.text.trim(),
                        receivedBy: receivedByCtrl.text.trim(),
                        chequeNumber: chequeNumCtrl.text.trim(),
                        chequeDate: chequeDate,
                        chequeClearanceStatus: chequeStatus,
                      );

                      final now = DateTime.now();
                      
                      if (purchase == null) {
                        final newPurchase = PurchaseModel(
                          id: "",
                          purchaseDate: purchaseDate,
                          vendorId: selectedVendor.id,
                          vendorName: selectedVendor.name,
                          itemId: selectedItem.id,
                          itemName: selectedItem.name,
                          quantity: qty,
                          unitPrice: price,
                          totalAmount: total,
                          invoiceNumber: invoiceCtrl.text.trim(),
                          paymentDetails: paymentDetails,
                          createdBy: "Admin",
                          updatedBy: "Admin",
                          createdAt: now,
                          updatedAt: now,
                        );
                        await _service.addPurchase(newPurchase);
                      } else {
                        final updated = purchase.copyWith(
                          purchaseDate: purchaseDate,
                          vendorId: selectedVendor.id,
                          vendorName: selectedVendor.name,
                          itemId: selectedItem.id,
                          itemName: selectedItem.name,
                          quantity: qty,
                          unitPrice: price,
                          totalAmount: total,
                          invoiceNumber: invoiceCtrl.text.trim(),
                          paymentDetails: paymentDetails,
                          updatedBy: "Admin",
                          updatedAt: now,
                        );
                        await _service.updatePurchase(purchase.id, updated, oldQuantity: purchase.quantity);
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(purchase == null ? 'Purchase successfully recorded. Stock updated.' : 'Purchase successfully updated.'),
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
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }
}
