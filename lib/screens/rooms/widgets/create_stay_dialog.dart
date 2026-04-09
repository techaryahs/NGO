import 'package:flutter/material.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/patient_model.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/screens/rooms/widgets/create_stay_dialog_components.dart';

class CreateStayDialog extends StatefulWidget {
  final RoomModel room;

  const CreateStayDialog({super.key, required this.room});

  @override
  State<CreateStayDialog> createState() => _CreateStayDialogState();
}

class _CreateStayDialogState extends State<CreateStayDialog> {
  PatientModel? selectedPatient;
  DateTime admissionDate = DateTime.now();
  int durationDays = 7;
  int attendantCount = 1;
  BedModel? selectedBed;
  final TextEditingController notesController = TextEditingController();

  bool isLoading = false;
  Map<String, dynamic>? pricing;
  double calculatedCost = 0;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  @override
  void dispose() {
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPricing() async {
    try {
      final roomService = ServiceLocator().roomService;
      final pricingData = await roomService.getPricing();
      setState(() {
        pricing = pricingData;
        _calculateCost();
      });
    } catch (e) {
      // Use defaults if pricing fails to load
    }
  }

  void _calculateCost() {
    if (pricing == null) return;

    if (widget.room.isPrivate) {
      final basePrice = (pricing!['privateRoomBasePrice'] ?? 600).toDouble();
      final includedAttendants = pricing!['privateRoomIncludedAttendants'] ?? 2;
      final extraFee = (pricing!['privateRoomExtraAttendantFee'] ?? 200)
          .toDouble();

      calculatedCost = RoomModel.calculatePrivateRoomCost(
        days: durationDays,
        attendants: attendantCount,
        basePrice: basePrice,
        includedAttendants: includedAttendants,
        extraAttendantFee: extraFee,
      );
    } else {
      final bedPrice = (pricing!['generalRoomBedPrice'] ?? 150).toDouble();
      calculatedCost = RoomModel.calculateGeneralRoomCost(
        days: durationDays,
        bedPrice: bedPrice,
        attendants: attendantCount,
      );
    }
  }

  Future<void> _createStay() async {
    if (selectedPatient == null) {
      _showSnackBar("Please select a patient", isError: true);
      return;
    }

    if (widget.room.isGeneral && selectedBed == null) {
      _showSnackBar("Please select a bed", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final roomService = ServiceLocator().roomService;
      final authService = ServiceLocator().authService;
      final user = authService.currentUser;
      if (user == null) throw Exception("User not authenticated");

      await roomService.createStay(
        patientId: selectedPatient!.id,
        patientName: selectedPatient!.fullName,
        roomId: widget.room.id,
        roomNumber: widget.room.roomNumber,
        roomType: widget.room.roomType,
        admissionDate: admissionDate,
        durationDays: durationDays,
        attendantCount: attendantCount,
        bedId: selectedBed?.id,
        bedLabel: selectedBed?.bedLabel,
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        createdBy: user.email,
      );

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("Stay created successfully");
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Failed to create stay: $e", isError: true);
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

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: admissionDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        admissionDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 750),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        ),
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
                        Icons.add_circle_outline_rounded,
                        color: Color(0xFF3B6D11),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Create New Stay",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        Text(
                          "Room ${widget.room.roomIdentifier} • ${widget.room.isPrivate ? 'Private' : 'General'}",
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF639922),
                          ),
                        ),
                      ],
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

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Patient Selection
                    const Text(
                      "SELECT PATIENT",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<PatientModel>>(
                      stream: ServiceLocator().patientService
                          .getPatientsByStatus('active'),
                      builder: (context, snapshot) {
                        final patients = snapshot.data ?? [];
                        final availablePatients = patients
                            .where((p) => p.roomId == null)
                            .toList();

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F9F0),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFC0DD97),
                              width: 1,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<PatientModel>(
                              value: selectedPatient,
                              isExpanded: true,
                              hint: const Text("Select a patient"),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF639922),
                              ),
                              items: availablePatients.map((patient) {
                                return DropdownMenuItem(
                                  value: patient,
                                  child: Text(patient.fullName),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => selectedPatient = value);
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Admission Date
                    const Text(
                      "ADMISSION DATE",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F9F0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFC0DD97),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              color: Color(0xFF639922),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "${admissionDate.day}/${admissionDate.month}/${admissionDate.year}",
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF27500A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Duration
                    const Text(
                      "STAY DURATION (DAYS)",
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
                            if (durationDays > 1) {
                              setState(() {
                                durationDays--;
                                _calculateCost();
                              });
                            }
                          },
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          color: const Color(0xFF639922),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F9F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFC0DD97),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              "$durationDays days",
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
                            setState(() {
                              durationDays++;
                              _calculateCost();
                            });
                          },
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          color: const Color(0xFF639922),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Attendants
                    const Text(
                      "NUMBER OF ATTENDANTS",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF27500A),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(widget.room.isPrivate ? 5 : 2, (
                        index,
                      ) {
                        final count = index + 1;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: index < (widget.room.isPrivate ? 4 : 1)
                                  ? 8
                                  : 0,
                            ),
                            child: CreateStayCountChip(
                              count: count,
                              isSelected: attendantCount == count,
                              onTap: () {
                                setState(() {
                                  attendantCount = count;
                                  _calculateCost();
                                });
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    if (!widget.room.isPrivate && attendantCount == 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFFFB74D),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Color(0xFFE65100),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "2nd attendant is self-expense (not included in package)",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Bed Selection (for general rooms with hierarchical beds)
                    if (widget.room.isGeneral &&
                        widget.room.beds.isNotEmpty) ...[
                      const Text(
                        "SELECT BED",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF27500A),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CreateStayBedSelectionGrid(
                        beds: widget.room.beds,
                        selectedBed: selectedBed,
                        onBedSelected: (bed) {
                          setState(() => selectedBed = bed);
                        },
                      ),
                      const SizedBox(height: 20),
                    ] else if (widget.room.isGeneral) ...[
                      // Legacy bed number selection
                      const Text(
                        "SELECT BED NUMBER",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF27500A),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(widget.room.totalBeds, (index) {
                          final bedNum = index + 1;
                          return CreateStayCountChip(
                            count: bedNum,
                            isSelected:
                                selectedBed?.bedLabel == bedNum.toString(),
                            onTap: () {
                              setState(() {
                                selectedBed = BedModel(
                                  id: '${widget.room.id}_$bedNum',
                                  bedLabel: bedNum.toString(),
                                  status: 'available',
                                );
                              });
                            },
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Cost Summary
                    if (pricing != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3DE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFC0DD97),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Estimated Total Cost",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF27500A),
                              ),
                            ),
                            Text(
                              "₹${calculatedCost.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3B6D11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Notes
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
                  ],
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
                  onPressed: isLoading ? null : _createStay,
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
                  label: Text(isLoading ? "Creating..." : "Create Stay"),
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
    );
  }
}
