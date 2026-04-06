import 'package:flutter/material.dart';
import '../rooms_page.dart';

class RoomCard extends StatelessWidget {
  final RoomData room;

  const RoomCard({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: room.isOccupied 
              ? const Color(0xFFE8B4B8) 
              : const Color(0xFFC0DD97),
          width: 1.5,
        ),
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
          onTap: () {
            // Room details action
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Room ${room.roomNumber}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: room.isOccupied
                            ? const Color(0xFFFFE5E7)
                            : const Color(0xFFE8F5E0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        room.isOccupied ? "Occupied" : "Available",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: room.isOccupied
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF3B6D11),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 16,
                      color: const Color(0xFF639922),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Capacity: ${room.capacity}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF639922),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.layers_outlined,
                      size: 16,
                      color: const Color(0xFF639922),
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
