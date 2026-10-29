import 'dart:async';
import 'dart:math';
import '../models/patient_model.dart';
import '../models/stay_model.dart';
import '../utils/stay_billing.dart';
import 'backend_api_service.dart';
import 'firebase_rtdb_rest_service.dart';
import 'payment_service.dart';
import 'photo_rtdb_service.dart';
import 'registration_number_service.dart';
import 'service_locator.dart';

/// Service layer for all patient-related operations.
///
/// Supports both Firebase RTDB and Fastify + PostgreSQL backend modes.
class PatientService {
  /// REST API service instance
  final FirebaseRTDBRestService? _rtdb;
  final BackendApiService? _backendApi;
  final PhotoRtdbService? _photos;
  final RegistrationNumberService? _registrationNumbers;
  final RoomService? _roomService;
  final PaymentService? _paymentService;

  /// Base path for patient records.
  final String _patientsPath = 'patients';
  Future<int>? _orphanCleanupFuture;

  PatientService({
    FirebaseRTDBRestService? rtdbService,
    BackendApiService? backendApiService,
    PhotoRtdbService? photos,
    RegistrationNumberService? registrationNumberService,
    RoomService? roomService,
    PaymentService? paymentService,
  }) : _rtdb = rtdbService,
       _backendApi =
           backendApiService ??
           (rtdbService == null ? _tryLocatorBackendApi() : null),
       _photos = photos,
       _registrationNumbers = registrationNumberService,
       _roomService = roomService,
       _paymentService = paymentService;

  static BackendApiService? _tryLocatorBackendApi() {
    try {
      return ServiceLocator().backendApiService;
    } catch (_) {
      return null;
    }
  }

  bool get isPostgres => _backendApi != null || _rtdb == null;

  FirebaseRTDBRestService get _safeRtdb {
    if (_rtdb != null) return _rtdb;
    return ServiceLocator().rtdbService;
  }

  RegistrationNumberService get _regService {
    final reg = _registrationNumbers;
    if (reg != null) return reg;
    if (_backendApi != null) {
      return RegistrationNumberService(
        rtdbService: _rtdb,
        backendApiService: _backendApi,
      );
    }
    try {
      return ServiceLocator().registrationNumberService;
    } catch (_) {
      return RegistrationNumberService(
        rtdbService: _rtdb,
        backendApiService: _backendApi,
      );
    }
  }

  RoomService get _resolvedRoomService {
    if (_roomService != null) return _roomService;
    if (_backendApi != null) {
      return RoomService(rtdbService: _rtdb, backendApiService: _backendApi);
    }
    return ServiceLocator().roomService;
  }

  PaymentService get _resolvedPaymentService {
    if (_paymentService != null) return _paymentService;
    if (_backendApi != null) {
      return PaymentService(_rtdb, _backendApi);
    }
    return ServiceLocator().paymentService;
  }

