import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../models/stay_model.dart';
import '../../services/room_service.dart';
import '../../utils/bed_helper.dart';
import '../../models/notification_model.dart';
import '../../utils/responsive_layout.dart';

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
                  _buildAlertsSection(),
                  const SizedBox(height: 24),
                  ResponsiveLayout(
                    mobile: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRecentAdmissions(),
                        const SizedBox(height: 16),
                        _buildRoomOccupancyOverview(),
                      ],
                    ),
                    tablet: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRecentAdmissions(),
                        const SizedBox(height: 16),
                        _buildRoomOccupancyOverview(),
                      ],
                    ),
                    desktop: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildRecentAdmissions()),
                        const SizedBox(width: 16),
                        Expanded(flex: 1, child: _buildRoomOccupancyOverview()),
                      ],
                    ),
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
      stream: RoomService.combineLatest2(
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
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(
              label: "Active Patients",
              value: data['activePatients'].toString(),
              icon: Icons.person_rounded,
              color: const Color(0xFF3B6D11),
            ),
             _StatCard(
              label: "Total In-House",
              value: data['totalInHouse'].toString(),
              icon: Icons.groups_rounded,
              color: const Color(0xFF0F6E56),
            ),
             _StatCard(
              label: "Available Beds",
              value: data['vacantBeds'].toString(),
              icon: Icons.bed_rounded,
              color: const Color(0xFF1976D2),
            ),
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

  Widget _buildAlertsSection() {
    return StreamBuilder<List<NotificationModel>>(
      stream: ServiceLocator().notificationService.getNotificationsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final notifications = snapshot.data!;
        if (notifications.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD32F2F).withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 24),
                  SizedBox(width: 10),
                  Text(
                    "Action Needed",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD32F2F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: notifications.length > 3 ? 3 : notifications.length,
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  final isPayment = notification.type == NotificationType.paymentPending;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isPayment ? Icons.payment_rounded : Icons.calendar_today_rounded,
                          color: isPayment ? const Color(0xFFD32F2F) : const Color(0xFFF57C00),
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                notification.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF27500A),
                                ),
                              ),
                              Text(
                                notification.message,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF639922)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (notifications.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    "+ ${notifications.length - 3} more alerts in notifications panel",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFF57C00),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
            ],
          ),
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

              final allStays = snapshot.data ?? [];

// Remove duplicate patients
              final uniqueMap = <String, StayModel>{};

              for (final stay in allStays) {
                uniqueMap[stay.patientId] = stay;
              }

              final stays = uniqueMap.values.toList();
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
                            stay.roomType == 'general'
                                ? "${stay.roomNumber} (${BedHelper.getBedDisplayName(stay.bedNumber.toString().trim())})"
                                : "${stay.roomNumber} (Private)",
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
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 220,
        minHeight: 120,
      ),
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
          mainAxisSize: MainAxisSize.min,
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
                mainAxisSize: MainAxisSize.min,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
