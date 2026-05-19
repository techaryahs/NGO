import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/vendor_model.dart';

/// Sub-tab to view Supplier Directory and manage vendor records
class VendorsTab extends StatefulWidget {
  const VendorsTab({super.key});

  @override
  State<VendorsTab> createState() => _VendorsTabState();
}

class _VendorsTabState extends State<VendorsTab> {
  final _service = ServiceLocator().inventoryExpenseService;
  final _searchController = TextEditingController();

  List<VendorModel> _vendors = [];
  StreamSubscription? _subscription;
  bool _loading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _subscription = _service.getVendorsStream().listen((data) {
      if (mounted) {
        setState(() {
          _vendors = data;
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

    final filteredVendors = _vendors.where((v) {
      return v.name.toLowerCase().contains(_searchQuery) ||
             v.contactPerson.toLowerCase().contains(_searchQuery) ||
             v.mobileNumber.contains(_searchQuery);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Search & Action Row
          _buildActionBar(context),
          const SizedBox(height: 20),
          
          // Vendor Grid
          Expanded(
            child: filteredVendors.isEmpty
                ? const Center(
                    child: Text("No supplier vendors registered", style: TextStyle(color: Color(0xFF639922))),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 340,
                      mainAxisExtent: 220,
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                    ),
                    itemCount: filteredVendors.length,
                    itemBuilder: (context, index) {
                      final vendor = filteredVendors[index];
                      return _buildVendorCard(context, vendor);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFDF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search vendor name or contact person...",
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
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showFormDialog(context),
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: const Text("Register Vendor"),
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

  Widget _buildVendorCard(BuildContext context, VendorModel vendor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFDF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vendor Name & Edit Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  vendor.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF27500A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF639922)),
                    onPressed: () => _showFormDialog(context, vendor: vendor),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFC62828)),
                    onPressed: () => _confirmDelete(vendor),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Contact Details
          _buildInfoRow(Icons.person_outline_rounded, vendor.contactPerson.isNotEmpty ? vendor.contactPerson : "N/A"),
          const SizedBox(height: 5),
          _buildInfoRow(Icons.phone_rounded, vendor.mobileNumber.isNotEmpty ? vendor.mobileNumber : "N/A"),
          const SizedBox(height: 5),
          _buildInfoRow(Icons.email_outlined, vendor.email.isNotEmpty ? vendor.email : "N/A"),
          const SizedBox(height: 5),
          _buildInfoRow(Icons.pin_rounded, vendor.address.isNotEmpty ? vendor.address : "N/A"),
          
          const Spacer(),
          const Divider(color: Color(0xFFC0DD97), height: 10, thickness: 0.5),
          
          // GST details or notes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                vendor.gstNumber.isNotEmpty ? "GSTIN: ${vendor.gstNumber}" : "GSTIN: Unregistered",
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: vendor.gstNumber.isNotEmpty ? const Color(0xFF3B6D11) : Colors.grey.shade600,
                ),
              ),
              if (vendor.notes.isNotEmpty)
                Tooltip(
                  message: vendor.notes,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3DE),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text("Notes", style: TextStyle(fontSize: 9, color: Color(0xFF27500A), fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: const Color(0xFF639922)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _confirmDelete(VendorModel vendor) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Vendor"),
        content: Text("Are you sure you want to permanently delete supplier '${vendor.name}'? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.deleteVendor(vendor.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vendor successfully deleted'), backgroundColor: Color(0xFF3B6D11)),
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

  void _showFormDialog(BuildContext context, {VendorModel? vendor}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: vendor?.name ?? "");
    final contactCtrl = TextEditingController(text: vendor?.contactPerson ?? "");
    final phoneCtrl = TextEditingController(text: vendor?.mobileNumber ?? "");
    final emailCtrl = TextEditingController(text: vendor?.email ?? "");
    final gstCtrl = TextEditingController(text: vendor?.gstNumber ?? "");
    final addressCtrl = TextEditingController(text: vendor?.address ?? "");
    final notesCtrl = TextEditingController(text: vendor?.notes ?? "");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(vendor == null ? "Register Supplier Vendor" : "Edit Vendor Details"),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: "Company/Vendor Name *"),
                    validator: (val) => val == null || val.isEmpty ? "Enter vendor name" : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: contactCtrl,
                          decoration: const InputDecoration(labelText: "Contact Person"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: phoneCtrl,
                          decoration: const InputDecoration(labelText: "Mobile Number"),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: emailCtrl,
                          decoration: const InputDecoration(labelText: "Email Address"),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: gstCtrl,
                          decoration: const InputDecoration(labelText: "GSTIN Number (Optional)"),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: "Vendor Address"),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: "Additional Notes"),
                    maxLines: 2,
                  ),
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
                if (vendor == null) {
                  await _service.addVendor(
                    name: nameCtrl.text.trim(),
                    contactPerson: contactCtrl.text.trim(),
                    mobileNumber: phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    gstNumber: gstCtrl.text.trim(),
                    address: addressCtrl.text.trim(),
                    notes: notesCtrl.text.trim(),
                    createdBy: "Admin",
                  );
                } else {
                  await _service.updateVendor(vendor.id, {
                    'name': nameCtrl.text.trim(),
                    'contactPerson': contactCtrl.text.trim(),
                    'mobileNumber': phoneCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'gstNumber': gstCtrl.text.trim(),
                    'address': addressCtrl.text.trim(),
                    'notes': notesCtrl.text.trim(),
                    'updatedBy': "Admin",
                  });
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(vendor == null ? 'Vendor registered successfully' : 'Vendor updated successfully'),
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
