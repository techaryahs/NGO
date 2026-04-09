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
        // Sort by admission date descending (newest first)
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
      return patients.where((p) => p.status == status).toList();
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
          .where((p) => p.roomId == roomId && p.status == 'active')
          .toList();
    });
  }

  /// Stream of active patients on a specific [floor].
  Stream<List<PatientModel>> getPatientsByFloor(int floor) {
    return getPatientsStream().map((patients) {
      return patients
          .where((p) => p.floor == floor && p.status == 'active')
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
        return PatientModel.fromMap(
          patientId,
          Map<String, dynamic>.from(data),
        );
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch patient: $e');
    }
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
    String? notes,
    required String createdBy,
    // New fields
    String? registrationNumber,
    DateTime? registrationDate,
    String? panCardNumber,
    String? aadhaarCardNumber,
    String? receiptNumber,
    String? modeOfPayment,
    String? utiNumber,
  }) async {
    try {
      final now = DateTime.now();
      final age = PatientModel.calculateAge(dateOfBirth);

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
        status: 'active',
        roomId: roomId,
        roomNumber: roomNumber,
        floor: floor,
        notes: notes,
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
      );

      // Push to generate unique key
      final patientId = await _rtdb.push(_patientsPath, patient.toMap());
      
      // Update the ID field in the database
      await _rtdb.patch('$_patientsPath/$patientId', {'id': patientId});
      
      return patientId;
    } catch (e) {
      throw Exception('Failed to add patient: $e');
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
      String patientId, Map<String, dynamic> updates) async {
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
      String patientId, String roomId, String roomNumber, int floor) async {
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
      
      // Find active stay for this patient
      final roomService = ServiceLocator().roomService;
      final stays = await roomService.getStaysByPatientStream(patientId).first;
      final activeStay = stays.where((s) => s.status == 'active').firstOrNull;
      
      // Complete the stay (this releases the bed)
      if (activeStay != null) {
        await roomService.completeStay(activeStay.id);
      }
      
      // Update patient status
      await updatePatient(patientId, {
        'status': 'discharged',
        'roomId': null,
        'roomNumber': null,
        'floor': null,
      });
    } catch (e) {
      throw Exception('Failed to discharge patient: $e');
    }
  }

  /// Reactivates a discharged patient.
  Future<void> reactivatePatient(String patientId) async {
    try {
      await updatePatient(patientId, {
        'status': 'active',
      });
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
  /// Returns a map with keys: `total`, `active`, `discharged`,
  /// `withRoom`, `withoutRoom`.
  Future<Map<String, int>> getPatientStats() async {
    try {
      final data = await _rtdb.get(_patientsPath);

      int total = 0;
      int active = 0;
      int discharged = 0;
      int withRoom = 0;

      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        total = mapData.length;

        mapData.forEach((key, value) {
          if (value is Map) {
            final patientData = Map<String, dynamic>.from(value);
            final status = patientData['status'] ?? 'active';

            if (status == 'active') active++;
            if (status == 'discharged') discharged++;
            if (patientData['roomId'] != null && status == 'active') {
              withRoom++;
            }
          }
        });
      }

      return {
        'total': total,
        'active': active,
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
      int discharged = 0;
      int withRoom = 0;

      if (data != null && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        total = mapData.length;

        mapData.forEach((key, value) {
          if (value is Map) {
            final patientData = Map<String, dynamic>.from(value);
            final status = patientData['status'] ?? 'active';

            if (status == 'active') active++;
            if (status == 'discharged') discharged++;
            if (patientData['roomId'] != null && status == 'active') {
              withRoom++;
            }
          }
        });
      }

      return {
        'total': total,
        'active': active,
        'discharged': discharged,
        'withRoom': withRoom,
        'withoutRoom': active - withRoom,
      };
    });
  }
}
