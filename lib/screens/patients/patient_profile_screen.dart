import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/patient_model.dart';
import '../../../models/stay_model.dart';
import '../../../services/service_locator.dart';
import 'widgets/edit_patient_dialog.dart';
import 'widgets/payment_dialog.dart';
import '../../utils/bed_helper.dart';
import 'utils/patient_info_download.dart';

class PatientProfileScreen extends StatefulWidget {
  final PatientModel patient;
  const PatientProfileScreen({super.key, required this.patient});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Uint8List? _decodePhoto(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      final base64Part = dataUrl.contains(',')
          ? dataUrl.split(',').last
          : dataUrl;
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  void _showEditDialog(BuildContext context, PatientModel currentPatient) {
    showDialog(
      context: context,
      builder: (context) => EditPatientDialog(
        patient: currentPatient,
        onPatientUpdated: () {
          setState(() {});
        },
      ),
    );
  }

  Future<void> _handlePayNow(
    BuildContext context,
    PatientModel currentPatient,
  ) async {
    final result = await showPatientPaymentDialog(
      context: context,
      patientName: currentPatient.fullName,
      contactNumber: currentPatient.contactNumber,
      bedsCount: currentPatient.bedIds?.length ?? 1,
      attendantsCount: currentPatient.attendants?.length ?? 0,
      roomIdentifier: currentPatient.roomNumber,
      alreadyPaid: currentPatient.totalPaidAmount ?? 0.0,
      showPayLater: false,
      totalBillOverride:
          currentPatient.advanceBilledAmount + currentPatient.attendanceCharges,
    );

    if (result != null && result.payment != null) {
      await ServiceLocator().patientService.recordPayment(
        currentPatient.id,
        result.payment!,
      );
      await ServiceLocator().patientService.updatePatient(currentPatient.id, {
        'paymentPending': result.payment!.paymentStatus == "Pending",
        'paymentStatus': result.payment!.paymentStatus,
        'totalPaidAmount': result.payment!.paidAmount,
        'currentDueAmount': result.payment!.pendingAmount,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successfully processed!'),
            backgroundColor: Color(0xFF3B6D11),
          ),
        );
      }
    }
  }

  Future<void> _downloadPatientInfo(PatientModel patient) async {
    print("INSIDE DOWNLOAD FUNCTION");

    try {
      print("STEP 1");

      final dateFmt = DateFormat('dd/MM/yyyy');
      final currencyFmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);

      print("STEP 2");

      final attendants = patient.attendants ?? [];

      final bedLabels =
          patient.bedLabels != null && patient.bedLabels!.isNotEmpty
          ? patient.bedLabels!
                .map(
                  (bed) => BedHelper.getBedDisplayName(
                    bed.toString().trim(),
                    roomIdentifier: patient.roomNumber,
                  ),
                )
                .toSet()
                .join(', ')
          : '';

      final totalAmount =
          (patient.totalPaidAmount ?? 0) + (patient.currentDueAmount ?? 0);

      print("STEP 3 - Creating Excel");

      final excel = Excel.createExcel();

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      //
      // =========================
      // PATIENT DETAILS SHEET
      // =========================
      //
      final patientSheet = excel['Patient Details'];

      patientSheet.appendRow([TextCellValue('Field'), TextCellValue('Value')]);

      patientSheet.appendRow([
        TextCellValue('Patient Name'),
        TextCellValue(patient.fullName),
      ]);

      patientSheet.appendRow([
        TextCellValue('Patient ID'),
        TextCellValue(patient.id),
      ]);

      patientSheet.appendRow([
        TextCellValue('Registration Number'),
        TextCellValue(patient.registrationNumber ?? ''),
      ]);

      patientSheet.appendRow([
        TextCellValue('Status'),
        TextCellValue(patient.status),
      ]);

      patientSheet.appendRow([
        TextCellValue('Age'),
        TextCellValue('${patient.age} Years'),
      ]);

      patientSheet.appendRow([
        TextCellValue('Gender'),
        TextCellValue(patient.gender),
      ]);

      patientSheet.appendRow([
        TextCellValue('Date of Birth'),
        TextCellValue(dateFmt.format(patient.dateOfBirth)),
      ]);

      patientSheet.appendRow([
        TextCellValue('Contact Number'),
        TextCellValue(patient.contactNumber),
      ]);

      patientSheet.appendRow([
        TextCellValue('Emergency Contact Name'),
        TextCellValue(patient.emergencyContactName),
      ]);

      patientSheet.appendRow([
        TextCellValue('Emergency Contact Number'),
        TextCellValue(patient.emergencyContact),
      ]);

      patientSheet.appendRow([
        TextCellValue('Medical Condition'),
        TextCellValue(patient.medicalCondition),
      ]);

      patientSheet.appendRow([
        TextCellValue('Room Number'),
        TextCellValue(patient.roomNumber ?? ''),
      ]);

      patientSheet.appendRow([
        TextCellValue('Floor'),
        TextCellValue(patient.floor?.toString() ?? ''),
      ]);

      patientSheet.appendRow([
        TextCellValue('Assigned Beds'),
        TextCellValue(bedLabels),
      ]);

      patientSheet.appendRow([
        TextCellValue('Admission Date'),
        TextCellValue(dateFmt.format(patient.admissionDate)),
      ]);

      patientSheet.appendRow([
        TextCellValue('Aadhaar Number'),
        TextCellValue(patient.aadhaarCardNumber ?? ''),
      ]);

      patientSheet.appendRow([
        TextCellValue('PAN Card Number'),
        TextCellValue(patient.panCardNumber ?? ''),
      ]);

      patientSheet.appendRow([
        TextCellValue('Notes'),
        TextCellValue(patient.notes ?? ''),
      ]);

      //
      // =========================
      // BILLING DETAILS SHEET
      // =========================
      //
      final billingSheet = excel['Billing Details'];

      billingSheet.appendRow([TextCellValue('Field'), TextCellValue('Value')]);

      billingSheet.appendRow([
        TextCellValue('Total Amount'),
        TextCellValue(currencyFmt.format(totalAmount)),
      ]);

      billingSheet.appendRow([
        TextCellValue('Paid Amount'),
        TextCellValue(currencyFmt.format(patient.totalPaidAmount ?? 0)),
      ]);

      billingSheet.appendRow([
        TextCellValue('Pending Amount'),
        TextCellValue(currencyFmt.format(patient.currentDueAmount ?? 0)),
      ]);

      billingSheet.appendRow([
        TextCellValue('Payment Status'),
        TextCellValue(patient.paymentStatus ?? 'Pending'),
      ]);

      //
      // =========================
      // ATTENDANTS SHEET
      // =========================
      //
      final attendantsSheet = excel['Attendants'];

      attendantsSheet.appendRow([
        TextCellValue('Sr No'),
        TextCellValue('Name'),
        TextCellValue('Age'),
        TextCellValue('Relation'),
      ]);

      for (int i = 0; i < attendants.length; i++) {
        final attendant = attendants[i];

        attendantsSheet.appendRow([
          TextCellValue('${i + 1}'),
          TextCellValue(attendant.name),
          TextCellValue(
            attendant.age != null ? attendant.age.toString() : 'N/A',
          ),
          TextCellValue(
            attendant.relation != null && attendant.relation!.trim().isNotEmpty
                ? attendant.relation!
                : 'N/A',
          ),
        ]);
      }

      excel.setDefaultSheet('Patient Details');

      print("STEP 4 - Before Save");

      final bytes = excel.save();

      print("STEP 5 - After Save");

      if (bytes == null) {
        throw Exception('Could not create Excel file');
      }

      print("STEP 6 - Bytes length: ${bytes.length}");

      final safeName = patient.fullName
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '')
          .toLowerCase();

