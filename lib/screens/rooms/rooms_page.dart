import 'package:flutter/material.dart';
import 'package:ngo/screens/rooms/widgets/room_card.dart';
import 'package:ngo/screens/rooms/widgets/add_room_dialog.dart';
import 'package:ngo/screens/rooms/widgets/pricing_settings_dialog.dart';
import 'package:ngo/screens/rooms/widgets/census_summary_widget.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/models/room_model.dart';

class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  String selectedRoomType = 'all'; // 'all', 'private', 'general'
  int selectedFloor = 0; // 0 = all floors, 1 = Floor 1, 2 = Floor 2
  String selectedStatus = 'all'; // 'all', 'available', 'occupied', 'partially_occupied', 'maintenance'
  String searchQuery = '';
  final TextEditingController searchController = TextEditingController();

  void _showAddRoomDialog() {
    showDialog(
      context: context,
      builder: (context) => AddRoomDialog(
        selectedFloor: selectedFloor == 0 ? 1 : selectedFloor,
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      selectedRoomType = 'all';
      selectedFloor = 0;
      selectedStatus = 'all';
      searchQuery = '';
      searchController.clear();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomService = ServiceLocator().roomService;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 700;
    final bool isWideDesktop = screenWidth >= 1150;

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

          final allRooms = roomsSnapshot.data ?? [];
          var rooms = List<RoomModel>.from(allRooms);

          // Calculate overall stats on the global database
          final totalRoomsCount = allRooms.length;
          final privateRoomsCount = allRooms.where((r) => r.isPrivate).length;
          final generalRoomsCount = allRooms.where((r) => r.isGeneral).length;
          final totalBeds = allRooms.fold(0, (sum, r) => sum + r.actualTotalBeds);
          final occupiedBeds = allRooms.fold(0, (sum, r) => sum + r.actualOccupiedBeds);
          final availableBeds = totalBeds - occupiedBeds;

          // Calculate per-floor stats
          final floor1Rooms = allRooms.where((r) => r.floor == 1).toList();
          final floor2Rooms = allRooms.where((r) => r.floor == 2).toList();

          final floor1Patients = floor1Rooms.fold(0, (sum, r) => sum + r.actualOccupiedBeds);
          final floor1VacantBeds = floor1Rooms.fold(0, (sum, r) => sum + r.actualAvailableBeds);
          final floor1TotalRooms = floor1Rooms.length;

          final floor2Patients = floor2Rooms.fold(0, (sum, r) => sum + r.actualOccupiedBeds);
          final floor2VacantBeds = floor2Rooms.fold(0, (sum, r) => sum + r.actualAvailableBeds);
          final floor2TotalRooms = floor2Rooms.length;

          // Apply filters
          if (selectedRoomType != 'all') {
            rooms = rooms.where((r) => r.roomType == selectedRoomType).toList();
          }
          if (selectedFloor != 0) {
            rooms = rooms.where((r) => r.floor == selectedFloor).toList();
          }
          if (selectedStatus != 'all') {
            rooms = rooms.where((r) => r.derivedOccupancyStatus == selectedStatus).toList();
          }
          if (searchQuery.isNotEmpty) {
            final query = searchQuery.toLowerCase();
            rooms = rooms.where((r) =>
              r.roomIdentifier.toLowerCase().contains(query) ||
              r.roomNumber.toLowerCase().contains(query) ||
              (r.notes != null && r.notes!.toLowerCase().contains(query))
            ).toList();
          }

          // Calculate grid parameters
          int crossAxisCount = 1;
          if (screenWidth >= 1400) {
            crossAxisCount = isWideDesktop ? 3 : 4; // adjustment when sidebar takes space
          } else if (screenWidth >= 1050) {
            crossAxisCount = isWideDesktop ? 2 : 3;
          } else if (screenWidth >= 700) {
            crossAxisCount = 2;
          }

          // Compute aspect ratio dynamically based on screen width to enforce a 265px card height
          double spacing = 16.0;
          double sidebarWidth = isWideDesktop ? 330.0 : 0.0;
          double gridWidth = screenWidth - (isWideDesktop ? sidebarWidth : 0.0) - 40.0; // 40px padding
          double cellWidth = (gridWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
          double childAspectRatio = (cellWidth / 265.0).clamp(0.6, 2.5);

          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              // HEADER ROW (Non-scrollable top margin, but inside custom scroll view)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Room Management",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
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
                ),
              ),

              // KPI HORIZONTAL CARDS SECTION
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: screenWidth >= 900
                      ? Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: "Private Rooms",
                                value: privateRoomsCount.toString(),
                                icon: Icons.hotel_rounded,
                                color: const Color(0xFF639922),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                label: "General Wards",
                                value: generalRoomsCount.toString(),
                                icon: Icons.bed_rounded,
                                color: const Color(0xFF97C459),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                label: "Total Rooms",
                                value: totalRoomsCount.toString(),
                                icon: Icons.meeting_room_outlined,
                                color: const Color(0xFF3B6D11),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                label: "Available Beds",
                                value: availableBeds.toString(),
                                icon: Icons.check_circle_outline_rounded,
                                color: const Color(0xFF0F6E56),
                              ),
                            ),
                          ],
                        )
                      : GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: isMobile ? 1 : 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: isMobile ? 3.4 : 2.5,
                          children: [
                            _StatCard(
                              label: "Private Rooms",
                              value: privateRoomsCount.toString(),
                              icon: Icons.hotel_rounded,
                              color: const Color(0xFF639922),
                            ),
                            _StatCard(
                              label: "General Wards",
                              value: generalRoomsCount.toString(),
                              icon: Icons.bed_rounded,
                              color: const Color(0xFF97C459),
                            ),
                            _StatCard(
                              label: "Total Rooms",
                              value: totalRoomsCount.toString(),
                              icon: Icons.meeting_room_outlined,
                              color: const Color(0xFF3B6D11),
                            ),
                            _StatCard(
                              label: "Available Beds",
                              value: availableBeds.toString(),
                              icon: Icons.check_circle_outline_rounded,
                              color: const Color(0xFF0F6E56),
                            ),
                          ],
                        ),
                ),
              ),

              // FLOOR OVERVIEW SECTION (Side-by-side cards)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FloorStatCard(
                          floor: 1,
                          label: "First Floor",
                          patients: floor1Patients,
                          vacantBeds: floor1VacantBeds,
                          totalRooms: floor1TotalRooms,
                          isSelected: selectedFloor == 1,
                          onTap: () => setState(() => selectedFloor = selectedFloor == 1 ? 0 : 1),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _FloorStatCard(
                          floor: 2,
                          label: "Second Floor",
                          patients: floor2Patients,
                          vacantBeds: floor2VacantBeds,
                          totalRooms: floor2TotalRooms,
                          isSelected: selectedFloor == 2,
                          onTap: () => setState(() => selectedFloor = selectedFloor == 2 ? 0 : 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // STICKY FILTER TOOLBAR
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyFilterBarDelegate(
                  height: isMobile ? 124.0 : 64.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFDF7),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                        top: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                      ),
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildSearchField(),
                              const SizedBox(height: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _buildRoomTypeFilter(),
                                      const SizedBox(width: 8),
                                      _buildFloorFilter(),
                                      const SizedBox(width: 8),
                                      _buildStatusFilter(),
                                      const SizedBox(width: 8),
                                      _buildResetButton(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildSearchField(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: _buildRoomTypeFilter(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: _buildFloorFilter(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: _buildStatusFilter(),
                              ),
                              const SizedBox(width: 12),
                              _buildResetButton(),
                            ],
                          ),
                  ),
                ),
              ),

              // MAIN AREA: GRID AND SIDEBAR
              SliverFillRemaining(
                hasScrollBody: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grid section (scrolls independently)
                    Expanded(
                      flex: 3,
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
                                    "No rooms match the criteria",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: const Color(0xFF639922).withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: _resetFilters,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text("Reset Filters"),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF3B6D11),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              key: ValueKey('${selectedRoomType}_${selectedFloor}_${selectedStatus}_$searchQuery'),
                              padding: const EdgeInsets.all(20),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: childAspectRatio,
                              ),
                              itemCount: rooms.length,
                              itemBuilder: (context, index) {
                                return RoomCard(room: rooms[index]);
                              },
                            ),
                    ),

                    // Right sidebar section (for Wide Desktop screens, scrolls independently)
                    if (isWideDesktop)
                      Container(
                        width: 320,
                        padding: const EdgeInsets.only(right: 20, top: 20, bottom: 20),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _RoomStatisticsSidebar(
                                totalRooms: totalRoomsCount,
                                privateRooms: privateRoomsCount,
                                generalRooms: generalRoomsCount,
                                totalBeds: totalBeds,
                                occupiedBeds: occupiedBeds,
                                availableBeds: availableBeds,
                                floor1Patients: floor1Patients,
                                floor2Patients: floor2Patients,
                              ),
                              const SizedBox(height: 16),
                              const CensusSummaryWidget(),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: searchController,
      onChanged: (val) => setState(() => searchQuery = val),
      decoration: InputDecoration(
        hintText: "Search rooms...",
        hintStyle: const TextStyle(color: Color(0xFF97C459), fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF639922), size: 18),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3B6D11), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildRoomTypeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedRoomType,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A), fontWeight: FontWeight.w600),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF639922), size: 18),
          items: const [
            DropdownMenuItem(value: 'all', child: Text("All Types")),
            DropdownMenuItem(value: 'private', child: Text("Private Rooms")),
            DropdownMenuItem(value: 'general', child: Text("General Wards")),
          ],
          onChanged: (val) {
            if (val != null) setState(() => selectedRoomType = val);
          },
        ),
      ),
    );
  }

  Widget _buildFloorFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedFloor,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A), fontWeight: FontWeight.w600),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF639922), size: 18),
          items: const [
            DropdownMenuItem(value: 0, child: Text("All Floors")),
            DropdownMenuItem(value: 1, child: Text("First Floor")),
            DropdownMenuItem(value: 2, child: Text("Second Floor")),
          ],
          onChanged: (val) {
            if (val != null) setState(() => selectedFloor = val);
          },
        ),
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedStatus,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A), fontWeight: FontWeight.w600),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF639922), size: 18),
          items: const [
            DropdownMenuItem(value: 'all', child: Text("All Statuses")),
            DropdownMenuItem(value: 'available', child: Text("Available")),
            DropdownMenuItem(value: 'occupied', child: Text("Full")),
            DropdownMenuItem(value: 'partially_occupied', child: Text("Partially Occupied")),
            DropdownMenuItem(value: 'pending_discharge', child: Text("Pending Discharge")),
            DropdownMenuItem(value: 'maintenance', child: Text("Maintenance")),
          ],
          onChanged: (val) {
            if (val != null) setState(() => selectedStatus = val);
          },
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return OutlinedButton.icon(
      onPressed: _resetFilters,
      icon: const Icon(Icons.refresh_rounded, size: 14),
      label: const Text("Reset"),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red.shade700,
        side: BorderSide(color: Colors.red.shade200, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.red.shade50.withOpacity(0.4),
      ),
    );
  }
}

