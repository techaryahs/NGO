import 'package:flutter/material.dart';
import 'package:ngo/services/service_locator.dart';

class AddRoomDialog extends StatefulWidget {
  final int selectedFloor;

  const AddRoomDialog({
    super.key,
    required this.selectedFloor,
  });

  @override
  State<AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<AddRoomDialog> {
  final TextEditingController roomNumberController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  
  String selectedRoomType = 'private'; // 'private' or 'general'
  int selectedFloor = 1;
  int totalBeds = 4; // For general rooms
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    selectedFloor = widget.selectedFloor;
  }

  @override
  void dispose() {
    roomNumberController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    if (roomNumberController.text.isEmpty) {
      _showSnackBar("Please enter a room number", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final roomService = ServiceLocator().roomService;
      await roomService.addRoom(
        roomNumber: roomNumberController.text.trim(),
        floor: selectedFloor,
        roomType: selectedRoomType,
        totalBeds: selectedRoomType == 'general' ? totalBeds : null,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("Room ${roomNumberController.text} added successfully");
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Failed to add room: $e", isError: true);
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
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        ),
        child: SingleChildScrollView(
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
                        Icons.add_home_rounded,
                        color: Color(0xFF3B6D11),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Add New Room",
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

            // Room Type Toggle
            const Text(
              "ROOM TYPE",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F9F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFC0DD97), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _RoomTypeButton(
                      label: "Private Room",
                      icon: Icons.hotel_rounded,
                      subtitle: "Max 5 attendants",
                      isSelected: selectedRoomType == 'private',
                      onTap: () => setState(() => selectedRoomType = 'private'),
                    ),
                  ),
                  Expanded(
                    child: _RoomTypeButton(
                      label: "General Room",
                      icon: Icons.bed_rounded,
                      subtitle: "Bed-based",
                      isSelected: selectedRoomType == 'general',
                      onTap: () => setState(() => selectedRoomType = 'general'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Room Number
            const Text(
              "ROOM NUMBER",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: roomNumberController,
              decoration: InputDecoration(
                hintText: "e.g., 101, 102, 201",
                hintStyle: const TextStyle(color: Color(0xFF97C459), fontSize: 14),
                prefixIcon: const Icon(Icons.meeting_room_outlined, color: Color(0xFF639922), size: 20),
                filled: true,
                fillColor: const Color(0xFFF4F9F0),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
            const SizedBox(height: 20),

            // Floor Selection
            const Text(
              "SELECT FLOOR",
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
                Expanded(
                  child: _FloorOption(
                    floor: 1,
                    isSelected: selectedFloor == 1,
                    onTap: () => setState(() => selectedFloor = 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FloorOption(
                    floor: 2,
                    isSelected: selectedFloor == 2,
                    onTap: () => setState(() => selectedFloor = 2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FloorOption(
                    floor: 3,
                    isSelected: selectedFloor == 3,
                    onTap: () => setState(() => selectedFloor = 3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Type-specific configuration
            if (selectedRoomType == 'general') ...[
              const Text(
                "NUMBER OF BEDS",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [2, 4, 6, 8].map((count) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: count < 8 ? 8 : 0),
                      child: _CountChip(
                        count: count,
                        isSelected: totalBeds == count,
                        onTap: () => setState(() => totalBeds = count),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],

            // Notes (optional)
            const Text(
              "NOTES (OPTIONAL)",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "Add any additional notes...",
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
                  onPressed: isLoading ? null : _handleAdd,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add_rounded, size: 18),
                  label: Text(isLoading ? "Adding..." : "Add Room"),
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

// Room Type Button
class _RoomTypeButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoomTypeButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? Colors.white : const Color(0xFF639922),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF27500A),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white70 : const Color(0xFF97C459),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Floor Option
class _FloorOption extends StatelessWidget {
  final int floor;
  final bool isSelected;
  final VoidCallback onTap;

  const _FloorOption({
    required this.floor,
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFF4F9F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFC0DD97),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.layers_outlined,
              color: isSelected ? Colors.white : const Color(0xFF639922),
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              "Floor $floor",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF27500A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Count Chip (for attendants/beds)
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
          color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFF4F9F0),
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
