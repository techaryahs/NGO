import 'package:flutter/material.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/services/service_locator.dart';

class ExtendStayDialog extends StatefulWidget {
  final StayModel stay;

  const ExtendStayDialog({super.key, required this.stay});

  @override
  State<ExtendStayDialog> createState() => _ExtendStayDialogState();
}

class _ExtendStayDialogState extends State<ExtendStayDialog> {
  final TextEditingController reasonController = TextEditingController();
  
  int additionalDays = 7;
  bool isLoading = false;
  Map<String, dynamic>? pricing;
  double additionalCost = 0;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadPricing() async {
    try {
      final roomService = ServiceLocator().roomService;
      final pricingData = await roomService.getPricing();
      setState(() {
        pricing = pricingData;
        _calculateCost();
      });
    } catch (e) {
      // Use defaults if pricing fails to load
    }
  }

  void _calculateCost() {
    if (pricing == null) return;

    if (widget.stay.roomType == 'private') {
      final basePrice = (pricing!['privateRoomBasePrice'] ?? 600).toDouble();
      final includedAttendants = pricing!['privateRoomIncludedAttendants'] ?? 2;
      final extraFee = (pricing!['privateRoomExtraAttendantFee'] ?? 200).toDouble();
      
      additionalCost = basePrice * additionalDays;
      final extras = widget.stay.attendantCount > includedAttendants
          ? widget.stay.attendantCount - includedAttendants
          : 0;
      additionalCost += extras * extraFee * additionalDays;
    } else {
      final bedPrice = (pricing!['generalRoomBedPrice'] ?? 150).toDouble();
      additionalCost = bedPrice * additionalDays;
    }
  }

  Future<void> _extendStay() async {
    setState(() => isLoading = true);

    try {
      final roomService = ServiceLocator().roomService;
      await roomService.extendStay(
        stayId: widget.stay.id,
        additionalDays: additionalDays,
        reason: reasonController.text.trim().isEmpty 
            ? "Extended by admin" 
            : reasonController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("Stay extended successfully");
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Failed to extend stay: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
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
    final newExpiryDate = widget.stay.effectiveExpiryDate.add(Duration(days: additionalDays));

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        ),
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
                        Icons.add_circle_outline_rounded,
                        color: Color(0xFF3B6D11),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Extend Stay",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        Text(
                          widget.stay.patientName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF639922),
                          ),
                        ),
                      ],
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

            // Current Stay Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F9F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 1),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Current Duration",
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF97C459),
                            ),
                          ),
                          Text(
                            "${widget.stay.totalDays} days",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF27500A),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            "Current Expiry",
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF97C459),
                            ),
                          ),
                          Text(
                            "${widget.stay.effectiveExpiryDate.day}/${widget.stay.effectiveExpiryDate.month}/${widget.stay.effectiveExpiryDate.year}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF27500A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.stay.extensions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFC0DD97)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 14, color: Color(0xFF639922)),
                        const SizedBox(width: 6),
                        Text(
                          "Extended ${widget.stay.extensions.length} time(s) • +${widget.stay.totalExtendedDays} days",
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF639922),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Additional Days
            const Text(
              "ADDITIONAL DAYS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (additionalDays > 1) {
                      setState(() {
                        additionalDays--;
                        _calculateCost();
                      });
                    }
                  },
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: const Color(0xFF639922),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F9F0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "+$additionalDays",
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3B6D11),
                          ),
                        ),
                        const Text(
                          "days",
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF639922),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      additionalDays++;
                      _calculateCost();
                    });
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: const Color(0xFF639922),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // New Expiry Date
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3DE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "New Expiry Date",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF639922),
                        ),
                      ),
                      Text(
                        "${newExpiryDate.day}/${newExpiryDate.month}/${newExpiryDate.year}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3B6D11),
                        ),
                      ),
                    ],
                  ),
                  if (pricing != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          "Additional Cost",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF639922),
                          ),
                        ),
                        Text(
                          "₹${additionalCost.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3B6D11),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Reason
            const Text(
              "REASON (OPTIONAL)",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "Enter reason for extension...",
                hintStyle: const TextStyle(color: Color(0xFF97C459), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF4F9F0),
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
            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF639922),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: isLoading ? null : _extendStay,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(isLoading ? "Extending..." : "Extend Stay"),
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
    );
  }
}