// TOP KPI CARD
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
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF639922),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// FLOOR CARD
class _FloorStatCard extends StatelessWidget {
  final int floor;
  final String label;
  final int patients;
  final int vacantBeds;
  final int totalRooms;
  final bool isSelected;
  final VoidCallback onTap;

  const _FloorStatCard({
    required this.floor,
    required this.label,
    required this.patients,
    required this.vacantBeds,
    required this.totalRooms,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 110,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11).withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFC0DD97),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.01),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFF639922),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.layers_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFF27500A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _FloorStatItem(
                        label: "Patients",
                        value: patients,
                        color: const Color(0xFF3B6D11),
                      ),
                      const SizedBox(width: 14),
                      _FloorStatItem(
                        label: "Vacant",
                        value: vacantBeds,
                        color: const Color(0xFF0F6E56),
                      ),
                      const SizedBox(width: 14),
                      _FloorStatItem(
                        label: "Rooms",
                        value: totalRooms,
                        color: const Color(0xFF639922),
                      ),
                    ],
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

class _FloorStatItem extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _FloorStatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.1,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF639922),
          ),
        ),
      ],
    );
  }
}

// SLIVER PERSISTENT HEADER DELEGATE FOR STICKY FILTER BAR
class _StickyFilterBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _StickyFilterBarDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFF0F7EA),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyFilterBarDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

