import '../../config/app_config.dart';
import '../../models/patient_model.dart';
import '../../models/stay_model.dart';
import '../../services/backend_api_service.dart';
import '../../services/firebase_rtdb_rest_service.dart';
import '../../services/service_locator.dart';
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
  final String? registrationNumber;
  final String? attendantName;
  final String? attendantId;
  final bool allowLegacyNameFallback;
  final bool identityUnresolved;
  final String room;
  final List<AttendanceInterval> intervals;
  const AttendanceRow({
    required this.patientId,
    required this.patientName,
    this.registrationNumber,
    this.attendantName,
    this.attendantId,
    this.allowLegacyNameFallback = true,
    this.identityUnresolved = false,
    required this.room,
    required this.intervals,
  });
  bool get isAttendant => attendantName != null;
  String get name => attendantName ?? patientName;
  String get displayName {
    if (isAttendant) {
      return '$attendantName${identityUnresolved ? ' (identity Pending)' : ''}';
    }
    if (registrationNumber != null && registrationNumber!.trim().isNotEmpty) {
      return '$patientName (#$registrationNumber)';
    }
    return patientName;
  }

  bool enabled(DateTime date) =>
      !identityUnresolved &&
      intervals.any((interval) => interval.contains(StayBilling.day(date)));
  String path(DateTime date) {
    final key = StayBilling.dateKey(date);
    if (!isAttendant) return 'attendance/daily/$key/$patientId';
    return 'attendant_attendance/daily/$key/$patientId/${safeKey(attendantId ?? attendantName!)}';
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
      ..sort((a, b) {
        final cmp = a.fullName.toLowerCase().compareTo(
          b.fullName.toLowerCase(),
        );
        if (cmp != 0) return cmp;
        final regA = int.tryParse(a.registrationNumber ?? '') ?? 0;
        final regB = int.tryParse(b.registrationNumber ?? '') ?? 0;
        if (regA != 0 && regB != 0) return regA.compareTo(regB);
        return (a.registrationNumber ?? '').compareTo(
          b.registrationNumber ?? '',
        );
      });
    for (final patient in sorted) {
      final intervals = <AttendanceInterval>[];
      final attendantIntervals = <String, List<AttendanceInterval>>{};
      final attendantNames = <String, String>{};
      Map<String, String> rosterMap(Iterable<Map> raw) {
        final people = raw.toList();
        return {
          for (var index = 0; index < people.length; index++)
            if (people[index]['name'] != null)
              (people[index]['id'] ??
                      (people
                                  .where(
                                    (p) => p['name'] == people[index]['name'],
                                  )
                                  .length >
                              1
                          ? 'unresolved_${index}_${people[index]['name']}'
                          : people[index]['name']))
                  .toString(): people[index]['name']
                  .toString(),
        };
      }

      final rooms = <String>{};
      void include(
        DateTime start,
        DateTime end,
        Map<String, String> people,
        String room,
      ) {
        final period = PricingHelper.attendancePeriod(start, end);
        final interval = AttendanceInterval(period.start, period.end);
        if (interval.end.isBefore(first) || interval.start.isAfter(last)) {
          return;
        }
        intervals.add(interval);
        if (room.isNotEmpty) rooms.add(room);
        for (final person in people.entries.where(
          (person) => person.value.trim().isNotEmpty,
        )) {
          attendantNames[person.key] = person.value;
          attendantIntervals.putIfAbsent(person.key, () => []).add(interval);
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
        final names = rosterMap(
          snapshot is List
              ? snapshot.whereType<Map>()
              : current
              ? (patient.attendants ?? <AttendantModel>[]).map((a) => a.toMap())
              : stay.attendantLabels.map(
                  (name) => {
                    'name': name.replaceFirst(RegExp(r' \(.*\)$'), ''),
                  },
                ),
        );
        include(stay.admissionDate, end, names, stay.roomNumber);
      }
      if (patientStays.isEmpty) {
        include(
          patient.registrationDate ?? patient.admissionDate,
          patient.status.toLowerCase() == 'discharged'
              ? patient.dischargeDate ?? patient.exitDate ?? today
              : patient.exitDate ?? today,
          rosterMap(
            (patient.attendants ?? <AttendantModel>[]).map((a) => a.toMap()),
          ),
          patient.roomNumber ?? patient.lobby ?? '',
        );
      }
      if (intervals.isEmpty) continue;
      // Historical attendance may contain an attendant no longer in today's roster.
      for (final entry in records.entries) {
        final parts = entry.key.split('/');
        if (parts.length < 5 ||
            parts.first != 'attendant_attendance' ||
            parts[3] != patient.id) {
          continue;
        }
        final date = DateTime.tryParse(parts[2]);
        final name = entry.value['attendantName']?.toString();
        final identity = entry.value['attendantId']?.toString() ?? parts[4];
        if (date != null &&
            name != null &&
            !attendantIntervals.containsKey(identity) &&
            !attendantNames.containsValue(name) &&
            intervals.any((interval) => interval.contains(date))) {
          attendantIntervals[identity] = intervals;
          attendantNames[identity] = name;
        }
      }
      final room = rooms.join(', ');
      result.add(
        AttendanceRow(
          patientId: patient.id,
          patientName: patient.fullName,
          registrationNumber: patient.registrationNumber,
          room: room,
          intervals: intervals,
        ),
      );
      for (final entry in attendantIntervals.entries) {
        result.add(
          AttendanceRow(
            patientId: patient.id,
            patientName: patient.fullName,
            registrationNumber: patient.registrationNumber,
            attendantName: attendantNames[entry.key] ?? entry.key,
            attendantId: entry.key == attendantNames[entry.key]
                ? null
                : entry.key,
            identityUnresolved: entry.key.startsWith('unresolved_'),
            allowLegacyNameFallback:
                attendantNames.values
                    .where((name) => name == attendantNames[entry.key])
                    .length ==
                1,
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
  Map<String, dynamic>? _record(AttendanceRow row, DateTime date) =>
      dirty[row.path(date)] ??
      data.records[row.path(date)] ??
      (row.isAttendant && row.attendantId != null && row.allowLegacyNameFallback
          ? data.records['attendant_attendance/daily/${StayBilling.dateKey(date)}/${row.patientId}/${AttendanceRow.safeKey(row.attendantName!)}']
          : null);
  String status(AttendanceRow row, DateTime date) =>
      _record(row, date)?['status']?.toString() ?? 'Unmarked';
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
      ...?_record(row, date),
      'patientId': row.patientId,
      'patientName': row.patientName,
      if (row.isAttendant) 'attendantName': row.attendantName,
      if (row.attendantId != null) 'attendantId': row.attendantId,
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
  Future<Set<String>> save([
    FirebaseRTDBRestService? db,
    BackendApiService? backendApi,
  ]) async {
    if (saving || dirty.isEmpty) return {};
    saving = true;
    final submitted = Map<String, Map<String, dynamic>>.from(dirty);
    final affected = affectedPatientIds;
    final currentPatch = patch;
    final usePostgres =
        backendApi != null || (db == null && AppConfig.usePostgresBackend);
    try {
      if (usePostgres) {
        final api = backendApi ?? ServiceLocator().backendApiService;
        final groups = <String, Map<String, dynamic>>{};
        currentPatch.forEach((path, val) {
          if (val is Map) {
            final parts = path.split('/');
            final kind = parts[0];
            final date = parts[2];
            final patientId = parts[3];
            final groupKey = '$kind|$date';
            final recordsForDate = groups.putIfAbsent(
              groupKey,
              () => <String, dynamic>{},
            );
            if (kind == 'attendant_attendance' && parts.length > 4) {
              final attKey = parts[4];
              final attMap =
                  recordsForDate.putIfAbsent(
                        patientId,
                        () => <String, dynamic>{},
                      )
                      as Map<String, dynamic>;
              attMap[attKey] = Map<String, dynamic>.from(val);
            } else {
              recordsForDate[patientId] = Map<String, dynamic>.from(val);
            }
          }
        });
        for (final entry in groups.entries) {
          final parts = entry.key.split('|');
          await api.postAttendanceBulk(
            kind: parts[0],
            date: parts[1],
            records: entry.value,
          );
        }
      } else {
        final rtdb = db ?? ServiceLocator().rtdbService;
        // REST PATCH also updates partitioned SQLite and targeted shared streams.
        await rtdb.patch('', currentPatch);
      }
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
  final FirebaseRTDBRestService? _db;
  final BackendApiService? _backendApi;
  AttendanceService([this._db, this._backendApi]);

  /// Project the same stored daily map used by the monthly grid into a profile.
  /// Missing days stay absent from the map and are displayed as Unmarked.
  static Map<String, Map<String, dynamic>> patientRecords(
    dynamic daily,
    String patientId,
  ) => {
    if (daily is Map)
      for (final day in daily.entries)
        if (day.value is Map && day.value[patientId] is Map)
          day.key.toString(): Map<String, dynamic>.from(day.value[patientId]),
  };

  static ({int present, int absent, int total, double percentage}) summary(
    Iterable<Map<String, dynamic>> records,
  ) {
    final marks = records.toList();
    final present = marks.where((r) => r['status'] == 'Present').length;
    final absent = marks.where((r) => r['status'] == 'Absent').length;
    final total = present + absent;
    return (
      present: present,
      absent: absent,
      total: total,
      percentage: total == 0 ? 0 : present * 100 / total,
    );
  }

  bool get isPostgres =>
      _backendApi != null || (_db == null && AppConfig.usePostgresBackend);

  Future<MonthlyAttendanceData> loadMonth(DateTime month) async {
    final first = StayBilling.dateKey(DateTime(month.year, month.month, 1));
    final last = StayBilling.dateKey(DateTime(month.year, month.month + 1, 0));
    final values = isPostgres
        ? await Future.wait<dynamic>([
            (_backendApi ?? ServiceLocator().backendApiService)
                .getAttendanceRange(
                  kind: 'attendance',
                  startKey: first,
                  endKey: last,
                ),
            (_backendApi ?? ServiceLocator().backendApiService)
                .getAttendanceRange(
                  kind: 'attendant_attendance',
                  startKey: first,
                  endKey: last,
                ),
          ])
        : await Future.wait<dynamic>([
            (_db ?? ServiceLocator().rtdbService).getByKeyRange(
              'attendance/daily',
              startKey: first,
              endKey: last,
            ),
            (_db ?? ServiceLocator().rtdbService).getByKeyRange(
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
