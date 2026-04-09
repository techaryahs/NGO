import 'package:flutter/material.dart';
import '../../../models/patient_model.dart';
import '../../../models/room_model.dart';
import '../../../models/bed_model.dart';
import '../../../services/service_locator.dart';

class EditPatientDialog extends StatefulWidget {
  final PatientModel patient;
  final Function()? onPatientUpdated;

  const EditPatientDialog({
    super.key,
    required this.patient,
    this.onPatientUpdated,
  });

  @override
  State<EditPatientDialog> createState() => _EditPatientDialogState();
}

class _EditPatientDialogState extends State<EditPatientDialog> {
  bool _isLoading = false;

  // Controllers
  late TextEditingController _patientNameController;
  late TextEditingController _mobileController;
  late TextEditingController _ageController;
  late TextEditingController _diagnosisController;
  late TextEditingController _attendantNameController;
  late TextEditingController _attendantContactController;
  late TextEditingController _allergiesController;
  late TextEditingController _notesController;

  String? _selectedGender;
  String? _selectedBloodType;
  
  // Room and Bed Selection
  RoomModel? _selectedRoom;
  List<BedModel> _selectedBeds = []; // Changed to list for multiple selection
  List<RoomModel> _availableRooms = [];
  List<BedModel> _availableBeds = [];
  List<String> _currentStayIds = []; // Track multiple stays

  final List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    _patientNameController = TextEditingController(text: widget.patient.fullName);
    _mobileController = TextEditingController(text: widget.patient.contactNumber);
    _ageController = TextEditingController(text: widget.patient.age.toString());
    _diagnosisController = TextEditingController(text: widget.patient.medicalCondition);
    _attendantNameController = TextEditingController(text: widget.patient.emergencyContactName);
    _attendantContactController = TextEditingController(text: widget.patient.emergencyContact);
    _allergiesController = TextEditingController(text: widget.patient.allergies ?? '');
    _notesController = TextEditingController(text: widget.patient.notes ?? '');
    
    _selectedGender = widget.patient.gender[0].toUpperCase() + widget.patient.gender.substring(1);
    _selectedBloodType = widget.patient.bloodType;
    
