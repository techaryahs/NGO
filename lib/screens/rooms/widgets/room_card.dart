import 'package:flutter/material.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/screens/rooms/widgets/room_details_dialog.dart';
import 'package:ngo/services/service_locator.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;

  const RoomCard({super.key, required this.room});

  void _showRoomDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => RoomDetailsDialog(room: room),
    );
  }

  void _showRoomMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _RoomMenuSheet(room: room),
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
                        "Room ${room.roomIdentifier}",
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
                    const SizedBox(width: 4),
                    // Three-dot menu
                    InkWell(
                      onTap: () => _showRoomMenu(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: const Color(0xFF639922),
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
                
                // Hierarchical Bed Display for General Rooms
                if (room.isGeneral && room.beds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _BedGrid(beds: room.beds),
                ] else if (room.isPrivate) ...[
                  // Private room attendants
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
                  // Legacy general room without beds
                  Row(
                    children: [
                      const Icon(
                        Icons.bed_outlined,
                        size: 16,
                        color: Color(0xFF639922),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Beds: ${room.actualOccupiedBeds}/${room.actualTotalBeds}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF639922),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                // Floor badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: room.floor == 1 
                        ? const Color(0xFF3B6D11).withOpacity(0.1)
                        : const Color(0xFF639922).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.layers_rounded,
                        size: 12,
                        color: room.floor == 1 
                            ? const Color(0xFF3B6D11)
                            : const Color(0xFF639922),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        room.floor == 1 ? "Ground" : "Floor 2",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: room.floor == 1 
                              ? const Color(0xFF3B6D11)
                              : const Color(0xFF639922),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bed Grid Widget - Shows individual beds with color-coded status
class _BedGrid extends StatelessWidget {
  final List<BedModel> beds;

  const _BedGrid({required this.beds});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: beds.map((bed) => _BedChip(bed: bed)).toList(),
    );
  }
}

/// Individual Bed Chip with status color
class _BedChip extends StatelessWidget {
  final BedModel bed;

  const _BedChip({required this.bed});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            bed.bedLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Room Menu Sheet - Options for soft/hard delete
class _RoomMenuSheet extends StatelessWidget {
  final RoomModel room;

  const _RoomMenuSheet({required this.room});

  Future<void> _softDelete(BuildContext context) async {
    // Store the navigator before async operations
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    navigator.pop(); // Close menu
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Room as Unavailable?'),
        content: Text(
          'Room ${room.roomIdentifier} will be marked as unavailable but not deleted. '
          'You can reactivate it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB74D),
              foregroundColor: Colors.white,
            ),
            child: const Text('Mark Unavailable'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ServiceLocator().roomService.updateRoom(room.id, {
          'status': 'unavailable',
        });
        
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Room ${room.roomIdentifier} marked as unavailable'),
            backgroundColor: const Color(0xFFFFB74D),
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to update room: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _hardDelete(BuildContext context) async {
    // Store the navigator before async operations
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    navigator.pop(); // Close menu
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room Permanently?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Room ${room.roomIdentifier} will be permanently deleted. '
              'This action cannot be undone.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warning: This will permanently delete all room data.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Show loading indicator
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Text('Deleting room ${room.roomIdentifier}...'),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      
      try {
        await ServiceLocator().roomService.deleteRoom(room.id);
        
        // Small delay to ensure database update propagates
        await Future.delayed(const Duration(milliseconds: 500));
        
        scaffoldMessenger.clearSnackBars();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('Room ${room.roomIdentifier} deleted permanently'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        scaffoldMessenger.clearSnackBars();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to delete room: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _hardDelete(context),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3DE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      room.isPrivate ? Icons.hotel_rounded : Icons.bed_rounded,
                      color: const Color(0xFF3B6D11),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Room ${room.roomIdentifier}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        Text(
                          '${room.isPrivate ? "Private" : "General"} • Floor ${room.floor}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF639922),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Menu options
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: Color(0xFFE65100),
                  size: 20,
                ),
              ),
              title: const Text(
                'Mark as Unavailable',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Soft delete - Can be reactivated later',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => _softDelete(context),
            ),
            
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.red.shade700,
                  size: 20,
                ),
              ),
              title: Text(
                'Delete Permanently',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
              subtitle: const Text(
                'Hard delete - Cannot be undone',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => _hardDelete(context),
            ),
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}