// STATS SIDEBAR PANEL
class _RoomStatisticsSidebar extends StatelessWidget {
  final int totalRooms;
  final int privateRooms;
  final int generalRooms;
  final int totalBeds;
  final int occupiedBeds;
  final int availableBeds;
  final int floor1Patients;
  final int floor2Patients;

  const _RoomStatisticsSidebar({
    required this.totalRooms,
    required this.privateRooms,
    required this.generalRooms,
    required this.totalBeds,
    required this.occupiedBeds,
    required this.availableBeds,
    required this.floor1Patients,
    required this.floor2Patients,
  });

  @override
  Widget build(BuildContext context) {
    final double occupancyRate = totalBeds > 0 ? (occupiedBeds / totalBeds) * 100 : 0.0;
    final double vacancyRate = totalBeds > 0 ? (availableBeds / totalBeds) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3DE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.insert_chart_outlined_rounded,
                  color: Color(0xFF3B6D11),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Room Statistics",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF27500A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatRow("Occupancy Rate", "${occupancyRate.toStringAsFixed(1)}%", Colors.red.shade700),
          const SizedBox(height: 10),
          _buildStatRow("Vacancy Rate", "${vacancyRate.toStringAsFixed(1)}%", const Color(0xFF3B6D11)),
          const SizedBox(height: 10),
          _buildStatRow("Private / General Rooms", "$privateRooms / $generalRooms", const Color(0xFF0F6E56)),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          const Text(
            "Patients per Floor",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF27500A),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("First Floor", style: TextStyle(fontSize: 12, color: Color(0xFF639922))),
              Text("$floor1Patients Patients", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF27500A))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Second Floor", style: TextStyle(fontSize: 12, color: Color(0xFF639922))),
              Text("$floor2Patients Patients", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF27500A))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF639922),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}