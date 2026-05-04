import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/service_locator.dart';
import '../../models/patient_model.dart';

class Attendance extends StatefulWidget {
  const Attendance({super.key});
  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {

  // ── Attendance state ─────────────────────────────────────────────────────
  final Map<String, bool> attendanceStatus = {};
  final Map<String, bool> attendantAttendanceStatus = {};

  // ── Weekly / Monthly futures ─────────────────────────────────────────────
  late Future<Map<String, Map<String, String>>> _weeklyData;
  late Future<Map<String, Map<String, String>>> _monthlyData;
  DateTime _selectedMonth = DateTime.now();

  // ── Patient stream + lazy-load state ────────────────────────────────────
  late Stream<List<PatientModel>> _patientsStream;
  List<PatientModel>? _allPatients;
  List<PatientModel> _visiblePatients = [];
  static const int _pageSize = 10;
  bool _isLoadingMore = false;
  late ScrollController _scrollController;

  // ── Animation ────────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _scrollController = ScrollController()..addListener(_onScroll);
    _patientsStream = ServiceLocator().patientService.getPatientsStream();
    _weeklyData = fetchWeeklyAttendance();
    _monthlyData = fetchMonthlyAttendance(_selectedMonth);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMorePatients();
    }
  }

  void _initPatients(List<PatientModel> all) {
    _allPatients = all;
    _visiblePatients = all.take(_pageSize).toList();
  }

  Future<void> _loadMorePatients() async {
    if (_allPatients == null) return;
    if (_visiblePatients.length >= _allPatients!.length) return;
    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 300));
    final next = _allPatients!
        .skip(_visiblePatients.length)
        .take(_pageSize)
        .toList();
    setState(() {
      _visiblePatients.addAll(next);
      _isLoadingMore = false;
    });
  }

  // ── Date helpers ─────────────────────────────────────────────────────────
  List<String> getLast7Days() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      return now.subtract(Duration(days: i)).toIso8601String().split('T')[0];
    }).reversed.toList();
  }

  List<String> getDaysOfMonth(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0);
    return List.generate(last.day, (i) {
      return DateTime(month.year, month.month, i + 1)
          .toIso8601String()
          .split('T')[0];
    });
  }

  String _monthTitle(DateTime m) => '${_monthShort(m.month)} ${m.year}';
  String _monthShort(int m) => const [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ][m - 1];

  // ── Data fetchers ─────────────────────────────────────────────────────────
  Future<Map<String, Map<String, String>>> fetchWeeklyAttendance() async {
    final dates = getLast7Days();
    final patients =
        await ServiceLocator().patientService.getPatientsStream().first;
    final result = <String, Map<String, String>>{
      for (var p in patients) p.fullName: {}
    };
    for (final date in dates) {
      final data = await ServiceLocator().rtdbService.get('attendance/$date');
      if (data != null && data is Map) {
        Map<String, dynamic>.from(data).forEach((_, v) {
          final name = v['patientName'] ?? '';
          final status = v['status'] ?? '';
          if (result.containsKey(name)) result[name]![date] = status;
        });
      }
    }
    return result;
  }

  Future<Map<String, Map<String, String>>> fetchMonthlyAttendance(
      DateTime month) async {
    final dates = getDaysOfMonth(month);
    final patients =
        await ServiceLocator().patientService.getPatientsStream().first;
    final result = <String, Map<String, String>>{
      for (var p in patients) p.fullName: {}
    };
    for (final date in dates) {
      final data = await ServiceLocator().rtdbService.get('attendance/$date');
      if (data != null && data is Map) {
        Map<String, dynamic>.from(data).forEach((_, v) {
          final name = v['patientName'] ?? '';
          final status = v['status'] ?? '';
          if (result.containsKey(name)) result[name]![date] = status;
        });
      }
    }
    return result;
  }

  // ── Mark attendance ───────────────────────────────────────────────────────
  Future<void> markAttendance(
      String patientId, String patientName, bool isPresent) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    try {
      await ServiceLocator().rtdbService.put('attendance/$today/$patientId', {
        'patientId': patientId,
        'patientName': patientName,
        'status': isPresent ? 'Present' : 'Absent',
        'date': today,
        'timestamp': DateTime.now().toIso8601String(),
      });
      setState(() => attendanceStatus[patientId] = isPresent);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: isPresent ? Colors.green : Colors.red,
          content: Text('$patientName marked as ${isPresent ? "Present" : "Absent"}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed: $e'),
        ));
      }
    }
  }

  Future<void> markAttendantAttendance(
      String patientId, String attendantName, bool isPresent) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final safeKey = attendantName.replaceAll(RegExp(r'[.#\$\[\]/]'), '_');
    try {
      await ServiceLocator().rtdbService.put(
          'attendant_attendance/$today/$patientId/$safeKey', {
        'patientId': patientId,
        'attendantName': attendantName,
        'status': isPresent ? 'Present' : 'Absent',
        'date': today,
        'timestamp': DateTime.now().toIso8601String(),
      });
      setState(() =>
          attendantAttendanceStatus['${patientId}_$attendantName'] = isPresent);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: isPresent ? Colors.green : Colors.red,
          content: Text('$attendantName marked as ${isPresent ? "Present" : "Absent"}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed: $e'),
        ));
      }
    }
  }

  // ── Shimmer skeleton ──────────────────────────────────────────────────────
  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8F5E9),
      highlightColor: Colors.white,
      child: ListView.builder(
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFD6EAC8)),
            title: Container(
              height: 12,
              width: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFD6EAC8),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            subtitle: Container(
              margin: const EdgeInsets.only(top: 8),
              height: 10,
              width: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFD6EAC8),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                  2,
                  (_) => Container(
                        margin: const EdgeInsets.only(left: 6),
                        width: 68,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6EAC8),
                          borderRadius: BorderRadius.circular(25),
                        ),
                      )),
            ),
          ),
        ),
      ),
    );
  }

  // ── Patient card ──────────────────────────────────────────────────────────
  Widget _buildPatientCard(PatientModel patient, int index) {
    final patientName = patient.fullName;
    final status = attendanceStatus[patient.id];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 250 + (index % _pageSize) * 50),
      curve: Curves.easeOut,
      builder: (context, val, child) =>
          Opacity(opacity: val, child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFC0DD97)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE6F4EA),
                child: Text(
                  patientName.isNotEmpty ? patientName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(patient.contactNumber ?? 'No contact',
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _attendBtn('Present', const Color(0xFF4CAF50),
                  () => markAttendance(patient.id, patientName, true)),
              const SizedBox(width: 6),
              _attendBtn('Absent', const Color(0xFFE53935),
                  () => markAttendance(patient.id, patientName, false)),
            ],
          ),
          children: [
            // Patient status chip
            if (status != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  Icon(status ? Icons.check_circle : Icons.cancel,
                      color: status ? Colors.green : Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Text('Patient: ${status ? "Present" : "Absent"}',
                      style: TextStyle(
                          color: status ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ]),
              ),

            // Attendants section header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('Attendants',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E4A1F))),
            ),

            // Attendants list
            Builder(builder: (ctx) {
              final attendants = patient.attendants ?? [];
              if (attendants.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('No attendants found',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                );
              }
              return Column(
                children: attendants.map<Widget>((a) {
                  final name = a.name;
                  final key = '${patient.id}_$name';
                  final aStatus = attendantAttendanceStatus[key];
                  return Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FBF3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD0E8B8)),
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFD8EEC4),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((a.relation ?? '').isNotEmpty)
                            Text('Relation: ${a.relation}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          if (aStatus != null)
                            Text(
                              aStatus ? '✓ Present' : '✗ Absent',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: aStatus ? Colors.green : Colors.red),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _smallBtn('P', const Color(0xFF4CAF50),
                              () => markAttendantAttendance(patient.id, name, true)),
                          const SizedBox(width: 6),
                          _smallBtn('A', const Color(0xFFE53935),
                              () => markAttendantAttendance(patient.id, name, false)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _attendBtn(String label, Color color, VoidCallback onTap) =>
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        onPressed: onTap,
        child: Text(label),
      );

  Widget _smallBtn(String label, Color color, VoidCallback onTap) =>
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12),
        ),
        onPressed: onTap,
        child: Text(label),
      );

  // ── Daily view ────────────────────────────────────────────────────────────
  Widget buildDailyView() {
    return StreamBuilder<List<PatientModel>>(
      stream: _patientsStream,
      builder: (context, snapshot) {
        // Show shimmer while waiting for first data
        if (!snapshot.hasData && _allPatients == null) {
          return _buildShimmerList();
        }

        if (snapshot.hasData) {
          final incoming = snapshot.data!;
          // Init / refresh lazy list only when patient list changes
          if (_allPatients == null ||
              _allPatients!.length != incoming.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _initPatients(incoming));
            });
          }
        }

        final patients = _visiblePatients.isNotEmpty
            ? _visiblePatients
            : (_allPatients ?? []);

        if (patients.isEmpty) {
          return const Center(child: Text('No patients found'));
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: patients.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            // "Load more" shimmer row at the bottom
            if (index == patients.length) {
              return Shimmer.fromColors(
                baseColor: const Color(0xFFE8F5E9),
                highlightColor: Colors.white,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              );
            }
            return _buildPatientCard(patients[index], index);
          },
        );
      },
    );
  }

  // ── Weekly view ───────────────────────────────────────────────────────────
  Widget _legendItem(String label, Color color, String text) => Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4)),
          child: Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 4),
        Text(text),
      ]);

  Widget buildWeeklyView() {
    return FutureBuilder(
      future: _weeklyData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Shimmer.fromColors(
            baseColor: const Color(0xFFE8F5E9),
            highlightColor: Colors.white,
            child: Column(children: [
              Container(height: 40, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
              Expanded(child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)))),
            ]),
          );
        }
        if (snapshot.hasError) return const Center(child: Text('Error loading weekly data'));
        final data = snapshot.data as Map<String, Map<String, String>>;
        if (data.isEmpty) return const Center(child: Text('No weekly data'));

        return FadeTransition(
          opacity: _fadeCtrl,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _legendItem('P', Colors.green, 'Present'),
                const SizedBox(width: 10),
                _legendItem('A', Colors.red, 'Absent'),
                const SizedBox(width: 10),
                _legendItem('-', Colors.grey, 'No Data'),
              ]),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD6E8C8)),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))]),
                child: LayoutBuilder(builder: (ctx, constraints) {
                  return DataTable(
                    columnSpacing: constraints.maxWidth / 14,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columns: [
                      const DataColumn(label: Text('Name')),
                      ...getLast7Days().map((d) => DataColumn(
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('${DateTime.parse(d).day} ${_monthShort(DateTime.parse(d).month)}'),
                            ),
                          )),
                    ],
                    rows: data.entries.toList().asMap().entries.map((e) {
                      final i = e.key;
                      final name = e.value.key;
                      final map = e.value.value;
                      return DataRow(
                        color: WidgetStateProperty.all(
                            i % 2 == 0 ? Colors.white : const Color(0xFFF7FBF3)),
                        cells: [
                          DataCell(Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E4A1F)))),
                          ...getLast7Days().map((date) {
                            final s = map[date];
                            if (s == null) return const DataCell(Text('-'));
                            return DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: s == 'Present'
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(s == 'Present' ? 'P' : 'A',
                                  style: TextStyle(
                                      color: s == 'Present' ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ));
                          }),
                        ],
                      );
                    }).toList(),
                  );
                }),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ── Monthly view ──────────────────────────────────────────────────────────
  Widget buildMonthlyView() {
    final dates = getDaysOfMonth(_selectedMonth);
    return FutureBuilder(
      future: _monthlyData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Shimmer.fromColors(
            baseColor: const Color(0xFFE8F5E9),
            highlightColor: Colors.white,
            child: Column(children: [
              Container(height: 50, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
              Expanded(child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)))),
            ]),
          );
        }
        if (snapshot.hasError) return const Center(child: Text('Error loading monthly data'));
        final data = snapshot.data as Map<String, Map<String, String>>;

        return FadeTransition(
          opacity: _fadeCtrl,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Month selector
            Row(children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                  _monthlyData = fetchMonthlyAttendance(_selectedMonth);
                  _fadeCtrl.forward(from: 0);
                }),
              ),
              Text(_monthTitle(_selectedMonth),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() {
                  _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                  _monthlyData = fetchMonthlyAttendance(_selectedMonth);
                  _fadeCtrl.forward(from: 0);
                }),
              ),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
                  border: TableBorder.all(color: Colors.grey.shade300),
                  columns: [
                    const DataColumn(label: Text('Name')),
                    ...dates.map((d) {
                      final dt = DateTime.parse(d);
                      return DataColumn(label: Text('${dt.day} ${_monthShort(dt.month)}'));
                    }),
                  ],
                  rows: data.entries.map((entry) {
                    return DataRow(cells: [
                      DataCell(Text(entry.key)),
                      ...dates.map((d) {
                        final s = entry.value[d];
                        if (s == null) return const DataCell(Text('-'));
                        return DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: s == 'Present'
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(s == 'Present' ? 'P' : 'A',
                              style: TextStyle(
                                  color: s == 'Present' ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold)),
                        ));
                      }),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: DefaultTabController(
        length: 3,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Patient Attendance',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Mark daily attendance for all patients',
                  style: TextStyle(fontSize: 14, color: Color(0xFF639922))),
              const SizedBox(height: 20),
              const TabBar(tabs: [
                Tab(text: 'Daily'),
                Tab(text: 'Weekly'),
                Tab(text: 'Monthly'),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(children: [
                  buildDailyView(),
                  buildWeeklyView(),
                  buildMonthlyView(),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}