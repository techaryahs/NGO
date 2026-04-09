import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/room_model.dart';
import '../../../models/bed_model.dart';
import 'patient_form_components.dart';

class AddPatientDialog extends StatefulWidget {
  final Function()? onPatientAdded;

  const AddPatientDialog({super.key, this.onPatientAdded});

  @override
  State<AddPatientDialog> createState() => _AddPatientDialogState();
}

class _AddPatientDialogState extends State<AddPatientDialog> {
  bool _isLoading = false;
  bool _isLoadingRooms = true;

  // Controllers
  final _dateController = TextEditingController();
  final _fileNoController = TextEditingController();
  final _patientNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _ageController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _addressController = TextEditingController();
  final _stateController = TextEditingController();
  final _localAddressController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _doctorNameController = TextEditingController();
  final _hospitalNameController = TextEditingController();
  final _attendantNameController = TextEditingController();
  final _attendantAgeController = TextEditingController();
  final _attendantCountController = TextEditingController();
  final _relationController = TextEditingController();

  String? _selectedGender;
  DateTime? _selectedDate;

  // Room and Bed Selection
  RoomModel? _selectedRoom;
  List<BedModel> _selectedBeds = []; // Changed to list for multiple selection
  List<RoomModel> _availableRooms = [];
  List<BedModel> _availableBeds = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableRooms();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _fileNoController.dispose();
    _patientNameController.dispose();
    _mobileController.dispose();
    _ageController.dispose();
    _pincodeController.dispose();
    _addressController.dispose();
    _stateController.dispose();
    _localAddressController.dispose();
    _diagnosisController.dispose();
    _doctorNameController.dispose();
    _hospitalNameController.dispose();
    _attendantNameController.dispose();
    _attendantAgeController.dispose();
    _attendantCountController.dispose();
    _relationController.dispose();
    super.dispose();
  }

  /// Load available rooms (filter out fully occupied rooms)
  Future<void> _loadAvailableRooms() async {
    try {
      final rooms = await ServiceLocator().roomService.getRoomsStream().first;
      if (mounted) {
        setState(() {
          _isLoadingRooms = false;
          // Do not filter out any rooms! We need to show them as disabled if full, so we can display their Expected Vacancy Date.
          _availableRooms = List.from(rooms)
            ..sort((a, b) => a.roomIdentifier.compareTo(b.roomIdentifier));
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
      _selectedBeds = []; // Reset bed selection
      // Only show available beds for selection
      _availableBeds = room?.beds.where((b) => b.isAvailable).toList() ?? [];

      // For private rooms, automatically select ALL beds
      if (room != null && room.isPrivate) {
        _selectedBeds = List.from(room.beds);
        // Set default attendant count to 1 if not already set
        if (_attendantCountController.text.trim().isEmpty) {
          _attendantCountController.text = '1';
        }
      }
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B6D11),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text =
            '${picked.day.toString().padLeft(2, '0')} / ${picked.month.toString().padLeft(2, '0')} / ${picked.year}';
      });
    }
  }

  Future<void> _savePatient() async {
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

    // Validate attendant count for private rooms
    if (_selectedRoom?.isPrivate == true) {
      final attendantCount = int.tryParse(
        _attendantCountController.text.trim(),
      );
      if (attendantCount == null || attendantCount < 1 || attendantCount > 5) {
        _showError(
          'Please enter a valid attendant count (1-5) for private rooms',
        );
        return;
      }
    }

    // Room and bed validation
    if (_selectedRoom == null) {
      _showError('Please select a room');
      return;
    }
    if (_selectedBeds.isEmpty) {
      _showError('Please select at least one bed');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = ServiceLocator().authRestService.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Concurrency check: Re-fetch room to verify beds are still available
      final roomService = ServiceLocator().roomService;
      final room = await roomService.getRoom(_selectedRoom!.id);
      if (room == null) {
        throw Exception('Selected room no longer exists');
      }

      // Additional check for private rooms - ensure room is not occupied
      if (room.isPrivate && room.derivedOccupancyStatus != 'available') {
        throw Exception(
          'Private room ${room.roomIdentifier} is no longer available. Please select another room.',
        );
      }

      // Check all selected beds are still available
      for (final selectedBed in _selectedBeds) {
        final bed = room.beds.where((b) => b.id == selectedBed.id).firstOrNull;
        if (bed == null || !bed.isAvailable) {
          throw Exception(
            'Bed ${selectedBed.bedLabel} is no longer available. Please reselect beds.',
          );
        }
      }

      // Calculate date of birth from age
      final age = int.tryParse(_ageController.text.trim()) ?? 0;
      final dateOfBirth = DateTime.now().subtract(Duration(days: age * 365));

      // Use selected date or current date for admission
      final admissionDate = _selectedDate ?? DateTime.now();

      // Build notes from additional fields
      final notesList = <String>[];
      if (_fileNoController.text.trim().isNotEmpty) {
        notesList.add('File No: ${_fileNoController.text.trim()}');
      }
      if (_addressController.text.trim().isNotEmpty) {
        notesList.add('Address: ${_addressController.text.trim()}');
      }
      if (_stateController.text.trim().isNotEmpty) {
        notesList.add('State: ${_stateController.text.trim()}');
      }
      if (_localAddressController.text.trim().isNotEmpty) {
        notesList.add('Local Address: ${_localAddressController.text.trim()}');
      }
      if (_pincodeController.text.trim().isNotEmpty) {
        notesList.add('Pincode: ${_pincodeController.text.trim()}');
      }
      if (_doctorNameController.text.trim().isNotEmpty) {
        notesList.add('Doctor: ${_doctorNameController.text.trim()}');
      }
      if (_hospitalNameController.text.trim().isNotEmpty) {
        notesList.add('Hospital: ${_hospitalNameController.text.trim()}');
      }
      if (_attendantAgeController.text.trim().isNotEmpty) {
        notesList.add('Attendant Age: ${_attendantAgeController.text.trim()}');
      }
      if (_attendantCountController.text.trim().isNotEmpty) {
        notesList.add(
          'Attendant Count: ${_attendantCountController.text.trim()}',
        );
      }
      if (_relationController.text.trim().isNotEmpty) {
        notesList.add('Relation: ${_relationController.text.trim()}');
      }
      notesList.add('Room: ${_selectedRoom!.roomIdentifier}');
      notesList.add('Beds: ${_selectedBeds.map((b) => b.bedLabel).join(", ")}');

      // Create patient
      final patientId = await ServiceLocator().patientService.addPatient(
        fullName: _patientNameController.text.trim(),
        dateOfBirth: dateOfBirth,
        gender: _selectedGender!.toLowerCase(),
        contactNumber: _mobileController.text.trim(),
        emergencyContact: _mobileController.text.trim(),
        emergencyContactName: _attendantNameController.text.trim(),
        medicalCondition: _diagnosisController.text.trim(),
        admissionDate: admissionDate,
        roomId: _selectedRoom!.id,
        roomNumber: _selectedRoom!.roomIdentifier,
        floor: _selectedRoom!.floor,
        bedIds: _selectedBeds.map((b) => b.id).toList(),
        bedLabels: _selectedBeds.map((b) => b.bedLabel).toList(),
        notes: notesList.isEmpty ? null : notesList.join('\n'),
        createdBy: currentUser.uid,
      );

      // Get attendant count (default to 1 if not specified)
      final attendantCount =
          int.tryParse(_attendantCountController.text.trim()) ?? 1;

      // Handle stay creation based on room type
      if (_selectedRoom!.isPrivate) {
        // Private room: 1 patient + attendants, single stay for the room
        await roomService.createStay(
          patientId: patientId,
          patientName: _patientNameController.text.trim(),
          roomId: _selectedRoom!.id,
          roomNumber: _selectedRoom!.roomIdentifier,
          roomType: _selectedRoom!.roomType,
          admissionDate: admissionDate,
          durationDays: 7, // Default 7 days
          attendantCount: attendantCount,
          bedId: _selectedBeds.isNotEmpty ? _selectedBeds.first.id : null,
          bedLabel: _selectedBeds.isNotEmpty
              ? _selectedBeds.map((b) => b.bedLabel).join(", ")
              : null,
          notes: 'Private room admission with $attendantCount attendant(s)',
          createdBy: currentUser.uid,
        );
      } else {
        // General room: Create separate stay for each selected bed
        for (final bed in _selectedBeds) {
          await roomService.createStay(
            patientId: patientId,
            patientName: _patientNameController.text.trim(),
            roomId: _selectedRoom!.id,
            roomNumber: _selectedRoom!.roomIdentifier,
            roomType: _selectedRoom!.roomType,
            admissionDate: admissionDate,
            durationDays: 7, // Default 7 days
            attendantCount: 1, // General rooms: 1 attendant per bed
            bedId: bed.id,
            bedLabel: bed.bedLabel,
            notes: _selectedBeds.length > 1
                ? 'Multiple beds: ${_selectedBeds.map((b) => b.bedLabel).join(", ")}'
                : 'General ward admission',
            createdBy: currentUser.uid,
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onPatientAdded?.call();
        _showSuccess(
          'Patient admitted successfully with ${_selectedBeds.length} bed(s)',
        );
      }
    } catch (e) {
      _showError('Failed to add patient: ${e.toString()}');
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
              const PatientDialogHeader(
                title: "Add patient",
                subtitle: "Fill in the details below to register a new patient",
                icon: Icons.person_add_outlined,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PatientFormSection(
                        label: "Patient information",
                        child: Column(
                          children: [
                            PatientFormRow2(
                              PatientFormField(
                                label: "Date",
                                hint: "",
                                isDate: true,
                                controller: _dateController,
                                onTap: () => _selectDate(context),
                              ),
                              PatientFormField(
                                label: "File no",
                                hint: "e.g. F-2024-001",
                                controller: _fileNoController,
                              ),
                            ),
                            const SizedBox(height: 12),
                            PatientFormRow2(
                              PatientFormField(
                                label: "Patient name",
                                hint: "Full name",
                                controller: _patientNameController,
                              ),
                              PatientFormField(
                                label: "Mobile no",
                                hint: "+91 XXXXX XXXXX",
                                keyboard: TextInputType.phone,
                                controller: _mobileController,
                              ),
                            ),
                            const SizedBox(height: 12),
                            PatientFormRow3(
                              PatientFormDropdown(
                                label: "Gender",
                                items: const ["Male", "Female", "Other"],
                                value: _selectedGender,
                                onChanged: (value) {
                                  setState(() => _selectedGender = value);
                                },
                              ),
                              PatientFormField(
                                label: "Age",
                                hint: "Years",
                                keyboard: TextInputType.number,
                                controller: _ageController,
                              ),
                              PatientFormField(
                                label: "Pincode",
                                hint: "000000",
                                keyboard: TextInputType.number,
                                controller: _pincodeController,
                              ),
                            ),
                            const SizedBox(height: 12),
                            PatientFormField(
                              label: "Permanent address",
                              hint: "Street, city, district",
                              controller: _addressController,
                            ),
                            const SizedBox(height: 12),
                            PatientFormRow2(
                              PatientFormField(
                                label: "State",
                                hint: "State",
                                controller: _stateController,
                              ),
                              PatientFormField(
                                label: "Mumbai local contact address",
                                hint: "Local address",
                                controller: _localAddressController,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      PatientFormSection(
                        label: "Medical details",
                        child: Column(
                          children: [
                            PatientFormField(
                              label: "Diagnosis",
                              hint: "Primary diagnosis",
                              controller: _diagnosisController,
                            ),
                            const SizedBox(height: 12),
                            PatientFormRow2(
                              PatientFormField(
                                label: "Doctor name",
                                hint: "Dr. name",
                                controller: _doctorNameController,
                              ),
                              PatientFormField(
                                label: "Hospital name",
                                hint: "Hospital / clinic",
                                controller: _hospitalNameController,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      PatientFormSection(
                        label: "Attendant details",
                        child: Column(
                          children: [
                            PatientFormRow3(
                              PatientFormField(
                                label: "Attendant name",
                                hint: "Full name",
                                controller: _attendantNameController,
                              ),
                              PatientFormField(
                                label: "Attendant age",
                                hint: "Years",
                                keyboard: TextInputType.number,
                                controller: _attendantAgeController,
                              ),
                              PatientFormField(
                                label: "Relation to patient",
                                hint: "e.g. Spouse",
                                controller: _relationController,
                              ),
                            ),
                            if (_selectedRoom?.isPrivate == true) ...[
                              const SizedBox(height: 12),
                              PatientFormRow2(
                                PatientFormField(
                                  label: "Number of attendants",
                                  hint: "1-5",
                                  keyboard: TextInputType.number,
                                  controller: _attendantCountController,
                                ),
                                const SizedBox(), // Empty space for alignment
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      PatientFormSection(
                        label: "Office use",
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
                                if (room.isPrivate) return room.occupiedCount == 0;
                                return room.occupiedCount < room.actualTotalBeds;
                              },
                              itemBuilder: (room, enabled) {
                                String subtitle;
                                if (!enabled && room.expectedVacancyDate != null) {
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
                                isPrivateRoom:
                                    _selectedRoom?.isPrivate ?? false,
                                onChanged: (beds) {
                                  setState(() => _selectedBeds = beds);
                                },
                              ),
                              if (_selectedRoom?.isPrivate == true)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE3F2FD),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF90CAF9),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Color(0xFF1976D2),
                                        size: 16,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Private room: One patient with their attendants (1-5 people)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF1976D2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                onSave: _isLoading ? null : _savePatient,
                isLoading: _isLoading,
                submitLabel: 'Save patient',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
