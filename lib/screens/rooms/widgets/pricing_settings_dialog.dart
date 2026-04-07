import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ngo/services/service_locator.dart';

class PricingSettingsDialog extends StatefulWidget {
  const PricingSettingsDialog({super.key});

  @override
  State<PricingSettingsDialog> createState() => _PricingSettingsDialogState();
}

class _PricingSettingsDialogState extends State<PricingSettingsDialog> {
  final _roomService = ServiceLocator().roomService;
  
  final TextEditingController privateBasePriceController = TextEditingController();
  final TextEditingController privateExtraAttendantController = TextEditingController();
  final TextEditingController generalBedPriceController = TextEditingController();
  
  int privateIncludedAttendants = 2;
  int privateMaxAttendants = 5;
  int generalDefaultBeds = 4;
  int generalMaxAttendants = 2;
  
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  @override
  void dispose() {
    privateBasePriceController.dispose();
    privateExtraAttendantController.dispose();
    generalBedPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadPricing() async {
    try {
      final pricing = await _roomService.getPricing();
      setState(() {
        privateBasePriceController.text = pricing['privateRoomBasePrice'].toString();
        privateExtraAttendantController.text = pricing['privateRoomExtraAttendantFee'].toString();
        generalBedPriceController.text = pricing['generalRoomBedPrice'].toString();
        privateIncludedAttendants = pricing['privateRoomIncludedAttendants'] ?? 2;
        privateMaxAttendants = pricing['privateRoomMaxAttendants'] ?? 5;
        generalDefaultBeds = pricing['generalRoomDefaultBeds'] ?? 4;
        generalMaxAttendants = pricing['generalRoomMaxAttendants'] ?? 2;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnackBar('Failed to load pricing: $e', isError: true);
      }
    }
  }

  Future<void> _savePricing() async {
    if (privateBasePriceController.text.isEmpty ||
        privateExtraAttendantController.text.isEmpty ||
        generalBedPriceController.text.isEmpty) {
      _showSnackBar('Please fill all price fields', isError: true);
      return;
    }

    setState(() => isSaving = true);

    try {
      await _roomService.updatePricing({
        'privateRoomBasePrice': double.parse(privateBasePriceController.text),
        'privateRoomIncludedAttendants': privateIncludedAttendants,
        'privateRoomExtraAttendantFee': double.parse(privateExtraAttendantController.text),
        'privateRoomMaxAttendants': privateMaxAttendants,
        'generalRoomBedPrice': double.parse(generalBedPriceController.text),
        'generalRoomDefaultBeds': generalDefaultBeds,
        'generalRoomMaxAttendants': generalMaxAttendants,
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Pricing updated successfully');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to save pricing: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF3B6D11),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        ),
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B6D11)),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF3DE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.attach_money_rounded,
                                color: Color(0xFF3B6D11),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              "Pricing Settings",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF27500A),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF639922),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Private Room Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F9F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.hotel_rounded, color: Color(0xFF3B6D11), size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                "PRIVATE ROOM PRICING",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF27500A),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Base Price
                          const Text(
                            "Base Price (per day)",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: privateBasePriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              hintText: "600",
                              prefixText: "₹ ",
                              hintStyle: const TextStyle(color: Color(0xFF97C459), fontSize: 14),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.all(12),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Included Attendants
                          const Text(
                            "Included Attendants",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [1, 2, 3].map((count) {
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: count < 3 ? 8 : 0),
                                  child: _CountChip(
                                    count: count,
                                    isSelected: privateIncludedAttendants == count,
                                    onTap: () => setState(() => privateIncludedAttendants = count),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          
                          // Extra Attendant Fee
                          const Text(
                            "Extra Attendant Fee (per day)",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: privateExtraAttendantController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              hintText: "200",
                              prefixText: "₹ ",
                              hintStyle: const TextStyle(color: Color(0xFF97C459), fontSize: 14),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.all(12),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Max Attendants
                          const Text(
                            "Maximum Attendants",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: List.generate(5, (index) {
                              final count = index + 1;
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: index < 4 ? 8 : 0),
                                  child: _CountChip(
                                    count: count,
                                    isSelected: privateMaxAttendants == count,
                                    onTap: () => setState(() => privateMaxAttendants = count),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // General Room Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F9F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bed_rounded, color: Color(0xFF3B6D11), size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                "GENERAL ROOM PRICING",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF27500A),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Bed Price
                          const Text(
                            "Price per Bed (per day)",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: generalBedPriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              hintText: "150",
                              prefixText: "₹ ",
                              hintStyle: const TextStyle(color: Color(0xFF97C459), fontSize: 14),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.all(12),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFFB74D), width: 1),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFE65100)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "General rooms include 1 attendant. 2nd attendant is self-expense.",
                                    style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF639922),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: isSaving ? null : _savePricing,
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(isSaving ? "Saving..." : "Save Settings"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B6D11),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CountChip({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFC0DD97),
            width: 1.5,
          ),
        ),
        child: Text(
          "$count",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF27500A),
          ),
        ),
      ),
    );
  }
}
