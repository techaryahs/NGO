import 'package:flutter/material.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/screens/rooms/widgets/room_details_dialog.dart';
import 'package:ngo/screens/rooms/widgets/create_stay_dialog.dart';
import 'package:ngo/screens/rooms/widgets/edit_room_dialog.dart';
import 'package:ngo/utils/bed_helper.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;

  const RoomCard({super.key, required this.room});

  void _showRoomDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => RoomDetailsDialog(room: room),
    );
  }

  void _showEditRoom(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EditRoomDialog(room: room),
    );
  }

  void _showAssignPatient(BuildContext context) {
    if (room.status == 'maintenance' || room.status == 'unavailable') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Cannot assign patient: Room is in ${room.status} state",
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    if (room.isFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cannot assign patient: Room is already full"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => CreateStayDialog(room: room),
    );
  }

  @override
  Widget build(BuildContext context) {
    final occupancyStatus = room.derivedOccupancyStatus;

    final isMaintenance = occupancyStatus == 'maintenance';
    final isFullyOccupied = occupancyStatus == 'occupied';
    final isPartialOccupied = occupancyStatus == 'partially_occupied';
    final isPendingDischarge = occupancyStatus == 'pending_discharge';

    Color borderColor;
    Color statusBgColor;
    Color statusTextColor;
    String statusText;

    if (isMaintenance) {
      borderColor = const Color(0xFFFFB74D);
      statusBgColor = const Color(0xFFFFF3E0);
      statusTextColor = const Color(0xFFE65100);
      statusText = "Maintenance";
    } else if (isFullyOccupied) {
      borderColor = const Color(0xFFE8B4B8);
      statusBgColor = const Color(0xFFFFE5E7);
      statusTextColor = const Color(0xFFD32F2F);
      statusText = "Full";
    } else if (isPartialOccupied) {
      borderColor = const Color(0xFFFFCC80);
      statusBgColor = const Color(0xFFFFF8E1);
      statusTextColor = const Color(0xFFE65100);
      statusText = "Partially Occupied";
    } else if (isPendingDischarge) {
      borderColor = const Color(0xFF90CAF9);
      statusBgColor = const Color(0xFFE3F2FD);
      statusTextColor = const Color(0xFF0D47A1);
      statusText = "Pending Discharge";
    } else {
      borderColor = const Color(0xFFC0DD97);
      statusBgColor = const Color(0xFFE8F5E0);
      statusTextColor = const Color(0xFF3B6D11);
      statusText = "Available";
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER (Room Name & Status Indicator)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        room.isPrivate
                            ? Icons.hotel_rounded
                            : Icons.bed_rounded,
                        color: const Color(0xFF27500A),
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Room ${room.roomIdentifier}",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF27500A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: statusTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // BADGES ROW (Type and Floor)
            Row(
              children: [
                _buildBadge(
                  icon: room.isPrivate
                      ? Icons.lock_outline
                      : Icons.people_outline,
                  label: room.isPrivate ? "Private" : "General",
                  bgColor: room.isPrivate
                      ? const Color(0xFFEAF3DE)
                      : const Color(0xFFE3F2FD),
                  textColor: room.isPrivate
                      ? const Color(0xFF3B6D11)
                      : const Color(0xFF1976D2),
                ),
                const SizedBox(width: 8),
                _buildBadge(
                  icon: Icons.layers_outlined,
                  label: room.floor == 1 ? "1st Floor" : "2nd Floor",
                  bgColor: const Color(0xFFF1F5F9),
                  textColor: const Color(0xFF475569),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // BED VISUALIZATION
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: room.isPrivate
                    ? _buildAttendantsVisualization()
                    : _buildBedsVisualization(),
              ),
            ),
            const SizedBox(height: 8),

            // OCCUPANCY & VACANCY ROW
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  room.isPrivate
                      ? "Attendants: ${room.currentAttendants}/${room.maxAttendants}"
                      : "Occupied: ${room.actualOccupiedBeds}/${room.actualTotalBeds}",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF639922),
                  ),
                ),
                if (room.expectedVacancyDate != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 10,
                        color: Color(0xFF97C459),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        "Vacancy: ${room.expectedVacancyDate!.day}/${room.expectedVacancyDate!.month}",
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF97C459),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),

            // QUICK ACTIONS BAR
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.visibility_outlined,
                    label: "View",
                    onTap: () => _showRoomDetails(context),
                    color: const Color(0xFF639922),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.edit_outlined,
                    label: "Edit",
                    onTap: () => _showEditRoom(context),
                    color: const Color(0xFF3B6D11),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.person_add_alt_1_outlined,
                    label: "Assign",
                    onTap: () => _showAssignPatient(context),
                    color: const Color(0xFF0F6E56),
                    isDisabled:
                        room.isFull ||
                        room.status == 'maintenance' ||
                        room.status == 'unavailable',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    bool isDisabled = false,
  }) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isDisabled ? Colors.grey.shade100 : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDisabled ? Colors.grey.shade200 : color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isDisabled ? Colors.grey.shade400 : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDisabled ? Colors.grey.shade400 : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendantsVisualization() {
    final List<Widget> chips = [];

    // Occupied attendant slots (Red)
    for (int i = 0; i < room.currentAttendants; i++) {
      chips.add(
        _buildBedChipWidget(label: "Attendant ${i + 1}", status: 'occupied'),
      );
    }

    // Available attendant slots (Green)
    final remainingSlots = room.maxAttendants - room.currentAttendants;
    for (int i = 0; i < remainingSlots; i++) {
      chips.add(
        _buildBedChipWidget(
          label: "Slot ${room.currentAttendants + i + 1}",
          status: 'available',
        ),
      );
    }

    if (chips.isEmpty) {
      return const Text(
        "No attendants configured",
        style: TextStyle(fontSize: 10, color: Colors.grey),
      );
    }

    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _buildBedsVisualization() {
    if (room.beds.isEmpty) {
      return const Text(
        "No beds tracked",
        style: TextStyle(fontSize: 10, color: Colors.grey),
      );
    }

    final Map<String, BedModel> uniqueBeds = {};
    for (final bed in room.beds) {
      final label = BedModel.formatBedLabel(
        bed.bedLabel,
        room.roomType,
        roomIdentifier: room.roomIdentifier,
      );
      final existing = uniqueBeds[label];
      if (existing == null || (!existing.isAvailable && bed.isAvailable)) {
        uniqueBeds[label] = bed;
      }
    }
    final displayBeds = uniqueBeds.values.toList();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: displayBeds.map((bed) {
        return _buildBedChipWidget(
          label: BedHelper.getBedDisplayName(
            bed.bedLabel,
            roomIdentifier: room.roomIdentifier,
          ),
          status: bed.status,
        );
      }).toList(),
    );
  }

  Widget _buildBedChipWidget({required String label, required String status}) {
    Color chipColor;
    Color borderCol;
    Color textCol;
    IconData icon;

    switch (status) {
      case 'occupied':
        chipColor = const Color(0xFFFFEBEE);
        borderCol = const Color(0xFFE57373);
        textCol = const Color(0xFFD32F2F);
        icon = Icons.bed_rounded;
        break;
      case 'reserved':
      case 'maintenance':
        chipColor = const Color(0xFFFFF3E0);
        borderCol = const Color(0xFFFFB74D);
        textCol = const Color(0xFFE65100);
        icon = Icons.build_rounded;
        break;
      default:
        chipColor = const Color(0xFFE8F5E9);
        borderCol = const Color(0xFFC5E1A5);
        textCol = const Color(0xFF558B2F);
        icon = Icons.bed_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderCol, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: textCol),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: textCol,
            ),
          ),
        ],
      ),
    );
  }
}
