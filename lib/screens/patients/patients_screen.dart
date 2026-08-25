import 'package:flutter/material.dart';
import '../../models/patient_model.dart';
import '../../services/service_locator.dart';
import '../../models/room_model.dart';
import '../../models/bed_model.dart';
import '../../models/stay_model.dart';
import '../../utils/bed_helper.dart';
import '../../utils/pricing_helper.dart';
import 'widgets/patient_card.dart';
import 'widgets/add_patient_dialog.dart';
import 'widgets/payment_dialog.dart';
import 'patient_profile_screen.dart';
import 'utils/patient_info_download.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';
import 'dart:io';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _searchController = TextEditingController();
  late final Stream<List<PatientModel>> _patientsStream;
  late final Stream<List<RoomModel>> _roomsStream;
  static const _pageSize = 25;
  int _visiblePatients = _pageSize;
  final Set<String> _locallyDeletedPatientIds = <String>{};

  String? _notesWithoutPlacement(String? notes) {
    final retained = (notes ?? '')
        .split('\n')
        .where(
          (line) => !RegExp(
            r'^\s*(Room|Lobby|Beds?)\s*:',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .where((line) => line.trim().isNotEmpty)
        .toList();
    return retained.isEmpty ? null : retained.join('\n');
  }

  String _selectedFilter = 'all'; // 'all', 'active', 'inactive', 'discharged'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Preserve one subscription while filtering so searches never briefly
    // render an empty list while a new REST stream starts.
    _patientsStream = ServiceLocator().patientService.getPatientsStream();
    _roomsStream = ServiceLocator().roomService.getRoomsStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddPatientDialog() {
    showDialog(
      context: context,
      builder: (context) => AddPatientDialog(
        onPatientAdded: () {
          // Refresh is handled by StreamBuilder
        },
      ),
    );
  }

  /// Returns the date stored in an Excel cell, supporting both Excel date cells
  /// and the date text formats used by older import sheets.
  DateTime? _parseExcelDate(CellValue? value) {
    if (value is DateCellValue) return value.asDateTimeLocal();
    if (value is DateTimeCellValue) return value.asDateTimeLocal();

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    for (final format in ['dd.MM.yyyy', 'dd/MM/yyyy', 'dd-MM-yyyy']) {
      try {
        return DateFormat(format).parseStrict(text);
      } catch (_) {
        // Try the next format.
      }
    }
    return DateTime.tryParse(text);
  }

  void _showPatientDetails(PatientModel patient) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PatientProfileScreen(patient: patient),
      ),
    );
  }

  Future<void> _confirmDeletePatient(PatientModel patient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete patient?'),
        content: Text(
          'Delete ${patient.fullName} permanently? Their room assignment, attendance and attendant attendance will also be removed.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3B6D11),
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B6D11),
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ServiceLocator().patientService.deletePatient(patient.id);
      if (mounted) {
        setState(() => _locallyDeletedPatientIds.add(patient.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete patient: $e')));
      }
    }
  }

  Future<void> _handlePayNow(PatientModel patient) async {
    final result = await showPatientPaymentDialog(
      context: context,
      patientName: patient.fullName,
      contactNumber: patient.contactNumber,
      bedsCount: patient.bedIds?.length ?? 1,
      attendantsCount: patient.attendants?.length ?? 0,
      roomIdentifier: patient.roomNumber,
      alreadyPaid: patient.totalPaidAmount ?? 0.0,
      showPayLater: false,
      totalBillOverride:
          patient.advanceBilledAmount + patient.attendanceCharges,
    );

    if (result != null && result.payment != null) {
      await ServiceLocator().patientService.recordPayment(
        patient.id,
        result.payment!,
      );
      await ServiceLocator().patientService.updatePatient(patient.id, {
        'advanceBilledAmount': result.payment!.totalAmount,
        'attendanceCharges': 0.0,
        'billingAmountOverride': result.totalAmountEdited
            ? result.payment!.totalAmount
            : patient.billingAmountOverride,
        'paymentPending': result.payment!.pendingAmount > 0,
        'paymentStatus': result.payment!.paymentStatus,
        // Payment state must never reactivate or otherwise change the
        // patient's admission lifecycle status.
        'totalPaidAmount': result.payment!.paidAmount,
        'currentDueAmount': result.payment!.pendingAmount,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successfully processed!'),
            backgroundColor: Color(0xFF3B6D11),
          ),
        );
      }
    }
  }

  Future<_RejoinPlacement?> _chooseRejoinPlacement(
    PatientModel patient,
  ) async {
    final roomService = ServiceLocator().roomService;
    final results = await Future.wait<dynamic>([
      roomService.getRoomsStream().first,
      roomService.getStaysByPatientStream(patient.id).first,
    ]);
    final rooms = results[0] as List<RoomModel>;
    final stays = List<StayModel>.from(results[1] as List<StayModel>)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final previousStay = stays.where((stay) => stay.bedId != null).firstOrNull;
    final previousLobby = patient.lobby?.trim().isNotEmpty == true
        ? patient.lobby!.trim()
        : RegExp(
            r'Lobby:\s*([^\n]+)',
            caseSensitive: false,
          ).firstMatch(patient.notes ?? '')?.group(1)?.trim();

    final placements = <_RejoinPlacement>[
      const _RejoinPlacement.unassigned(),
    ];
    for (final room in rooms) {
      if (room.status == 'maintenance' || room.status == 'unavailable') {
        continue;
      }
      for (final bed in BedHelper.selectableAvailableBeds(room)) {
        final previousBed = previousStay?.roomId == room.id
            ? room.beds
                  .where((candidate) => candidate.id == previousStay?.bedId)
                  .firstOrNull
            : null;
        final isPrevious = previousBed != null &&
            BedHelper.getBedDisplayName(
                  previousBed.bedLabel,
                  roomIdentifier: room.roomIdentifier,
                ) ==
                BedHelper.getBedDisplayName(
                  bed.bedLabel,
                  roomIdentifier: room.roomIdentifier,
                );
        placements.add(
          _RejoinPlacement.bed(
            room: room,
            bed: bed,
            isPreviousBed: isPrevious,
          ),
        );
      }
    }
    placements.sort((a, b) {
      if (a.isPreviousBed != b.isPreviousBed) return a.isPreviousBed ? -1 : 1;
      final aHasRoom = a.room != null;
      final bHasRoom = b.room != null;
      if (aHasRoom != bHasRoom) return aHasRoom ? -1 : 1;
      return a.label.compareTo(b.label);
    });

    const lobbyNames = [
      '1D Lobby 1',
      '1D Lobby 2',
      '1B Lobby 1',
      '1B Lobby 2',
      '2E Lobby 1',
      '2E Lobby 2',
      '2B Lobby 1',
      '2B Lobby 2',
    ];
    placements.addAll(
      lobbyNames.map(
        (name) => _RejoinPlacement.lobby(
          name,
          isPreviousLobby: previousLobby == name,
        ),
      ),
    );

    if (!mounted) return null;
    if (placements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No beds or lobbies are currently available.'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      return null;
    }
    var selected = placements.firstWhere(
      (placement) => placement.isPreviousBed || placement.isPreviousLobby,
      orElse: () => placements.first,
    );
    return showDialog<_RejoinPlacement>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Rejoin ${patient.fullName}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  previousLobby != null
                      ? 'The previous lobby is available. You may use it or choose another placement.'
                      : previousStay == null
                      ? 'Choose an available bed or lobby.'
                      : placements.any((p) => p.isPreviousBed)
                      ? 'The previous bed is available. You may use it or choose another placement.'
                      : 'The previous bed is occupied. Choose another available bed or a lobby.',
                ),
                const SizedBox(height: 14),
                Container(
                  height: 360,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAF3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD5E8C2)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const _RejoinSectionTitle(
                        icon: Icons.bed_outlined,
                        label: 'Available room beds',
                      ),
                      if (!placements.any(
                        (placement) => placement.room != null,
                      ))
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 2, 4, 12),
                          child: Text(
                            'No room beds are currently available. You can choose a lobby or assign later.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ...placements
                          .where((placement) => placement.room != null)
                          .map(
                            (placement) => _RejoinPlacementTile(
                              placement: placement,
                              selected: identical(selected, placement),
                              onTap: () =>
                                  setDialogState(() => selected = placement),
                            ),
                          ),
                      const SizedBox(height: 10),
                      const _RejoinSectionTitle(
                        icon: Icons.weekend_outlined,
                        label: 'Lobby placement',
                      ),
                      ...placements
                          .where((placement) => placement.lobbyName != null)
                          .map(
                            (placement) => _RejoinPlacementTile(
                              placement: placement,
                              selected: identical(selected, placement),
                              onTap: () =>
                                  setDialogState(() => selected = placement),
                            ),
                          ),
                      const SizedBox(height: 10),
                      const _RejoinSectionTitle(
                        icon: Icons.person_outline_rounded,
                        label: 'Assign later',
                      ),
                      _RejoinPlacementTile(
                        placement: placements.firstWhere(
                          (placement) => placement.isUnassigned,
                        ),
                        selected: selected.isUnassigned,
                        onTap: () => setDialogState(
                          () => selected = placements.firstWhere(
                            (placement) => placement.isUnassigned,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Rejoin'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejoinPatient(PatientModel patient) async {
    try {
      final placement = await _chooseRejoinPlacement(patient);
      if (placement == null) return;

      final now = DateTime.now();
      final patientService = ServiceLocator().patientService;
      final roomService = ServiceLocator().roomService;
      final priorStays = await roomService
          .getStaysByPatientStream(patient.id)
          .first;
      final priorStart = patient.registrationDate ?? patient.admissionDate;
      final priorEnd = patient.exitDate ?? patient.dischargeDate;
      if (patient.lobby?.trim().isNotEmpty == true &&
          priorEnd != null &&
          !priorStays.any((stay) =>
              stay.admissionDate.millisecondsSinceEpoch ==
              priorStart.millisecondsSinceEpoch)) {
        await roomService.createLobbyStay(
          patientId: patient.id,
          patientName: patient.fullName,
          lobbyName: patient.lobby!.trim(),
          admissionDate: priorStart,
          durationDays: priorEnd.difference(priorStart).inDays.clamp(1, 3650),
          attendantCount: patient.attendants?.length ?? 0,
          attendantLabels: (patient.attendants ?? const <AttendantModel>[])
              .map((a) => a.relation?.trim().isNotEmpty == true
                  ? '${a.name} (${a.relation})'
                  : a.name)
              .toList(),
          createdBy: 'system',
          status: 'completed',
          completedAt: priorEnd,
        );
      }
      final pricing = await ServiceLocator().roomService.getPricing();
      final estimatedTotal = placement.isUnassigned
          ? 0.0
          : PricingHelper.calculateDailyCharge(
            placement.room?.isPrivate ?? false,
            patient.attendants?.length ?? 0,
            pricing: pricing,
          ) *
          PricingHelper.advanceDays;
      final baseUpdates = <String, dynamic>{
        'status': 'active',
        'dischargeDate': null,
        'admissionDate': now.millisecondsSinceEpoch,
        'registrationDate': now.millisecondsSinceEpoch,
        'isAdvancePeriod': true,
        'advanceBilledAmount': estimatedTotal,
        // A rejoin starts a fresh billing cycle. Never carry a custom bill
        // total from the patient's previous completed stay into this stay.
        'billingAmountOverride': null,
        'attendanceCharges': 0.0,
        'totalPresentDays': 0,
        'totalAbsentDays': 0,
        'maxStayDays': 60,
        'extensionDays': 0,
        'extensionApproved': false,
        'extensionReason': null,
        'roomId': null,
        'roomNumber': null,
        'floor': null,
        'bedIds': null,
        'bedLabels': null,
        'lobby': null,
        'notes': _notesWithoutPlacement(patient.notes),
        'exitDate': null,
        'totalPaidAmount': 0.0,
        'currentDueAmount': estimatedTotal,
        'paymentPending': estimatedTotal > 0,
        'paymentStatus': estimatedTotal > 0 ? 'Unpaid' : 'Paid',
      };
      // Reactivate first as unassigned. If the chosen bed is taken between
      // opening and confirming the dialog, the patient safely remains active
      // and unassigned instead of receiving a duplicate bed assignment.
      await patientService.updatePatient(patient.id, baseUpdates);

      // createStay re-fetches the room and rejects a bed that another user
      // occupied after this dialog opened.
      if (placement.room != null && placement.bed != null) {
        final user = ServiceLocator().authRestService.currentUser;
        try {
          await ServiceLocator().roomService.createStay(
            patientId: patient.id,
            patientName: patient.fullName,
            roomId: placement.room!.id,
            roomNumber: placement.room!.roomIdentifier,
            roomType: placement.room!.roomType,
            admissionDate: now,
            durationDays: PricingHelper.advanceDays,
            attendantCount: patient.attendants?.length ?? 0,
            attendantLabels: (patient.attendants ?? const <AttendantModel>[])
                .map((a) => a.relation?.trim().isNotEmpty == true
                    ? '${a.name} (${a.relation})'
                    : a.name)
                .toList(),
            bedId: placement.bed!.id,
            bedLabel: placement.bed!.bedLabel,
            notes: placement.isPreviousBed
                ? 'Previous bed reassigned on rejoin'
                : 'Bed assigned on rejoin',
            createdBy: user?.uid ?? 'system',
          );
          await patientService.updatePatient(patient.id, {
            'roomId': placement.room!.id,
            'roomNumber': placement.room!.roomIdentifier,
            'floor': placement.room!.floor,
            'bedIds': [placement.bed!.id],
            'bedLabels': [placement.bed!.bedLabel],
            'lobby': null,
          });
        } catch (error) {
          await ServiceLocator().paymentService
              .recalculatePatientAttendanceAndBilling(patient.id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Patient rejoined unassigned because the selected bed is no longer available: $error',
              ),
              backgroundColor: const Color(0xFFE65100),
            ),
          );
          setState(() => _selectedFilter = 'active');
          return;
        }
      } else if (placement.lobbyName != null) {
        await patientService.updatePatient(patient.id, {
          'floor': placement.lobbyFloor,
          'lobby': placement.lobbyName,
          'roomId': null,
          'roomNumber': null,
          'bedIds': null,
          'bedLabels': null,
        });
        await roomService.createLobbyStay(
          patientId: patient.id,
          patientName: patient.fullName,
          lobbyName: placement.lobbyName!,
          admissionDate: now,
          durationDays: PricingHelper.advanceDays,
          attendantCount: patient.attendants?.length ?? 0,
          attendantLabels: (patient.attendants ?? const <AttendantModel>[])
              .map((a) => a.relation?.trim().isNotEmpty == true
                  ? '${a.name} (${a.relation})'
                  : a.name)
              .toList(),
          createdBy:
              ServiceLocator().authRestService.currentUser?.uid ?? 'system',
        );
      }

      await ServiceLocator().paymentService
          .recalculatePatientAttendanceAndBilling(patient.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Patient rejoined: ${placement.label}'),
          backgroundColor: const Color(0xFF3B6D11),
        ),
      );
      setState(() => _selectedFilter = 'active');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not rejoin patient: $error'),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
    }
  }

  // List<PatientModel> _filterPatients(List<PatientModel> patients) {
  //   if (_selectedFilter == 'all') return patients;
  //   if (_selectedFilter == 'active') {
  //     return patients
  //         .where(
  //           (p) => p.status == 'active' || p.status.toLowerCase() == 'paid',
  //         )
  //         .toList();
  //   }
  //   return patients.where((p) => p.status == _selectedFilter).toList();
  // }
  List<PatientModel> _filterPatients(List<PatientModel> patients) {
    patients = patients
        .where((patient) => !_locallyDeletedPatientIds.contains(patient.id))
        .toList();
    List<PatientModel> filtered;

    if (_selectedFilter == 'all') {
      filtered = patients;
    } else if (_selectedFilter == 'active') {
      filtered = patients
          .where(
            (p) => p.status == 'active' || p.status.toLowerCase() == 'paid',
          )
          .toList();
    } else {
      filtered = patients.where((p) => p.status == _selectedFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      filtered = filtered
          .where(
            (patient) =>
                patient.searchKey.contains(query) ||
                patient.contactNumber.contains(query) ||
                (patient.registrationNumber?.toLowerCase().contains(query) ??
                    false),
          )
          .toList();
    }

    // Sort: active/paid first, discharged/others below
    filtered.sort((a, b) {
      bool aActive = a.status == 'active' || a.status.toLowerCase() == 'paid';
      bool bActive = b.status == 'active' || b.status.toLowerCase() == 'paid';
      if (aActive && !bActive) return -1;
      if (!aActive && bActive) return 1;
      return 0;
    });

    return filtered;
  }

  // bool _shouldCountInPatientStats(PatientModel patient) {
  //   final status = patient.status.toLowerCase();
  //   final notes = patient.notes?.toLowerCase() ?? '';
  //   return status != 'inactive' && !notes.contains('imported from excel');
  // }
  bool _shouldCountInPatientStats(PatientModel patient) {
    final status = patient.status.toLowerCase();
    return status == 'active' || status == 'paid';
  }

  bool _isActivePatient(PatientModel patient) {
    final status = patient.status.toLowerCase();
    return status == 'active' || status == 'paid';
  }

  bool _matchesDownloadStatus(PatientModel patient, String statusFilter) {
    final status = patient.status.toLowerCase();
    if (statusFilter == 'active') return _isActivePatient(patient);
    return status == statusFilter;
  }

  String _downloadStatusLabel(String statusFilter) {
    switch (statusFilter) {
      case 'active':
        return 'Active';
      case 'inactive':
        return 'Inactive';
      case 'discharged':
        return 'Discharged';
      default:
        return 'Patients';
    }
  }

  String _displayPatientStatus(PatientModel patient) {
    final status = patient.status.toLowerCase();
    if (status == 'active' || status == 'paid') return 'Active';
    if (status == 'inactive') return 'Inactive';
    if (status == 'discharged') return 'Discharged';
    return patient.status;
  }

  String _formatPatientDate(DateTime? date) {
    if (date == null || date.millisecondsSinceEpoch == 0) return '';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatAssignedBeds(PatientModel patient) {
    final beds = patient.bedLabels;
    if (beds == null || beds.isEmpty) return '';

    return beds
        .map(
          (bed) => BedHelper.getBedDisplayName(
            bed.toString().trim(),
            roomIdentifier: patient.roomNumber,
          ),
        )
        .toSet()
        .join(', ');
  }

  Future<void> _downloadPatientsInfoByStatus(
    List<PatientModel> patients,
    String statusFilter,
  ) async {
    final statusLabel = _downloadStatusLabel(statusFilter);
    final selectedPatients =
        patients
            .where((patient) => _matchesDownloadStatus(patient, statusFilter))
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (selectedPatients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No ${statusLabel.toLowerCase()} patients to download'),
        ),
      );
      return;
    }

    try {
      final currencyFmt = NumberFormat.currency(
        symbol: 'Rs ',
        decimalDigits: 0,
      );
      final excel = Excel.createExcel();

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final patientSheet = excel['$statusLabel Patients'];
      patientSheet.appendRow([
        TextCellValue('Sr No'),
        TextCellValue('Patient Name'),
        TextCellValue('Patient ID'),
        TextCellValue('Registration Number'),
        TextCellValue('Status'),
        TextCellValue('Age'),
        TextCellValue('Gender'),
        TextCellValue('Date of Birth'),
        TextCellValue('Contact Number'),
        TextCellValue('Emergency Contact Name'),
        TextCellValue('Emergency Contact Number'),
        TextCellValue('Medical Condition'),
        TextCellValue('Room Number'),
        TextCellValue('Floor'),
        TextCellValue('Assigned Beds'),
        TextCellValue('Admission Date'),
        TextCellValue('Aadhaar Number'),
        TextCellValue('PAN Card Number'),
        TextCellValue('Notes'),
        TextCellValue('Total Amount'),
        TextCellValue('Paid Amount'),
        TextCellValue('Pending Amount'),
        TextCellValue('Payment Status'),
        TextCellValue('Attendants'),
      ]);

      for (int i = 0; i < selectedPatients.length; i++) {
        final patient = selectedPatients[i];
        final attendants = patient.attendants ?? [];
        final totalAmount =
            (patient.totalPaidAmount ?? 0) + (patient.currentDueAmount ?? 0);

        patientSheet.appendRow([
          TextCellValue('${i + 1}'),
          TextCellValue(patient.fullName),
          TextCellValue(patient.id),
          TextCellValue(patient.registrationNumber ?? ''),
          TextCellValue(_displayPatientStatus(patient)),
          TextCellValue('${patient.age} Years'),
          TextCellValue(patient.gender),
          TextCellValue(_formatPatientDate(patient.dateOfBirth)),
          TextCellValue(patient.contactNumber),
          TextCellValue(patient.emergencyContactName),
          TextCellValue(patient.emergencyContact),
          TextCellValue(patient.medicalCondition),
          TextCellValue(patient.roomNumber ?? ''),
          TextCellValue(patient.floor?.toString() ?? ''),
          TextCellValue(_formatAssignedBeds(patient)),
          TextCellValue(_formatPatientDate(patient.admissionDate)),
          TextCellValue(patient.aadhaarCardNumber ?? ''),
          TextCellValue(patient.panCardNumber ?? ''),
          TextCellValue(patient.notes ?? ''),
          TextCellValue(currencyFmt.format(totalAmount)),
          TextCellValue(currencyFmt.format(patient.totalPaidAmount ?? 0)),
          TextCellValue(currencyFmt.format(patient.currentDueAmount ?? 0)),
          TextCellValue(patient.paymentStatus ?? 'Pending'),
          TextCellValue(
            attendants.isEmpty
                ? 'N/A'
                : attendants.map((attendant) => attendant.name).join(', '),
          ),
        ]);
      }

      final attendantsSheet = excel['Attendants'];
      attendantsSheet.appendRow([
        TextCellValue('Patient Name'),
        TextCellValue('Patient ID'),
        TextCellValue('Sr No'),
        TextCellValue('Name'),
        TextCellValue('Age'),
        TextCellValue('Relation'),
        TextCellValue('Aadhaar Number'),
      ]);

      for (final patient in selectedPatients) {
        final attendants = patient.attendants ?? [];
        if (attendants.isEmpty) {
          attendantsSheet.appendRow([
            TextCellValue(patient.fullName),
            TextCellValue(patient.id),
            TextCellValue(''),
            TextCellValue('N/A'),
            TextCellValue(''),
            TextCellValue(''),
            TextCellValue(''),
          ]);
          continue;
        }

        for (int i = 0; i < attendants.length; i++) {
          final attendant = attendants[i];
          attendantsSheet.appendRow([
            TextCellValue(patient.fullName),
            TextCellValue(patient.id),
            TextCellValue('${i + 1}'),
            TextCellValue(attendant.name),
            TextCellValue(
              attendant.age != null && attendant.age!.trim().isNotEmpty
                  ? attendant.age!
                  : 'N/A',
            ),
            TextCellValue(
              attendant.relation != null &&
                      attendant.relation!.trim().isNotEmpty
                  ? attendant.relation!
                  : 'N/A',
            ),
            TextCellValue(attendant.aadhaarNumber ?? ''),
          ]);
        }
      }

      excel.setDefaultSheet('$statusLabel Patients');
      final bytes = excel.save();

      if (bytes == null) {
        throw Exception('Could not create Excel file');
      }

      final dateStamp = DateFormat('yyyy_MM_dd').format(DateTime.now());
      final savedLocation = await savePatientInfoWorkbook(
        bytes: bytes,
        fileName: '${statusFilter}_patients_$dateStamp',
      );

      if (savedLocation == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Download cancelled')));
        }
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$statusLabel patient info downloaded successfully'),
          backgroundColor: Color(0xFF3B6D11),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
    }
  }

  Future<void> _importFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null) {
        if (!mounted) return;
        setState(() {
          // You could add a loading state here
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Importing patients, please wait...'),
            duration: Duration(seconds: 2),
          ),
        );

        var bytes = result.files.single.bytes;
        if (bytes == null && result.files.single.path != null) {
          bytes = await File(result.files.single.path!).readAsBytes();
        }

        if (bytes == null) {
          throw Exception('Could not read file bytes');
        }

        var excel = Excel.decodeBytes(bytes);
        int addedCount = 0;
        final importedPatients = <String, Map<String, dynamic>>{};

        final currentUser = ServiceLocator().authRestService.currentUser;
        if (currentUser == null) {
          throw Exception('User not authenticated');
        }
        final existingPatients = await ServiceLocator().patientService
            .getPatientsStream()
            .first;
        final existingPatientsByRegistration = <String, PatientModel>{
          for (final patient in existingPatients)
            if ((patient.registrationNumber ?? '').trim().isNotEmpty)
              patient.registrationNumber!.trim(): patient,
        };

        for (var table in excel.tables.keys) {
          var rows = excel.tables[table]?.rows ?? [];
          final columnIndexes = <String, int>{};

          for (var row in rows) {
            final headerValues = row
                .map(
                  (cell) => (cell?.value?.toString() ?? '')
                      .toLowerCase()
                      .replaceAll(RegExp(r'[^a-z0-9]'), ''),
                )
                .toList();
            final isHeader = headerValues.any(
              (value) =>
                  value.contains('registration') ||
                  value == 'regno' ||
                  value == 'name' ||
                  value.contains('nameofpatient'),
            );

            if (isHeader) {
              for (var index = 0; index < headerValues.length; index++) {
                final value = headerValues[index];
                if (value.contains('registration') || value == 'regno') {
                  columnIndexes['registration'] = index;
                } else if (value == 'date' || value.contains('dateofreceipt')) {
                  columnIndexes['date'] = index;
                } else if (value == 'name' || value.contains('nameofpatient')) {
                  columnIndexes['name'] = index;
                } else if (value.contains('address')) {
                  columnIndexes['address'] = index;
                } else if (value.contains('pan')) {
                  columnIndexes['pan'] = index;
                } else if (value.contains('aadhar') ||
                    value.contains('aadhaar') ||
                    value.contains('adhar')) {
                  columnIndexes['aadhaar'] = index;
                } else if (value.contains('receipt') ||
                    value.contains('reciept')) {
                  columnIndexes['receipt'] = index;
                } else if (value.contains('transaction') ||
                    value.contains('uti')) {
                  columnIndexes['transaction'] = index;
                } else if (value == 'total' || value.contains('totalamount')) {
                  columnIndexes['totalAmount'] = index;
                } else if (value == 'paid' ||
                    value.contains('paidamount') ||
                    value.contains('amountpaid')) {
                  columnIndexes['paidAmount'] = index;
                } else if (value.contains('amount') ||
                    value.contains('amtrecd')) {
                  columnIndexes['amount'] = index;
                } else if (value.contains('modeofpayment')) {
                  columnIndexes['paymentMode'] = index;
                }
              }
              continue;
            }

            String valueFor(String field, int legacyIndex) {
              final index = columnIndexes[field] ?? legacyIndex;
              if (index < 0 || index >= row.length) return '';
              return row[index]?.value?.toString().trim() ?? '';
            }

            final regNo = valueFor('registration', 0);
            final patientName = valueFor('name', 2);

            // Skip empty rows
            if (regNo.isEmpty && patientName.isEmpty) {
              continue;
            }

            // Skip rows without a patient name
            if (patientName.isEmpty) {
              continue;
            }

            final dateIndex = columnIndexes['date'] ?? 1;
            final regDate = dateIndex < row.length
                ? _parseExcelDate(row[dateIndex]?.value) ?? DateTime.now()
                : DateTime.now();

            String name = patientName;
            String address = valueFor('address', 3);
            String pan = valueFor('pan', 4);
            String adhar = valueFor('aadhaar', 5);
            final paidAmountText = columnIndexes.containsKey('paidAmount')
                ? valueFor('paidAmount', -1)
                : valueFor('amount', 6);
            final totalAmountText = columnIndexes.containsKey('totalAmount')
                ? valueFor('totalAmount', -1)
                : paidAmountText;
            double parseAmount(String value) =>
                double.tryParse(
                  value.replaceAll(',', '').replaceAll('₹', '').trim(),
                ) ??
                0.0;
            final paidAmount = parseAmount(paidAmountText);
            final totalAmount = parseAmount(totalAmountText);
            final dueAmount = (totalAmount - paidAmount)
                .clamp(0, double.infinity)
                .toDouble();
            String receiptNo = valueFor('receipt', 7);
            String modeOfPayment = columnIndexes.containsKey('paymentMode')
                ? valueFor('paymentMode', -1)
                : (columnIndexes.isEmpty ? valueFor('paymentMode', 8) : '');
            String utiNo = valueFor('transaction', 9);

            List<String> notesList = [];

            if (address.isNotEmpty) {
              notesList.add('Address: $address');
            }

            notesList.add('Imported from Excel');

            List<PaymentModel>? payments;

            if (paidAmount > 0) {
              payments = [
                PaymentModel(
                  id: 'payment_${DateTime.now().millisecondsSinceEpoch}',
                  amount: paidAmount,
                  totalAmount: totalAmount,
                  paidAmount: paidAmount,
                  pendingAmount: dueAmount,
                  paymentStatus: dueAmount > 0 ? 'Partial' : 'Paid',
                  method: modeOfPayment.isNotEmpty ? modeOfPayment : 'Cash',
                  date: regDate,
                  receiptNumber: receiptNo.isNotEmpty ? receiptNo : null,
                  transactionId: utiNo.isNotEmpty ? utiNo : null,
                  notes: 'Imported from Excel',
                ),
              ];
            }

            // A registration number identifies one patient.  A sheet may
            // contain several receipt rows for that same patient, so collect
            // all payments before creating the patient record.
            final patientKey = regNo.isNotEmpty
                ? regNo
                : '${name.toLowerCase()}|${adhar.trim()}';
            final importedPatient = importedPatients.putIfAbsent(
              patientKey,
              () => {
                'fullName': name,
                'admissionDate': regDate,
                'registrationNumber': regNo,
                'pan': pan,
                'aadhaar': adhar,
                'receiptNumber': receiptNo,
                'modeOfPayment': modeOfPayment,
                'transactionNumber': utiNo,
                'notes': notesList.join('\n'),
                'payments': <PaymentModel>[],
                'totalAmount': 0.0,
                'hasExplicitTotalAmount': columnIndexes.containsKey(
                  'totalAmount',
                ),
              },
            );
            (importedPatient['payments'] as List<PaymentModel>).addAll(
              payments ?? [],
            );
            final hasExplicitTotalAmount =
                importedPatient['hasExplicitTotalAmount'] as bool;
            // A repeated Total Amount is the patient's single overall bill;
            // only receipt/paid amounts are additive. With an Amount-only
            // sheet, each row is both a payment and a separate bill amount.
            importedPatient['totalAmount'] = hasExplicitTotalAmount
                ? (importedPatient['totalAmount'] as double) > totalAmount
                      ? importedPatient['totalAmount']
                      : totalAmount
                : (importedPatient['totalAmount'] as double) + totalAmount;
          }
        }

        for (final importedPatient in importedPatients.values) {
          final patientPayments =
              importedPatient['payments'] as List<PaymentModel>;
          final totalAmount = importedPatient['totalAmount'] as double;
          final hasExplicitTotalAmount =
              importedPatient['hasExplicitTotalAmount'] as bool;
          final paidAmount = patientPayments.fold<double>(
            0,
            (sum, payment) => sum + payment.amount,
          );
          final registrationNumber =
              importedPatient['registrationNumber'] as String;
          final existingPatient =
              existingPatientsByRegistration[registrationNumber.trim()];

          if (existingPatient != null) {
            final existingPayments = existingPatient.payments ?? [];
            final newPayments = patientPayments.where((newPayment) {
              return !existingPayments.any((existingPayment) {
                final hasReceiptNumbers =
                    (newPayment.receiptNumber ?? '').isNotEmpty &&
                    (existingPayment.receiptNumber ?? '').isNotEmpty;
                if (hasReceiptNumbers) {
                  return newPayment.receiptNumber ==
                      existingPayment.receiptNumber;
                }
                return (newPayment.transactionId ?? '').isNotEmpty &&
                    newPayment.transactionId == existingPayment.transactionId &&
                    newPayment.amount == existingPayment.amount;
              });
            }).toList();

            if (newPayments.isEmpty && !hasExplicitTotalAmount) {
              continue;
            }

            for (final payment in newPayments) {
              await ServiceLocator().patientService.recordPayment(
                existingPatient.id,
                payment,
              );
            }

            final existingPaidAmount = existingPayments.fold<double>(
              0,
              (sum, payment) => sum + payment.amount,
            );
            final existingBill =
                existingPatient.advanceBilledAmount +
                existingPatient.attendanceCharges;
            final recordedExistingBill =
                existingPaidAmount + (existingPatient.currentDueAmount ?? 0);
            final combinedPaidAmount =
                existingPaidAmount +
                newPayments.fold<double>(
                  0,
                  (sum, payment) => sum + payment.amount,
                );
            final addedBillAmount = newPayments.fold<double>(
              0,
              (sum, payment) => sum + payment.totalAmount,
            );
            final currentBillAmount = existingBill > recordedExistingBill
                ? existingBill
                : recordedExistingBill;
            final combinedBillAmount = hasExplicitTotalAmount
                ? totalAmount
                : currentBillAmount + addedBillAmount;
            final combinedDueAmount = (combinedBillAmount - combinedPaidAmount)
                .clamp(0, double.infinity)
                .toDouble();

            await ServiceLocator().patientService
                .updatePatient(existingPatient.id, {
                  'totalPaidAmount': combinedPaidAmount,
                  'currentDueAmount': combinedDueAmount,
                  'paymentPending': combinedDueAmount > 0,
                  'paymentStatus': combinedDueAmount > 0 ? 'Partial' : 'Paid',
                  'status': combinedDueAmount > 0 ? 'active' : 'Paid',
                  'advanceBilledAmount':
                      combinedBillAmount - existingPatient.attendanceCharges,
                });
            addedCount++;
            continue;
          }

          await ServiceLocator().patientService.addPatient(
            fullName: importedPatient['fullName'] as String,
            dateOfBirth: DateTime.now(), // Default since not provided
            gender: 'unknown',
            contactNumber: 'Not Provided',
            emergencyContact: 'Not Provided',
            emergencyContactName: 'Not Provided',
            medicalCondition: 'Not Provided',
            admissionDate: importedPatient['admissionDate'] as DateTime,
            createdBy: currentUser.uid,
            registrationNumber: registrationNumber,
            registrationDate: importedPatient['admissionDate'] as DateTime,
            panCardNumber: (importedPatient['pan'] as String).isNotEmpty
                ? importedPatient['pan'] as String
                : null,
            aadhaarCardNumber: (importedPatient['aadhaar'] as String).isNotEmpty
                ? importedPatient['aadhaar'] as String
                : null,
            receiptNumber:
                (importedPatient['receiptNumber'] as String).isNotEmpty
                ? importedPatient['receiptNumber'] as String
                : null,
            modeOfPayment:
                (importedPatient['modeOfPayment'] as String).isNotEmpty
                ? importedPatient['modeOfPayment'] as String
                : null,
            utiNumber:
                (importedPatient['transactionNumber'] as String).isNotEmpty
                ? importedPatient['transactionNumber'] as String
                : null,
            status: paidAmount > 0 && totalAmount <= paidAmount
                ? 'Paid'
                : 'active',
            notes: importedPatient['notes'] as String,
            payments: patientPayments,
            initialTotalAmount: totalAmount,
          );
          addedCount++;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully processed $addedCount patients!'),
              backgroundColor: const Color(0xFF3B6D11),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing Excel: $e'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: Column(
        children: [
          // Header with stats
          StreamBuilder<List<PatientModel>>(
            // Share the broadcast stream with the list to avoid a second
            // full patient download while filtering or searching.
            stream: _patientsStream,
            builder: (context, snapshot) {
              final allPatients = snapshot.data ?? [];
              final countedPatients = allPatients
                  .where(_shouldCountInPatientStats)
                  .toList();
              final patientCount = countedPatients.length;
              final attendeeCount = countedPatients.fold<int>(
                0,
                (sum, patient) => sum + (patient.attendants?.length ?? 0),
              );
              final totalPeopleCount = patientCount + attendeeCount;

              return StreamBuilder<List<RoomModel>>(
                stream: _roomsStream,
                builder: (context, roomsSnapshot) {
                  final rooms = roomsSnapshot.data ?? [];
                  final totalBeds = rooms.fold<int>(
                    0,
                    (sum, room) => sum + room.actualTotalBeds,
                  );
                  final availableBeds = rooms.fold<int>(
                    0,
                    (sum, room) => sum + room.actualAvailableBeds,
                  );
                  final occupiedBeds = rooms.fold<int>(
                    0,
                    (sum, room) => sum + room.actualOccupiedBeds,
                  );

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFDF7),
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFFC0DD97),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                "Patient Management",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF27500A),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _importFromExcel,
                              icon: const Icon(
                                Icons.upload_file_rounded,
                                size: 18,
                              ),
                              label: const Text("Import Excel"),
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
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    PopupMenuButton<String>(
                                      tooltip: 'Download patient info',
                                      padding: EdgeInsets.zero,
                                      offset: const Offset(0, 8),
                                      color: Colors.white,
                                      elevation: 6,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: const BorderSide(
                                          color: Color(0xFFC0DD97),
                                        ),
                                      ),
                                      onSelected: (status) =>
                                          _downloadPatientsInfoByStatus(
                                            allPatients,
                                            status,
                                          ),
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'active',
                                          child: _DownloadMenuItem(
                                            icon: Icons.person_rounded,
                                            label: 'Active Patients',
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'inactive',
                                          child: _DownloadMenuItem(
                                            icon: Icons.person_off_outlined,
                                            label: 'Inactive Patients',
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'discharged',
                                          child: _DownloadMenuItem(
                                            icon: Icons.logout_rounded,
                                            label: 'Discharged Patients',
                                          ),
                                        ),
                                      ],
                                      child: Container(
                                        width: 154,
                                        height: 44,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFF3B6D11),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.download_outlined,
                                              size: 18,
                                              color: Color(0xFF3B6D11),
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Download',
                                              style: TextStyle(
                                                color: Color(0xFF3B6D11),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            SizedBox(width: 4),
                                            Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 18,
                                              color: Color(0xFF3B6D11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _showAddPatientDialog,
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 18,
                                      ),
                                      label: const Text("Add Patient"),
                                      style: ElevatedButton.styleFrom(
                                        fixedSize: const Size(154, 44),
                                        backgroundColor: const Color(
                                          0xFF3B6D11,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final cards = <Widget>[
                              _StatCard(
                                label: "Total People",
                                value: totalPeopleCount.toString(),
                                icon: Icons.groups_2_outlined,
                                color: const Color(0xFF3B6D11),
                              ),
                              _StatCard(
                                label: "Patients",
                                value: patientCount.toString(),
                                icon: Icons.person_rounded,
                                color: const Color(0xFF639922),
                              ),
                              _StatCard(
                                label: "Attendees",
                                value: attendeeCount.toString(),
                                icon: Icons.people_outline_rounded,
                                color: const Color(0xFF0F6E56),
                              ),
                              _StatCard(
                                label: "Beds",
                                value: totalBeds.toString(),
                                icon: Icons.bed_outlined,
                                color: const Color(0xFF3B6D11),
                              ),
                              _StatCard(
                                label: "Occupied",
                                value: occupiedBeds.toString(),
                                icon: Icons.bed_rounded,
                                color: const Color(0xFFD66A1F),
                              ),
                              _StatCard(
                                label: "Available",
                                value: availableBeds.toString(),
                                icon: Icons.event_available_outlined,
                                color: const Color(0xFF757575),
                              ),
                            ];

                            const spacing = 10.0;
                            const minimumCardWidth = 150.0;
                            final oneLineWidth =
                                (minimumCardWidth * cards.length) +
                                (spacing * (cards.length - 1));

                            if (constraints.maxWidth >= oneLineWidth) {
                              return Row(
                                children: [
                                  for (
                                    var index = 0;
                                    index < cards.length;
                                    index++
                                  ) ...[
                                    if (index > 0)
                                      const SizedBox(width: spacing),
                                    Expanded(child: cards[index]),
                                  ],
                                ],
                              );
                            }

                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                for (final card in cards)
                                  SizedBox(
                                    width: minimumCardWidth,
                                    child: card,
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Search Bar
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                        _visiblePatients = _pageSize;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search patients by name...',
                      hintStyle: TextStyle(
                        color: const Color(0xFF639922).withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF639922),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _visiblePatients = _pageSize;
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFC0DD97)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFC0DD97)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF3B6D11),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),

                // Filter Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'All',
                      isSelected: _selectedFilter == 'all',
                      onTap: () => setState(() => _selectedFilter = 'all'),
                    ),
                    _FilterChip(
                      label: 'Active',
                      isSelected: _selectedFilter == 'active',
                      onTap: () => setState(() => _selectedFilter = 'active'),
                    ),
                    _FilterChip(
                      label: 'Inactive',
                      isSelected: _selectedFilter == 'inactive',
                      onTap: () => setState(() => _selectedFilter = 'inactive'),
                    ),
                    _FilterChip(
                      label: 'Discharged',
                      isSelected: _selectedFilter == 'discharged',
                      onTap: () =>
                          setState(() => _selectedFilter = 'discharged'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Patients List
          Expanded(
            child: StreamBuilder<List<PatientModel>>(
              stream: _patientsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: Color(0xFFD32F2F),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Color(0xFF639922)),
                        ),
                      ],
                    ),
                  );
                }
                final patients = _filterPatients(snapshot.data ?? []);

                if (patients.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 64,
                          color: const Color(0xFF639922).withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No patients found'
                              : 'No patients yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: const Color(
                              0xFF639922,
                            ).withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_searchQuery.isEmpty)
                          TextButton.icon(
                            onPressed: _showAddPatientDialog,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text("Add First Patient"),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF3B6D11),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                final visiblePatients = patients
                    .take(_visiblePatients)
                    .toList();
                final hasMore = visiblePatients.length < patients.length;
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: visiblePatients.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == visiblePatients.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _visiblePatients += _pageSize),
                          child: Text(
                            'Load more (${patients.length - visiblePatients.length} remaining)',
                          ),
                        ),
                      );
                    }
                    final patient = visiblePatients[index];
                    return PatientCard(
                      patient: patient,
                      onTap: () => _showPatientDetails(patient),
                      onEdit: () => _showPatientDetails(patient),
                      onDischarge: () async {
                        try {
                          await ServiceLocator().patientService
                              .dischargePatient(patient.id);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Patient discharged successfully',
                                ),
                                backgroundColor: Color(0xFF3B6D11),
                              ),
                            );
                            setState(() {
                              _selectedFilter = 'discharged';
                            });
                          }
                        } catch (error) {
                          if (!context.mounted) return;
                          final missing = error.toString().contains(
                            'Patient not found',
                          );
                          if (missing) {
                            setState(
                              () => _locallyDeletedPatientIds.add(patient.id),
                            );
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                missing
                                    ? 'This patient was already deleted. The list has been refreshed.'
                                    : 'Could not discharge patient: $error',
                              ),
                              backgroundColor: missing
                                  ? const Color(0xFF3B6D11)
                                  : const Color(0xFFD32F2F),
                            ),
                          );
                        }
                      },
                      onPayNow: () => _handlePayNow(patient),
                      onDelete: () => _confirmDeletePatient(patient),
                      onRejoin: () => _rejoinPatient(patient),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RejoinPlacement {
  final RoomModel? room;
  final BedModel? bed;
  final String? lobbyName;
  final bool isPreviousBed;
  final bool isPreviousLobby;

  const _RejoinPlacement._({
    this.room,
    this.bed,
    this.lobbyName,
    this.isPreviousBed = false,
    this.isPreviousLobby = false,
  });

  const _RejoinPlacement.unassigned() : this._();

  const _RejoinPlacement.bed({
    required RoomModel room,
    required BedModel bed,
    required bool isPreviousBed,
  }) : this._(room: room, bed: bed, isPreviousBed: isPreviousBed);

  const _RejoinPlacement.lobby(
    String lobbyName, {
    required bool isPreviousLobby,
  }) : this._(
         lobbyName: lobbyName,
         isPreviousLobby: isPreviousLobby,
       );

  int? get lobbyFloor => lobbyName?.isNotEmpty == true
      ? int.tryParse(lobbyName![0])
      : null;

  bool get isUnassigned => room == null && bed == null && lobbyName == null;

  String get label {
    if (room != null && bed != null) {
      final bedName = BedHelper.getBedDisplayName(
        bed!.bedLabel,
        roomIdentifier: room!.roomIdentifier,
      );
      return '${isPreviousBed ? "Previous bed — " : ""}${room!.roomIdentifier} · $bedName · Floor ${room!.floor}';
    }
    if (lobbyName != null) {
      return '${isPreviousLobby ? "Previous lobby — " : "Lobby — "}$lobbyName';
    }
    return 'Rejoin without room or lobby';
  }
}

