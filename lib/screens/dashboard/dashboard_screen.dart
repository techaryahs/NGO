import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../models/stay_model.dart';
import '../../services/room_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Overview",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF27500A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Real-time analytics and census tracking",
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF639922),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildPrimaryStatsRow(),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _buildRecentAdmissions()),
                      const SizedBox(width: 16),
                      Expanded(flex: 1, child: _buildRoomOccupancyOverview()),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryStatsRow() {
    return StreamBuilder<Map<String, dynamic>>(
      stream: Rx.combineLatest2(
        ServiceLocator().patientService.getPatientStatsStream(),
        ServiceLocator().roomService.getFullCensusStream(),
        (Map<String, int> patientStats, Map<String, dynamic> census) {
          return {
            'activePatients': patientStats['active'] ?? 0,
            'totalInHouse': census['totalInHouse'] ?? 0,
            'vacantBeds': census['vacantBeds'] ?? 0,
            'totalPatients': patientStats['total'] ?? 0,
          };
        },
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11)));
        }

        final data = snapshot.data!;
        return Row(
          children: [
            _StatCard(
              label: "Active Patients",
              value: data['activePatients'].toString(),
              icon: Icons.person_rounded,
              color: const Color(0xFF3B6D11),
            ),
            const SizedBox(width: 16),
             _StatCard(
              label: "Total In-House",
              value: data['totalInHouse'].toString(),
              icon: Icons.groups_rounded,
              color: const Color(0xFF0F6E56),
            ),
            const SizedBox(width: 16),
             _StatCard(
              label: "Available Beds",
              value: data['vacantBeds'].toString(),
              icon: Icons.bed_rounded,
              color: const Color(0xFF1976D2),
            ),
            const SizedBox(width: 16),
             _StatCard(
              label: "Total Registered",
              value: data['totalPatients'].toString(),
              icon: Icons.assignment_ind_rounded,
              color: const Color(0xFFF57C00),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentAdmissions() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Recent Admissions",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A),
                  ),
                ),
                Icon(Icons.history_rounded, color: Color(0xFF639922), size: 20),
              ],
            ),
          ),
          StreamBuilder<List<StayModel>>(
            stream: ServiceLocator().roomService.getActiveStaysStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11))),
                );
              }

              final stays = snapshot.data ?? [];
              if (stays.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(
                    child: Text(
                      "No active stays right now.",
                      style: TextStyle(color: Color(0xFF639922)),
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stays.length > 5 ? 5 : stays.length,
                itemBuilder: (context, index) {
                  final stay = stays[index];
                  // Format Date securely without intl
                  final date = stay.admissionDate;
                  final dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                           color: index == (stays.length > 5 ? 4 : stays.length - 1)
                              ? Colors.transparent
                              : const Color(0xFFC0DD97),
                           width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFFEAF3DE),
                              radius: 18,
                              child: Text(
                                stay.patientName.isNotEmpty ? stay.patientName[0].toUpperCase() : '?',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF3B6D11)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stay.patientName,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF27500A)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Admitted: $dateStr",
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF639922)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B6D11).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "${stay.roomNumber} ${stay.roomType == 'general' ? '(Bed ${stay.bedNumber})' : '(Private)'}",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3B6D11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRoomOccupancyOverview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Room Logistics",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A),
                  ),
                ),
                Icon(Icons.meeting_room_rounded, color: Color(0xFF639922), size: 20),
              ],
            ),
          ),
          StreamBuilder<Map<String, int>>(
            stream: ServiceLocator().roomService.getRoomStatsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                 return const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF3B6D11))),
                );
              }

              final stats = snapshot.data!;
              return Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    _MiniStatRow("Total Rooms", stats['totalRooms'].toString(), Icons.domain_rounded),
                    const Divider(color: Color(0xFFC0DD97), height: 24, thickness: 0.5),
                    _MiniStatRow("Occupied Rooms", stats['occupiedRooms'].toString(), Icons.door_front_door_rounded, color: const Color(0xFFF57C00)),
                    const SizedBox(height: 12),
                    _MiniStatRow("Available Rooms", stats['availableRooms'].toString(), Icons.meeting_room_outlined, color: const Color(0xFF3B6D11)),
                    const Divider(color: Color(0xFFC0DD97), height: 24, thickness: 0.5),
                    _MiniStatRow("Total Beds", stats['totalBeds'].toString(), Icons.bed_rounded),
                    const SizedBox(height: 12),
                    _MiniStatRow("Occupied Beds", stats['occupiedBeds'].toString(), Icons.single_bed_rounded, color: const Color(0xFFD32F2F)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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

class _MiniStatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStatRow(this.label, this.value, this.icon, {this.color = const Color(0xFF27500A)});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF639922),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
