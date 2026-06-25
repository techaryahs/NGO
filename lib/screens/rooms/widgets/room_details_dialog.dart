import 'package:flutter/material.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/screens/rooms/widgets/create_stay_dialog.dart';
import 'package:ngo/screens/rooms/widgets/extend_stay_dialog.dart';
import 'package:ngo/utils/bed_helper.dart';

class RoomDetailsDialog extends StatelessWidget {
  final RoomModel room;

  const RoomDetailsDialog({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final roomService = ServiceLocator().roomService;
    final isLobbyRoom = BedHelper.isLobbyRoom(room.roomIdentifier);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 750,
        constraints: const BoxConstraints(maxHeight: 750),
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
                        room.isPrivate
                            ? Icons.hotel_rounded
                            : Icons.bed_rounded,
                        color: const Color(0xFF3B6D11),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Room ${room.roomIdentifier}",
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

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Room Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F9F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFC0DD97),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _InfoItem(
                              label: "Status",
                              value: _formatStatus(room.derivedOccupancyStatus),
                              icon: Icons.info_outline_rounded,
                              isStatus: true,
                            ),
                          ),
                          if (room.isPrivate)
                            Expanded(
                              child: _InfoItem(
                                label: "Attendants",
                                value:
                                    "${room.currentAttendants}/${room.maxAttendants}",
                                icon: Icons.people_outline_rounded,
                              ),
                            )
                          else
                            Expanded(
                              child: _InfoItem(
                                label: "Beds",
                                value:
                                    "${room.actualOccupiedBeds}/${room.actualTotalBeds}",
                                icon: Icons.bed_outlined,
                              ),
                            ),
                          if (isLobbyRoom)
                            const Expanded(
                              child: _InfoItem(
                                label: "Lobbies",
                                value: "2",
                                icon: Icons.weekend_outlined,
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

                    // Hierarchical Bed Display for all rooms with beds
                    if (room.beds.isNotEmpty) ...[
                      const Text(
                        "Bed Status",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF27500A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _BedStatusGrid(
                        beds: room.beds,
                        roomType: room.roomType,
                        roomIdentifier: room.roomIdentifier,
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (isLobbyRoom) ...[
                      const Text(
                        "Lobbies",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF27500A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _LobbyStatusCard(label: 'Lobby 1', status: 'lobby'),
                          _LobbyStatusCard(label: 'Lobby 2', status: 'lobby'),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

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
                        if (room.isDerivedAvailable || room.isPartiallyOccupied)
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    CreateStayDialog(room: room),
                              );
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text("Create Stay"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B6D11),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Stays List
                    StreamBuilder<List<StayModel>>(
                      stream: roomService.getStaysByRoomStream(room.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
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
                                  color: const Color(
                                    0xFF639922,
                                  ).withOpacity(0.3),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "No active stays in this room",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: const Color(
                                      0xFF639922,
                                    ).withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: stays.length,
                          itemBuilder: (context, index) {
                            final stay = stays[index];
                            return _StayCard(
                              stay: stay,
                              roomType: room.roomType,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    return status
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

/// Bed Status Grid - Shows all beds with their status
class _BedStatusGrid extends StatelessWidget {
  final List<BedModel> beds;
  final String roomType;
  final String roomIdentifier;

  const _BedStatusGrid({
    required this.beds,
    required this.roomType,
    required this.roomIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, BedModel> uniqueBeds = {};
    for (final bed in beds) {
      final label = BedModel.formatBedLabel(
        bed.bedLabel,
        roomType,
        roomIdentifier: roomIdentifier,
      );
      final existing = uniqueBeds[label];
      if (existing == null || (existing.isAvailable && !bed.isAvailable)) {
        uniqueBeds[label] = bed;
      }
    }
    final displayBeds = uniqueBeds.values.toList();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: displayBeds
          .map(
            (bed) => _BedStatusCard(
              bed: bed,
              roomType: roomType,
              roomIdentifier: roomIdentifier,
            ),
          )
          .toList(),
    );
  }
}

class _LobbyStatusCard extends StatelessWidget {
  final String label;
  final String status;

  const _LobbyStatusCard({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final isOccupied = status == 'occupied';
    final isLobby = status == 'lobby';
    final bgColor = isLobby
        ? const Color(0xFFE3F2FD)
        : isOccupied
        ? const Color(0xFFFFE5E7)
        : const Color(0xFFE8F5E0);
    final textColor = isLobby
        ? const Color(0xFF1976D2)
        : isOccupied
        ? const Color(0xFFD32F2F)
        : const Color(0xFF3B6D11);
    final borderColor = isLobby
        ? const Color(0xFF90CAF9)
        : isOccupied
        ? const Color(0xFFE8B4B8)
        : const Color(0xFFC0DD97);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.weekend_outlined, size: 15, color: textColor),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              Text(
                isLobby ? 'LOBBY' : status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: textColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual Bed Status Card
class _BedStatusCard extends StatelessWidget {
  final BedModel bed;
  final String roomType;
  final String roomIdentifier;

  const _BedStatusCard({
    required this.bed,
    required this.roomType,
    required this.roomIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Color borderColor;
    IconData icon;

    switch (bed.status) {
      case 'occupied':
        bgColor = const Color(0xFFFFE5E7);
        textColor = const Color(0xFFD32F2F);
        borderColor = const Color(0xFFE8B4B8);
        icon = Icons.bed_rounded;
        break;
      case 'maintenance':
        bgColor = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE65100);
        borderColor = const Color(0xFFFFB74D);
        icon = Icons.build_rounded;
        break;
      default:
        bgColor = const Color(0xFFE8F5E0);
        textColor = const Color(0xFF3B6D11);
        borderColor = const Color(0xFFC0DD97);
        icon = Icons.bed_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: textColor),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                BedHelper.getBedDisplayName(
                  bed.bedLabel.toString(),
                  roomIdentifier: roomIdentifier,
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              Text(
                bed.status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: textColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isStatus;

  const _InfoItem({
    required this.label,
    required this.value,
    required this.icon,
    this.isStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF639922)),
        const SizedBox(height: 6),
        if (isStatus)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3DE),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF27500A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF27500A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF639922)),
        ),
      ],
    );
  }
}

class _StayCard extends StatelessWidget {
  final StayModel stay;
  final String roomType;

  const _StayCard({required this.stay, required this.roomType});

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
        content: Text(
          "Are you sure you want to complete the stay for ${stay.patientName}?",
        ),
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
                    if (stay.bedId != null || stay.bedNumber != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.bed_outlined,
                            size: 14,
                            color: Color(0xFF639922),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            BedHelper.getBedDisplayName(
                              (stay.bedNumber ??
                                      stay.bedId?.split('_').last ??
                                      'N/A')
                                  .toString(),
                              roomIdentifier: stay.roomNumber,
                            ),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                value:
                    "${stay.admissionDate.day}/${stay.admissionDate.month}/${stay.admissionDate.year}",
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
              style: const TextStyle(fontSize: 10, color: Color(0xFF97C459)),
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