class _RejoinSectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RejoinSectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF3B6D11)),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF3B6D11),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RejoinPlacementTile extends StatelessWidget {
  final _RejoinPlacement placement;
  final bool selected;
  final VoidCallback onTap;

  const _RejoinPlacementTile({
    required this.placement,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = placement.isUnassigned
        ? Icons.schedule_rounded
        : placement.lobbyName != null
        ? Icons.weekend_outlined
        : Icons.bed_outlined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected ? const Color(0xFFE6F2DA) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? const Color(0xFF3B6D11)
                    : const Color(0xFFD5E8C2),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: const Color(0xFF3B6D11)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        placement.label,
                        style: const TextStyle(
                          color: Color(0xFF27500A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (placement.isUnassigned)
                        const Text(
                          'Rejoin now and choose a room or lobby later in Edit Patient',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? const Color(0xFF3B6D11)
                      : const Color(0xFF97C459),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Stat card widget
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC0DD97), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF639922),
                  ),
                  maxLines: 1,
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

class _DownloadMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DownloadMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF3B6D11)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27500A),
              ),
            ),
          ),
          const Icon(
            Icons.table_chart_outlined,
            size: 17,
            color: Color(0xFF639922),
          ),
        ],
      ),
    );
  }
}

// Filter chip widget
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B6D11)
                : const Color(0xFFC0DD97),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF27500A),
          ),
        ),
      ),
    );
  }
}
