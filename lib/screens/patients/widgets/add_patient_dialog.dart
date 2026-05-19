import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/room_model.dart';
import '../../../models/bed_model.dart';
import '../../../models/patient_model.dart';
import 'patient_form_components.dart';
import 'payment_dialog.dart';

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
  final _attendantCountController = TextEditingController();
  
  // List to hold multiple attendants
  final List<_AttendantEntry> _attendants = [_AttendantEntry()];

  // New field controllers
  final _registrationNumberController = TextEditingController();
  final _registrationDateController = TextEditingController();
  final _panCardController = TextEditingController();
  final _aadhaarCardController = TextEditingController();
  final _receiptNumberController = TextEditingController();
  final _utiNumberController = TextEditingController();

  String? _selectedGender;
  DateTime? _selectedDate;
  DateTime? _selectedRegistrationDate;
  String? _selectedModeOfPayment;
  
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
    for (final attendant in _attendants) {
      attendant.dispose();
    }
    _attendantCountController.dispose();
    _registrationNumberController.dispose();
    _registrationDateController.dispose();
    _panCardController.dispose();
    _aadhaarCardController.dispose();
    _receiptNumberController.dispose();
    _utiNumberController.dispose();
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
        _dateController.text = '${picked.day.toString().padLeft(2, '0')} / ${picked.month.toString().padLeft(2, '0')} / ${picked.year}';
      });
    }
  }

  Future<void> _selectRegistrationDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
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
        _selectedRegistrationDate = picked;
        _registrationDateController.text =
            '${picked.day.toString().padLeft(2, '0')} / ${picked.month.toString().padLeft(2, '0')} / ${picked.year}';
      });
    }
  }

  /// Step 1 — Validate form, show payment dialog, then save on confirmation.
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
    if (_attendants.isEmpty || _attendants.first.nameController.text.trim().isEmpty) {
      _showError('Please enter at least one attendant name');
      return;
    }
    if (_selectedRoom?.isPrivate == true) {
      final attendantCount = int.tryParse(_attendantCountController.text.trim());
      if (attendantCount == null || attendantCount < 1 || attendantCount > 5) {
        _showError('Please enter a valid attendant count (1-5) for private rooms');
        return;
      }
    }
    if (_selectedRoom == null) {
      _showError('Please select a room');
      return;
    }
    if (_selectedBeds.isEmpty) {
      _showError('Please select at least one bed');
      return;
    }

    // Show payment dialog before saving.
    final payment = await showPatientPaymentDialog(
      context: context,
      patientName: _patientNameController.text.trim(),
      contactNumber: _mobileController.text.trim(),
      bedsCount: _selectedBeds.length,
      attendantsCount: _attendants.where((a) => a.nameController.text.trim().isNotEmpty).length,
      roomIdentifier: _selectedRoom?.roomIdentifier,
    );
    if (payment == null) return; // User cancelled

    await _doSavePatient(payment);
  }

  /// Step 2 — Actual database save (validation already done by _savePatient).
  Future<void> _doSavePatient(PaymentModel initialPayment) async {
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
      if (_attendantCountController.text.trim().isNotEmpty) {
        notesList.add(
          'Attendant Count: ${_attendantCountController.text.trim()}',
        );
      }
      final structuredAttendants = <AttendantModel>[];

      for (int i = 0; i < _attendants.length; i++) {
        final att = _attendants[i];
        final name = att.nameController.text.trim();
        final age = att.ageController.text.trim();
        final relation = att.relationController.text.trim();
        if (name.isNotEmpty) {
          notesList.add('Attendant ${i + 1}: $name (Age: ${age.isEmpty ? 'N/A' : age}, Relation: ${relation.isEmpty ? 'N/A' : relation})');
          structuredAttendants.add(AttendantModel(
            name: name,
            age: age.isNotEmpty ? age : null,
            relation: relation.isNotEmpty ? relation : null,
          ));
        }
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
        emergencyContactName: _attendants.isNotEmpty ? _attendants.first.nameController.text.trim() : "",
        medicalCondition: _diagnosisController.text.trim(),
        admissionDate: admissionDate,
        roomId: _selectedRoom!.id,
        roomNumber: _selectedRoom!.roomIdentifier,
        floor: _selectedRoom!.floor,
        bedIds: _selectedBeds.map((b) => b.id).toList(),
        bedLabels: _selectedBeds.map((b) => b.bedLabel).toList(),
        notes: notesList.isEmpty ? null : notesList.join('\n'),
        createdBy: currentUser.uid,
        registrationNumber: _registrationNumberController.text.trim().isNotEmpty
            ? _registrationNumberController.text.trim()
            : null,
        registrationDate: _selectedRegistrationDate,
        panCardNumber: _panCardController.text.trim().isNotEmpty
            ? _panCardController.text.trim()
            : null,
        aadhaarCardNumber: _aadhaarCardController.text.trim().isNotEmpty
            ? _aadhaarCardController.text.trim()
            : null,
        receiptNumber: _receiptNumberController.text.trim().isNotEmpty
            ? _receiptNumberController.text.trim()
            : null,
        modeOfPayment: _selectedModeOfPayment,
        utiNumber: _utiNumberController.text.trim().isNotEmpty
            ? _utiNumberController.text.trim()
            : null,
        attendants: structuredAttendants.isNotEmpty ? structuredAttendants : null,
        payments: [initialPayment],
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
                            _Row2(
                              _NatureField(
                                label: "Registration number",
                                hint: "e.g. REG-2024-001",
                                controller: _registrationNumberController,
                              ),
                              _NatureField(
                                label: "Registration date",
                                hint: "",
                                isDate: true,
                                controller: _registrationDateController,
                                onTap: () => _selectRegistrationDate(context),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(
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
                      _Section(
                        label: "Identity documents",
                        child: _Row2(
                          _NatureField(
                            label: "PAN card number",
                            hint: "ABCDE1234F",
                            controller: _panCardController,
                          ),
                          _NatureField(
                            label: "Aadhaar card number",
                            hint: "XXXX XXXX XXXX",
                            keyboard: TextInputType.number,
                            controller: _aadhaarCardController,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Office use",
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
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(
                                label: "Receipt number",
                                hint: "e.g. RCP-2024-001",
                                controller: _receiptNumberController,
                              ),
                              _NatureDropdown(
                                label: "Mode of payment",
                                items: const [
                                  "Cash",
                                  "UPI",
                                  "Card",
                                  "Cheque",
                                  "NEFT / RTGS",
                                  "Other",
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedModeOfPayment = value);
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            _NatureField(
                              label: "UTI number",
                              hint: "Unique transaction identifier",
                              controller: _utiNumberController,
                            ),
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
              _DialogFooter(
                onCancel: () => Navigator.pop(context),
                onSave: _isLoading ? null : _savePatient,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F9F0),
        border: Border(bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3DE),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC0DD97), width: 1.5),
            ),
            child: const Icon(Icons.person_add_outlined, color: Color(0xFF3B6D11), size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Add patient",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF27500A)),
              ),
              Text(
                "Fill in the details below to register a new patient",
                style: TextStyle(fontSize: 12, color: Color(0xFF639922)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _DialogFooter extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final bool isLoading;

  const _DialogFooter({
    required this.onCancel,
    required this.onSave,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F9F0),
        border: Border(top: BorderSide(color: Color(0xFFC0DD97), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: isLoading ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF639922),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFC0DD97)),
              ),
            ),
            child: const Text("Cancel", style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: onSave,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEAF3DE)),
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(
              isLoading ? "Saving..." : "Save patient",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B6D11),
              foregroundColor: const Color(0xFFEAF3DE),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section ───────────────────────────────────────────────────────────────────

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
            const Expanded(child: Divider(color: Color(0xFFC0DD97), thickness: 0.5)),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

// ── Grid helpers ──────────────────────────────────────────────────────────────

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

// ── Field ─────────────────────────────────────────────────────────────────────

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
              color: const Color(0xFF97C459).withOpacity(0.75),
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

// ── Dropdown ──────────────────────────────────────────────────────────────────

class _NatureDropdown extends StatefulWidget {
  final String label;
  final List<String> items;
  final ValueChanged<String?>? onChanged;

  const _NatureDropdown({
    required this.label,
    required this.items,
    this.onChanged,
  });

  @override
  State<_NatureDropdown> createState() => _NatureDropdownState();
}

class _NatureDropdownState extends State<_NatureDropdown> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: selected,
          hint: Text(
            "Select",
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
          items: widget.items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            setState(() => selected = v);
            widget.onChanged?.call(v);
          },
        ),
      ],
    );
  }
}

