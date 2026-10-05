import '../../models/patient_model.dart';
import '../../models/stay_model.dart';
import '../../services/firebase_rtdb_rest_service.dart';
import '../../utils/pricing_helper.dart';
import '../../utils/stay_billing.dart';

class AttendanceInterval {
  final DateTime start;
  final DateTime end;
  const AttendanceInterval(this.start, this.end);
  bool contains(DateTime date) => !date.isBefore(start) && !date.isAfter(end);
}

class AttendanceRow {
  final String patientId;
  final String patientName;
  final String? attendantName;
  final String room;
  final List<AttendanceInterval> intervals;
  const AttendanceRow({
    required this.patientId,
    required this.patientName,
    this.attendantName,
    required this.room,
    required this.intervals,
  });
  bool get isAttendant => attendantName != null;
  String get name => attendantName ?? patientName;
  bool enabled(DateTime date) =>
      intervals.any((interval) => interval.contains(StayBilling.day(date)));
  String path(DateTime date) {
    final key = StayBilling.dateKey(date);
    if (!isAttendant) return 'attendance/daily/$key/$patientId';
    return 'attendant_attendance/daily/$key/$patientId/${safeKey(attendantName!)}';
  }

  static String safeKey(String name) =>
      name.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
}

class MonthlyAttendanceData {
  final DateTime month;
  final Map<String, Map<String, dynamic>> records;
  MonthlyAttendanceData(this.month, this.records);
  List<DateTime> get dates => List.generate(
    DateTime(month.year, month.month + 1, 0).day,
    (index) => DateTime(month.year, month.month, index + 1),
  );

  List<AttendanceRow> rows(
    List<PatientModel> patients,
    List<StayModel> stays, {
    DateTime? now,
  }) {
    final first = dates.first;
    final last = dates.last;
    final today = StayBilling.day(now ?? DateTime.now());
    final result = <AttendanceRow>[];
    final byPatient = <String, List<StayModel>>{};
    for (final stay in stays.where((stay) => stay.status != 'cancelled')) {
      byPatient.putIfAbsent(stay.patientId, () => []).add(stay);
    }
    final sorted = [...patients]
      ..sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
    for (final patient in sorted) {
      final intervals = <AttendanceInterval>[];
      final attendantIntervals = <String, List<AttendanceInterval>>{};
      final rooms = <String>{};
      void include(
        DateTime start,
        DateTime end,
        Iterable<String> names,
        String room,
      ) {
        final period = PricingHelper.attendancePeriod(start, end);
        final interval = AttendanceInterval(period.start, period.end);
        if (interval.end.isBefore(first) || interval.start.isAfter(last)) {
          return;
        }
        intervals.add(interval);
        if (room.isNotEmpty) rooms.add(room);
        for (final name in names.where((name) => name.trim().isNotEmpty)) {
          attendantIntervals.putIfAbsent(name, () => []).add(interval);
        }
      }

      final patientStays = byPatient[patient.id] ?? const <StayModel>[];
      for (final stay in patientStays) {
        final current =
            StayBilling.cycleFor(stay, patient) ==
            StayBilling.currentCycle(patient);
        final ongoing =
            stay.isActive &&
            current &&
            patient.status.toLowerCase() != 'discharged';
        final end = ongoing
            ? patient.exitDate ?? today
            : stay.completedAt ??
                  (current ? patient.dischargeDate : null) ??
                  stay.updatedAt;
        final snapshot = stay.patientSnapshot['attendants'];
        final names = <String>{
          if (snapshot is List)
            for (final item in snapshot)
              if (item is Map && item['name'] != null) item['name'].toString(),
          if (current && snapshot is! List)
            ...?patient.attendants?.map((a) => a.name),
          if (snapshot is! List && !current)
            ...stay.attendantLabels.map(
              (name) => name.replaceFirst(RegExp(r' \(.*\)$'), ''),
            ),
        };
        include(stay.admissionDate, end, names, stay.roomNumber);
      }
      if (patientStays.isEmpty) {
        include(
          patient.registrationDate ?? patient.admissionDate,
          patient.status.toLowerCase() == 'discharged'
              ? patient.dischargeDate ?? patient.exitDate ?? today
              : patient.exitDate ?? today,
          patient.attendants?.map((a) => a.name) ?? const <String>[],
          patient.roomNumber ?? patient.lobby ?? '',
        );
      }
      if (intervals.isEmpty) continue;
      // Historical attendance may contain an attendant no longer in today's roster.
      for (final entry in records.entries) {
        final parts = entry.key.split('/');
        if (parts.first != 'attendant_attendance' || parts[3] != patient.id) {
          continue;
        }
        final date = DateTime.tryParse(parts[2]);
        final name = entry.value['attendantName']?.toString();
        if (date != null &&
            name != null &&
            !attendantIntervals.containsKey(name) &&
            intervals.any((interval) => interval.contains(date))) {
          attendantIntervals[name] = intervals;
        }
      }
      final room = rooms.join(', ');
      result.add(
        AttendanceRow(
          patientId: patient.id,
          patientName: patient.fullName,
          room: room,
          intervals: intervals,
        ),
      );
      for (final entry in attendantIntervals.entries) {
        result.add(
          AttendanceRow(
            patientId: patient.id,
            patientName: patient.fullName,
            attendantName: entry.key,
            room: room,
            intervals: entry.value,
          ),
        );
      }
    }
    return result;
  }
}

