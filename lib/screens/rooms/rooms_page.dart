import 'package:flutter/material.dart';
import 'package:ngo/screens/rooms/widgets/room_card.dart';
import 'package:ngo/screens/rooms/widgets/add_room_dialog.dart';

class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  int selectedFloor = 1;
  
  // Mock data for rooms
  final Map<int, List<RoomData>> roomsByFloor = {
    1: [
      RoomData(roomNumber: '101', floor: 1, isOccupied: true, capacity: 2),
      RoomData(roomNumber: '102', floor: 1, isOccupied: false, capacity: 4),
      RoomData(roomNumber: '103', floor: 1, isOccupied: true, capacity: 2),
      RoomData(roomNumber: '104', floor: 1, isOccupied: false, capacity: 3),
      RoomData(roomNumber: '105', floor: 1, isOccupied: true, capacity: 2),
    ],
    2: [
      RoomData(roomNumber: '201', floor: 2, isOccupied: false, capacity: 2),
      RoomData(roomNumber: '202', floor: 2, isOccupied: true, capacity: 4),
      RoomData(roomNumber: '203', floor: 2, isOccupied: false, capacity: 2),
      RoomData(roomNumber: '204', floor: 2, isOccupied: true, capacity: 3),
    ],
    3: [
      RoomData(roomNumber: '301', floor: 3, isOccupied: true, capacity: 2),
      RoomData(roomNumber: '302', floor: 3, isOccupied: false, capacity: 4),
      RoomData(roomNumber: '303', floor: 3, isOccupied: true, capacity: 2),
    ],
  };

  void _addRoom(String roomNumber, int floor, int capacity) {
    setState(() {
      roomsByFloor[floor]?.add(
        RoomData(roomNumber: roomNumber, floor: floor, isOccupied: false, capacity: capacity),
      );
    });
  }

  void _showAddRoomDialog() {
    showDialog(
      context: context,
      builder: (context) => AddRoomDialog(
        onAdd: _addRoom,
        selectedFloor: selectedFloor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentFloorRooms = roomsByFloor[selectedFloor] ?? [];
    final occupiedCount = currentFloorRooms.where((r) => r.isOccupied).length;
    final availableCount = currentFloorRooms.length - occupiedCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: Column(
        children: [
          // Header with stats
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFDF7),
              border: Border(
                bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Room Management",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _showAddRoomDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text("Add Room"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B6D11),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatCard(
                      label: "Total Rooms",
                      value: currentFloorRooms.length.toString(),
                      icon: Icons.meeting_room_outlined,
                      color: const Color(0xFF3B6D11),
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: "Occupied",
                      value: occupiedCount.toString(),
                      icon: Icons.person_rounded,
                      color: const Color(0xFF639922),
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: "Available",
                      value: availableCount.toString(),
                      icon: Icons.check_circle_outline_rounded,
                      color: const Color(0xFF0F6E56),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Floor selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                const Text(
                  "Select Floor:",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A),
                  ),
                ),
                const SizedBox(width: 12),
                _FloorTab(
                  label: "1st Floor",
                  isSelected: selectedFloor == 1,
                  onTap: () => setState(() => selectedFloor = 1),
                ),
                const SizedBox(width: 8),
                _FloorTab(
                  label: "2nd Floor",
                  isSelected: selectedFloor == 2,
                  onTap: () => setState(() => selectedFloor = 2),
                ),
                const SizedBox(width: 8),
                _FloorTab(
                  label: "3rd Floor",
                  isSelected: selectedFloor == 3,
                  onTap: () => setState(() => selectedFloor = 3),
                ),
              ],
            ),
          ),

          // Rooms grid
          Expanded(
            child: currentFloorRooms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.meeting_room_outlined,
                          size: 64,
                          color: const Color(0xFF639922).withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No rooms on this floor",
                          style: TextStyle(
                            fontSize: 16,
                            color: const Color(0xFF639922).withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _showAddRoomDialog,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text("Add First Room"),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF3B6D11),
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: currentFloorRooms.length,
                    itemBuilder: (context, index) {
                      return RoomCard(room: currentFloorRooms[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Stat card widget
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F9F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF639922),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Floor tab widget
class _FloorTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FloorTab({
    required this.label,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFF4F9F0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFC0DD97),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF27500A),
          ),
        ),
      ),
    );
  }
}

// Room data model
class RoomData {
  final String roomNumber;
  final int floor;
  final bool isOccupied;
  final int capacity;

  RoomData({
    required this.roomNumber,
    required this.floor,
    required this.isOccupied,
    required this.capacity,
  });
}
