import 'package:flutter/material.dart';
import '../../../utils/bed_helper.dart';
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
  late TextEditingController _allergiesController;
  late TextEditingController _notesController;

  final List<_AttendantEntry> _attendants = [];

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
    _allergiesController = TextEditingController(
      text: widget.patient.allergies ?? '',
    );
    
    // Initialize attendants
    if (widget.patient.attendants != null && widget.patient.attendants!.isNotEmpty) {
      for (final att in widget.patient.attendants!) {
        final entry = _AttendantEntry();
        entry.nameController.text = att.name;
        entry.ageController.text = att.age ?? '';
        entry.relationController.text = att.relation ?? '';
        _attendants.add(entry);
      }
    } else {
      // Fallback for legacy patients
      final entry = _AttendantEntry();
      if (widget.patient.emergencyContactName.isNotEmpty) {
        entry.nameController.text = widget.patient.emergencyContactName;
      }
      _attendants.add(entry);
    }
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
    _allergiesController.dispose();
    _notesController.dispose();
    for (final att in _attendants) {
      att.dispose();
    }
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
    if (_attendants.isEmpty || _attendants.first.nameController.text.trim().isEmpty) {
      _showError('Please enter at least one attendant name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final roomService = ServiceLocator().roomService;
      final patientService = ServiceLocator().patientService;

      // Calculate new date of birth from age
      final age = int.tryParse(_ageController.text.trim()) ?? 0;
      final dateOfBirth = DateTime.now().subtract(Duration(days: age * 365));

      final structuredAttendants = <AttendantModel>[];
      for (final att in _attendants) {
        final name = att.nameController.text.trim();
        if (name.isNotEmpty) {
          structuredAttendants.add(AttendantModel(
            name: name,
            age: att.ageController.text.trim().isNotEmpty ? att.ageController.text.trim() : null,
            relation: att.relationController.text.trim().isNotEmpty ? att.relationController.text.trim() : null,
          ));
        }
      }

      final updates = <String, dynamic>{
        'fullName': _patientNameController.text.trim(),
        'contactNumber': _mobileController.text.trim(),
        'gender': _selectedGender!.toLowerCase(),
        'dateOfBirth': dateOfBirth.millisecondsSinceEpoch,
        'age': age,
        'medicalCondition': _diagnosisController.text.trim(),
        'emergencyContactName': structuredAttendants.isNotEmpty ? structuredAttendants.first.name : '',
        'allergies': _allergiesController.text.trim().isEmpty
            ? null
            : _allergiesController.text.trim(),
        'bloodType': _selectedBloodType,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'attendants': structuredAttendants.map((a) => a.toMap()).toList(),
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
              '${BedHelper.getBedDisplayName(selectedBed.bedLabel)} is no longer available. Please reselect beds.',
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
                ? 'Multiple beds: ${_selectedBeds.map((b) => BedHelper.getBedDisplayName(b.bedLabel)).join(", ")}'
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
                        label: "Attendant details",
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < _attendants.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF4F9F0),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFC0DD97), width: 1),
                                  ),
                                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        margin: const EdgeInsets.only(top: 18, right: 8),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF3B6D11),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: _Row3(
                                          _NatureField(
                                            label: "Attendant name",
                                            hint: "Full name",
                                            controller: _attendants[i].nameController,
                                          ),
                                          _NatureField(
                                            label: "Age",
                                            hint: "Years",
                                            keyboard: TextInputType.number,
                                            controller: _attendants[i].ageController,
                                          ),
                                          _NatureField(
                                            label: "Relation",
                                            hint: "e.g. Spouse",
                                            controller: _attendants[i].relationController,
                                          ),
                                        ),
                                      ),
                                      if (_attendants.length > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 14),
                                          child: IconButton(
                                            icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFD32F2F), size: 20),
                                            tooltip: "Remove attendant",
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                            padding: EdgeInsets.zero,
                                            onPressed: () {
                                              setState(() {
                                                _attendants[i].dispose();
                                                _attendants.removeAt(i);
                                              });
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            // ── Add Attendant Button ──
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _attendants.add(_AttendantEntry());
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3DE),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF3B6D11),
                                    width: 1,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_circle_rounded, size: 18, color: Color(0xFF3B6D11)),
                                    SizedBox(width: 6),
                                    Text(
                                      "Add another attendant",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF3B6D11),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
                      const SizedBox(height: 20),
                      // ── Payment Summary ──
                      _PaymentSummary(
                        bedsCount: _selectedBeds.length,
                        attendantsCount: _attendants.where((a) => a.nameController.text.trim().isNotEmpty).length,
                        isPrivateRoom: _selectedRoom?.isPrivate ?? false,
                        roomIdentifier: _selectedRoom?.roomIdentifier,
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

// ── Components required inside this dialog ────────────────────────────────────

class _AttendantEntry {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController relationController = TextEditingController();

  void dispose() {
    nameController.dispose();
    ageController.dispose();
    relationController.dispose();
  }
}

class _Row3 extends StatelessWidget {
  final Widget a, b, c;
  const _Row3(this.a, this.b, this.c);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
        const SizedBox(width: 12),
        Expanded(child: c),
      ],
    );
  }
}

