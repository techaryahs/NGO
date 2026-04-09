import 'package:flutter/material.dart';
import '../../../models/patient_model.dart';
import '../../../models/room_model.dart';
import '../../../models/bed_model.dart';
import '../../../services/service_locator.dart';
import 'patient_form_components.dart';

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
  bool _isLoadingRooms = true;

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

  final List<String> _bloodTypes = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  @override
  void initState() {
    super.initState();
    _patientNameController = TextEditingController(
      text: widget.patient.fullName,
    );
    _mobileController = TextEditingController(
      text: widget.patient.contactNumber,
    );
    _ageController = TextEditingController(text: widget.patient.age.toString());
    _diagnosisController = TextEditingController(
      text: widget.patient.medicalCondition,
    );
    _attendantNameController = TextEditingController(
      text: widget.patient.emergencyContactName,
    );
    _attendantContactController = TextEditingController(
      text: widget.patient.emergencyContact,
    );
    _allergiesController = TextEditingController(
      text: widget.patient.allergies ?? '',
    );
    _notesController = TextEditingController(text: widget.patient.notes ?? '');

    _selectedGender =
        widget.patient.gender[0].toUpperCase() +
        widget.patient.gender.substring(1);
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
        final stays = await roomService
            .getStaysByPatientStream(widget.patient.id)
            .first;
        final activeStays = stays.where((s) => s.status == 'active').toList();

        if (activeStays.isNotEmpty) {
          _currentStayIds = activeStays.map((s) => s.id).toList();

          // Find current room and beds
          final currentRoom = rooms
              .where((r) => r.id == widget.patient.roomId)
              .firstOrNull;
          if (currentRoom != null) {
            _selectedRoom = currentRoom;

            // Collect all beds from active stays
            for (final stay in activeStays) {
              if (stay.bedId != null) {
                final bed = currentRoom.beds
                    .where((b) => b.id == stay.bedId)
                    .firstOrNull;
                if (bed != null && !_selectedBeds.any((b) => b.id == bed.id)) {
                  _selectedBeds.add(bed);
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _isLoadingRooms = false;
          _availableRooms = List.from(rooms)
            ..sort((a, b) => a.roomIdentifier.compareTo(b.roomIdentifier));

          if (_selectedRoom != null) {
            _availableBeds = _selectedRoom!.beds
                .where(
                  (b) =>
                      b.isAvailable || _selectedBeds.any((sb) => sb.id == b.id),
                )
                .toList();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRooms = false);
      }
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
      _availableBeds =
          room?.beds
              .where(
                (b) =>
                    b.isAvailable || _selectedBeds.any((sb) => sb.id == b.id),
              )
              .toList() ??
          [];
          
      // For private rooms, automatically select ALL beds
      if (room != null && room.isPrivate) {
        _selectedBeds = List.from(room.beds);
      }
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
      final roomChanged =
          _selectedRoom != null && _selectedRoom!.id != widget.patient.roomId;
      bool bedsChanged = false;
      if (_selectedBeds.length != _currentStayIds.length) {
        bedsChanged = true;
      } else {
        for (final bed in _selectedBeds) {
          if (bed.currentStayId == null || !_currentStayIds.contains(bed.currentStayId)) {
            bedsChanged = true;
            break;
          }
        }
      }

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
          final bed = room.beds
              .where((b) => b.id == selectedBed.id)
              .firstOrNull;
          if (bed == null ||
              (!bed.isAvailable &&
                  !_currentStayIds.contains(bed.currentStayId))) {
            throw Exception(
              'Bed ${selectedBed.bedLabel} is no longer available. Please reselect beds.',
            );
          }
        }

        // Complete all old stays
        for (final stayId in _currentStayIds) {
          await roomService.completeStay(stayId);
        }

        // Create new stays for selected bed(s)
        final currentUser = ServiceLocator().authRestService.currentUser;
        if (_selectedRoom!.isPrivate) {
          // For private rooms, we only need to create one stay which reserves the whole room
          final bed = _selectedBeds.first;
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
        } else {
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
              notes: 'Room changed from ${widget.patient.roomNumber ?? "N/A"}',
              createdBy: currentUser?.uid ?? 'system',
            );
          }
        }

        // Update patient room info
        updates['roomId'] = _selectedRoom!.id;
        updates['roomNumber'] = _selectedRoom!.roomIdentifier;
        updates['floor'] = _selectedRoom!.floor;
        updates['bedIds'] = _selectedBeds.map((b) => b.id).toList();
        updates['bedLabels'] = _selectedBeds.map((b) => b.bedLabel).toList();
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
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              PatientDialogHeader(
                title: "Edit patient",
                subtitle: "Update patient information",
                icon: Icons.edit_outlined,
                trailing: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFF639922),
                ),
              ),

              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PatientFormSection(
                        label: "Personal Information",
                        child: Column(
                          children: [
                            PatientFormField(
                              label: "Patient name",
                              hint: "Full name",
                              controller: _patientNameController,
                            ),
                            const SizedBox(height: 12),
                            PatientFormRow2(
                              PatientFormField(
                                label: "Mobile no",
                                hint: "+91 XXXXX XXXXX",
                                keyboard: TextInputType.phone,
                                controller: _mobileController,
                              ),
                              PatientFormField(
                                label: "Age",
                                hint: "Years",
                                keyboard: TextInputType.number,
                                controller: _ageController,
                              ),
                            ),
                            const SizedBox(height: 12),
                            PatientFormDropdown(
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
                      PatientFormSection(
                        label: "Medical Information",
                        child: Column(
                          children: [
                            PatientFormField(
                              label: "Diagnosis",
                              hint: "Primary diagnosis",
                              controller: _diagnosisController,
                            ),
                            const SizedBox(height: 12),
                            PatientFormRow2(
                              PatientFormDropdown(
                                label: "Blood Type",
                                items: _bloodTypes,
                                value: _selectedBloodType,
                                onChanged: (value) {
                                  setState(() => _selectedBloodType = value);
                                },
                              ),
                              PatientFormField(
                                label: "Allergies",
                                hint: "Known allergies",
                                controller: _allergiesController,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      PatientFormSection(
                        label: "Emergency Contact",
                        child: PatientFormRow2(
                          PatientFormField(
                            label: "Contact Name",
                            hint: "Full name",
                            controller: _attendantNameController,
                          ),
                          PatientFormField(
                            label: "Contact Number",
                            hint: "Phone number",
                            keyboard: TextInputType.phone,
                            controller: _attendantContactController,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      PatientFormSection(
                        label: "Additional Notes",
                        child: PatientFormField(
                          label: "Notes",
                          hint: "Any additional information",
                          controller: _notesController,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      PatientFormSection(
                        label: "Room Assignment",
                        child: _isLoadingRooms
                            ? Container(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: const Column(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFF3B6D11),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Loading rooms...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF639922),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PatientRoomDropdown(
                              label: "Room",
                              rooms: _availableRooms,
                              selectedRoom: _selectedRoom,
                              isRoomEnabled: (room) {
                                if (room.id == widget.patient.roomId) return true;
                                if (room.isPrivate) return room.occupiedCount == 0;
                                return room.occupiedCount < room.actualTotalBeds;
                              },
                              itemBuilder: (room, enabled) {
                                String subtitle;
                                if (room.id == widget.patient.roomId) {
                                  subtitle = ' - Current';
                                } else if (!enabled && room.expectedVacancyDate != null) {
                                  final date = room.expectedVacancyDate!;
                                  subtitle = ' - Expected Free: ${date.day}/${date.month}/${date.year}';
                                } else if (!enabled) {
                                  subtitle = ' - Full';
                                } else if (room.isPrivate) {
                                  subtitle = ' - Available';
                                } else {
                                  subtitle = ' - ${room.actualAvailableBeds} beds available';
                                }
                                return Text(
                                  '${room.roomIdentifier}$subtitle',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: enabled ? const Color(0xFF27500A) : const Color(0xFF999999),
                                  ),
                                );
                              },
                              onChanged: _onRoomSelected,
                            ),
                            if (_selectedRoom != null) ...[
                              const SizedBox(height: 12),
                              PatientBedSelection(
                                label: "Bed",
                                beds: _availableBeds,
                                selectedBeds: _selectedBeds,
                                isPrivateRoom: _selectedRoom?.isPrivate ?? false,
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

              PatientDialogFooter(
                onCancel: () => Navigator.pop(context),
                onSave: _isLoading ? null : _updatePatient,
                isLoading: _isLoading,
                submitLabel: 'Update patient',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