      print("STEP 7 - Opening Save Dialog");

      final savedLocation = await savePatientInfoWorkbook(
        bytes: bytes,
        fileName: 'patient_${safeName.isEmpty ? patient.id : safeName}',
      );

      print("STEP 8 - Dialog Returned");
      print(savedLocation);

      if (savedLocation == null) {
        print("STEP 9 - User Cancelled");

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Download cancelled')));
        }
        return;
      }

      print("STEP 10 - Success");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient info downloaded successfully'),
          backgroundColor: Color(0xFF3B6D11),
        ),
      );
    } catch (e, st) {
      print("DOWNLOAD ERROR: $e");
      print(st);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
    }
  }

  void _showDischargeConfirmation(
    BuildContext context,
    PatientModel currentPatient,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Discharge Patient'),
        content: Text(
          'Are you sure you want to discharge ${currentPatient.fullName}? This will remove them from their assigned room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ServiceLocator().patientService.dischargePatient(
                  currentPatient.id,
                );
                if (context.mounted) {
                  Navigator.pop(context); // Close confirmation
                  Navigator.pop(context); // Close profile page, back to listing
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Patient discharged successfully'),
                      backgroundColor: Color(0xFF3B6D11),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: const Color(0xFFD32F2F),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            child: const Text('Discharge'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PatientModel>>(
      stream: ServiceLocator().patientService.getPatientsStream(),
      builder: (context, snapshot) {
        final patientList = snapshot.data ?? [];
        final currentPatient = patientList.firstWhere(
          (p) => p.id == widget.patient.id,
          orElse: () => widget.patient,
        );

        final isActive =
            currentPatient.status == 'active' ||
            currentPatient.status.toLowerCase() == 'paid';
        final showPayBtn =
            (currentPatient.currentDueAmount ?? 0) > 0 ||
            currentPatient.paymentStatus != 'Paid';
        final payBtnLabel = currentPatient.paymentStatus == 'Partial'
            ? 'Pay Remaining'
            : 'Pay Now';
        final photoBytes = _decodePhoto(currentPatient.photoDataUrl);

        return Scaffold(
          backgroundColor: const Color(0xFFF0F7EA),
          body: Column(
            children: [
              // Sticky Top Navigation / Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFDF7),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    // Back button and Actions row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back to Patients button
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFF3B6D11),
                            size: 20,
                          ),
                          label: const Text(
                            "Back to Patients",
                            style: TextStyle(
                              color: Color(0xFF3B6D11),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            backgroundColor: const Color(0xFFEAF3DE),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),

                        // Action buttons row
                        Row(
                          children: [
                            ElevatedButton.icon(
                              // onPressed: () =>
                              //     _downloadPatientInfo(currentPatient),
                              onPressed: () {
                                print("DOWNLOAD BUTTON CLICKED");
                                _downloadPatientInfo(currentPatient);
                              },
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 16,
                              ),
                              label: const Text('Download Excel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF3B6D11),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(
                                    color: Color(0xFF3B6D11),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (isActive) ...[
                              // Discharge Patient
                              OutlinedButton.icon(
                                onPressed: () => _showDischargeConfirmation(
                                  context,
                                  currentPatient,
                                ),
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  size: 16,
                                ),
                                label: const Text('Discharge Patient'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFD32F2F),
                                  side: const BorderSide(
                                    color: Color(0xFFD32F2F),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Pay Now / Pay Remaining
                              if (showPayBtn) ...[
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _handlePayNow(context, currentPatient),
                                  icon: const Icon(
                                    Icons.payment_rounded,
                                    size: 16,
                                  ),
                                  label: Text(payBtnLabel),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B6D11),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],

                              // Edit Details
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _showEditDialog(context, currentPatient),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('Edit Details'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF639922),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Patient Details Header Info
                    Row(
                      children: [
                        // Avatar
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFEAF3DE)
                                : const Color(0xFFE8E8E8),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFF97C459)
                                  : const Color(0xFFBDBDBD),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: photoBytes != null
                                ? Image.memory(photoBytes, fit: BoxFit.cover)
                                : Center(
                                    child: Text(
                                      _getInitials(currentPatient.fullName),
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isActive
                                            ? const Color(0xFF3B6D11)
                                            : const Color(0xFF757575),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Information
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    currentPatient.fullName,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF27500A),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  _StatusBadge(status: currentPatient.status),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    'Patient ID: ${currentPatient.id.substring(0, 8)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF639922),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (currentPatient.registrationNumber !=
                                      null) ...[
                                    const SizedBox(width: 16),
                                    Text(
                                      'Reg No: ${currentPatient.registrationNumber}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF639922),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tab Bar
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        labelColor: const Color(0xFF3B6D11),
                        unselectedLabelColor: const Color(0xFF639922),
                        indicatorColor: const Color(0xFF3B6D11),
                        indicatorWeight: 3,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'Payment History'),
                          Tab(text: 'Attendance'),
                          Tab(text: 'Stays'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Tab View
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _OverviewTab(patient: currentPatient),
                    _PaymentHistoryTab(patient: currentPatient),
                    _AttendanceTab(patient: currentPatient),
                    _StaysTab(patient: currentPatient),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Status Badge Widget ──
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status.toLowerCase()) {
      case 'active':
        bgColor = const Color(0xFFEAF3DE);
        textColor = const Color(0xFF3B6D11);
        label = 'Active';
        break;
      case 'paid':
        bgColor = const Color(0xFFEAF3DE);
        textColor = const Color(0xFF3B6D11);
        label = 'Paid';
        break;
      case 'inactive':
        bgColor = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE65100);
        label = 'Inactive';
        break;
      case 'partial':
        bgColor = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE65100);
        label = 'Partial';
        break;
      case 'pending':
        bgColor = const Color(0xFFFFEBEE);
        textColor = const Color(0xFFD32F2F);
        label = 'Pending';
        break;
      case 'discharged':
        bgColor = const Color(0xFFE8E8E8);
        textColor = const Color(0xFF757575);
        label = 'Discharged';
        break;
      default:
        bgColor = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE65100);
        label = status[0].toUpperCase() + status.substring(1);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

// ── 1. Overview Tab ──
class _OverviewTab extends StatelessWidget {
  final PatientModel patient;

  const _OverviewTab({required this.patient});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Use a grid-like structure for personal, medical, and emergency info
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildPersonalInfo(),
                          const SizedBox(height: 20),
                          _buildFinancialSummary(),
                          const SizedBox(height: 20),
                          _buildMedicalInfo(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Expanded(
                    //   child: Column(
                    //     children: [
                    //       _buildEmergencyInfo(),
                    //       const SizedBox(height: 20),
                    //       _buildRoomAssignment(),
                    //       const SizedBox(height: 20),
                    //       _buildAdmissionDetails(),
                    //     ],
                    //   ),
                    // ),
                    Expanded(
                      child: Column(
                        children: [
                          _buildEmergencyInfo(),
                          const SizedBox(height: 20),

                          _buildRoomAssignment(),
                          const SizedBox(height: 20),

                          _buildIdentityInformation(),
                          const SizedBox(height: 20),

                          _buildAdmissionDetails(),
                          const SizedBox(height: 20),

                          _buildAttendantsDropdown(),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildPersonalInfo(),
                    const SizedBox(height: 20),
                    _buildFinancialSummary(),
                    const SizedBox(height: 20),
                    _buildMedicalInfo(),
                    const SizedBox(height: 20),
                    _buildEmergencyInfo(),
                    const SizedBox(height: 20),
                    _buildRoomAssignment(),
                    _buildIdentityInformation(),
                    const SizedBox(height: 20),
                    const SizedBox(height: 20),
                    _buildAdmissionDetails(),
                  ],
                ),

              // if (patient.notes != null && patient.notes!.isNotEmpty) ...[
              //   const SizedBox(height: 20),
              //   _Section(
              //     label: "Additional Notes",
              //     child: Container(
              //       width: double.infinity,
              //       padding: const EdgeInsets.all(16),
              //       decoration: BoxDecoration(
              //         color: const Color(0xFFFAFDF7),
              //         borderRadius: BorderRadius.circular(12),
              //         border: Border.all(
              //           color: const Color(0xFFC0DD97),
              //           width: 1,
              //         ),
              //       ),
              //       child: Text(
              //         patient.notes!,
              //         style: const TextStyle(
              //           fontSize: 14,
              //           color: Color(0xFF27500A),
              //           height: 1.5,
              //         ),
              //       ),
              //     ),
              //   ),
              // ],
              // Attendants Section
              // if (patient.attendants != null &&
              //     patient.attendants!.isNotEmpty) ...[
              //   const SizedBox(height: 20),
              //   // _Section(
              //   //   label: "Attendants",
              //   //   child: SizedBox(
              //   //     height: patient.attendants!.length > 2 ? 220 : null,
              //   //     child: patient.attendants!.length > 2
              //   //         ? ListView.builder(
              //   //             itemCount: patient.attendants!.length,
              //   //             itemBuilder: (context, index) => _AttendantCard(
              //   //               attendant: patient.attendants![index],
              //   //             ),
              //   //           )
              //   //         : Column(
              //   //             children: patient.attendants!
              //   //                 .map((a) => _AttendantCard(attendant: a))
              //   //                 .toList(),
              //   //           ),
              //   //   ),
              //   // ),
              //   _Section(
              //     label: "Attendants",
              //     child: patient.attendants!.length > 2
              //         ? SizedBox(
              //             height: 240,
              //             child: ListView.builder(
              //               physics: const AlwaysScrollableScrollPhysics(),
              //               itemCount: patient.attendants!.length,
              //               itemBuilder: (context, index) => _AttendantCard(
              //                 attendant: patient.attendants![index],
              //               ),
              //             ),
              //           )
              //         : Column(
              //             children: patient.attendants!
              //                 .map((a) => _AttendantCard(attendant: a))
              //                 .toList(),
              //           ),
              //   ),
              // ],

              // Additional Notes (attendant lines removed)
              if (patient.notes != null && patient.notes!.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Section(
                  label: "Additional Notes",
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFDF7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFC0DD97),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _cleanNotes(patient.notes!),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF27500A),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _cleanNotes(String notes) {
    final lines = notes.split('\n');
    final filtered = lines.where((line) {
      final lower = line.toLowerCase();
      return !lower.startsWith('attendant ') &&
          !lower.startsWith('attendant count');
    }).toList();
    return filtered.join('\n').trim();
  }

  Widget _buildPersonalInfo() {
    final dobStr =
        '${patient.dateOfBirth.day}/${patient.dateOfBirth.month}/${patient.dateOfBirth.year}';
    return _Section(
      label: "Personal Information",
      child: Column(
        children: [
          _Row2(
            _InfoField(
              label: "Age",
              value: "${patient.age} years",
              icon: Icons.cake_outlined,
            ),
            _InfoField(
              label: "Gender",
              value:
                  patient.gender[0].toUpperCase() + patient.gender.substring(1),
              icon: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 12),
          _Row2(
            _InfoField(
              label: "Contact Number",
              value: patient.contactNumber,
              icon: Icons.phone_outlined,
            ),
            _InfoField(
              label: "Date of Birth",
              value: dobStr,
              icon: Icons.calendar_today_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSummary() {
    final currencyFmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    double total =
        (patient.totalPaidAmount ?? 0) + (patient.currentDueAmount ?? 0);
    return _Section(
      label: "Financial Summary",
      child: Column(
        children: [
          _Row2(
            _InfoField(
              label: "Total Amount",
              value: currencyFmt.format(total),
              icon: Icons.receipt_long_outlined,
            ),
            _InfoField(
              label: "Paid Amount",
              value: currencyFmt.format(patient.totalPaidAmount ?? 0),
              icon: Icons.check_circle_outline,
            ),
          ),
          const SizedBox(height: 12),
          _Row2(
            _InfoField(
              label: "Pending Amount",
              value: currencyFmt.format(patient.currentDueAmount ?? 0),
              icon: Icons.pending_actions_outlined,
            ),
            _InfoField(
              label: "Payment Status",
              value: patient.paymentStatus ?? "Pending",
              icon: Icons.info_outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalInfo() {
    return _Section(
      label: "Medical Information",
      child: Column(
        children: [
          _InfoField(
            label: "Medical Condition",
            value: patient.medicalCondition,
            icon: Icons.medical_services_outlined,
            fullWidth: true,
          ),
          if (patient.allergies != null && patient.allergies!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoField(
              label: "Allergies",
              value: patient.allergies!,
              icon: Icons.warning_amber_rounded,
              fullWidth: true,
            ),
          ],
          if (patient.bloodType != null && patient.bloodType!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoField(
              label: "Blood Type",
              value: patient.bloodType!,
              icon: Icons.bloodtype_outlined,
              fullWidth: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmergencyInfo() {
    return _Section(
      label: "Emergency Contact",
      child: _Row2(
        _InfoField(
          label: "Contact Name",
          value: patient.emergencyContactName.isNotEmpty
              ? patient.emergencyContactName
              : "N/A",
          icon: Icons.contact_emergency_outlined,
        ),
        _InfoField(
          label: "Contact Number",
          value: patient.emergencyContact.isNotEmpty
              ? patient.emergencyContact
              : "N/A",
          icon: Icons.phone_in_talk_outlined,
        ),
      ),
    );
  }

  Widget _buildRoomAssignment() {
    if (patient.roomNumber == null) {
      return _Section(
        label: "Room Assignment",
        child: _InfoField(
          label: "Room Status",
          value: "No room assigned yet",
          icon: Icons.meeting_room_outlined,
          fullWidth: true,
        ),
      );
    }
    final bedLabels = patient.bedLabels != null && patient.bedLabels!.isNotEmpty
        ? patient.bedLabels!
              .map((bed) {
                final raw = bed.toString().trim();
                return BedHelper.getBedDisplayName(
                  raw,
                  roomIdentifier: patient.roomNumber,
                );
              })
              .toSet() // Remove duplicates
              .join(', ')
        : 'N/A';
    return _Section(
      label: "Room Assignment",
      child: Column(
        children: [
          _Row2(
            _InfoField(
              label: "Room Number",
              value: patient.roomNumber!,
              icon: Icons.meeting_room_outlined,
            ),
            _InfoField(
              label: "Floor",
              value: "Floor ${patient.floor ?? 0}",
              icon: Icons.layers_outlined,
            ),
          ),
          const SizedBox(height: 12),
          _InfoField(
            label: "Assigned Beds",
            value: bedLabels,
            icon: Icons.bed_outlined,
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityInformation() {
    return _Section(
      label: "Identity Information",
      child: _Row2(
        _InfoField(
          label: "Aadhaar Number",
          value: (patient.aadhaarCardNumber?.trim().isNotEmpty ?? false)
              ? patient.aadhaarCardNumber!
              : '—',
          icon: Icons.badge_outlined,
        ),
        _InfoField(
          label: "PAN Card Number",
          value: (patient.panCardNumber?.trim().isNotEmpty ?? false)
              ? patient.panCardNumber!
              : '—',
          icon: Icons.credit_card_outlined,
        ),
      ),
    );
  }

  Widget _buildAdmissionDetails() {
    final admStr =
        '${patient.admissionDate.day}/${patient.admissionDate.month}/${patient.admissionDate.year}';
    final daysAdmitted = DateTime.now()
        .difference(patient.admissionDate)
        .inDays;
    return _Section(
      label: "Admission Details",
      child: _Row2(
        _InfoField(
          label: "Admission Date",
          value: admStr,
          icon: Icons.event_outlined,
        ),
        _InfoField(
          label: "Days Admitted",
          value: "$daysAdmitted days",
          icon: Icons.access_time_outlined,
        ),
      ),
    );
  }

  Widget _buildAttendantsDropdown() {
    final attendants = patient.attendants ?? [];

    return _Section(
      label: "Attendees",
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.all(12),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: const Color(0xFFC0DD97).withOpacity(0.6)),
          ),

          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: const Color(0xFFC0DD97).withOpacity(0.6)),
          ),

          title: Row(
            children: [
              const Icon(Icons.people_alt_outlined, color: Color(0xFF3B6D11)),
              const SizedBox(width: 10),
              Text(
                "Attendees (${attendants.length})",
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                ),
              ),
            ],
          ),

          children: [
            SizedBox(
              height: attendants.length > 3 ? 280 : null,
              child: attendants.length > 3
                  ? Scrollbar(
                      thumbVisibility: true,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: attendants.length,
                        itemBuilder: (context, index) {
                          return _AttendantCard(attendant: attendants[index]);
                        },
                      ),
                    )
                  : Column(
                      children: attendants
                          .map((a) => _AttendantCard(attendant: a))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Widget ──
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
                fontWeight: FontWeight.bold,
                color: Color(0xFF639922),
                letterSpacing: 0.8,
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

// ── Info Field Widget ──
class _InfoField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;

  const _InfoField({
    required this.label,
    required this.value,
    required this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3DE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF3B6D11)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF639922),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Row2 helper ──
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

// ── 2. Payment History Tab ──
class _PaymentHistoryTab extends StatelessWidget {
  final PatientModel patient;

  const _PaymentHistoryTab({required this.patient});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ServiceLocator().paymentService.getAllPaymentsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
          );
        }

        final allPayments = snapshot.data ?? [];
        final patientPayments = allPayments
            .where((p) => p['patientId'] == patient.id)
            .toList();

        if (patientPayments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 64,
                  color: const Color(0xFF639922).withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  "No payment history found",
                  style: TextStyle(
                    fontSize: 16,
                    color: const Color(0xFF639922).withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        final totalPaid = patientPayments.fold(
          0.0,
          (sum, p) => sum + (p['amount'] ?? 0.0),
        );
        final currencyFmt = NumberFormat.currency(
          symbol: "₹",
          decimalDigits: 0,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total Paid Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B6D11), Color(0xFF639922)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B6D11).withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "TOTAL AMOUNT PAID",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "All payments recorded via Payments Module",
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                    Text(
                      currencyFmt.format(totalPaid),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Transaction History",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF27500A),
                ),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: patientPayments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final payment = patientPayments[index];
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    payment['date'] ?? 0,
                  );
                  final method = payment['method']?.toString() ?? "CASH";
                  final amount = (payment['amount'] ?? 0).toDouble();

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFC0DD97).withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F9F0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            method.toLowerCase().contains('online')
                                ? Icons.qr_code_rounded
                                : method.toLowerCase().contains('check')
                                ? Icons.account_balance_rounded
                                : Icons.money_rounded,
                            color: const Color(0xFF3B6D11),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                method.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF639922),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd MMM yyyy, hh:mm a').format(date),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF27500A),
                                ),
                              ),
                              if (payment['notes'] != null &&
                                  payment['notes'].toString().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  payment['notes'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              currencyFmt.format(amount),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B6D11),
                              ),
                            ),
                            if (payment['receiptNumber'] != null)
                              Text(
                                "Rec: ${payment['receiptNumber']}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 3. Attendance Tab ──
class _AttendanceTab extends StatefulWidget {
  final PatientModel patient;

  const _AttendanceTab({required this.patient});

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  late Future<Map<String, Map<String, dynamic>>> _attendanceDataFuture;
  late Future<Map<String, dynamic>> _attendantAttendanceFuture;

  @override
  void initState() {
    super.initState();

    _attendanceDataFuture = _loadAttendanceData();
    _attendantAttendanceFuture = _loadAttendantAttendance();

    _attendantAttendanceFuture.then((data) {
      print("ATTENDANT DATA = $data");
    });
  }

  Future<Map<String, Map<String, dynamic>>> _loadAttendanceData() async {
    final result = <String, Map<String, dynamic>>{};

    try {
      final data = await ServiceLocator().rtdbService.get('attendance/daily');

      if (data != null && data is Map) {
        data.forEach((dateStr, records) {
          if (records is Map) {
            records.forEach((patientId, record) {
              if (patientId == widget.patient.id && record is Map) {
                result[dateStr] = Map<String, dynamic>.from(record);
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint("Attendance error: $e");
    }

    return result;
  }

  Future<Map<String, dynamic>> _loadAttendantAttendance() async {
    final result = <String, dynamic>{};

    try {
      final data = await ServiceLocator().rtdbService.get(
        'attendant_attendance/daily',
      );

      if (data != null && data is Map) {
        data.forEach((dateStr, records) {
          if (records is Map && records.containsKey(widget.patient.id)) {
            final attendants = Map<String, dynamic>.from(
              records[widget.patient.id],
            );

            result[dateStr] = attendants;
          }
        });
      }
    } catch (e) {
      debugPrint("Attendant attendance error: $e");
    }

    return result;
  }

  Map<String, dynamic> _computeSummaries(
    Map<String, Map<String, dynamic>> attendanceMap,
  ) {
    int totalPresent = 0;
    int totalAbsent = 0;

    final monthly = <String, Map<String, int>>{};
    final yearly = <String, Map<String, int>>{};

    attendanceMap.forEach((dateStr, record) {
      final status = record['status']?.toString() ?? '';
      final isPresent = status.toLowerCase() == 'present';

      if (isPresent) {
        totalPresent++;
      } else {
        totalAbsent++;
      }

      try {
        final date = DateTime.parse(dateStr);
        final monthStr = DateFormat('MMMM yyyy').format(date);
        final yearStr = date.year.toString();

        monthly.putIfAbsent(monthStr, () => {'present': 0, 'absent': 0});
        yearly.putIfAbsent(yearStr, () => {'present': 0, 'absent': 0});

        if (isPresent) {
          monthly[monthStr]!['present'] = monthly[monthStr]!['present']! + 1;
          yearly[yearStr]!['present'] = yearly[yearStr]!['present']! + 1;
        } else {
          monthly[monthStr]!['absent'] = monthly[monthStr]!['absent']! + 1;
          yearly[yearStr]!['absent'] = yearly[yearStr]!['absent']! + 1;
        }
      } catch (_) {}
    });

    final totalDays = totalPresent + totalAbsent;
    final rate = totalDays > 0
        ? (totalPresent / totalDays * 100).toStringAsFixed(1)
        : '0.0';

    return {
      'totalPresent': totalPresent,
      'totalAbsent': totalAbsent,
      'totalDays': totalDays,
      'rate': rate,
      'monthly': monthly,
      'yearly': yearly,
    };
  }

  // @override
  // Widget build(BuildContext context) {
  //   return FutureBuilder<Map<String, Map<String, dynamic>>>(
  //     future: _attendanceDataFuture,
  //     builder: (context, snapshot) {
  //       if (snapshot.connectionState == ConnectionState.waiting) {
  //         return const Center(
  //           child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
  //         );
  //       }

  //       final patientData = snapshot.data ?? {};

  //       return FutureBuilder<Map<String, dynamic>>(
  //         future: _attendantAttendanceFuture,
  //         builder: (context, attendantSnapshot) {
  //           final attendantData = attendantSnapshot.data ?? {};

  //           // Compute totals
  //           int patientPresent = patientData.values
  //               .where((r) => r['status'] == 'Present')
  //               .length;
  //           int patientAbsent = patientData.values
  //               .where((r) => r['status'] == 'Absent')
  //               .length;

  //           // Attendant totals across all dates
  //           int attendantPresent = 0;
  //           int attendantAbsent = 0;
  //           attendantData.forEach((date, attendants) {
  //             if (attendants is Map) {
  //               attendants.forEach((key, val) {
  //                 if (val is Map) {
  //                   if (val['status'] == 'Present') attendantPresent++;
  //                   if (val['status'] == 'Absent') attendantAbsent++;
  //                 }
  //               });
  //             }
  //           });

  //           return SingleChildScrollView(
  //             padding: const EdgeInsets.all(24),
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 _CalendarView(
  //                   patientData: patientData,
  //                   attendantData: attendantData,
  //                   patientName: widget.patient.fullName,
  //                 ),
  //                 const SizedBox(height: 32),

  //                 // ── Overall summary counts ──
  //                 const Text(
  //                   "Overall Summary",
  //                   style: TextStyle(
  //                     fontSize: 16,
  //                     fontWeight: FontWeight.bold,
  //                     color: Color(0xFF27500A),
  //                   ),
  //                 ),
  //                 const SizedBox(height: 12),

  //                 // Patient counts
  //                 Container(
  //                   padding: const EdgeInsets.all(16),
  //                   decoration: BoxDecoration(
  //                     color: Colors.white,
  //                     borderRadius: BorderRadius.circular(12),
  //                     border: Border.all(
  //                       color: const Color(0xFFC0DD97).withOpacity(0.5),
  //                     ),
  //                   ),
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       const Text(
  //                         "Patient",
  //                         style: TextStyle(
  //                           fontWeight: FontWeight.w600,
  //                           fontSize: 14,
  //                           color: Color(0xFF27500A),
  //                         ),
  //                       ),
  //                       const SizedBox(height: 10),
  //                       Row(
  //                         children: [
  //                           _CountChip(
  //                             label: "Present",
  //                             count: patientPresent,
  //                             color: Colors.green,
  //                           ),
  //                           const SizedBox(width: 12),
  //                           _CountChip(
  //                             label: "Absent",
  //                             count: patientAbsent,
  //                             color: const Color(0xFFD32F2F),
  //                           ),
  //                           const SizedBox(width: 12),
  //                           _CountChip(
  //                             label: "Total",
  //                             count: patientPresent + patientAbsent,
  //                             color: const Color(0xFF3B6D11),
  //                           ),
  //                         ],
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //                 const SizedBox(height: 12),

  //                 // Attendant counts
  //                 Container(
  //                   padding: const EdgeInsets.all(16),
  //                   decoration: BoxDecoration(
  //                     color: Colors.white,
  //                     borderRadius: BorderRadius.circular(12),
  //                     border: Border.all(
  //                       color: const Color(0xFFC0DD97).withOpacity(0.5),
  //                     ),
  //                   ),
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       const Text(
  //                         "Attendants",
  //                         style: TextStyle(
  //                           fontWeight: FontWeight.w600,
  //                           fontSize: 14,
  //                           color: Color(0xFF27500A),
  //                         ),
  //                       ),
  //                       const SizedBox(height: 10),
  //                       Row(
  //                         children: [
  //                           _CountChip(
  //                             label: "Present",
  //                             count: attendantPresent,
  //                             color: Colors.green,
  //                           ),
  //                           const SizedBox(width: 12),
  //                           _CountChip(
  //                             label: "Absent",
  //                             count: attendantAbsent,
  //                             color: const Color(0xFFD32F2F),
  //                           ),
  //                           const SizedBox(width: 12),
  //                           _CountChip(
  //                             label: "Total",
  //                             count: attendantPresent + attendantAbsent,
  //                             color: const Color(0xFF3B6D11),
  //                           ),
  //                         ],
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );
  // }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: _attendanceDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
          );
        }

        final patientData = snapshot.data ?? {};

        return FutureBuilder<Map<String, dynamic>>(
          future: _attendantAttendanceFuture,
          builder: (context, attendantSnapshot) {
            final attendantData = attendantSnapshot.data ?? {};

            int patientPresent = patientData.values
                .where((r) => r['status'] == 'Present')
                .length;
            int patientAbsent = patientData.values
                .where((r) => r['status'] == 'Absent')
                .length;

            int attendantPresent = 0;
            int attendantAbsent = 0;
            attendantData.forEach((date, attendants) {
              if (attendants is Map) {
                attendants.forEach((key, val) {
                  if (val is Map) {
                    if (val['status'] == 'Present') attendantPresent++;
                    if (val['status'] == 'Absent') attendantAbsent++;
                  }
                });
              }
            });

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── LEFT: Calendar ──
                  Flexible(
                    flex: 5,
                    child: _CalendarView(
                      patientData: patientData,
                      attendantData: attendantData,
                      patientName: widget.patient.fullName,
                    ),
                  ),
                  const SizedBox(width: 28),

                  // ── RIGHT: Overall Summary ──
                  Flexible(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Overall Summary",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Patient summary
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFC0DD97).withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Patient",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF27500A),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _CountChip(
                                    label: "Present",
                                    count: patientPresent,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 10),
                                  _CountChip(
                                    label: "Absent",
                                    count: patientAbsent,
                                    color: const Color(0xFFD32F2F),
                                  ),
                                  const SizedBox(width: 10),
                                  _CountChip(
                                    label: "Total",
                                    count: patientPresent + patientAbsent,
                                    color: const Color(0xFF3B6D11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Attendant summary
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFC0DD97).withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Attendants",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF27500A),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _CountChip(
                                    label: "Present",
                                    count: attendantPresent,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 10),
                                  _CountChip(
                                    label: "Absent",
                                    count: attendantAbsent,
                                    color: const Color(0xFFD32F2F),
                                  ),
                                  const SizedBox(width: 10),
                                  _CountChip(
                                    label: "Total",
                                    count: attendantPresent + attendantAbsent,
                                    color: const Color(0xFF3B6D11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Micro Stat Item Card ──
class _StatItemCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItemCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC0DD97).withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF639922),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 4. Stays Tab ──
class _StaysTab extends StatelessWidget {
  final PatientModel patient;

  const _StaysTab({required this.patient});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StayModel>>(
      stream: ServiceLocator().roomService.getStaysByPatientStream(patient.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
          );
        }

        final stays = snapshot.data ?? [];
        final activeStays = stays.where((s) => s.status == 'active').toList();
        final pastStays = stays.where((s) => s.status != 'active').toList();

        if (stays.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.meeting_room_outlined,
                  size: 64,
                  color: const Color(0xFF639922).withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  "No stays history found",
                  style: TextStyle(
                    fontSize: 16,
                    color: const Color(0xFF639922).withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active stays
              if (activeStays.isNotEmpty) ...[
                const Text(
                  "Active Stay Details",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF27500A),
                  ),
                ),
                const SizedBox(height: 12),
                ...activeStays
                    .map((stay) => _buildActiveStayCard(stay))
                    .toList(),
                const SizedBox(height: 32),
              ],

              // Past stays
              if (pastStays.isNotEmpty) ...[
                const Text(
                  "Stay History",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF27500A),
                  ),
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pastStays.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final stay = pastStays[index];
                    return _buildCompletedStayCard(stay);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveStayCard(StayModel stay) {
    final currencyFmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM yyyy');

    final admStr = dateFmt.format(stay.admissionDate);
    final expDisStr = dateFmt.format(stay.effectiveExpiryDate);
    final daysRemaining = stay.daysRemaining;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B6D11), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B6D11).withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFEAF3DE),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.bed_outlined,
                      color: Color(0xFF3B6D11),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Room ${stay.roomNumber} • Bed ${stay.bedNumber ?? 'N/A'}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF27500A),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B6D11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "ACTIVE OCCUPANCY",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Durations
                Row(
                  children: [
                    Expanded(
                      child: _buildMicroDetail(
                        label: "Admission Date",
                        value: admStr,
                        icon: Icons.calendar_today_rounded,
                      ),
                    ),
                    Expanded(
                      child: _buildMicroDetail(
                        label: "Expected Discharge",
                        value: expDisStr,
                        icon: Icons.event_available_rounded,
                      ),
                    ),
                    Expanded(
                      child: _buildMicroDetail(
                        label: "Days Remaining",
                        value: daysRemaining >= 0
                            ? "$daysRemaining days"
                            : "Expired",
                        icon: Icons.access_time_filled_rounded,
                        valueColor: daysRemaining >= 0
                            ? const Color(0xFF3B6D11)
                            : const Color(0xFFD32F2F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Cost details
                Row(
                  children: [
                    Expanded(
                      child: _buildMicroDetail(
                        label: "Base Cost",
                        value: currencyFmt.format(stay.baseCost),
                        icon: Icons.money_rounded,
                      ),
                    ),
                    Expanded(
                      child: _buildMicroDetail(
                        label: "Extra Attendants Cost",
                        value: currencyFmt.format(stay.extraAttendantCost),
                        icon: Icons.group_outlined,
                      ),
                    ),
                    Expanded(
                      child: _buildMicroDetail(
                        label: "Total Cost",
                        value: currencyFmt.format(stay.totalCost),
                        icon: Icons.payments_outlined,
                        valueColor: const Color(0xFF3B6D11),
                      ),
                    ),
                  ],
                ),

                // Extensions Section if present
                if (stay.extensions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFFC0DD97), thickness: 0.5),
                  const SizedBox(height: 12),
                  const Text(
                    "Stay Extensions Timeline",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF27500A),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...stay.extensions.map((ext) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F9F0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFC0DD97).withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.history_rounded,
                            size: 16,
                            color: Color(0xFF639922),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Extended by ${ext.additionalDays} days on ${dateFmt.format(ext.extendedOn)}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF27500A),
                                  ),
                                ),
                                if (ext.reason.isNotEmpty)
                                  Text(
                                    "Reason: ${ext.reason}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            "+${currencyFmt.format(ext.additionalCost)}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF3B6D11),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedStayCard(StayModel stay) {
    final currencyFmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM yyyy');

    final admStr = dateFmt.format(stay.admissionDate);
    final disStr = dateFmt.format(stay.effectiveExpiryDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8E8E8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.meeting_room_outlined,
              color: Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Room ${stay.roomNumber} (Bed ${stay.bedNumber ?? 'N/A'})",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF27500A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "$admStr - $disStr (${stay.totalDays} days)",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currencyFmt.format(stay.totalCost),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF639922),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E8E8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "COMPLETED",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMicroDetail({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: const Color(0xFF639922).withOpacity(0.7),
            ),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF639922),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? const Color(0xFF27500A),
          ),
        ),
      ],
    );
  }
}

class _AttendantCard extends StatelessWidget {
  final AttendantModel attendant;

  const _AttendantCard({required this.attendant});

  Uint8List? _decodePhoto(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      final base64Part = dataUrl.contains(',')
          ? dataUrl.split(',').last
          : dataUrl;
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoBytes = _decodePhoto(attendant.photoDataUrl);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97)),
      ),
      child: Row(
        children: [
          // ── Left: info ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attendant.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF27500A),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (attendant.age != null)
                      _MiniChip(Icons.cake_outlined, '${attendant.age} yrs'),
                    if (attendant.relation != null)
                      _MiniChip(Icons.family_restroom, attendant.relation!),
                    if (attendant.aadhaarNumber != null)
                      _MiniChip(Icons.credit_card, attendant.aadhaarNumber!),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Right: photo ──
          ClipOval(
            child: Container(
              width: 56,
              height: 56,
              color: const Color(0xFFE3F2FD),
              child: photoBytes != null
                  ? Image.memory(photoBytes, fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        attendant.name.isNotEmpty
                            ? attendant.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xFF639922)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF639922)),
        ),
      ],
    );
  }
}

class _CalendarView extends StatefulWidget {
  final Map<String, Map<String, dynamic>> patientData;
  final Map<String, dynamic> attendantData;
  final String patientName;

  const _CalendarView({
    required this.patientData,
    required this.attendantData,
    required this.patientName,
  });

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _hoveredDate;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(
      _currentMonth.year,
      _currentMonth.month,
    );
    final firstWeekday =
        DateTime(_currentMonth.year, _currentMonth.month, 1).weekday % 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month navigation
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Color(0xFF3B6D11)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() {
                _currentMonth = DateTime(
                  _currentMonth.year,
                  _currentMonth.month - 1,
                );
              }),
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy').format(_currentMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF27500A),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Color(0xFF3B6D11)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() {
                _currentMonth = DateTime(
                  _currentMonth.year,
                  _currentMonth.month + 1,
                );
              }),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Day headers
        Row(
          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF639922),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),

        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: firstWeekday + daysInMonth,
          itemBuilder: (context, index) {
            if (index < firstWeekday) return const SizedBox();

            final day = index - firstWeekday + 1;
            final dateStr = DateFormat(
              'yyyy-MM-dd',
            ).format(DateTime(_currentMonth.year, _currentMonth.month, day));

            final patientRecord = widget.patientData[dateStr];
            final patientStatus = patientRecord?['status']?.toString();
            final attendantRecords = widget.attendantData[dateStr];
            final hasAttendantData =
                attendantRecords != null && attendantRecords is Map;
            final isSelected = _hoveredDate == dateStr;
            final isPresent = patientStatus == 'Present';
            final isAbsent = patientStatus == 'Absent';
            final hasData = patientStatus != null || hasAttendantData;

            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                if (!hasData) return;
                setState(() {
                  _hoveredDate = _hoveredDate == dateStr ? null : dateStr;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFEAF3DE) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3B6D11)
                        : const Color(0xFFE0EDD0),
                    width: isSelected ? 1.5 : 0.8,
                  ),
                ),
                child: Center(
                  child: isPresent
                      // Green filled circle for present
                      ? Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3B6D11),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              "$day",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : isAbsent
                      // Red outlined circle for absent
                      ? Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFD32F2F),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              "$day",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD32F2F),
                              ),
                            ),
                          ),
                        )
                      : Text(
                          "$day",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF27500A),
                          ),
                        ),
                ),
              ),
            );
          },
        ),

        // Detail card shown below tapped date
        if (_hoveredDate != null) ...[
          const SizedBox(height: 10),
          _DateDetailCard(
            date: _hoveredDate!,
            patientName: widget.patientName,
            patientRecord: widget.patientData[_hoveredDate!],
            attendantRecords: widget.attendantData[_hoveredDate!],
          ),
        ],

        const SizedBox(height: 8),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _LegendItem(
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B6D11),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    "1",
                    style: TextStyle(fontSize: 8, color: Colors.white),
                  ),
                ),
              ),
              label: "Present",
            ),
            _LegendItem(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFD32F2F),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Text(
                    "1",
                    style: TextStyle(fontSize: 8, color: Color(0xFFD32F2F)),
                  ),
                ),
              ),
              label: "Absent",
            ),
          ],
        ),
      ],
    );
  }
}