class _NatureField extends StatelessWidget {
  final String label;
  final String hint;
  final bool isDate;
  final TextInputType keyboard;
  final TextEditingController? controller;
  final VoidCallback? onTap;

  const _NatureField({
    required this.label,
    required this.hint,
    this.isDate = false,
    this.keyboard = TextInputType.text,
    this.controller,
    this.onTap,
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
          readOnly: isDate,
          onTap: onTap,
          keyboardType: isDate ? TextInputType.datetime : keyboard,
          style: const TextStyle(fontSize: 13, color: Color(0xFF27500A)),
          decoration: InputDecoration(
            hintText: isDate ? "DD / MM / YYYY" : hint,
            hintStyle: TextStyle(
              color: const Color(0xFF97C459).withValues(alpha: 0.75),
              fontSize: 13,
            ),
            suffixIcon: isDate
                ? const Icon(Icons.calendar_today_outlined, color: Color(0xFF639922), size: 16)
                : null,
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
        ),
      ],
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  final int bedsCount;
  final int attendantsCount;
  final bool isPrivateRoom;
  final String? roomIdentifier;

  static const double _bedRatePerDay = 500.0;         // ₹ per bed per day
  static const double _attendantRatePerDay = 150.0;   // ₹ per attendant per day
  static const int _defaultDays = 7;                  // default stay duration

  const _PaymentSummary({
    required this.bedsCount,
    required this.attendantsCount,
    required this.isPrivateRoom,
    this.roomIdentifier,
  });

  String _fmt(double amount) {
    if (amount >= 1000) {
      return '₹${amount.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'),
        (m) => '${m[1]},',
      )}';
    }
    return '₹${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    if (roomIdentifier == null) return const SizedBox.shrink();

    final bedTotal = isPrivateRoom ? (700.0 * _defaultDays) : (bedsCount * 600.0 * _defaultDays);
    final attendantTotal = isPrivateRoom ? (attendantsCount * 200.0 * _defaultDays) : 0.0;
    final grandTotal = bedTotal + attendantTotal;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B6D11), Color(0xFF5A9A1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B6D11).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'PAYMENT SUMMARY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_defaultDays-day estimate',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                _SummaryRow(
                  icon: Icons.bed_outlined,
                  label: isPrivateRoom ? 'Private Room' : 'Grouped Beds ($bedsCount)',
                  count: isPrivateRoom ? 1 : bedsCount,
                  rate: isPrivateRoom ? 700.0 : 600.0,
                  total: bedTotal,
                  days: _defaultDays,
                ),
                if (isPrivateRoom) ...[
                  const SizedBox(height: 8),
                  _SummaryRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Attendants',
                    count: attendantsCount,
                    rate: 200.0,
                    total: attendantTotal,
                    days: _defaultDays,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 0.5, color: Colors.white.withValues(alpha: 0.3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Estimated Total',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _fmt(grandTotal),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: const Text(
              '* Estimate based on standard rates. Actual charges may vary.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 9.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final double rate;
  final double total;
  final int days;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.rate,
    required this.total,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    final isZero = count == 0;
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label × $count',
            style: TextStyle(
              color: Colors.white.withValues(alpha: isZero ? 0.5 : 1.0),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          isZero ? '—' : '₹${rate.toStringAsFixed(0)}/day × $days days',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 10.5,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: Text(
            isZero ? '₹0' : '₹${total.toStringAsFixed(0)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withValues(alpha: isZero ? 0.5 : 1.0),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
