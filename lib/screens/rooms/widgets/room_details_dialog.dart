import 'package:flutter/material.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/screens/rooms/widgets/create_stay_dialog.dart';
import 'package:ngo/screens/rooms/widgets/extend_stay_dialog.dart';

class RoomDetailsDialog extends StatelessWidget {
  final RoomModel room;

  const RoomDetailsDialog({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final roomService = ServiceLocator().roomService;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 700),
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
                      child: Icon(
                        room.isPrivate ? Icons.hotel_rounded : Icons.bed_rounded,
                        color: const Color(0xFF3B6D11),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Room ${room.roomNumber}",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        Text(
                          "${room.isPrivate ? 'Private' : 'General'} Room • Floor ${room.floor}",
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

            // Room Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F9F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC0DD97), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _InfoItem(
                      label: "Status",
                      value: room.status.toUpperCase(),
                      icon: Icons.info_outline_rounded,
                    ),
                  ),
                  if (room.isPrivate)
                    Expanded(
                      child: _InfoItem(
                        label: "Attendants",
                        value: "${room.currentAttendants}/${room.maxAttendants}",
                        icon: Icons.people_outline_rounded,
                      ),
                    )
                  else
                    Expanded(
                      child: _InfoItem(
                        label: "Beds",
                        value: "${room.occupiedBeds}/${room.totalBeds}",
                        icon: Icons.bed_outlined,
                      ),
                    ),
                  Expanded(
                    child: _InfoItem(
                      label: "Floor",
                      value: "${room.floor}",
                      icon: Icons.layers_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Active Stays Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Active Stays",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF27500A),
                  ),
                ),
                if (room.isAvailable || (room.isGeneral && room.hasAvailableBeds))
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (context) => CreateStayDialog(room: room),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text("Create Stay"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B6D11),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Stays List
            Expanded(
              child: StreamBuilder<List<StayModel>>(
                stream: roomService.getStaysByRoomStream(room.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final stays = snapshot.data ?? [];

                  if (stays.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy_rounded,
                            size: 48,
                            color: const Color(0xFF639922).withOpacity(0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "No active stays in this room",
                            style: TextStyle(
                              fontSize: 14,
                              color: const Color(0xFF639922).withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: stays.length,
                    itemBuilder: (context, index) {
                      final stay = stays[index];
                      return _StayCard(stay: stay);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF639922)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF27500A),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF639922),
          ),
        ),
      ],
    );
  }
}

class _StayCard extends StatelessWidget {
  final StayModel stay;

  const _StayCard({required this.stay});

  void _showExtendDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ExtendStayDialog(stay: stay),
    );
  }

  Future<void> _completeStay(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Complete Stay"),
        content: Text("Are you sure you want to complete the stay for ${stay.patientName}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B6D11),
            ),
            child: const Text("Complete"),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator().roomService.completeStay(stay.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Stay completed successfully"),
              backgroundColor: Color(0xFF3B6D11),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to complete stay: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysLeft = stay.daysRemaining;
    final isExpiringSoon = daysLeft <= 3 && daysLeft > 0;
    final isExpired = daysLeft < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpired
              ? const Color(0xFFE8B4B8)
              : isExpiringSoon
                  ? const Color(0xFFFFB74D)
                  : const Color(0xFFC0DD97),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stay.patientName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (stay.bedNumber != null)
                      Text(
                        "Bed ${stay.bedNumber}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF639922),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isExpired
                      ? const Color(0xFFFFE5E7)
                      : isExpiringSoon
                          ? const Color(0xFFFFF3E0)
                          : const Color(0xFFE8F5E0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isExpired
                      ? "EXPIRED"
                      : isExpiringSoon
                          ? "$daysLeft days left"
                          : "$daysLeft days left",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isExpired
                        ? const Color(0xFFD32F2F)
                        : isExpiringSoon
                            ? const Color(0xFFE65100)
                            : const Color(0xFF3B6D11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StayDetail(
                icon: Icons.calendar_today_rounded,
                label: "Admission",
                value: "${stay.admissionDate.day}/${stay.admissionDate.month}/${stay.admissionDate.year}",
              ),
              const SizedBox(width: 16),
              _StayDetail(
                icon: Icons.event_rounded,
                label: "Duration",
                value: "${stay.totalDays} days",
              ),
              const SizedBox(width: 16),
              _StayDetail(
                icon: Icons.people_outline_rounded,
                label: "Attendants",
                value: "${stay.attendantCount}",
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _showExtendDialog(context),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text("Extend"),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3B6D11),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _completeStay(context),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: const Text("Complete"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B6D11),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StayDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StayDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF639922)),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF97C459),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
