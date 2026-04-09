import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../models/room_model.dart';
import '../../../models/bed_model.dart';

class AddPatientDialog extends StatefulWidget {
  final Function()? onPatientAdded;

  const AddPatientDialog({super.key, this.onPatientAdded});

  @override
  State<AddPatientDialog> createState() => _AddPatientDialogState();
}

class _AddPatientDialogState extends State<AddPatientDialog> {
  bool _isLoading = false;

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
  final _relationController = TextEditingController();

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
    _attendantNameController.dispose();
    _attendantAgeController.dispose();
    _relationController.dispose();
    _registrationNumberController.dispose();
    _registrationDateController.dispose();
    _panCardController.dispose();
    _aadhaarCardController.dispose();
    _receiptNumberController.dispose();
    _utiNumberController.dispose();
    super.dispose();
  }

  /// Load all rooms (no filtering)
  Future<void> _loadAvailableRooms() async {
    try {
      final rooms = await ServiceLocator().roomService.getRoomsStream().first;
      setState(() {
        _availableRooms = rooms; // Show all rooms without filtering
      });
    } catch (e) {
      // Silently fail - user can retry by reopening dialog
    }
  }

  /// Handle room selection and load available beds
  void _onRoomSelected(RoomModel? room) {
    setState(() {
      _selectedRoom = room;
      _selectedBeds = []; // Reset bed selection
      _availableBeds = room?.beds.where((b) => b.isAvailable).toList() ?? [];
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
      
      // Check all selected beds are still available
      for (final selectedBed in _selectedBeds) {
        final bed = room.beds.where((b) => b.id == selectedBed.id).firstOrNull;
        if (bed == null || !bed.isAvailable) {
          throw Exception('Bed ${selectedBed.bedLabel} is no longer available. Please reselect beds.');
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
      );

      // Get attendant count (default to 1 if not specified)
      final attendantCount = int.tryParse(_attendantAgeController.text.trim()) != null ? 1 : 1;

      // Create a stay for each selected bed
      for (final bed in _selectedBeds) {
        await roomService.createStay(
          patientId: patientId,
          patientName: _patientNameController.text.trim(),
          roomId: _selectedRoom!.id,
          roomNumber: _selectedRoom!.roomIdentifier,
          roomType: _selectedRoom!.roomType,
          admissionDate: admissionDate,
          durationDays: 7, // Default 7 days
          attendantCount: attendantCount,
          bedId: bed.id,
          bedLabel: bed.bedLabel,
          notes: _selectedBeds.length > 1 
              ? 'Multiple beds: ${_selectedBeds.map((b) => b.bedLabel).join(", ")}'
              : 'Initial admission',
          createdBy: currentUser.uid,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onPatientAdded?.call();
        _showSuccess('Patient admitted successfully with ${_selectedBeds.length} bed(s)');
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
          color: Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Section(
                        label: "Patient information",
                        child: Column(
                          children: [
                            _Row2(
                              _NatureField(
                                label: "Date",
                                hint: "",
                                isDate: true,
                                controller: _dateController,
                                onTap: () => _selectDate(context),
                              ),
                              _NatureField(
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
                              _NatureField(
                                label: "Mobile no",
                                hint: "+91 XXXXX XXXXX",
                                keyboard: TextInputType.phone,
                                controller: _mobileController,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _Row3(
                              _NatureDropdown(
                                label: "Gender",
                                items: const ["Male", "Female", "Other"],
                                onChanged: (value) {
                                  setState(() => _selectedGender = value);
                                },
                              ),
                              _NatureField(
                                label: "Age",
                                hint: "Years",
                                keyboard: TextInputType.number,
                                controller: _ageController,
                              ),
                              _NatureField(
                                label: "Pincode",
                                hint: "000000",
                                keyboard: TextInputType.number,
                                controller: _pincodeController,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _NatureField(
                              label: "Permanent address",
                              hint: "Street, city, district",
                              controller: _addressController,
                            ),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(
                                label: "State",
                                hint: "State",
                                controller: _stateController,
                              ),
                              _NatureField(
                                label: "Mumbai local contact address",
                                hint: "Local address",
                                controller: _localAddressController,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Medical details",
                        child: Column(
                          children: [
                            _NatureField(
                              label: "Diagnosis",
                              hint: "Primary diagnosis",
                              controller: _diagnosisController,
                            ),
                            const SizedBox(height: 12),
                            _Row2(
                              _NatureField(
                                label: "Doctor name",
                                hint: "Dr. name",
                                controller: _doctorNameController,
                              ),
                              _NatureField(
                                label: "Hospital name",
                                hint: "Hospital / clinic",
                                controller: _hospitalNameController,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        label: "Attendant details",
                        child: _Row3(
                          _NatureField(
                            label: "Attendant name",
                            hint: "Full name",
                            controller: _attendantNameController,
                          ),
                          _NatureField(
                            label: "Attendant age",
                            hint: "Years",
                            keyboard: TextInputType.number,
                            controller: _attendantAgeController,
                          ),
                          _NatureField(
                            label: "Relation to patient",
                            hint: "e.g. Spouse",
                            controller: _relationController,
                          ),
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

