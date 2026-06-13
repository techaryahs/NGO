import 'package:flutter/material.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/models/room_config.dart';
import 'package:ngo/screens/rooms/widgets/add_room_dialog_components.dart';

class AddRoomDialog extends StatefulWidget {
  final int selectedFloor;

  const AddRoomDialog({super.key, required this.selectedFloor});

  @override
  State<AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<AddRoomDialog> {
  final TextEditingController notesController = TextEditingController();
  final TextEditingController bedLabelsController = TextEditingController();
  final TextEditingController bedCountController = TextEditingController();

  String selectedRoomType = 'private'; // 'private' or 'general'
  int selectedFloor = 1;
  String? selectedRoomIdentifier; // Dropdown selection
  int bedCount = 4;
  bool useCustomBedLabels = false;
  bool isLoading = false;
  RoomConfig? roomConfig;
  bool configLoading = true;
  List<String> existingRoomIdentifiers = []; // Track already added rooms

  @override
  void initState() {
    super.initState();
    selectedFloor = widget.selectedFloor.clamp(1, 2);
    bedCountController.text = '4';
    _loadRoomConfig();
    _loadExistingRooms();
  }

  @override
  void dispose() {
    notesController.dispose();
    bedLabelsController.dispose();
    bedCountController.dispose();
    super.dispose();
  }

  /// Load room configuration from JSON
  Future<void> _loadRoomConfig() async {
    try {
      final config = await RoomConfig.load();
      setState(() {
        roomConfig = config;
        configLoading = false;
      });
    } catch (e) {
      setState(() {
        configLoading = false;
      });
      if (mounted) {
        _showSnackBar("Failed to load room configuration: $e", isError: true);
      }
    }
  }

  /// Load existing rooms from database to filter them out
  Future<void> _loadExistingRooms() async {
    try {
      final roomService = ServiceLocator().roomService;
      final rooms = await roomService.getRoomsStream().first;
      setState(() {
        existingRoomIdentifiers = rooms.map((r) => r.roomIdentifier).toList();
      });
    } catch (e) {
      // Silently fail - worst case, user might see already added rooms
    }
  }

  /// Get available room identifiers based on floor and room type
  /// Filters out rooms that have already been added
  List<String> _getAvailableRooms() {
    if (roomConfig == null) return [];
    final allRooms = roomConfig!.getAvailableRooms(
      floor: selectedFloor,
      roomType: selectedRoomType,
    );
    // Filter out rooms that already exist in the database
    return allRooms
        .where((room) => !existingRoomIdentifiers.contains(room))
        .toList();
  }

  /// Handle floor change - reset room identifier
  void _onFloorChanged(int floor) {
    setState(() {
      selectedFloor = floor;
      selectedRoomIdentifier = null; // Reset room selection
    });
  }

  /// Handle room type change - reset room identifier
  void _onRoomTypeChanged(String type) {
    setState(() {
      selectedRoomType = type;
      selectedRoomIdentifier = null; // Reset room selection

      // Set default bed count based on type
      if (type == 'private') {
        bedCount = 2;
        bedCountController.text = '2';
      } else {
        bedCount = 4;
        bedCountController.text = '4';
      }
    });
  }

  /// Handle room identifier selection - auto-populate bed count
  void _onRoomIdentifierChanged(String? identifier) {
    if (identifier == null || roomConfig == null) return;

    setState(() {
      selectedRoomIdentifier = identifier;

      // Auto-populate bed count from config
      final defaultBeds = roomConfig!.getDefaultBedCount(identifier);
      bedCount = defaultBeds;
      bedCountController.text = defaultBeds.toString();
    });
  }

  Future<void> _handleAdd() async {
    if (selectedRoomIdentifier == null) {
      _showSnackBar("Please select a room identifier", isError: true);
      return;
    }

    // Validate room configuration
    if (roomConfig != null &&
        !roomConfig!.isValidRoom(
          roomIdentifier: selectedRoomIdentifier!,
          floor: selectedFloor,
          roomType: selectedRoomType,
        )) {
      _showSnackBar("Invalid room configuration", isError: true);
      return;
    }

    if (selectedRoomType == 'general') {
      if (useCustomBedLabels) {
        if (bedLabelsController.text.isEmpty) {
          _showSnackBar(
            "Please enter bed labels or disable custom labels",
            isError: true,
          );
          return;
        }
      } else {
        final count = int.tryParse(bedCountController.text);
        if (count == null || count < 1) {
          _showSnackBar("Please enter a valid bed count", isError: true);
          return;
        }
      }
    }

    setState(() => isLoading = true);

    try {
      final roomService = ServiceLocator().roomService;

      // Parse bed labels if provided
      List<String>? bedLabels;
      if (selectedRoomType == 'general' && useCustomBedLabels) {
        bedLabels = bedLabelsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (selectedRoomIdentifier != null) {
        final configuredLabels =
            roomConfig?.getDefaultBedLabels(selectedRoomIdentifier!) ?? [];
        if (configuredLabels.isNotEmpty) {
          bedLabels = configuredLabels;
        }
      }

      // Parse bed count
      int? totalBeds;
      if (selectedRoomType == 'general' && !useCustomBedLabels) {
        totalBeds = int.tryParse(bedCountController.text) ?? 4;
      } else if (selectedRoomType == 'private') {
        totalBeds = int.tryParse(bedCountController.text) ?? 2;
      }

      await roomService.addRoom(
        roomNumber: selectedRoomIdentifier!,
        roomIdentifier: selectedRoomIdentifier!,
        floor: selectedFloor,
        roomType: selectedRoomType,
        totalBeds: totalBeds,
        bedLabels: bedLabels,
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("Room $selectedRoomIdentifier added successfully");
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Failed to add room: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.red.shade700
            : const Color(0xFF3B6D11),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (configLoading) {
      return const RoomConfigLoadingView();
    }

    final availableRooms = _getAvailableRooms();
    final canSelectRoom = availableRooms.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 780),
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
                          Icons.add_home_rounded,
                          color: Color(0xFF3B6D11),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "Add New Room",
                        style: TextStyle(
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

              // Step 1: Floor Selection
              AddRoomFloorSelection(
                selectedFloor: selectedFloor,
                onFloorSelected: _onFloorChanged,
                roomConfig: roomConfig,
              ),
              const SizedBox(height: 20),

              // Step 2: Room Type Selection
              AddRoomTypeSelection(
                selectedRoomType: selectedRoomType,
                onRoomTypeSelected: _onRoomTypeChanged,
              ),
              const SizedBox(height: 20),

              // Step 3: Room Identifier Dropdown
              const Text(
                "STEP 3: SELECT ROOM IDENTIFIER",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              if (availableRooms.isEmpty && canSelectRoom) ...[
                // All rooms added message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFC0DD97),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: const Color(0xFF3B6D11),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "All rooms added!",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF27500A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "All ${selectedRoomType == 'private' ? 'private' : 'general'} rooms for Floor $selectedFloor have been added to the system.",
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF639922),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: canSelectRoom
                        ? const Color(0xFFF4F9F0)
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: canSelectRoom
                          ? const Color(0xFFC0DD97)
                          : const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedRoomIdentifier,
                      isExpanded: true,
                      hint: Text(
                        canSelectRoom
                            ? "Select a room identifier"
                            : "Select floor and room type first",
                        style: TextStyle(
                          color: canSelectRoom
                              ? const Color(0xFF97C459)
                              : const Color(0xFFBDBDBD),
                          fontSize: 14,
                        ),
                      ),
                      icon: Icon(
                        Icons.arrow_drop_down_rounded,
                        color: canSelectRoom
                            ? const Color(0xFF639922)
                            : const Color(0xFFBDBDBD),
                      ),
                      items: availableRooms.map((room) {
                        final defaultBeds =
                            roomConfig?.getDefaultBedCount(room) ?? 0;
                        return DropdownMenuItem(
                          value: room,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                room,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF27500A),
                                ),
                              ),
                              Text(
                                "$defaultBeds beds",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF97C459),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: canSelectRoom
                          ? _onRoomIdentifierChanged
                          : null,
                    ),
                  ),
                ),
              if (!canSelectRoom)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: Colors.orange.shade400,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Please select both floor and room type to see available rooms",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),

              // Step 4: Bed Configuration (Auto-populated)
              if (selectedRoomIdentifier != null) ...[
                AddRoomBedConfiguration(
                  selectedRoomType: selectedRoomType,
                  useCustomBedLabels: useCustomBedLabels,
                  bedLabelsController: bedLabelsController,
                  bedCountController: bedCountController,
                  onUseCustomBedLabelsChanged: (value) {
                    setState(() => useCustomBedLabels = value);
                  },
                  defaultBeds:
                      roomConfig?.getDefaultBedCount(selectedRoomIdentifier!) ??
                      0,
                  onDecreaseBedCount: () {
                    final current = int.tryParse(bedCountController.text) ?? 4;
                    if (current > 1) {
                      setState(() {
                        bedCountController.text = (current - 1).toString();
                      });
                    }
                  },
                  onIncreaseBedCount: () {
                    final current = int.tryParse(bedCountController.text) ?? 4;
                    if (current < 20) {
                      setState(() {
                        bedCountController.text = (current + 1).toString();
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
              ],

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
                maxLines: 2,
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
                    onPressed: isLoading || selectedRoomIdentifier == null
                        ? null
                        : _handleAdd,
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
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(isLoading ? "Adding..." : "Add Room"),
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
