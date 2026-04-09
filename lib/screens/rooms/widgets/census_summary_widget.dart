import 'package:flutter/material.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/widgets/animated_counter.dart';

/// Census Summary Widget - Real-time in-house analytics
/// 
/// Displays:
/// - Total Patients (count of all occupied beds)
/// - Total Attendants (sum from all active Private Room stays)
/// - Total In-House (Patients + Attendants)
/// - Vacant Beds (total available beds)
/// - Per-Floor breakdown
class CensusSummaryWidget extends StatelessWidget {
  const CensusSummaryWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final roomService = ServiceLocator().roomService;

    return StreamBuilder<List<RoomModel>>(
      stream: roomService.getRoomsStream(),
      builder: (context, roomsSnapshot) {
        return StreamBuilder<Map<String, dynamic>>(
          stream: roomService.getFullCensusStream(),
          builder: (context, censusSnapshot) {
            if ((roomsSnapshot.connectionState == ConnectionState.waiting || 
                 censusSnapshot.connectionState == ConnectionState.waiting) &&
                !roomsSnapshot.hasData && !censusSnapshot.hasData) {
              return const _LoadingCard();
            }

            final census = censusSnapshot.data ?? {
              'totalPatients': 0,
              'totalAttendants': 0,
              'totalInHouse': 0,
              'vacantBeds': 0,
            };

            final rooms = roomsSnapshot.data ?? [];

            // Calculate per-floor stats
            final floor1Rooms = rooms.where((r) => r.floor == 1).toList();
            final floor2Rooms = rooms.where((r) => r.floor == 2).toList();

            final floor1Patients = floor1Rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualOccupiedBeds) +
                floor1Rooms.where((r) => r.isPrivate && r.isOccupied).length;
            final floor1VacantBeds = floor1Rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualAvailableBeds);

            final floor2Patients = floor2Rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualOccupiedBeds) +
                floor2Rooms.where((r) => r.isPrivate && r.isOccupied).length;
            final floor2VacantBeds = floor2Rooms.where((r) => r.isGeneral).fold(0, (sum, r) => sum + r.actualAvailableBeds);

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3DE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.analytics_rounded,
                            color: Color(0xFF3B6D11),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Census Summary",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF27500A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Overall Stats Grid
                    Row(
                      children: [
                        Expanded(
                          child: _CensusStatCard(
                            label: "Patients",
                            value: census['totalPatients'] ?? 0,
                            icon: Icons.person_rounded,
                            color: const Color(0xFF3B6D11),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CensusStatCard(
                            label: "Attendants",
                            value: census['totalAttendants'] ?? 0,
                            icon: Icons.people_rounded,
                            color: const Color(0xFF639922),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _CensusStatCard(
                            label: "In-House",
                            value: census['totalInHouse'] ?? 0,
                            icon: Icons.home_rounded,
                            color: const Color(0xFF0F6E56),
                            isHighlighted: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CensusStatCard(
                            label: "Vacant Beds",
                            value: census['vacantBeds'] ?? 0,
                            icon: Icons.bed_outlined,
                            color: const Color(0xFF97C459),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Divider
                    Container(
                      height: 1,
                      color: const Color(0xFFC0DD97),
                    ),
                    const SizedBox(height: 16),

                    // Per-Floor Breakdown
                    const Text(
                      "Floor Breakdown",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Floor 1 Stats
                    _FloorCensusCard(
                      floor: 1,
                      label: "Ground Floor",
                      rooms: RoomModel.floor1Rooms,
                      patients: floor1Patients,
                      vacantBeds: floor1VacantBeds,
                    ),
                    const SizedBox(height: 10),

                    // Floor 2 Stats
                    _FloorCensusCard(
                      floor: 2,
                      label: "First Floor",
                      rooms: RoomModel.floor2Rooms,
                      patients: floor2Patients,
                      vacantBeds: floor2VacantBeds,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CensusStatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool isHighlighted;

  const _CensusStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withOpacity(0.1) : const Color(0xFFF4F9F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted ? color : const Color(0xFFC0DD97),
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF639922),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedCounterWithScale(
            value: value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorCensusCard extends StatelessWidget {
  final int floor;
  final String label;
  final List<String> rooms;
  final int patients;
  final int vacantBeds;

  const _FloorCensusCard({
    required this.floor,
    required this.label,
    required this.rooms,
    required this.patients,
    required this.vacantBeds,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: floor == 1 
                            ? const Color(0xFF3B6D11).withOpacity(0.1)
                            : const Color(0xFF639922).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.layers_rounded,
                        size: 16,
                        color: floor == 1 
                            ? const Color(0xFF3B6D11)
                            : const Color(0xFF639922),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF27500A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Room identifiers
              Text(
                rooms.join(", "),
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF97C459),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FloorStatItem(
                  label: "Patients",
                  value: patients,
                  color: const Color(0xFF3B6D11),
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: const Color(0xFFC0DD97),
              ),
              Expanded(
                child: _FloorStatItem(
                  label: "Vacant",
                  value: vacantBeds,
                  color: const Color(0xFF0F6E56),
                ),
              ),
            ],
          ),
        ],
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
      children: [
        AnimatedCounter(
          value: value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
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

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B6D11)),
          ),
        ),
      ),
    );
  }
}