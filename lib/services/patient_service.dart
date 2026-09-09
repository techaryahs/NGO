import 'dart:async';
import '../models/patient_model.dart';
import '../models/stay_model.dart';
import '../utils/stay_billing.dart';
import 'firebase_rtdb_rest_service.dart';
import 'service_locator.dart';

/// Service layer for all patient-related RTDB operations.
///
/// Uses REST API for CRUD and polling-based streaming.
/// All paths follow the schema: `/patients/$pushKey`.
class PatientService {
  /// REST API service instance
  final FirebaseRTDBRestService _rtdb;

  /// Base path for patient records.
  final String _patientsPath = 'patients';
  Future<int>? _orphanCleanupFuture;

  PatientService({required FirebaseRTDBRestService rtdbService})
    : _rtdb = rtdbService;

  // ===========================================================================
  // STREAMS — Real-time listeners (polling-based)
  // ===========================================================================

  /// Stream of ALL patients, sorted by admission date (newest first).
  // Stream<List<PatientModel>> getPatientsStream() {
  //   return _rtdb.stream(_patientsPath).map((data) {
  //     final List<PatientModel> patients = [];
  //     if (data != null && data is Map) {
  //       final mapData = Map<String, dynamic>.from(data);
  //       mapData.forEach((key, value) {
  //         if (value is Map) {
  //           patients.add(
  //             PatientModel.fromMap(key, Map<String, dynamic>.from(value)),
  //           );
  //         }
  //       });
  //       // Sort by admission date descending (newest first)
  //       patients.sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
  //     }
  //     return patients;
  //   });

