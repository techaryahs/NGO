import 'dart:async';
import '../models/patient_model.dart';
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
  Stream<List<PatientModel>> getPatientsByStatuses(
    List<String> statuses,
  ) {
    return _rtdb
        .queryAnyStream(
          _patientsPath,
          orderBy: 'status',
          equalToAny: statuses,
        )
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
          patients.sort(
            (a, b) => b.admissionDate.compareTo(a.admissionDate),
          );
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

    final data = await _rtdb.get(_patientsPath);
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
    try {
      final patient = await getPatient(patientId);
      if (patient == null) throw Exception('Patient not found');

      final updatedPayments = List<PaymentModel>.from(patient.payments ?? []);
      updatedPayments.add(payment);

      // Update patient record
      await _rtdb.patch('$_patientsPath/$patientId', {
        'payments': updatedPayments.map((p) => p.toMap()).toList(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Also record in global payments collection for the "Payments" section
      final globalPaymentData = payment.toMap();
      globalPaymentData['patientId'] = patientId;
      globalPaymentData['patientName'] = patient.fullName;

      await _rtdb.push('payments', globalPaymentData);
    } catch (e) {
      throw Exception('Failed to record payment: $e');
    }
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

      await _rtdb.patch('$_patientsPath/$patientId', updates);
    } catch (e) {
      throw Exception('Failed to update patient: $e');
    }
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

  /// Discharges a patient: sets status to 'discharged' and clears room.
  /// Also releases the bed by completing the active stay.
  Future<void> dischargePatient(String patientId) async {
    try {
      // Get patient to find their room/bed
      final patient = await getPatient(patientId);
      if (patient == null) throw Exception('Patient not found');

      final dischargeActionTime = DateTime.now();
      final billingAdmissionDate =
          patient.registrationDate ?? patient.admissionDate;
      final finalTotal =
          patient.advanceBilledAmount + patient.attendanceCharges;
      final finalPaid = patient.totalPaidAmount ?? 0.0;
      final finalPending = (finalTotal - finalPaid).clamp(
        0.0,
        double.infinity,
      );

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
        final activeStays = stays
            .where((s) => s.status == 'active')
            .toList();
        for (final activeStay in activeStays) {
          try {
            await roomService.completeStay(
              activeStay.id,
              completedAt: patient.exitDate ?? dischargeActionTime,
              billingAdmissionDate: billingAdmissionDate,
              totalCost: finalTotal,
              paidAmount: finalPaid,
              pendingAmount: finalPending,
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
      // Release every active stay before removing the patient so beds and room
      // census data cannot retain an orphaned occupant.
      final activeStays = await ServiceLocator().roomService
          .getStaysByPatientStream(patientId)
          .first;
      for (final stay in activeStays.where((stay) => stay.status == 'active')) {
        try {
          await ServiceLocator().roomService.completeStay(stay.id);
        } catch (_) {
          // Do not make an inconsistent legacy stay prevent the explicitly
          // requested patient deletion.
        }
      }

      // Attendance is keyed by date, so remove this patient's records from
      // every date (including attendant attendance) in one root patch.
      dynamic attendance;
      dynamic attendantAttendance;
      try {
        attendance = await _rtdb.get('attendance/daily');
      } catch (_) {}
      try {
        attendantAttendance = await _rtdb.get('attendant_attendance/daily');
      } catch (_) {}
      final cleanup = <String, dynamic>{};
      if (attendance is Map) {
        attendance.forEach((date, records) {
          if (records is Map && records.containsKey(patientId)) {
            cleanup['attendance/daily/$date/$patientId'] = null;
          }
        });
      }
      if (attendantAttendance is Map) {
        attendantAttendance.forEach((date, records) {
          if (records is Map && records.containsKey(patientId)) {
            cleanup['attendant_attendance/daily/$date/$patientId'] = null;
          }
        });
      }
      // Payment dashboards read these global collections, while the patient
      // record holds the detailed payment list. Remove matching ledger rows.
      for (final path in const ['payments', 'paymentHistory']) {
        dynamic payments;
        try {
          payments = await _rtdb.get(path);
        } catch (_) {
          continue;
        }
        if (payments is Map) {
          payments.forEach((paymentId, payment) {
            if (payment is Map &&
                payment['patientId']?.toString() == patientId) {
              cleanup['$path/$paymentId'] = null;
            }
          });
        }
      }
      if (cleanup.isNotEmpty) {
        try {
          await _rtdb.patch('', cleanup);
        } catch (_) {
          // Some older deployments do not grant access to every optional
          // ledger path. The patient record can still be deleted.
        }
      }
      await _rtdb.delete('$_patientsPath/$patientId');
    } catch (e) {
      throw Exception('Failed to delete patient: $e');
    }
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