/// A screen-local editing buffer. No network request occurs on a cell edit.
class MonthlyAttendanceEditor {
  final MonthlyAttendanceData data;
  final Map<String, Map<String, dynamic>> dirty = {};
  bool saving = false;
  MonthlyAttendanceEditor(this.data);
  String status(AttendanceRow row, DateTime date) =>
      (dirty[row.path(date)] ?? data.records[row.path(date)])?['status']
          ?.toString() ??
      'Unmarked';
  bool isDirty(AttendanceRow row, DateTime date) =>
      dirty.containsKey(row.path(date));
  void edit(AttendanceRow row, DateTime date, String status) {
    if (saving || !row.enabled(date)) return;
    if (!const {'Present', 'Absent', 'Unmarked'}.contains(status)) {
      throw ArgumentError('Invalid attendance status');
    }
    final path = row.path(date);
    if ((data.records[path]?['status'] ?? 'Unmarked') == status) {
      dirty.remove(path);
      return;
    }
    dirty[path] = {
      ...?data.records[path],
      'patientId': row.patientId,
      'patientName': row.patientName,
      if (row.isAttendant) 'attendantName': row.attendantName,
      'date': StayBilling.dateKey(date),
      'status': status,
      'source': 'manual',
    };
  }

  Map<String, dynamic> get patch => {
    for (final entry in dirty.entries)
      entry.key: {
        ...entry.value,
        'timestamp': DateTime.now().toIso8601String(),
      },
  };
  Set<String> get affectedPatientIds =>
      dirty.values.map((record) => record['patientId'] as String).toSet();
  Future<Set<String>> save(FirebaseRTDBRestService db) async {
    if (saving || dirty.isEmpty) return {};
    saving = true;
    final submitted = Map<String, Map<String, dynamic>>.from(dirty);
    final affected = affectedPatientIds;
    try {
      // REST PATCH also updates partitioned SQLite and targeted shared streams.
      await db.patch('', patch);
      data.records.addAll(submitted);
      for (final entry in submitted.entries) {
        if (identical(dirty[entry.key], entry.value)) dirty.remove(entry.key);
      }
      return affected;
    } finally {
      saving = false;
    }
  }
}

class AttendanceService {
  final FirebaseRTDBRestService db;
  AttendanceService(this.db);
  Future<MonthlyAttendanceData> loadMonth(DateTime month) async {
    final first = StayBilling.dateKey(DateTime(month.year, month.month, 1));
    final last = StayBilling.dateKey(DateTime(month.year, month.month + 1, 0));
    final values = await Future.wait<dynamic>([
      db.getByKeyRange('attendance/daily', startKey: first, endKey: last),
      db.getByKeyRange(
        'attendant_attendance/daily',
        startKey: first,
        endKey: last,
      ),
    ]);
    final records = <String, Map<String, dynamic>>{};
    for (var index = 0; index < values.length; index++) {
      final daily = values[index];
      if (daily is! Map) continue;
      for (final date in daily.entries) {
        if (date.value is! Map) continue;
        for (final patient in (date.value as Map).entries) {
          if (patient.value is! Map) continue;
          if (index == 0) {
            records['attendance/daily/${date.key}/${patient.key}'] =
                Map<String, dynamic>.from(patient.value);
          } else {
            for (final attendant in (patient.value as Map).entries) {
              if (attendant.value is Map) {
                records['attendant_attendance/daily/${date.key}/${patient.key}/${attendant.key}'] =
                    Map<String, dynamic>.from(attendant.value);
              }
            }
          }
        }
      }
    }
    return MonthlyAttendanceData(month, records);
  }
}
