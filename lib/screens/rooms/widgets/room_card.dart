import 'package:flutter/material.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/screens/rooms/widgets/room_details_dialog.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;

  const RoomCard({super.key, required this.room});

  void _showRoomDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => RoomDetailsDialog(room: room),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOccupied = room.status == 'occupied';
    final isMaintenance = room.status == 'maintenance';
    
    Color borderColor;
    Color statusBgColor;
    Color statusTextColor;
    String statusText;
    
    if (isMaintenance) {
      borderColor = const Color(0xFFFFB74D);
      statusBgColor = const Color(0xFFFFF3E0);
      statusTextColor = const Color(0xFFE65100);
      statusText = "Maintenance";
    } else if (isOccupied) {
      borderColor = const Color(0xFFE8B4B8);
      statusBgColor = const Color(0xFFFFE5E7);
      statusTextColor = const Color(0xFFD32F2F);
      statusText = "Occupied";
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
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showRoomDetails(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "Room ${room.roomNumber}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF27500A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Room Type Badge
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: room.isPrivate 
                        ? const Color(0xFFEAF3DE) 
                        : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        room.isPrivate ? Icons.hotel_rounded : Icons.bed_rounded,
                        size: 12,
                        color: room.isPrivate 
                            ? const Color(0xFF3B6D11) 
                            : const Color(0xFF1976D2),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        room.isPrivate ? "Private" : "General",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: room.isPrivate 
                              ? const Color(0xFF3B6D11) 
                              : const Color(0xFF1976D2),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // Details
                if (room.isPrivate) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.people_outline_rounded,
                        size: 16,
                        color: Color(0xFF639922),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Attendants: ${room.currentAttendants}/${room.maxAttendants}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF639922),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.bed_outlined,
                        size: 16,
                        color: Color(0xFF639922),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Beds: ${room.occupiedBeds}/${room.totalBeds}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF639922),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.layers_outlined,
                      size: 16,
                      color: Color(0xFF639922),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Floor ${room.floor}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF639922),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
