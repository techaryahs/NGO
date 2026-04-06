import 'package:flutter/material.dart';

class AddRoomDialog extends StatefulWidget {
  final Function(String roomNumber, int floor, int capacity) onAdd;
  final int selectedFloor;

  const AddRoomDialog({
    super.key,
    required this.onAdd,
    required this.selectedFloor,
  });

  @override
  State<AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<AddRoomDialog> {
  final TextEditingController roomNumberController = TextEditingController();
  final TextEditingController capacityController = TextEditingController();
  int selectedFloor = 1;
  int selectedCapacity = 2;
  bool isFormVisible = false;

  @override
  void initState() {
    super.initState();
    selectedFloor = widget.selectedFloor;
  }

  @override
  void dispose() {
    roomNumberController.dispose();
    capacityController.dispose();
    super.dispose();
  }

  void _handleAdd() {
    if (roomNumberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please enter a room number"),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    final capacity = isFormVisible && capacityController.text.isNotEmpty
        ? int.tryParse(capacityController.text) ?? selectedCapacity
        : selectedCapacity;

    widget.onAdd(roomNumberController.text, selectedFloor, capacity);
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Room ${roomNumberController.text} added successfully"),
        backgroundColor: const Color(0xFF3B6D11),
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
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFC0DD97),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

            // Toggle button
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
                    child: _ToggleButton(
                      label: "Quick Add",
                      icon: Icons.flash_on_rounded,
                      isSelected: !isFormVisible,
                      onTap: () => setState(() => isFormVisible = false),
                    ),
                  ),
                  Expanded(
                    child: _ToggleButton(
                      label: "Detailed Form",
                      icon: Icons.edit_note_rounded,
                      isSelected: isFormVisible,
                      onTap: () => setState(() => isFormVisible = true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Form content
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isFormVisible ? _buildDetailedForm() : _buildQuickAdd(),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF639922),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _handleAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text("Add Room"),
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

  Widget _buildQuickAdd() {
    return Column(
      key: const ValueKey('quick'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const Text(
          "ROOM CAPACITY",
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
            _CapacityChip(
              capacity: 1,
              isSelected: selectedCapacity == 1,
              onTap: () => setState(() => selectedCapacity = 1),
            ),
            const SizedBox(width: 8),
            _CapacityChip(
              capacity: 2,
              isSelected: selectedCapacity == 2,
              onTap: () => setState(() => selectedCapacity = 2),
            ),
            const SizedBox(width: 8),
            _CapacityChip(
              capacity: 3,
              isSelected: selectedCapacity == 3,
              onTap: () => setState(() => selectedCapacity = 3),
            ),
            const SizedBox(width: 8),
            _CapacityChip(
              capacity: 4,
              isSelected: selectedCapacity == 4,
              onTap: () => setState(() => selectedCapacity = 4),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailedForm() {
    return Column(
      key: const ValueKey('detailed'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            hintText: "Enter room number",
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
        const SizedBox(height: 16),
        const Text(
          "FLOOR NUMBER",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F9F0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC0DD97), width: 1),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selectedFloor,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF639922)),
              style: const TextStyle(fontSize: 14, color: Color(0xFF27500A)),
              items: [1, 2, 3].map((floor) {
                return DropdownMenuItem(
                  value: floor,
                  child: Row(
                    children: [
                      const Icon(Icons.layers_outlined, size: 18, color: Color(0xFF639922)),
                      const SizedBox(width: 8),
                      Text("Floor $floor"),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => selectedFloor = value);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "ROOM CAPACITY",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: capacityController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: "Enter capacity (e.g., 2, 4)",
            hintStyle: const TextStyle(color: Color(0xFF97C459), fontSize: 14),
            prefixIcon: const Icon(Icons.people_outline_rounded, color: Color(0xFF639922), size: 20),
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
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3DE),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFC0DD97), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF639922)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Room will be created on Floor $selectedFloor",
                  style: const TextStyle(fontSize: 12, color: Color(0xFF639922)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Toggle button widget
class _ToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF639922),
            ),
            const SizedBox(width: 6),
            Text(
              label,
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

// Floor option widget
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

// Capacity chip widget
class _CapacityChip extends StatelessWidget {
  final int capacity;
  final bool isSelected;
  final VoidCallback onTap;

  const _CapacityChip({
    required this.capacity,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
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
          child: Column(
            children: [
              Icon(
                Icons.person_rounded,
                color: isSelected ? Colors.white : const Color(0xFF639922),
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                "$capacity",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF27500A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