  /// Deterministically generates a unique patient ID prefixed with timestamp.
  static String generatePatientId() {
    final now = DateTime.now();
    final random = Random.secure();
    return 'p_${now.microsecondsSinceEpoch}_${List<int>.generate(12, (_) => random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

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
    final sourceStream = isPostgres
        ? _backendApi!.stream(_patientsPath)
        : _safeRtdb.stream(_patientsPath);

    return sourceStream.map((data) {
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
    });
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
    if (isPostgres) {
      return getPatientsStream().map((patients) {
        return patients.where((p) => statuses.contains(p.status)).toList();
      });
    }
    return _safeRtdb
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
        });
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
      final data = isPostgres
          ? await _backendApi!.get('$_patientsPath/$patientId')
          : await _safeRtdb.get('$_patientsPath/$patientId');
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

    if (isPostgres) {
      dynamic data;
      try {
        data = await _backendApi!.get(
          '$_patientsPath?search=${Uri.encodeComponent(registrationNumber.trim())}&format=map',
        );
      } catch (_) {
        data = await _backendApi!.get(_patientsPath);
      }
      if (data is! Map) return null;
      for (final entry in Map<String, dynamic>.from(data).entries) {
        if (entry.key == excludingPatientId || entry.value is! Map) continue;
        final storedNumber =
            (entry.value['registrationNumber']?.toString() ?? '').trim();
        if (storedNumber.toLowerCase() == normalized) {
          return PatientModel.fromMap(
            entry.key,
            Map<String, dynamic>.from(entry.value),
          );
        }
      }
      return null;
    }

    // Ask Firebase for matching records only. Downloading the entire patient
    // collection made a simple add/edit fail on slower connections.
    dynamic data;
    try {
      data = await _safeRtdb.query(
        _patientsPath,
        orderBy: 'registrationNumber',
        equalTo: registrationNumber.trim(),
      );
    } catch (_) {
      // Older Firebase projects can be missing the registrationNumber index
      // during a rules rollout. Preserve duplicate protection (at the cost of
      // one full read) instead of blocking a new admission with a 400 error.
      data = await _safeRtdb.get(_patientsPath);
    }
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
  /// Generates a collision-resistant key before uploading photos, then writes
  /// the complete patient in one database request.
  Future<String> addPatient({
    String? id,
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
    List<Map<String, dynamic>>? initialStays,
  }) async {
    try {
      if (payments != null && payments.isNotEmpty) {
        throw StateError('Import payments through the trusted payment backend');
      }
      final now = DateTime.now();
      final patientId = id ?? generatePatientId();

      // Automatically allocate monotonic registration number if not provided
      if (registrationNumber == null || registrationNumber.trim().isEmpty) {
        registrationNumber = await _regService.allocateNextRegistrationNumber(
          idempotencyKey: patientId,
        );
      }

      String? photoRef;
      if (photoDataUrl != null && photoDataUrl.isNotEmpty) {
        final bytes = PhotoRtdbService.decodeLegacyBase64(photoDataUrl);
        if (bytes == null) throw StateError('Patient photo is invalid');
        photoRef = await (_photos ?? ServiceLocator().photoRtdbService)
            .uploadPhoto(
              photoPath: PhotoRtdbService.patientPath(patientId),
              bytes: bytes,
            );
      }
      final storedAttendants = <AttendantModel>[];
      for (var index = 0; index < (attendants?.length ?? 0); index++) {
        final attendant = attendants![index];
        var ref = attendant.photoRef;
        final dataUrl = attendant.photoDataUrl;
        if (dataUrl != null && dataUrl.isNotEmpty) {
          final bytes = PhotoRtdbService.decodeLegacyBase64(dataUrl);
          if (bytes == null) throw StateError('Attendant photo is invalid');
          ref = await (_photos ?? ServiceLocator().photoRtdbService)
              .uploadPhoto(
                photoPath: PhotoRtdbService.attendantPath(patientId, '$index'),
                bytes: bytes,
              );
        }
        storedAttendants.add(
          AttendantModel.fromMap({
            ...attendant.toMap(),
            'photoDataUrl': null,
            'photoRef': ref,
          }),
        );
      }
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

      final patient = PatientModel(
        id: patientId,
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
        photoDataUrl: null,
        photoRef: photoRef,
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
        attendants: storedAttendants.isEmpty ? null : storedAttendants,
        payments: payments,
      );

      // Registration records the planned stay, never actual presence. Attendance
      // is written only by an explicit attendance operation.
      if (isPostgres) {
        try {
          await _backendApi!.registerPatient({
            ...patient.toMap(),
            if (initialStays != null) 'stays': initialStays,
          });
        } on BackendApiException catch (e) {
          if (e.statusCode == 409) {
            if (e.message.toLowerCase().contains('registration number')) {
              throw StateError(e.message);
            }
            throw _resolvedRoomService.bedConflict(e.message);
          }
          rethrow;
        }
        return patientId;
      }

      final existingWithReg = await getPatientByRegistrationNumber(
        registrationNumber,
        excludingPatientId: patientId,
      );
      if (existingWithReg != null) {
        throw StateError(
          'Registration number "$registrationNumber" is already assigned to another patient.',
        );
      }

      await _safeRtdb.patch('', {'$_patientsPath/$patientId': patient.toMap()});

      return patientId;
    } catch (e) {
      if (e is BedConflictException || e is StateError) rethrow;
      throw Exception('Failed to add patient: $e');
    }
  }

  /// Reads daily attendance or attendant attendance for a date window via the
  /// active backend (PostgreSQL `/api/attendance` or RTDB `/attendance/daily`).
  Future<dynamic> getAttendanceRangeForProfile({
    required String kind,
    required String startKey,
    required String endKey,
  }) async {
    if (isPostgres) {
      return await _backendApi!.getAttendanceRange(
        kind: kind,
        startKey: startKey,
        endKey: endKey,
      );
    }
    return await _safeRtdb.getByKeyRange(
      '$kind/daily',
      startKey: startKey,
      endKey: endKey,
    );
  }

  /// Compatibility for older callers. A planned period is eligibility/estimate
  /// data, not evidence of presence for either patients or attendants.
  static Map<String, dynamic> initialAdmissionAttendance({
    required String patientId,
    required String patientName,
    required DateTime start,
    required DateTime? exit,
    required String cycleId,
    required List<AttendantModel> attendants,
  }) => const {};

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

      if (isPostgres) {
        if (updates.containsKey('registrationNumber')) {
          final existing = await getPatient(patientId);
          final existingReg = existing?.registrationNumber?.trim();
          final proposedReg = updates['registrationNumber']?.toString().trim();
          if (proposedReg != null &&
              proposedReg.isNotEmpty &&
              proposedReg.toLowerCase() != (existingReg ?? '').toLowerCase()) {
            final duplicate = await getPatientByRegistrationNumber(
              proposedReg,
              excludingPatientId: patientId,
            );
            if (duplicate != null) {
              throw StateError(
                'Registration number "$proposedReg" is already assigned to another patient.',
              );
            }
          }
        }
        await _backendApi!.updatePatient(patientId, updates);
        if (updates.containsKey('attendants')) {
          // The server updates the admission roster and bill in the same commit.
          // Publish the changed stay snapshot to the retained attendance screen.
          await _backendApi.refresh('stays?patientId=$patientId&format=map');
        }
        return;
      }

      // Registration number uniqueness check on update
      if (updates.containsKey('registrationNumber')) {
        final existingRaw = await _safeRtdb.get(
          '$_patientsPath/$patientId/registrationNumber',
        );
        final existingReg = existingRaw?.toString().trim();
        final proposedReg = updates['registrationNumber']?.toString().trim();
        if (proposedReg != null &&
            proposedReg.isNotEmpty &&
            proposedReg.toLowerCase() != (existingReg ?? '').toLowerCase()) {
          final duplicate = await getPatientByRegistrationNumber(
            proposedReg,
            excludingPatientId: patientId,
          );
          if (duplicate != null) {
            throw StateError(
              'Registration number "$proposedReg" is already assigned to another patient.',
            );
          }
        }
      }

      final rootUpdates = <String, dynamic>{
        for (final entry in updates.entries)
          '$_patientsPath/$patientId/${entry.key}': entry.value,
      };
      if ([
        'registrationNumber',
        'photoRef',
        'attendants',
      ].any(updates.containsKey)) {
        final patient = await _safeRtdb.get('$_patientsPath/$patientId');
        if (patient is Map) {
          final merged = {...patient, ...updates};
          final rawStays = await _safeRtdb.getByChildValue(
            'stays',
            child: 'patientId',
            value: patientId,
          );
          final stays = ServiceLocator().roomService.parseStaysFromData(
            rawStays,
          );
          final rawAttendants = merged['attendants'];
          for (final stay in stays.where((stay) => stay.isActive)) {
            rootUpdates['stays/${stay.id}/patientSnapshot'] = {
              for (final key in [
                'registrationNumber',
                'photoRef',
                'admissionDate',
              ])
                key: merged[key],
              if (rawAttendants is List)
                'attendants': [
                  for (final attendant in rawAttendants)
                    if (attendant is Map)
                      (Map<String, dynamic>.from(attendant)
                        ..remove('photoDataUrl')),
                ],
            };
          }
        }
      }
      await _safeRtdb.patch('', rootUpdates);
    } catch (e) {
      if (e is StateError || e is ArgumentError) rethrow;
      throw Exception('Failed to update patient: $e');
    }
  }

  /// Compatibility for older callers. Dates and discharge readiness must never
  /// create attendance or reconcile existing historical marks implicitly.
  Future<void> syncAutomaticPatientAttendance({
    required String patientId,
    required String patientName,
    required DateTime start,
    required DateTime end,
    required String cycleId,
    DateTime? previousStart,
    DateTime? previousEnd,
    bool skipRead = false,
  }) async {}

  Future<void> clearAutomaticPatientAttendance({
    required String patientId,
    required String cycleId,
    DateTime? previousStart,
    DateTime? previousEnd,
  }) async {}

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

  Future<Map<String, dynamic>> getDischargeReadiness(
    String patientId, {
    PatientModel? patientOverride,
    DateTime? checkoutAt,
  }) async {
    if (isPostgres) {
      final actualCheckout = checkoutAt ?? DateTime.now();
      // Readiness is a hypothetical settlement, never an admission edit.
      // In particular, do not persist a stale profile's planned exit override.
      final snapshot = await _backendApi!.financialSnapshot(
        patientId,
        checkoutAt: actualCheckout,
      );
      final patient = PatientModel.fromMap(
        patientId,
        Map<String, dynamic>.from(snapshot['patient'] as Map),
      );
      final balance =
          patient.admissionBalances[StayBilling.currentCycle(patient)];
      final summary = balance is Map ? balance : const <String, dynamic>{};
      final pendingRecords = summary['pendingAttendance'] is List
          ? summary['pendingAttendance'] as List
          : const [];
      final missingPatient = pendingRecords
          .where((row) => row is Map && row['kind'] == 'attendance')
          .length;
      final missingAttendants = pendingRecords
          .where((row) => row is Map && row['kind'] == 'attendant_attendance')
          .length;
      final pending =
          (summary['due'] as num?)?.toDouble() ?? patient.currentDueAmount ?? 0;
      final refundDue =
          (summary['refundDue'] as num?)?.toDouble() ?? patient.refundDueAmount;
      final reasons = <String>[
        if (summary['reconciliationRequired'] == true)
          'Reconcile receipt allocations, admission identities and invoice evidence before discharge or refund.',
      ];
      return {
        'total': summary['total'] ?? patient.advanceBilledAmount,
        'paid': summary['netPaid'] ?? patient.totalPaidAmount ?? 0,
        'pending': pending,
        'refundDue': summary['reconciliationRequired'] == true ? 0.0 : refundDue,
        'unverifiedRefundDue': summary['reconciliationRequired'] == true ? refundDue : null,
        'plannedExitDate': patient.exitDate?.millisecondsSinceEpoch,
        'checkoutAt': actualCheckout.millisecondsSinceEpoch,
        'checkoutAdjustment': summary['checkoutAdjustment'],
        'missingPatientDays': missingPatient,
        'missingAttendantMarks': missingAttendants,
        'ready': reasons.isEmpty,
        'reasons': reasons,
      };
    }
    await _persistOverrideExitDate(patientId, patientOverride);
    await _resolvedPaymentService.recalculatePatientAttendanceAndBilling(
      patientId,
    );
    final snapshot = isPostgres
        ? await _backendApi!.financialSnapshot(patientId)
        : null;
    final patient = snapshot != null
        ? PatientModel.fromMap(
            patientId,
            Map<String, dynamic>.from(snapshot['patient'] as Map),
          )
        : await getPatient(patientId);
    if (patient == null) throw StateError('Patient not found');
    final stays = isPostgres
        ? await _resolvedPaymentService.loadStays(patientId)
        : await _resolvedRoomService.getStaysByPatientStream(patientId).first;
    final cycleId = StayBilling.currentCycle(patient);
    final cycleSegments = stays
        .where((stay) => StayBilling.cycleFor(stay, patient) == cycleId)
        .toList();
    final plannedExit = _effectivePlannedExitDate(patient, cycleSegments);
    final requiredThrough = (checkoutAt ?? plannedExit) == null
        ? null
        : _lastRequiredAttendanceDay(exit: checkoutAt ?? plannedExit!);
    final start = _attendanceStartDay(
      patient,
      cycleSegments,
      through: requiredThrough,
    );
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

    // Discharge needs an explicit planned exit boundary. Do not use today as
    // an implicit exit date and then ask staff to mark attendance beyond the
    // agreed stay period.
    final needsPlannedExit = plannedExit == null && checkoutAt == null;

    var missingPatientDays = 0;
    var missingAttendantMarks = 0;
    DateTime? end;
    if (!needsPlannedExit) {
      end = requiredThrough!;
      // Only the admission's attendance window is needed to validate
      // discharge — not the complete attendance history.
      dynamic patientAttendance;
      try {
        patientAttendance = isPostgres
            ? await _backendApi!.getAttendanceRange(
                kind: 'attendance',
                startKey: StayBilling.dateKey(start),
                endKey: StayBilling.dateKey(end),
              )
            : await _safeRtdb.getByKeyRange(
                'attendance/daily',
                startKey: StayBilling.dateKey(start),
                endKey: StayBilling.dateKey(end),
              );
      } catch (_) {
        patientAttendance = null;
      }
      for (
        var date = start;
        !date.isAfter(end);
        date = DateTime(date.year, date.month, date.day + 1)
      ) {
        final dateKey = StayBilling.dateKey(date);
        final patientRecord =
            patientAttendance is Map && patientAttendance[dateKey] is Map
            ? patientAttendance[dateKey][patientId]
            : null;
        if (patientRecord is! Map ||
            !{'Present', 'Absent'}.contains(patientRecord['status'])) {
          missingPatientDays++;
        }
      }
      final attendants = await _safeRtdb.getByKeyRange(
        'attendant_attendance/daily',
        startKey: StayBilling.dateKey(start),
        endKey: StayBilling.dateKey(end),
      );
      for (
        var date = start;
        !date.isAfter(end);
        date = DateTime(date.year, date.month, date.day + 1)
      ) {
        final daily = attendants is Map
            ? attendants[StayBilling.dateKey(date)]
            : null;
        final marks = daily is Map && daily[patientId] is Map
            ? daily[patientId] as Map
            : const {};
        for (final attendant in patient.attendants ?? <AttendantModel>[]) {
          final unique =
              patient.attendants!
                  .where((a) => a.name == attendant.name)
                  .length ==
              1;
          final record =
              marks[attendant.id] ??
              (unique
                  ? marks[attendant.name.replaceAll(RegExp(r'[.#$\[\]/]'), '_')]
                  : null);
          if (record is! Map ||
              !const {'Present', 'Absent'}.contains(record['status'])) {
            missingAttendantMarks++;
          }
        }
      }
    }
    final reasons = <String>[
      if (needsPlannedExit)
        'Set the planned exit date before discharging this patient.',
    ];
    return {
      'total': total,
      'paid': paid,
      'pending': pending,
      'refundDue': refundDue,
      'plannedExitDate': plannedExit?.millisecondsSinceEpoch,
      'missingPatientDays': missingPatientDays,
      'missingAttendantMarks': missingAttendantMarks,
      'ready': reasons.isEmpty,
      'reasons': reasons,
    };
  }





  Future<void> _persistOverrideExitDate(
    String patientId,
    PatientModel? patientOverride,
  ) async {
    final visibleExit = patientOverride?.exitDate;
    if (visibleExit == null) return;

    if (isPostgres) {
      await updatePatient(patientId, {
        'exitDate': visibleExit.millisecondsSinceEpoch,
      });
      return;
    }

    final rawPatient = await _safeRtdb.get('$_patientsPath/$patientId');
    final rawExit = rawPatient is Map ? rawPatient['exitDate'] : null;
    final savedExit = rawExit == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            rawExit is num
                ? rawExit.toInt()
                : int.tryParse(rawExit.toString()) ?? 0,
          );
    if (savedExit?.millisecondsSinceEpoch ==
        visibleExit.millisecondsSinceEpoch) {
      return;
    }

    await _safeRtdb.patch('', {
      '$_patientsPath/$patientId/exitDate': visibleExit.millisecondsSinceEpoch,
      '$_patientsPath/$patientId/updatedAt':
          DateTime.now().millisecondsSinceEpoch,
    });
  }

  DateTime _lastRequiredAttendanceDay({required DateTime exit}) {
    if (isPostgres) return StayBilling.day(exit);
    var end = StayBilling.day(exit);
    if (exit.hour > 9 || (exit.hour == 9 && exit.minute > 0)) {
      end = end.add(const Duration(days: 1));
    }
    return end.subtract(const Duration(days: 1));
  }

  DateTime _attendanceStartDay(
    PatientModel patient,
    List<StayModel> cycleSegments, {
    DateTime? through,
  }) {
    final candidates = <DateTime>[
      patient.admissionDate,
      if (patient.registrationDate != null) patient.registrationDate!,
      for (final segment in cycleSegments) segment.admissionDate,
    ].map(StayBilling.day).toList();

    if (through != null) {
      final usable = candidates
          .where((date) => !date.isAfter(through))
          .toList();
      if (usable.isNotEmpty) {
        usable.sort();
        return usable.last;
      }
      return StayBilling.day(through);
    }

    candidates.sort();
    return candidates.last;
  }

  DateTime? _effectivePlannedExitDate(
    PatientModel patient,
    List<StayModel> cycleSegments,
  ) {
    final recordedExit = patient.exitDate;
    if (recordedExit == null) return null;

    final activeExpectedDates =
        cycleSegments
            .where((stay) => stay.isActive)
            .map((stay) => stay.expectedDischargeDate)
            .where((date) => date.millisecondsSinceEpoch > 0)
            .toList()
          ..sort();
    if (activeExpectedDates.isEmpty) return recordedExit;

    final currentStayExit = activeExpectedDates.first;
    return currentStayExit.isBefore(recordedExit)
        ? currentStayExit
        : recordedExit;
  }

  /// Discharges a patient: sets status to 'discharged' and clears room.
  /// Also releases the bed by completing the active stay.
  Future<void> dischargePatient(
    String patientId, {
    PatientModel? patientOverride,
    DateTime? checkoutAt,
  }) async {
    try {
      if (isPostgres) {
        await _persistOverrideExitDate(patientId, patientOverride);
        await _backendApi!.dischargePatient(
          patientId,
          checkoutAt: checkoutAt ?? DateTime.now(),
        );
        return;
      }
      final readiness = await getDischargeReadiness(
        patientId,
        patientOverride: patientOverride,
        checkoutAt: checkoutAt ?? DateTime.now(),
      );
      if (readiness['ready'] != true) {
        throw StateError((readiness['reasons'] as List).join(' '));
      }
      // Get patient to find their room/bed
      final patient = patientOverride ?? await getPatient(patientId);
      if (patient == null) throw Exception('Patient not found');

      final actualDischargeDate = checkoutAt ?? DateTime.now();
      final billingAdmissionDate =
          patient.registrationDate ?? patient.admissionDate;

      final roomService = _resolvedRoomService;
      // Lifecycle status is the primary action and must not depend on room or
      // legacy stay cleanup succeeding.
      await updatePatient(patientId, {
        'status': 'discharged',
        'dischargeDate': actualDischargeDate.millisecondsSinceEpoch,
      });

      // Release all active placements as best-effort cleanup.
      try {
        final stays = await roomService
            .getStaysByPatientStream(patientId)
            .first;
        final activeStays = stays.where((s) => s.status == 'active').toList();
        for (final activeStay in activeStays) {
          try {
            await roomService.completeStay(
              activeStay.id,
              completedAt: actualDischargeDate,
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
        await _resolvedPaymentService.recalculatePatientAttendanceAndBilling(
          patientId,
        );
      } catch (_) {
        // Discharge is already complete. Billing reconciliation can be
        // retried later and must not make the action appear to have failed.
      }

      if (!isPostgres) {
        // Keep lifecycle status authoritative. Billing/payment reconciliation
        // must not leave a discharged patient active or in the legacy Paid
        // lifecycle state.
        await updatePatient(patientId, {
          'status': 'discharged',
          'dischargeDate': actualDischargeDate.millisecondsSinceEpoch,
        });
      }
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
      if (isPostgres) {
        await _backendApi!.deletePatient(patientId);
        return;
      }
      final rawPatient = await _safeRtdb.get('$_patientsPath/$patientId');
      final patient = rawPatient is Map
          ? PatientModel.fromMap(patientId, rawPatient)
          : null;
      final stays = await ServiceLocator().paymentService.loadStays(patientId);
      await _purgePatientArtifacts(
        patientId,
        stays,
        attendanceStart: patient?.registrationDate ?? patient?.admissionDate,
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
    if (isPostgres) return 0;
    final rawPatients = await _safeRtdb.get(_patientsPath);
    final patientIds = rawPatients is Map
        ? rawPatients.keys.map((key) => key.toString()).toSet()
        : <String>{};
    final rawActive = await _safeRtdb.getByChildValue(
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
    for (final roomId
        in stays
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
            (stay) => stay.roomId == roomId && stay.isActive && room.isPrivate,
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
        'rooms/$roomId/version': room.version + 1,
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
        _safeRtdb.getByKeyRange(
          'attendance/daily',
          startKey: startKey,
          endKey: endKey,
        ),
        _safeRtdb.getByKeyRange(
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
      dynamic records;
      try {
        records = await _safeRtdb.getByChildValue(
          path,
          child: 'patientId',
          value: patientId,
        );
      } catch (_) {
        // Some deployed databases may not yet have the payment index even
        // though the current rules define it. Fall back to one full read so a
        // patient can still be deleted, then filter locally to preserve the
        // exact cleanup scope.
        final allRecords = await _safeRtdb.get(path);
        records = allRecords is Map
            ? {
                for (final entry in allRecords.entries)
                  if (entry.value is Map &&
                      entry.value['patientId']?.toString() == patientId)
                    entry.key: entry.value,
              }
            : null;
      }
      if (records is Map) {
        for (final id in records.keys) {
          cleanup['$path/$id'] = null;
        }
      }
    }
    await _safeRtdb.patch('', cleanup);
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
      final data = isPostgres
          ? await _backendApi!.get(_patientsPath)
          : await _safeRtdb.get(_patientsPath);

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
    final sourceStream = isPostgres
        ? _backendApi!.stream(_patientsPath)
        : _safeRtdb.stream(_patientsPath);

    return sourceStream.map((data) {
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
