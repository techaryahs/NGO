import 'package:flutter/material.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/services/service_locator.dart';

class EditRoomDialog extends StatefulWidget {
  final RoomModel room;

  const EditRoomDialog({super.key, required this.room});

  @override
  State<EditRoomDialog> createState() => _EditRoomDialogState();
}

class _EditRoomDialogState extends State<EditRoomDialog> {
  final TextEditingController notesController = TextEditingController();
  final TextEditingController maxAttendantsController = TextEditingController();
  
  late String selectedStatus;
  late int bedCount;
  late int maxAttendants;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    notesController.text = widget.room.notes ?? '';
    selectedStatus = widget.room.status;
    maxAttendants = widget.room.maxAttendants;
    bedCount = widget.room.actualTotalBeds;
    maxAttendantsController.text = maxAttendants.toString();
  }

  @override
  void dispose() {
    notesController.dispose();
    maxAttendantsController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => isLoading = true);

    try {
      final roomService = ServiceLocator().roomService;
      final Map<String, dynamic> updates = {
        'status': selectedStatus,
        'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      };

      if (widget.room.isPrivate) {
        final parsedAttendants = int.tryParse(maxAttendantsController.text) ?? widget.room.maxAttendants;
        updates['maxAttendants'] = parsedAttendants;
      } else {
        // Adjust general room beds
        final currentBeds = List<BedModel>.from(widget.room.beds);
        
        if (bedCount > currentBeds.length) {
          // Add extra beds
          for (int i = currentBeds.length + 1; i <= bedCount; i++) {
            currentBeds.add(BedModel.create(roomId: widget.room.id, bedLabel: 'bed$i'));
          }
        } else if (bedCount < currentBeds.length) {
          // Remove available beds starting from the end
          int toRemove = currentBeds.length - bedCount;
          
          // Check if we can safely remove them (are there enough available beds?)
          final availableBeds = currentBeds.where((b) => b.isAvailable).toList();
          if (availableBeds.length < toRemove) {
            throw Exception('Cannot reduce bed count. Some beds are occupied/maintenance and cannot be removed.');
          }

          for (int i = currentBeds.length - 1; i >= 0 && toRemove > 0; i--) {
            if (currentBeds[i].isAvailable) {
              currentBeds.removeAt(i);
              toRemove--;
            }
          }
        }

        updates['beds'] = currentBeds.map((b) => b.toMap()).toList();
        updates['totalBeds'] = currentBeds.length;
      }

      await roomService.updateRoom(widget.room.id, updates);
      
      // Update room status metadata
      await roomService.updateRoomStatus(widget.room.id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Room ${widget.room.roomIdentifier} updated successfully"),
            backgroundColor: const Color(0xFF3B6D11),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update room: $e"),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        ),
        child: SingleChildScrollView(
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
                        child: const Icon(
                          Icons.edit_note_rounded,
                          color: Color(0xFF3B6D11),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Edit Room ${widget.room.roomIdentifier}",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF27500A),
                        ),
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

              // Room Status Selection
              const Text(
                "ROOM STATUS",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F9F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedStatus,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'available',
                        child: Text("Available"),
                      ),
                      DropdownMenuItem(
                        value: 'maintenance',
                        child: Text("Maintenance"),
                      ),
                      DropdownMenuItem(
                        value: 'unavailable',
                        child: Text("Unavailable"),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedStatus = value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Capacity Section
              if (widget.room.isPrivate) ...[
                const Text(
                  "MAX ATTENDANTS",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        final current = int.tryParse(maxAttendantsController.text) ?? widget.room.maxAttendants;
                        if (current > 1) {
                          setState(() {
                            maxAttendantsController.text = (current - 1).toString();
                          });
                        }
                      },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      color: const Color(0xFF639922),
                    ),
                    Expanded(
                      child: TextField(
                        controller: maxAttendantsController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF4F9F0),
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        final current = int.tryParse(maxAttendantsController.text) ?? widget.room.maxAttendants;
                        setState(() {
                          maxAttendantsController.text = (current + 1).toString();
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: const Color(0xFF639922),
                    ),
                  ],
                ),
              ] else ...[
                const Text(
                  "NUMBER OF BEDS",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (bedCount > 1) {
                          // Check if we can decrease
                          final occupied = widget.room.actualOccupiedBeds;
                          if (bedCount - 1 < occupied) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Cannot reduce below currently occupied beds"),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          setState(() => bedCount--);
                        }
                      },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      color: const Color(0xFF639922),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F9F0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                        ),
                        child: Text(
                          "$bedCount",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF27500A),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => bedCount++);
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: const Color(0xFF639922),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // Notes (optional)
              const Text(
                "NOTES (OPTIONAL)",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "Add any additional notes...",
                  hintStyle: const TextStyle(
                    color: Color(0xFF97C459),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4F9F0),
                  contentPadding: const EdgeInsets.all(12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFFC0DD97),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF639922),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF639922),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text("Cancel"),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : _handleSave,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(isLoading ? "Saving..." : "Save Changes"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B6D11),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
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
        ),
      ),
    );
  }
}
