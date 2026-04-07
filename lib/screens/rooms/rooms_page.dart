import 'package:flutter/material.dart';
import 'package:ngo/screens/rooms/widgets/room_card.dart';
import 'package:ngo/screens/rooms/widgets/add_room_dialog.dart';
import 'package:ngo/screens/rooms/widgets/pricing_settings_dialog.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/models/room_model.dart';

class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  String selectedRoomType = 'all'; // 'all', 'private', 'general'
  int selectedFloor = 0; // 0 = all floors

  void _showAddRoomDialog() {
    showDialog(
      context: context,
      builder: (context) => AddRoomDialog(
        selectedFloor: selectedFloor == 0 ? 1 : selectedFloor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomService = ServiceLocator().roomService;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: StreamBuilder<List<RoomModel>>(
        stream: roomService.getRoomsStream(),
        builder: (context, roomsSnapshot) {
          // Show loading only on first load
          if (roomsSnapshot.connectionState == ConnectionState.waiting && 
              !roomsSnapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B6D11)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    "Loading rooms...",
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF639922),
                    ),
                  ),
                ],
              ),
            );
          }

          if (roomsSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading rooms',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${roomsSnapshot.error}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF639922),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          var rooms = roomsSnapshot.data ?? [];
          
          // Apply filters
          if (selectedRoomType != 'all') {
            rooms = rooms.where((r) => r.roomType == selectedRoomType).toList();
          }
          if (selectedFloor != 0) {
            rooms = rooms.where((r) => r.floor == selectedFloor).toList();
          }

          // Calculate stats from rooms
          final totalRooms = rooms.length;
          final privateRooms = rooms.where((r) => r.isPrivate).length;
          final generalRooms = rooms.where((r) => r.isGeneral).length;
          final totalBeds = rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.totalBeds);
          final occupiedBeds = rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.occupiedBeds);
          final availableBeds = totalBeds - occupiedBeds;

          return Column(
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
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => PricingSettingsDialog(),
                                );
                              },
                              icon: const Icon(Icons.attach_money_rounded, size: 18),
                              label: const Text("Pricing"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF3B6D11),
                                side: const BorderSide(color: Color(0xFF3B6D11), width: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
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
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _StatCard(
                          label: "Total Rooms",
                          value: totalRooms.toString(),
                          icon: Icons.meeting_room_outlined,
                          color: const Color(0xFF3B6D11),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: "Private",
                          value: privateRooms.toString(),
                          icon: Icons.hotel_rounded,
                          color: const Color(0xFF639922),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: "General",
                          value: generalRooms.toString(),
                          icon: Icons.bed_rounded,
                          color: const Color(0xFF97C459),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: "Available Beds",
                          value: availableBeds.toString(),
                          icon: Icons.check_circle_outline_rounded,
                          color: const Color(0xFF0F6E56),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Filters
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Text(
                      "Room Type:",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _FilterTab(
                      label: "All",
                      isSelected: selectedRoomType == 'all',
                      onTap: () => setState(() => selectedRoomType = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: "Private",
                      isSelected: selectedRoomType == 'private',
                      onTap: () => setState(() => selectedRoomType = 'private'),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: "General",
                      isSelected: selectedRoomType == 'general',
                      onTap: () => setState(() => selectedRoomType = 'general'),
                    ),
                    const SizedBox(width: 24),
                    const Text(
                      "Floor:",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _FilterTab(
                      label: "All",
                      isSelected: selectedFloor == 0,
                      onTap: () => setState(() => selectedFloor = 0),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: "1st",
                      isSelected: selectedFloor == 1,
                      onTap: () => setState(() => selectedFloor = 1),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: "2nd",
                      isSelected: selectedFloor == 2,
                      onTap: () => setState(() => selectedFloor = 2),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: "3rd",
                      isSelected: selectedFloor == 3,
                      onTap: () => setState(() => selectedFloor = 3),
                    ),
                  ],
                ),
              ),

              // Rooms grid
              Expanded(
                child: rooms.isEmpty
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
                              "No rooms found",
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
                        itemCount: rooms.length,
                        itemBuilder: (context, index) {
                          return RoomCard(room: rooms[index]);
                        },
                      ),
              ),
            ],
          );
        },
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

// Filter tab widget
class _FilterTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterTab({
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
