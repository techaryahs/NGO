import 'package:flutter/material.dart';

class AddRoomFloorOption extends StatelessWidget {
  final int floor;
  final String label;
  final List<String> rooms;
  final bool isSelected;
  final VoidCallback onTap;

  const AddRoomFloorOption({
    super.key,
    required this.floor,
    required this.label,
    required this.rooms,
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFF4F9F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B6D11)
                : const Color(0xFFC0DD97),
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
            const SizedBox(height: 8),
            Text(
              'Floor \$floor',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xFF27500A),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white70 : const Color(0xFF97C459),
              ),
            ),
            if (rooms.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                rooms.join(', '),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white60 : const Color(0xFF639922),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AddRoomTypeButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const AddRoomTypeButton({
    super.key,
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
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: isSelected ? Colors.white70 : const Color(0xFF97C459),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddRoomBedConfiguration extends StatelessWidget {
  final String selectedRoomType;
  final bool useCustomBedLabels;
  final TextEditingController bedLabelsController;
  final TextEditingController bedCountController;
  final ValueChanged<bool> onUseCustomBedLabelsChanged;
  final VoidCallback onDecreaseBedCount;
  final VoidCallback onIncreaseBedCount;
  final int defaultBeds;

  const AddRoomBedConfiguration({
    super.key,
    required this.selectedRoomType,
    required this.useCustomBedLabels,
    required this.bedLabelsController,
    required this.bedCountController,
    required this.onUseCustomBedLabelsChanged,
    required this.onDecreaseBedCount,
    required this.onIncreaseBedCount,
    required this.defaultBeds,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "STEP 4: BED CONFIGURATION",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 12),

        // Custom Bed Labels Toggle (for general wards)
        if (selectedRoomType == 'general') ...[
          Row(
            children: [
              Checkbox(
                value: useCustomBedLabels,
                onChanged: (value) => onUseCustomBedLabelsChanged(value ?? false),
                activeColor: const Color(0xFF3B6D11),
              ),
              const Text(
                "Use custom bed labels (non-sequential)",
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF27500A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        if (useCustomBedLabels && selectedRoomType == 'general') ...[
          const Text(
            "BED LABELS (comma-separated)",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF27500A),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bedLabelsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: "e.g., 23, 21, 19, 17, 15, 13, 11, 9, 7, 5, 3, 1",
              hintStyle: const TextStyle(
                color: Color(0xFF97C459),
                fontSize: 13,
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(
                  Icons.list_alt_rounded,
                  color: Color(0xFF639922),
                  size: 20,
                ),
              ),
              filled: true,
              fillColor: const Color(0xFFF4F9F0),
              contentPadding: const EdgeInsets.all(12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFFC0DD97),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFF639922),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ] else ...[
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
            children: [
              // Decrease button
              IconButton(
                onPressed: onDecreaseBedCount,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: const Color(0xFF639922),
              ),
              // Number input
              Expanded(
                child: TextField(
                  controller: bedCountController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: "4",
                    hintStyle: const TextStyle(
                      color: Color(0xFF97C459),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF4F9F0),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFC0DD97),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF639922),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              // Increase button
              IconButton(
                onPressed: onIncreaseBedCount,
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: const Color(0xFF639922),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFC0DD97),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: Color(0xFF3B6D11),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Default: \$defaultBeds beds (from configuration)",
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF3B6D11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}


class RoomConfigLoadingView extends StatelessWidget {
  const RoomConfigLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B6D11)),
            ),
            SizedBox(height: 20),
            Text(
              'Loading room configuration...',
              style: TextStyle(fontSize: 14, color: Color(0xFF639922)),
            ),
          ],
        ),
      ),
    );
  }
}


class AddRoomFloorSelection extends StatelessWidget {
  final int? selectedFloor;
  final ValueChanged<int> onFloorSelected;
  final dynamic roomConfig;

  const AddRoomFloorSelection({
    super.key,
    this.selectedFloor,
    required this.onFloorSelected,
    this.roomConfig,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STEP 1: SELECT FLOOR',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF27500A), letterSpacing: 0.6),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AddRoomFloorOption(
                floor: 1,
                label: 'Ground Floor',
                rooms: roomConfig?.getFloor(1)?.getAllRooms() ?? [],
                isSelected: selectedFloor == 1,
                onTap: () => onFloorSelected(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AddRoomFloorOption(
                floor: 2,
                label: 'First Floor',
                rooms: roomConfig?.getFloor(2)?.getAllRooms() ?? [],
                isSelected: selectedFloor == 2,
                onTap: () => onFloorSelected(2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AddRoomTypeSelection extends StatelessWidget {
  final String? selectedRoomType;
  final ValueChanged<String> onRoomTypeSelected;

  const AddRoomTypeSelection({
    super.key,
    this.selectedRoomType,
    required this.onRoomTypeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STEP 2: SELECT ROOM TYPE',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF27500A), letterSpacing: 0.6),
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
                child: AddRoomTypeButton(
                  label: 'Private Room',
                  icon: Icons.hotel_rounded,
                  subtitle: 'Attendant-based pricing',
                  isSelected: selectedRoomType == 'private',
                  onTap: () => onRoomTypeSelected('private'),
                ),
              ),
              Expanded(
                child: AddRoomTypeButton(
                  label: 'General Ward',
                  icon: Icons.bed_rounded,
                  subtitle: 'Bed-based pricing',
                  isSelected: selectedRoomType == 'general',
                  onTap: () => onRoomTypeSelected('general'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