  // }
  Stream<List<PatientModel>> getPatientsStream() {
    return _rtdb.stream(_patientsPath).map((data) {
      final List<PatientModel> patients = [];

      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);

        mapData.forEach((key, value) {
          if (value is Map) {
            patients.add(
              PatientModel.fromMap(key, Map<String, dynamic>.from(value)),
            );
          }
        });

        // Sort by admission date descending
        patients.sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
      }

      return patients;
    }).asBroadcastStream(); // 🔥 THIS LINE FIXES YOUR ERROR
  }

  /// Stream of patients filtered by [status] ('active', 'discharged', etc).
  ///
  /// Note: REST API queries are limited, so we fetch all and filter client-side.
  Stream<List<PatientModel>> getPatientsByStatus(String status) {
    return getPatientsStream().map((patients) {
      if (status == 'active') {
        return patients
            .where((p) => p.status == 'active' || p.status == 'Paid')
            .toList();
      }
      return patients.where((p) => p.status == status).toList();
    });
  }

  /// Server-filtered stream for screens that only need selected statuses.
  Stream<List<PatientModel>> getPatientsByStatuses(List<String> statuses) {
    return _rtdb
        .queryAnyStream(_patientsPath, orderBy: 'status', equalToAny: statuses)
        .map((data) {
          final patients = <PatientModel>[];
          if (data is Map) {
            data.forEach((key, value) {
              if (value is Map) {
                patients.add(
                  PatientModel.fromMap(
                    key.toString(),
                    Map<String, dynamic>.from(value),
                  ),
                );
              }
            });
          }
          patients.sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
          return patients;
        })
        .asBroadcastStream();
  }

  /// Client-side search by patient name against `searchKey`.
  ///
  /// RTDB does not support full-text search natively, so we stream all
  /// patients and filter in-memory. For large datasets, consider
  /// integrating Algolia or Typesense.
  Stream<List<PatientModel>> searchPatients(String query) {
    return getPatientsStream().map((patients) {
      final searchKey = query.toLowerCase().trim();
      if (searchKey.isEmpty) return patients;
      return patients
          .where((patient) => patient.searchKey.contains(searchKey))
          .toList();
    });
  }

  /// Stream of active patients assigned to a specific [roomId].
  Stream<List<PatientModel>> getPatientsByRoom(String roomId) {
    return getPatientsStream().map((patients) {
      return patients
          .where(
            (p) =>
                p.roomId == roomId &&
                (p.status == 'active' || p.status == 'Paid'),
          )
          .toList();
    });
  }

  /// Stream of active patients on a specific [floor].
  Stream<List<PatientModel>> getPatientsByFloor(int floor) {
    return getPatientsStream().map((patients) {
      return patients
          .where(
            (p) =>
                p.floor == floor &&
                (p.status == 'active' || p.status == 'Paid'),
          )
          .toList();
    });
  }

  // ===========================================================================
  // READ — One-shot fetches
  // ===========================================================================

  /// Fetch a single patient by [patientId].
  /// Returns `null` if the patient does not exist.
  Future<PatientModel?> getPatient(String patientId) async {
    try {
      final data = await _rtdb.get('$_patientsPath/$patientId');
      if (data != null && data is Map) {
        return PatientModel.fromMap(patientId, Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch patient: $e');
    }
  }

  /// Firebase push IDs are unique, but each registration number must also
  /// identify exactly one patient record.
  Future<PatientModel?> getPatientByRegistrationNumber(
    String registrationNumber, {
    String? excludingPatientId,
  }) async {
    final normalized = registrationNumber.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    // Ask Firebase for matching records only. Downloading the entire patient
    // collection made a simple add/edit fail on slower connections.
    final data = await _rtdb.query(
      _patientsPath,
      orderBy: 'registrationNumber',
      equalTo: registrationNumber.trim(),
    );
    if (data is! Map) return null;
    for (final entry in Map<String, dynamic>.from(data).entries) {
      if (entry.key == excludingPatientId || entry.value is! Map) continue;
      final storedNumber = (entry.value['registrationNumber']?.toString() ?? '')
          .trim();
      if (storedNumber.toLowerCase() == normalized) {
        return PatientModel.fromMap(
          entry.key,
          Map<String, dynamic>.from(entry.value),
        );
      }
    }
    return null;
  }

  // ===========================================================================
  // CREATE — Add new patient
  // ===========================================================================

  /// Adds a new patient record under `/patients/$pushKey`.
  ///
  /// Uses REST API POST to generate a unique key, then writes the data.
  /// Returns the generated push-key (patient ID).
  Future<String> addPatient({
    required String fullName,
    required DateTime dateOfBirth,
    required String gender,
    required String contactNumber,
    required String emergencyContact,
    required String emergencyContactName,
    required String medicalCondition,
    String? allergies,
    String? bloodType,
    required DateTime admissionDate,
    String? roomId,
    String? roomNumber,
    int? floor,
    List<String>? bedIds,
    List<String>? bedLabels,
    String? photoDataUrl,
    String? photoFileName,
    String? notes,
    String? address,
    String? lobby,
    DateTime? exitDate,
    required String createdBy,
    // New fields
    String? registrationNumber,
    DateTime? registrationDate,
    String? panCardNumber,
    String? aadhaarCardNumber,
    String? receiptNumber,
    String? modeOfPayment,
    String? utiNumber,
    String? status,
    bool isAdvancePeriod = true,
    double advanceBilledAmount = 0.0,
    double attendanceCharges = 0.0,
    int totalPresentDays = 0,
    int totalAbsentDays = 0,
    List<AttendantModel>? attendants,
    List<PaymentModel>? payments,
    double? initialTotalAmount,
  }) async {
    try {
      final now = DateTime.now();
      final age = PatientModel.calculateAge(dateOfBirth);
      final initialPaidAmount = (payments ?? []).fold<double>(
        0,
        (total, payment) => total + payment.amount,
      );
      final totalAmount =
          initialTotalAmount ??
          (advanceBilledAmount + attendanceCharges > 0
              ? advanceBilledAmount + attendanceCharges
              : initialPaidAmount);
      final initialDueAmount = (totalAmount - initialPaidAmount)
          .clamp(0, double.infinity)
          .toDouble();
      final initialPaymentStatus = initialPaidAmount <= 0
          ? 'Unpaid'
          : initialDueAmount > 0
          ? 'Partial'
          : 'Paid';

      // Generate temporary ID for the model
      final tempId = 'temp_${now.millisecondsSinceEpoch}';

      final patient = PatientModel(
        id: tempId,
        fullName: fullName,
        searchKey: fullName.toLowerCase(),
        dateOfBirth: dateOfBirth,
        age: age,
        gender: gender,
        contactNumber: contactNumber,
        emergencyContact: emergencyContact,
        emergencyContactName: emergencyContactName,
        medicalCondition: medicalCondition,
        allergies: allergies,
        bloodType: bloodType,
        admissionDate: admissionDate,
        // Admission state and payment state are separate concerns. A newly
        // admitted patient remains active even when the initial bill is paid.
        status: status ?? 'active',
        paymentPending: initialDueAmount > 0,
        paymentStatus: initialPaymentStatus,
        totalPaidAmount: initialPaidAmount,
        currentDueAmount: initialDueAmount,
        roomId: roomId,
        roomNumber: roomNumber,
        floor: floor,
        bedIds: bedIds,
        bedLabels: bedLabels,
        photoDataUrl: photoDataUrl,
        photoFileName: photoFileName,
        notes: notes,
        address: address,
        lobby: lobby,
        exitDate: exitDate,
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
        registrationNumber: registrationNumber,
        registrationDate: registrationDate,
        panCardNumber: panCardNumber,
        aadhaarCardNumber: aadhaarCardNumber,
        receiptNumber: receiptNumber,
        modeOfPayment: modeOfPayment,
        utiNumber: utiNumber,
        isAdvancePeriod: isAdvancePeriod,
        // Imported totals are also the initial billed amount.  The Payments
        // dashboard reads this field when calculating its Bill and Due cards.
        advanceBilledAmount: initialTotalAmount ?? advanceBilledAmount,
        attendanceCharges: attendanceCharges,
        totalPresentDays: totalPresentDays,
        totalAbsentDays: totalAbsentDays,
        attendants: attendants,
        payments: payments,
      );

      // Push to generate unique key
      final patientId = await _rtdb.push(_patientsPath, patient.toMap());

      // Update the ID field in the database
      await _rtdb.patch('$_patientsPath/$patientId', {'id': patientId});

      if (exitDate != null) {
        await syncAutomaticPatientAttendance(
          patientId: patientId,
          patientName: fullName,
          start: registrationDate ?? admissionDate,
          end: exitDate,
          cycleId: admissionDate.millisecondsSinceEpoch.toString(),
        );
      }

      // Also record any initial payments in the global history
      if (payments != null && payments.isNotEmpty) {
        for (final payment in payments) {
          final globalPaymentData = payment.toMap();
          globalPaymentData['patientId'] = patientId;
          globalPaymentData['patientName'] = fullName;
          await _rtdb.push('payments', globalPaymentData);
        }
      }

      return patientId;
    } catch (e) {
      throw Exception('Failed to add patient: $e');
    }
  }

  /// Records a new payment for a patient and also adds it to a global payments collection.
  Future<void> recordPayment(String patientId, PaymentModel payment) async {
    final patient = await getPatient(patientId);
    if (patient == null) throw StateError('Patient not found');
    await ServiceLocator().paymentService.recordPayment(
      patientId: patientId,
      patientName: patient.fullName,
      payment: payment,
    );
  }

  // ===========================================================================
  // UPDATE — Partial updates
  // ===========================================================================

  /// Applies a partial update to patient at `/patients/$patientId`.
  ///
  /// Automatically updates `updatedAt`, recalculates `searchKey` if
  /// `fullName` changes, and recalculates `age` if `dateOfBirth` changes.
  Future<void> updatePatient(
    String patientId,
    Map<String, dynamic> updates,
  ) async {
    try {
      updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

      // Auto-sync searchKey when fullName changes
      if (updates.containsKey('fullName')) {
        updates['searchKey'] = (updates['fullName'] as String).toLowerCase();
      }

      // Auto-recalculate age when dateOfBirth changes
      if (updates.containsKey('dateOfBirth')) {
        final dob = updates['dateOfBirth'] is int
            ? DateTime.fromMillisecondsSinceEpoch(updates['dateOfBirth'] as int)
            : updates['dateOfBirth'] as DateTime;
        updates['age'] = PatientModel.calculateAge(dob);
        if (updates['dateOfBirth'] is DateTime) {
          updates['dateOfBirth'] = dob.millisecondsSinceEpoch;
        }
      }

      final rootUpdates = <String, dynamic>{
        for (final entry in updates.entries)
          '$_patientsPath/$patientId/${entry.key}': entry.value,
      };
      if ([
        'registrationNumber',
        'photoDataUrl',
        'attendants',
      ].any(updates.containsKey)) {
        final patient = await _rtdb.get('$_patientsPath/$patientId');
        if (patient is Map) {
          final merged = {...patient, ...updates};
          final stays = await ServiceLocator().roomService
              .getStaysByPatientStream(patientId)
              .first;
          for (final stay in stays.where((stay) => stay.isActive)) {
            rootUpdates['stays/${stay.id}/patientSnapshot'] = {
              for (final key in [
                'registrationNumber',
                'photoDataUrl',
                'attendants',
                'admissionDate',
              ])
                key: merged[key],
            };
          }
        }
      }
      await _rtdb.patch('', rootUpdates);

      if ({
        'registrationDate',
        'admissionDate',
        'exitDate',
        'fullName',
      }.any(updates.containsKey)) {
        final revised = await getPatient(patientId);
        if (revised?.exitDate != null) {
          await syncAutomaticPatientAttendance(
            patientId: patientId,
            patientName: revised!.fullName,
            start: revised.registrationDate ?? revised.admissionDate,
            end: revised.exitDate!,
            cycleId: revised.admissionDate.millisecondsSinceEpoch.toString(),
          );
        } else if (revised != null) {
          await clearAutomaticPatientAttendance(
            patientId: patientId,
            cycleId: revised.admissionDate.millisecondsSinceEpoch.toString(),
          );
        }
      }
    } catch (e) {
      throw Exception('Failed to update patient: $e');
    }
  }

  /// Saves automatic patient presence for a planned registration-to-exit
  /// period. Manual Present/Absent choices always win, and attendant
  /// attendance is deliberately kept separate and remains manual.
  Future<void> syncAutomaticPatientAttendance({
    required String patientId,
    required String patientName,
    required DateTime start,
    required DateTime end,
    required String cycleId,
  }) async {
    final firstDay = StayBilling.day(start);
    final lastDay = StayBilling.day(end);
    if (lastDay.isBefore(firstDay)) {
      throw ArgumentError('Exit date cannot be before registration date.');
    }

    dynamic rawAttendance;
    try {
      rawAttendance = await _rtdb.get('attendance/daily');
    } catch (_) {}
    final attendance = rawAttendance is Map ? rawAttendance : const {};
    final desiredDates = <String>{};
    final updates = <String, dynamic>{};

    for (
      var date = firstDay;
      !date.isAfter(lastDay);
      date = DateTime(date.year, date.month, date.day + 1)
    ) {
      final dateKey = StayBilling.dateKey(date);
      desiredDates.add(dateKey);
      final daily = attendance[dateKey];
      final existing = daily is Map ? daily[patientId] : null;
      final isManual = existing is Map &&
          existing['source'] != 'automatic_registration_period' &&
          {'Present', 'Absent'}.contains(existing['status']);
      if (isManual) continue;
      updates['attendance/daily/$dateKey/$patientId'] = {
        'patientId': patientId,
        'patientName': patientName,
        'status': 'Present',
        'date': dateKey,
        'source': 'automatic_registration_period',
        'cycleId': cycleId,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }

    if (attendance is Map) {
      attendance.forEach((rawDate, rawDaily) {
        if (rawDaily is! Map) return;
        final existing = rawDaily[patientId];
        if (existing is Map &&
            existing['source'] == 'automatic_registration_period' &&
            existing['cycleId']?.toString() == cycleId &&
            !desiredDates.contains(rawDate.toString())) {
          updates['attendance/daily/$rawDate/$patientId'] = null;
        }
      });
    }

    if (updates.isNotEmpty) await _rtdb.patch('', updates);
  }

  Future<void> clearAutomaticPatientAttendance({
    required String patientId,
    required String cycleId,
  }) async {
    dynamic rawAttendance;
    try {
      rawAttendance = await _rtdb.get('attendance/daily');
    } catch (_) {
      return;
    }
    if (rawAttendance is! Map) return;
    final updates = <String, dynamic>{};
    rawAttendance.forEach((rawDate, rawDaily) {
      if (rawDaily is! Map) return;
      final existing = rawDaily[patientId];
      if (existing is Map &&
          existing['source'] == 'automatic_registration_period' &&
          existing['cycleId']?.toString() == cycleId) {
        updates['attendance/daily/$rawDate/$patientId'] = null;
      }
    });
    if (updates.isNotEmpty) await _rtdb.patch('', updates);
  }

  // ===========================================================================
  // ROOM ASSIGNMENT
  // ===========================================================================

  /// Assigns a patient to a room.
  Future<void> assignToRoom(
    String patientId,
    String roomId,
    String roomNumber,
    int floor,
  ) async {
    try {
      await updatePatient(patientId, {
        'roomId': roomId,
        'roomNumber': roomNumber,
        'floor': floor,
      });
    } catch (e) {
      throw Exception('Failed to assign patient to room: $e');
    }
  }

  /// Removes a patient from their current room.
  Future<void> removeFromRoom(String patientId) async {
    try {
      await updatePatient(patientId, {
        'roomId': null,
        'roomNumber': null,
        'floor': null,
        'bedIds': null,
        'bedLabels': null,
      });
    } catch (e) {
      throw Exception('Failed to remove patient from room: $e');
    }
  }

  // ===========================================================================
  // STATUS TRANSITIONS
  // ===========================================================================

  Future<Map<String, dynamic>> getDischargeReadiness(String patientId) async {
    await ServiceLocator().paymentService
        .recalculatePatientAttendanceAndBilling(patientId);
    final patient = await getPatient(patientId);
    if (patient == null) throw StateError('Patient not found');
    if (patient.exitDate != null) {
      await syncAutomaticPatientAttendance(
        patientId: patientId,
        patientName: patient.fullName,
        start: patient.registrationDate ?? patient.admissionDate,
        end: patient.exitDate!,
        cycleId: patient.admissionDate.millisecondsSinceEpoch.toString(),
      );
    }
    final stays = await ServiceLocator().roomService
        .getStaysByPatientStream(patientId)
        .first;
    final cycleId = StayBilling.currentCycle(patient);
    final cycleSegments = stays
        .where((stay) => StayBilling.cycleFor(stay, patient) == cycleId)
        .toList();
    final balance = patient.admissionBalances[cycleId];
    final summary = balance is Map ? balance : const <String, dynamic>{};
    final total =
        (summary['total'] as num?)?.toDouble() ??
        patient.advanceBilledAmount + patient.attendanceCharges;
    final paid =
        (summary['netPaid'] as num?)?.toDouble() ??
        patient.totalPaidAmount ??
        0;
    final pending =
        (summary['due'] as num?)?.toDouble() ??
        (total - paid).clamp(0, double.infinity);
    final refundDue =
        (summary['refundDue'] as num?)?.toDouble() ??
        (paid - total).clamp(0, double.infinity);

    final patientAttendance = await _rtdb.get('attendance/daily');
    final attendantAttendance = await _rtdb.get('attendant_attendance/daily');
    // Attendance readiness belongs to the current admission cycle. Older
    // admission/registration values can remain on rejoined records, so use
    // the later current-cycle boundary and stop at the recorded exit date.
    final admissionDay = StayBilling.day(patient.admissionDate);
    final registrationDay = patient.registrationDate == null
        ? admissionDay
        : StayBilling.day(patient.registrationDate!);
    final start = registrationDay.isAfter(admissionDay)
        ? registrationDay
        : admissionDay;
    final requestedEnd = StayBilling.day(
      patient.exitDate ?? patient.dischargeDate ?? DateTime.now(),
    );
    final end = requestedEnd.isBefore(start) ? start : requestedEnd;
    var missingPatientDays = 0;
    var missingAttendantMarks = 0;
    String key(DateTime date) => StayBilling.dateKey(date);
    for (
      var date = start;
      !date.isAfter(end);
      date = DateTime(date.year, date.month, date.day + 1)
    ) {
      final dateKey = key(date);
      final patientRecord =
          patientAttendance is Map && patientAttendance[dateKey] is Map
          ? patientAttendance[dateKey][patientId]
          : null;
      if (patientRecord is! Map ||
          !{'Present', 'Absent'}.contains(patientRecord['status'])) {
        missingPatientDays++;
      }
      final segment = _segmentForDate(cycleSegments, date);
      if (segment == null) continue;
      final names = _attendantNames(segment, patient);
      final daily =
          attendantAttendance is Map &&
              attendantAttendance[dateKey] is Map &&
              attendantAttendance[dateKey][patientId] is Map
          ? attendantAttendance[dateKey][patientId] as Map
          : const {};
      for (final name in names) {
        final safe = name.replaceAll(RegExp(r'[.#\$\[\]/]'), '_');
        final record = daily[safe];
        if (record is! Map ||
            !{'Present', 'Absent'}.contains(record['status'])) {
          missingAttendantMarks++;
        }
      }
    }
    final reasons = <String>[
      if (missingPatientDays > 0)
        '$missingPatientDays patient attendance day(s) are unmarked between ${_shortDate(start)} and ${_shortDate(end)}.',
      if (missingAttendantMarks > 0)
        '$missingAttendantMarks attendant attendance record(s) are unmarked between ${_shortDate(start)} and ${_shortDate(end)}.',
      if (pending > 0.005) '₹${pending.toStringAsFixed(0)} remains to be paid.',
      if (refundDue > 0.005)
        '₹${refundDue.toStringAsFixed(0)} must be refunded first.',
    ];
    return {
      'total': total,
      'paid': paid,
      'pending': pending,
      'refundDue': refundDue,
      'missingPatientDays': missingPatientDays,
      'missingAttendantMarks': missingAttendantMarks,
      'ready': reasons.isEmpty,
      'reasons': reasons,
    };
  }

  String _shortDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  StayModel? _segmentForDate(List<StayModel> segments, DateTime date) {
    final candidates = segments.where((segment) {
      if (StayBilling.day(segment.admissionDate).isAfter(date)) return false;
      if (segment.isActive) return true;
      return !StayBilling.day(
        segment.completedAt ?? segment.updatedAt,
      ).isBefore(date);
    }).toList()..sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
    return candidates.firstOrNull;
  }

  List<String> _attendantNames(StayModel stay, PatientModel patient) {
    final raw = stay.patientSnapshot['attendants'];
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map && item['name']?.toString().trim().isNotEmpty == true)
            item['name'].toString().trim(),
      ];
    }
    if (stay.attendantLabels.isNotEmpty) return stay.attendantLabels;
    return [
      for (final attendant in patient.attendants ?? const []) attendant.name,
    ];
  }

  /// Discharges a patient: sets status to 'discharged' and clears room.
  /// Also releases the bed by completing the active stay.
  Future<void> dischargePatient(String patientId) async {
    try {
      final readiness = await getDischargeReadiness(patientId);
      if (readiness['ready'] != true) {
        throw StateError((readiness['reasons'] as List).join(' '));
      }
      // Get patient to find their room/bed
      final patient = await getPatient(patientId);
      if (patient == null) throw Exception('Patient not found');

      final dischargeActionTime = DateTime.now();
      final billingAdmissionDate =
          patient.registrationDate ?? patient.admissionDate;
      // Lifecycle status is the primary action and must not depend on room or
      // legacy stay cleanup succeeding.
      await updatePatient(patientId, {
        'status': 'discharged',
        'dischargeDate': dischargeActionTime.millisecondsSinceEpoch,
      });

      // Release all active placements as best-effort cleanup.
      final roomService = ServiceLocator().roomService;
      try {
        final stays = await roomService
            .getStaysByPatientStream(patientId)
            .first;
        final activeStays = stays.where((s) => s.status == 'active').toList();
        for (final activeStay in activeStays) {
          try {
            await roomService.completeStay(
              activeStay.id,
              completedAt: patient.exitDate ?? dischargeActionTime,
              billingAdmissionDate:
                  activeStay.notes?.startsWith('Shifted from ') == true
                  ? null
                  : billingAdmissionDate,
            );
          } catch (_) {
            // A malformed historical stay must not reactivate the patient or
            // block discharge. Other valid stays continue to be released.
          }
        }
      } catch (_) {
        // The patient is already discharged. Stay reconciliation can retry.
      }

      // Freeze attendance and billing at the actual discharge timestamp.
      // Without this recalculation, amounts last computed while the patient
      // was active can continue to include days after discharge.
      try {
        await ServiceLocator().paymentService
            .recalculatePatientAttendanceAndBilling(patientId);
      } catch (_) {
        // Discharge is already complete. Billing reconciliation can be
        // retried later and must not make the action appear to have failed.
      }

      // Keep lifecycle status authoritative. Billing/payment reconciliation
      // must not leave a discharged patient active or in the legacy Paid
      // lifecycle state.
      await updatePatient(patientId, {
        'status': 'discharged',
        'dischargeDate': dischargeActionTime.millisecondsSinceEpoch,
      });
    } catch (e) {
      throw Exception('Failed to discharge patient: $e');
    }
  }

  /// Reactivates a discharged patient.
  Future<void> reactivatePatient(String patientId) async {
    try {
      await updatePatient(patientId, {'status': 'active'});
    } catch (e) {
      throw Exception('Failed to reactivate patient: $e');
    }
  }

  // ===========================================================================
  // DELETE
  // ===========================================================================

  /// Permanently deletes a patient record.
  Future<void> deletePatient(String patientId) async {
    try {
      final rawPatient = await _rtdb.get('$_patientsPath/$patientId');
      final patient = rawPatient is Map
          ? PatientModel.fromMap(patientId, rawPatient)
          : null;
      final stays = await ServiceLocator().paymentService.loadStays(patientId);
      await _purgePatientArtifacts(
        patientId,
        stays,
        attendanceStart:
            patient?.registrationDate ?? patient?.admissionDate,
      );
    } catch (e) {
      throw Exception('Failed to delete patient: $e');
    }
  }

  /// Repairs records left by older versions that deleted the patient before
  /// completing the related cleanup.
  Future<int> purgeOrphanedPatientRecords() async {
    final running = _orphanCleanupFuture;
    if (running != null) return running;
    final cleanup = _purgeOrphanedPatientRecords();
    _orphanCleanupFuture = cleanup;
    try {
      return await cleanup;
    } finally {
      // Re-check whenever another data screen opens. This also repairs an
      // orphan created after an earlier successful no-op check.
      if (identical(_orphanCleanupFuture, cleanup)) {
        _orphanCleanupFuture = null;
      }
    }
  }

  /// Runs an immediate repair when a screen has directly observed an orphan.
  Future<int> repairOrphanedPatientRecordsNow() =>
      _purgeOrphanedPatientRecords();

  Future<int> _purgeOrphanedPatientRecords() async {
    final rawPatients = await _rtdb.get(_patientsPath);
    final patientIds = rawPatients is Map
        ? rawPatients.keys.map((key) => key.toString()).toSet()
        : <String>{};
    final rawActive = await _rtdb.getByChildValue(
      'stays',
      child: 'status',
      value: 'active',
    );
    if (rawActive is! Map) return 0;
    final orphanIds = <String>{
      for (final value in rawActive.values)
        if (value is Map &&
            value['patientId'] != null &&
            !patientIds.contains(value['patientId'].toString()))
          value['patientId'].toString(),
    };
    for (final patientId in orphanIds) {
      final stays = await ServiceLocator().paymentService.loadStays(patientId);
      await _purgePatientArtifacts(patientId, stays);
    }
    return orphanIds.length;
  }

  Future<void> _purgePatientArtifacts(
    String patientId,
    List<StayModel> stays, {
    DateTime? attendanceStart,
  }) async {
    final cleanup = <String, dynamic>{
      'patients/$patientId': null,
      for (final stay in stays) 'stays/${stay.id}': null,
    };
    final stayIds = stays.map((stay) => stay.id).toSet();
    final roomService = ServiceLocator().roomService;
    for (final roomId in stays
        .where((stay) => stay.roomType != 'lobby' && stay.roomId.isNotEmpty)
        .map((stay) => stay.roomId)
        .toSet()) {
      final room = await roomService.getRoom(roomId);
      if (room == null) continue;
      final fixedBeds = room.beds.map((bed) {
        final belongsToPatient = bed.currentPatientId == patientId;
        final belongsToStay =
            bed.currentStayId != null && stayIds.contains(bed.currentStayId);
        return belongsToPatient || belongsToStay
            ? bed.copyWith(
                status: 'available',
                clearPatientId: true,
                clearStayId: true,
              )
            : bed;
      }).toList();
      final occupied = fixedBeds.where((bed) => bed.isOccupied).length;
      final removedAttendants = stays
          .where(
            (stay) =>
                stay.roomId == roomId && stay.isActive && room.isPrivate,
          )
          .fold<int>(0, (sum, stay) => sum + stay.attendantCount);
      cleanup.addAll({
        'rooms/$roomId/beds': roomService.bedsToRtdbMap(fixedBeds),
        'rooms/$roomId/occupiedBeds': occupied,
        'rooms/$roomId/currentAttendants':
            (room.currentAttendants - removedAttendants).clamp(0, 999),
        'rooms/$roomId/status': room.status == 'maintenance'
            ? 'maintenance'
            : occupied == 0
            ? 'available'
            : room.isPrivate && occupied < room.actualTotalBeds
            ? 'partially_occupied'
            : occupied >= room.actualTotalBeds
            ? 'occupied'
            : 'available',
        'rooms/$roomId/updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    if (stays.isNotEmpty || attendanceStart != null) {
      final starts = <DateTime>[
        if (attendanceStart != null) attendanceStart,
        ...stays.map((stay) => stay.admissionDate),
      ]..sort();
      final startKey = StayBilling.dateKey(starts.first);
      final endKey = StayBilling.dateKey(DateTime.now());
      final attendanceReads = await Future.wait<dynamic>([
        _rtdb.getByKeyRange(
          'attendance/daily',
          startKey: startKey,
          endKey: endKey,
        ),
        _rtdb.getByKeyRange(
          'attendant_attendance/daily',
          startKey: startKey,
          endKey: endKey,
        ),
      ]);
      for (final pathIndex in [0, 1]) {
        final records = attendanceReads[pathIndex];
        if (records is! Map) continue;
        final path = pathIndex == 0
            ? 'attendance/daily'
            : 'attendant_attendance/daily';
        for (final entry in records.entries) {
          if (entry.value is Map &&
              (entry.value as Map).containsKey(patientId)) {
            cleanup['$path/${entry.key}/$patientId'] = null;
          }
        }
      }
    }

    for (final path in const ['payments', 'paymentHistory']) {
      final records = await _rtdb.getByChildValue(
        path,
        child: 'patientId',
        value: patientId,
      );
      if (records is Map) {
        for (final id in records.keys) {
          cleanup['$path/$id'] = null;
        }
      }
    }
    await _rtdb.patch('', cleanup);
  }

  // ===========================================================================
  // STATISTICS
  // ===========================================================================

  /// Fetches aggregate statistics across all patients.
  ///
  /// Returns a map with keys: `total`, `active`, `inactive`, `discharged`,
  /// `withRoom`, `withoutRoom`.
  Future<Map<String, int>> getPatientStats() async {
    try {
      final data = await _rtdb.get(_patientsPath);

      int total = 0;
      int active = 0;
      int inactive = 0;
      int discharged = 0;
      int withRoom = 0;

      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        total = mapData.length;

        mapData.forEach((key, value) {
          if (value is Map) {
            final patientData = Map<String, dynamic>.from(value);
            final status = patientData['status'] ?? 'active';

            if (status == 'active' || status == 'Paid') active++;
            if (status.toString().toLowerCase() == 'inactive') inactive++;
            if (status == 'discharged') discharged++;
            if (patientData['roomId'] != null &&
                (status == 'active' || status == 'Paid')) {
              withRoom++;
            }
          }
        });
      }

      return {
        'total': total,
        'active': active,
        'inactive': inactive,
        'discharged': discharged,
        'withRoom': withRoom,
        'withoutRoom': active - withRoom,
      };
    } catch (e) {
      throw Exception('Failed to fetch patient statistics: $e');
    }
  }

  /// Real-time stream of patient statistics.
  ///
  /// This uses polling to simulate realtime updates.
  Stream<Map<String, int>> getPatientStatsStream() {
    return _rtdb.stream(_patientsPath).map((data) {
      int total = 0;
      int active = 0;
      int inactive = 0;
      int discharged = 0;
      int withRoom = 0;

      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        total = mapData.length;

        mapData.forEach((key, value) {
          if (value is Map) {
            final patientData = Map<String, dynamic>.from(value);
            final status = patientData['status'] ?? 'active';

            if (status == 'active' || status == 'Paid') active++;
            if (status.toString().toLowerCase() == 'inactive') inactive++;
            if (status == 'discharged') discharged++;
            if (patientData['roomId'] != null &&
                (status == 'active' || status == 'Paid')) {
              withRoom++;
            }
          }
        });
      }

      return {
        'total': total,
        'active': active,
        'inactive': inactive,
        'discharged': discharged,
        'withRoom': withRoom,
        'withoutRoom': active - withRoom,
      };
    });
  }
}