    _loadRoomsAndCurrentStay();
  }

  /// Load all rooms and current patient stay
  Future<void> _loadRoomsAndCurrentStay() async {
    try {
      final roomService = ServiceLocator().roomService;
      final rooms = await roomService.getRoomsStream().first;
      
      // Load current stays to get bed info
      if (widget.patient.roomId != null) {
        final stays = await roomService.getStaysByPatientStream(widget.patient.id).first;
        final activeStays = stays.where((s) => s.status == 'active').toList();
        
        if (activeStays.isNotEmpty) {
          _currentStayIds = activeStays.map((s) => s.id).toList();
          
          // Find current room and beds
          final currentRoom = rooms.where((r) => r.id == widget.patient.roomId).firstOrNull;
          if (currentRoom != null) {
            _selectedRoom = currentRoom;
            
            // Collect all beds from active stays
            for (final stay in activeStays) {
              if (stay.bedId != null) {
                final bed = currentRoom.beds.where((b) => b.id == stay.bedId).firstOrNull;
                if (bed != null && !_selectedBeds.any((b) => b.id == bed.id)) {
                  _selectedBeds.add(bed);
                }
              }
            }
          }
        }
      }
      
      setState(() {
        _availableRooms = rooms;
        if (_selectedRoom != null) {
          _availableBeds = _selectedRoom!.beds.where((b) => 
            b.isAvailable || _selectedBeds.any((sb) => sb.id == b.id)
          ).toList();
        }
      });
    } catch (e) {
      // Silently fail - user can still edit other fields
    }
  }

  /// Handle room selection and load available beds
  void _onRoomSelected(RoomModel? room) {
    setState(() {
      _selectedRoom = room;
      // Only reset beds if changing to a different room
      if (room?.id != widget.patient.roomId) {
        _selectedBeds = [];
      }
      _availableBeds = room?.beds.where((b) => 
        b.isAvailable || _selectedBeds.any((sb) => sb.id == b.id)
      ).toList() ?? [];
    });
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _mobileController.dispose();
    _ageController.dispose();
    _diagnosisController.dispose();
    _attendantNameController.dispose();
    _attendantContactController.dispose();
    _allergiesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _updatePatient() async {
    // Validation
    if (_patientNameController.text.trim().isEmpty) {
      _showError('Please enter patient name');
      return;
    }
    if (_mobileController.text.trim().isEmpty) {
      _showError('Please enter mobile number');
      return;
    }
    if (_selectedGender == null) {
      _showError('Please select gender');
      return;
    }
    if (_ageController.text.trim().isEmpty) {
      _showError('Please enter age');
      return;
    }
    if (_diagnosisController.text.trim().isEmpty) {
      _showError('Please enter diagnosis');
      return;
    }
    if (_attendantNameController.text.trim().isEmpty) {
      _showError('Please enter attendant name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final roomService = ServiceLocator().roomService;
      final patientService = ServiceLocator().patientService;
      
      // Calculate new date of birth from age
      final age = int.tryParse(_ageController.text.trim()) ?? 0;
      final dateOfBirth = DateTime.now().subtract(Duration(days: age * 365));

      final updates = <String, dynamic>{
        'fullName': _patientNameController.text.trim(),
        'contactNumber': _mobileController.text.trim(),
        'gender': _selectedGender!.toLowerCase(),
        'dateOfBirth': dateOfBirth.millisecondsSinceEpoch,
        'age': age,
        'medicalCondition': _diagnosisController.text.trim(),
        'emergencyContactName': _attendantNameController.text.trim(),
        'emergencyContact': _attendantContactController.text.trim(),
        'allergies': _allergiesController.text.trim().isEmpty 
            ? null 
            : _allergiesController.text.trim(),
        'bloodType': _selectedBloodType,
        'notes': _notesController.text.trim().isEmpty 
            ? null 
            : _notesController.text.trim(),
      };

      // Handle room/bed change
      final roomChanged = _selectedRoom != null && _selectedRoom!.id != widget.patient.roomId;
      final bedsChanged = _selectedBeds.isNotEmpty && 
          !_selectedBeds.every((bed) => _currentStayIds.isNotEmpty);
      
      if (roomChanged || bedsChanged) {
        if (_selectedRoom == null || _selectedBeds.isEmpty) {
          _showError('Please select room and at least one bed');
          setState(() => _isLoading = false);
          return;
        }
        
        // Concurrency check: Re-fetch room to verify beds are still available
        final room = await roomService.getRoom(_selectedRoom!.id);
        if (room == null) {
          throw Exception('Selected room no longer exists');
        }
        
        // Check all selected beds
        for (final selectedBed in _selectedBeds) {
          final bed = room.beds.where((b) => b.id == selectedBed.id).firstOrNull;
          if (bed == null || (!bed.isAvailable && !_currentStayIds.contains(bed.currentStayId))) {
            throw Exception('Bed ${selectedBed.bedLabel} is no longer available. Please reselect beds.');
          }
        }
        
        // Complete all old stays
        for (final stayId in _currentStayIds) {
          await roomService.completeStay(stayId);
        }
        
        // Create new stays for each selected bed
        final currentUser = ServiceLocator().authRestService.currentUser;
        for (final bed in _selectedBeds) {
          await roomService.createStay(
            patientId: widget.patient.id,
            patientName: _patientNameController.text.trim(),
            roomId: _selectedRoom!.id,
            roomNumber: _selectedRoom!.roomIdentifier,
            roomType: _selectedRoom!.roomType,
            admissionDate: widget.patient.admissionDate,
            durationDays: 7, // Default duration
            attendantCount: 1,
            bedId: bed.id,
            bedLabel: bed.bedLabel,
            notes: _selectedBeds.length > 1
                ? 'Multiple beds: ${_selectedBeds.map((b) => b.bedLabel).join(", ")}'
                : 'Room changed from ${widget.patient.roomNumber ?? "N/A"}',
            createdBy: currentUser?.uid ?? 'system',
          );
        }
        
        // Update patient room info
        updates['roomId'] = _selectedRoom!.id;
        updates['roomNumber'] = _selectedRoom!.roomIdentifier;
        updates['floor'] = _selectedRoom!.floor;
      }

      await patientService.updatePatient(widget.patient.id, updates);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onPatientUpdated?.call();
        _showSuccess('Patient updated successfully');
      }
    } catch (e) {
      _showError('Failed to update patient: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFD32F2F),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF3B6D11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F9F0),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3DE),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFC0DD97),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        color: Color(0xFF3B6D11),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Edit patient",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                            ),
                          ),
                          Text(
                            "Update patient information",
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF639922),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFF639922),
                    ),
                  ],
                ),
              ),

              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Section(
                        label: "Personal Information",
                        child: Column(
                          children: [
                            _NatureField(
                              label: "Patient name",
                              hint: "Full name",
                              controller: _patientNameController,
                            ),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(
                                label: "Mobile no",
                                hint: "+91 XXXXX XXXXX",
                                keyboard: TextInputType.phone,
                                controller: _mobileController,
                              ),
                              _NatureField(
                                label: "Age",
                                hint: "Years",
                                keyboard: TextInputType.number,
                                controller: _ageController,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _NatureDropdown(
                              label: "Gender",
                              items: const ["Male", "Female", "Other"],
                              value: _selectedGender,
                              onChanged: (value) {
                                setState(() => _selectedGender = value);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Medical Information",
                        child: Column(
                          children: [
                            _NatureField(
                              label: "Diagnosis",
                              hint: "Primary diagnosis",
                              controller: _diagnosisController,
                            ),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureDropdown(
                                label: "Blood Type",
                                items: _bloodTypes,
                                value: _selectedBloodType,
                                onChanged: (value) {
                                  setState(() => _selectedBloodType = value);
                                },
                              ),
                              _NatureField(
                                label: "Allergies",
                                hint: "Known allergies",
                                controller: _allergiesController,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Emergency Contact",
                        child: _Row2(
                          _NatureField(
                            label: "Contact Name",
                            hint: "Full name",
                            controller: _attendantNameController,
                          ),
                          _NatureField(
                            label: "Contact Number",
                            hint: "Phone number",
                            keyboard: TextInputType.phone,
                            controller: _attendantContactController,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Additional Notes",
                        child: _NatureField(
                          label: "Notes",
                          hint: "Any additional information",
                          controller: _notesController,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Room Assignment",
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _RoomDropdown(
                              label: "Room",
                              rooms: _availableRooms,
                              selectedRoom: _selectedRoom,
                              onChanged: _onRoomSelected,
                            ),
                            if (_selectedRoom != null) ...[
                              const SizedBox(height: 12),
                              _BedSelection(
                                label: "Bed",
                                beds: _availableBeds,
                                selectedBeds: _selectedBeds,
                                onChanged: (beds) {
                                  setState(() => _selectedBeds = beds);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F9F0),
                  border: Border(
                    top: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF639922),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFFC0DD97)),
                        ),
                      ),
                      child: const Text("Cancel", style: TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _updatePatient,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFEAF3DE),
                                ),
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        _isLoading ? "Updating..." : "Update patient",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B6D11),
                        foregroundColor: const Color(0xFFEAF3DE),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Section
class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF639922),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(color: Color(0xFFC0DD97), thickness: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

// Row2 helper
class _Row2 extends StatelessWidget {
  final Widget a, b;
  const _Row2(this.a, this.b);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }
}

// Field
class _NatureField extends StatelessWidget {
  final String label;
  final String hint;
  final TextInputType keyboard;
  final TextEditingController? controller;
  final int maxLines;

  const _NatureField({
    required this.label,
    required this.hint,
    this.keyboard = TextInputType.text,
    this.controller,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: const Color(0xFF97C459).withOpacity(0.75),
              fontSize: 13,
            ),
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// Dropdown
class _NatureDropdown extends StatelessWidget {
  final String label;
  final List<String> items;
  final String? value;
  final ValueChanged<String?>? onChanged;

  const _NatureDropdown({
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: value,
          hint: Text(
            "Select",
            style: TextStyle(
              color: const Color(0xFF97C459).withOpacity(0.75),
              fontSize: 13,
            ),
          ),
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          dropdownColor: const Color(0xFFF4F9F0),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
            ),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF639922),
            size: 20,
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// Room Dropdown
class _RoomDropdown extends StatelessWidget {
  final String label;
  final List<RoomModel> rooms;
  final RoomModel? selectedRoom;
  final ValueChanged<RoomModel?>? onChanged;

  const _RoomDropdown({
    required this.label,
    required this.rooms,
    this.selectedRoom,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<RoomModel>(
          value: selectedRoom,
          hint: Text(
            "Select room",
            style: TextStyle(color: const Color(0xFF97C459).withOpacity(0.75), fontSize: 13),
          ),
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          dropdownColor: const Color(0xFFF4F9F0),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
            ),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF639922), size: 20),
          items: rooms.map((room) {
            final floorName = room.floor == 1 ? 'Ground' : 'First';
            final roomTypeLabel = room.isPrivate ? 'Private' : 'General';
            final availableBeds = room.actualAvailableBeds;
            
            return DropdownMenuItem(
              value: room,
              child: Text(
                '${room.roomIdentifier} (Floor $floorName - $roomTypeLabel) - $availableBeds beds available',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// Bed Selection
class _BedSelection extends StatelessWidget {
  final String label;
  final List<BedModel> beds;
  final List<BedModel> selectedBeds;
  final ValueChanged<List<BedModel>>? onChanged;

  const _BedSelection({
    required this.label,
    required this.beds,
    required this.selectedBeds,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
                letterSpacing: 0.5,
              ),
            ),
            if (selectedBeds.isNotEmpty)
              Text(
                '${selectedBeds.length} selected',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF3B6D11),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (beds.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFE69C)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF856404), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No beds available in this room',
                    style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: beds.map((bed) {
                  final isSelected = selectedBeds.any((b) => b.id == bed.id);
                  return FilterChip(
                    label: Text('Bed ${bed.bedLabel}'),
                    selected: isSelected,
                    onSelected: (selected) {
                      final newSelection = List<BedModel>.from(selectedBeds);
                      if (selected) {
                        newSelection.add(bed);
                      } else {
                        newSelection.removeWhere((b) => b.id == bed.id);
                      }
                      onChanged?.call(newSelection);
                    },
                    backgroundColor: const Color(0xFFF4F9F0),
                    selectedColor: const Color(0xFF3B6D11),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF27500A),
                    ),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFC0DD97),
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF3B6D11)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can select multiple beds for patient + attendants',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF3B6D11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

}