// ── Room Dropdown ─────────────────────────────────────────────────────────────

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

// ── Bed Selection ─────────────────────────────────────────────────────────────

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

// ── Payment Summary ───────────────────────────────────────────────────────────

class _PaymentSummary extends StatelessWidget {
  final int bedsCount;
  final int attendantsCount;
  final bool isPrivateRoom;
  final String? roomIdentifier;

  // ── Pricing constants (edit here to update rates) ──
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
    // Don't show until a room is selected
    if (roomIdentifier == null) return const SizedBox.shrink();

    final bedTotal = bedsCount * _bedRatePerDay * _defaultDays;
    final attendantTotal = attendantsCount * _attendantRatePerDay * _defaultDays;
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
          // Header
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

          // Divider
          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.3)),

          // Breakdown rows
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                _SummaryRow(
                  icon: Icons.bed_outlined,
                  label: 'Beds',
                  count: bedsCount,
                  rate: _bedRatePerDay,
                  total: bedTotal,
                  days: _defaultDays,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Attendants',
                  count: attendantsCount,
                  rate: _attendantRatePerDay,
                  total: attendantTotal,
                  days: _defaultDays,
                ),
              ],
            ),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 0.5, color: Colors.white.withValues(alpha: 0.3)),
          ),

          // Grand total
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

          // Disclaimer
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