class _DateDetailCard extends StatelessWidget {
  final String date;
  final String patientName;
  final Map<String, dynamic>? patientRecord;
  final dynamic attendantRecords;

  const _DateDetailCard({
    required this.date,
    required this.patientName,
    required this.patientRecord,
    required this.attendantRecords,
  });

  @override
  Widget build(BuildContext context) {
    final patientStatus = patientRecord?['status']?.toString() ?? 'No record';
    final formattedDate = DateFormat(
      'EEE, dd MMM yyyy',
    ).format(DateTime.parse(date));

    final List<Map<String, String>> attendantRows = [];
    if (attendantRecords != null && attendantRecords is Map) {
      Map<String, dynamic>.from(attendantRecords).forEach((key, val) {
        if (val is Map) {
          attendantRows.add({
            'name': val['attendantName']?.toString() ?? 'Unknown',
            'status': val['status']?.toString() ?? 'Unknown',
          });
        }
      });
    }

    Widget statusBadge(String status) {
      final isPresent = status == 'Present';
      final isNoRecord = status == 'No record';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isPresent
              ? Colors.green.shade100
              : isNoRecord
              ? Colors.grey.shade100
              : Colors.red.shade100,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isPresent
                ? Colors.green.shade800
                : isNoRecord
                ? Colors.grey
                : Colors.red.shade800,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Date
          Text(
            formattedDate,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF639922),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),

          // ── Patient section label ──
          const Text(
            "Patient",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3B6D11),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: Color(0xFF3B6D11),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  patientName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF27500A),
                  ),
                ),
              ),
              statusBadge(patientStatus),
            ],
          ),

          // ── Attendees section ──
          if (attendantRows.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: Color(0xFFE0EDD0), height: 1, thickness: 0.8),
            const SizedBox(height: 6),
            const Text(
              "Attendees",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1565C0),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            // Scrollable if more than 3
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: attendantRows.length > 3 ? 110 : double.infinity,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: attendantRows.map((a) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_alt_outlined,
                            size: 14,
                            color: Color(0xFF1565C0),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              a['name']!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF27500A),
                              ),
                            ),
                          ),
                          statusBadge(a['status']!),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Widget child;
  final String label;
  const _LegendItem({required this.child, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF639922)),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
