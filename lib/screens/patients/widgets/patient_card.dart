import 'package:flutter/material.dart';
import '../../../models/patient_model.dart';

class PatientCard extends StatelessWidget {
  final PatientModel patient;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDischarge;

  const PatientCard({
    super.key,
    required this.patient,
    this.onTap,
    this.onEdit,
    this.onDischarge,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = patient.status == 'active';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFC0DD97),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B6D11).withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isActive 
                        ? const Color(0xFFEAF3DE)
                        : const Color(0xFFE8E8E8),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive 
                          ? const Color(0xFF97C459)
                          : const Color(0xFFBDBDBD),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(patient.fullName),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isActive 
                            ? const Color(0xFF3B6D11)
                            : const Color(0xFF757575),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Patient Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              patient.fullName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF27500A),
                              ),
                            ),
                          ),
                          _StatusBadge(status: patient.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _InfoChip(
                            icon: Icons.cake_outlined,
                            label: '${patient.age} years',
                          ),
                          const SizedBox(width: 8),
                          _InfoChip(
                            icon: Icons.phone_outlined,
                            label: patient.contactNumber,
                          ),
                          if (patient.roomNumber != null) ...[
                            const SizedBox(width: 8),
                            _InfoChip(
                              icon: Icons.meeting_room_outlined,
                              label: 'Room ${patient.roomNumber}',
                              color: const Color(0xFF3B6D11),
                            ),
                          ],
                          if (patient.bedLabels != null && patient.bedLabels!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _InfoChip(
                              icon: Icons.bed_outlined,
                              label: patient.bedLabels!.join(", "),
                              color: const Color(0xFF3B6D11),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        patient.medicalCondition,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF639922),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                
                // Actions
                if (isActive) ...[
                  const SizedBox(width: 12),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: Color(0xFF639922),
                      size: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onSelected: (value) {
                      if (value == 'edit' && onEdit != null) {
                        onEdit!();
                      } else if (value == 'discharge' && onDischarge != null) {
                        onDischarge!();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B6D11)),
                            SizedBox(width: 8),
                            Text('Edit Details'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'discharge',
                        child: Row(
                          children: [
                            Icon(Icons.logout_rounded, size: 18, color: Color(0xFFD32F2F)),
                            SizedBox(width: 8),
                            Text('Discharge'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'active':
        bgColor = const Color(0xFFEAF3DE);
        textColor = const Color(0xFF3B6D11);
        label = 'Active';
        break;
      case 'discharged':
        bgColor = const Color(0xFFE8E8E8);
        textColor = const Color(0xFF757575);
        label = 'Discharged';
        break;
      default:
        bgColor = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE65100);
        label = 'Transferred';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? const Color(0xFF639922);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: chipColor.withOpacity(0.7)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: chipColor,
          ),
        ),
      ],
    );
  }
}
