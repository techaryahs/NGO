import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../../services/service_locator.dart';
import '../../models/patient_model.dart';
import '../../utils/bed_helper.dart';
import 'dart:convert';

class FlattenedAttendant {
  final PatientModel patient;
  final AttendantModel attendant;
  FlattenedAttendant(this.patient, this.attendant);
}

class Attendance extends StatefulWidget {
  const Attendance({super.key});
  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────────────────
  String _attendanceType = 'patient'; // 'patient' or 'attendant'
  int _selectedTabIndex = 0; // 0: Daily, 1: Weekly, 2: Monthly

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final Map<String, bool> attendanceStatus = {};
  final Map<String, bool> attendantAttendanceStatus = {};

  late Future<Map<String, Map<String, String>>> _weeklyData;
  late Future<Map<String, Map<String, String>>> _monthlyData;
  DateTime _selectedMonth = DateTime.now();

  late Stream<List<PatientModel>> _patientsStream;
  List<PatientModel>? _allPatients;

  StreamSubscription? _patientSub;
  StreamSubscription? _attendantSub;

  // Pagination
  static const int _pageSize = 15;
  int _currentPatientLimit = _pageSize;
  int _currentAttendantLimit = _pageSize;
  bool _isLoadingMore = false;
  late ScrollController _scrollController;

  // Animations
  late AnimationController _fadeCtrl;
  late TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_selectedTabIndex != _tabController.index) {
        setState(() {
          _selectedTabIndex = _tabController.index;
          _fadeCtrl.forward(from: 0);
        });
      }
    });

    _scrollController = ScrollController()..addListener(_onScroll);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    _patientsStream = ServiceLocator().patientService.getPatientsStream();
    _refreshFutures();
    _initRealtimeStreams();
  }

  void _initRealtimeStreams() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    _patientSub = ServiceLocator().rtdbService
        .stream('attendance/daily/$today')
        .listen((data) {
          if (data != null && data is Map) {
            final newStatus = <String, bool>{};
            data.forEach((k, v) {
              if (v['status'] == 'Present') newStatus[k] = true;
              if (v['status'] == 'Absent') newStatus[k] = false;
            });
            if (mounted) {
              setState(() {
                attendanceStatus.clear();
                attendanceStatus.addAll(newStatus);
              });
            }
          }
        });

    _attendantSub = ServiceLocator().rtdbService
        .stream('attendant_attendance/daily/$today')
        .listen((data) {
          if (data != null && data is Map) {
            final newStatus = <String, bool>{};
            data.forEach((patientId, attendantsMap) {
              if (attendantsMap is Map) {
                attendantsMap.forEach((attendantSafeKey, v) {
                  final key = '${patientId}_${v['attendantName']}';
                  if (v['status'] == 'Present') newStatus[key] = true;
                  if (v['status'] == 'Absent') newStatus[key] = false;
                });
              }
            });
            if (mounted) {
              setState(() {
                attendantAttendanceStatus.clear();
                attendantAttendanceStatus.addAll(newStatus);
              });
            }
          }
        });
  }

  void _refreshFutures() {
    _weeklyData = fetchWeeklyAttendance(_attendanceType);
    _monthlyData = fetchMonthlyAttendance(_selectedMonth, _attendanceType);
  }

  @override
  void dispose() {
    _patientSub?.cancel();
    _attendantSub?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _fadeCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 200));
    setState(() {
      if (_attendanceType == 'patient') {
        _currentPatientLimit += _pageSize;
      } else {
        _currentAttendantLimit += _pageSize;
      }
      _isLoadingMore = false;
    });
  }

  // ── Data Fetching ────────────────────────────────────────────────────────

  List<String> getLast7Days() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: i));
      return DateFormat('yyyy-MM-dd').format(date);
    }).reversed.toList();
  }

  List<String> getDaysOfMonth(DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0);
    return List.generate(last.day, (i) {
      final date = DateTime(month.year, month.month, i + 1);
      return DateFormat('yyyy-MM-dd').format(date);
    });
  }

  String _monthTitle(DateTime m) => '${_monthShort(m.month)} ${m.year}';
  String _monthShort(int m) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];

  Future<Map<String, Map<String, String>>> fetchWeeklyAttendance(
    String type,
  ) async {
    final dates = getLast7Days();
    final pathPrefix = type == 'patient'
        ? 'attendance/daily'
        : 'attendant_attendance/daily';
    final result = <String, Map<String, String>>{};

    for (final date in dates) {
      final data = await ServiceLocator().rtdbService.get('$pathPrefix/$date');
      if (data != null && data is Map) {
        if (type == 'patient') {
          Map<String, dynamic>.from(data).forEach((_, v) {
            final name = v['patientName'] ?? '';
            final status = v['status'] ?? '';
            if (name.isNotEmpty) {
              result.putIfAbsent(name, () => {})[date] = status;
            }
          });
        } else {
          // Attendants are stored under date / patientId / safeKey
          Map<String, dynamic>.from(data).forEach((patientId, attendantsMap) {
            if (attendantsMap is Map) {
              Map<String, dynamic>.from(attendantsMap).forEach((_, v) {
                final name = v['attendantName'] ?? '';
                final status = v['status'] ?? '';
                if (name.isNotEmpty) {
                  result.putIfAbsent(name, () => {})[date] = status;
                }
              });
            }
          });
        }
      }
    }
    return result;
  }

  Future<Map<String, Map<String, String>>> fetchMonthlyAttendance(
    DateTime month,
    String type,
  ) async {
    final dates = getDaysOfMonth(month);
    final pathPrefix = type == 'patient'
        ? 'attendance/daily'
        : 'attendant_attendance/daily';
    final result = <String, Map<String, String>>{};

    for (final date in dates) {
      final data = await ServiceLocator().rtdbService.get('$pathPrefix/$date');
      if (data != null && data is Map) {
        if (type == 'patient') {
          Map<String, dynamic>.from(data).forEach((_, v) {
            final name = v['patientName'] ?? '';
            final status = v['status'] ?? '';
            if (name.isNotEmpty) {
              result.putIfAbsent(name, () => {})[date] = status;
            }
          });
        } else {
          Map<String, dynamic>.from(data).forEach((patientId, attendantsMap) {
            if (attendantsMap is Map) {
              Map<String, dynamic>.from(attendantsMap).forEach((_, v) {
                final name = v['attendantName'] ?? '';
                final status = v['status'] ?? '';
                if (name.isNotEmpty) {
                  result.putIfAbsent(name, () => {})[date] = status;
                }
              });
            }
          });
        }
      }
    }
    return result;
  }

  Future<void> markAttendance(
    String patientId,
    String patientName,
    bool isPresent,
  ) async {
    final dateObj = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(dateObj);

    final bool? previousStatus = attendanceStatus[patientId];
    setState(() => attendanceStatus[patientId] = isPresent);

    try {
      await ServiceLocator().rtdbService
          .put('attendance/daily/$today/$patientId', {
            'patientId': patientId,
            'patientName': patientName,
            'status': isPresent ? 'Present' : 'Absent',
            'date': today,
            'timestamp': DateTime.now().toIso8601String(),
          });

      // -- Billing Integration --
      await ServiceLocator().paymentService.updatePatientBillingFromAttendance(
        patientId: patientId,
        dateMarked: dateObj,
        isPresent: isPresent,
        wasPresent: previousStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: isPresent
                ? const Color(0xFF3B6D11)
                : const Color(0xFFD32F2F),
            content: Text(
              '$patientName marked as ${isPresent ? "Present" : "Absent"}',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (previousStatus != null) {
            attendanceStatus[patientId] = previousStatus;
          } else {
            attendanceStatus.remove(patientId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to update attendance'),
          ),
        );
      }
    }
  }

  Future<void> markAttendantAttendance(
    String patientId,
    String attendantName,
    bool isPresent,
  ) async {
    final dateObj = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(dateObj);
    final safeKey = attendantName.replaceAll(RegExp(r'[.#\$\[\]/]'), '_');
    final String statusKey = '${patientId}_$attendantName';

    final bool? previousStatus = attendantAttendanceStatus[statusKey];
    setState(() => attendantAttendanceStatus[statusKey] = isPresent);

    try {
      await ServiceLocator().rtdbService
          .put('attendant_attendance/daily/$today/$patientId/$safeKey', {
            'patientId': patientId,
            'attendantName': attendantName,
            'status': isPresent ? 'Present' : 'Absent',
            'date': today,
            'timestamp': DateTime.now().toIso8601String(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: isPresent
                ? const Color(0xFF3B6D11)
                : const Color(0xFFD32F2F),
            content: Text(
              '$attendantName marked as ${isPresent ? "Present" : "Absent"}',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (previousStatus != null) {
            attendantAttendanceStatus[statusKey] = previousStatus;
          } else {
            attendantAttendanceStatus.remove(statusKey);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to update attendance'),
          ),
        );
      }
    }
  }

  // ── Layout & UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9F0),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildDailyView(),
                  _buildWeeklyView(),
                  _buildMonthlyView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Attendance',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E4A1F),
                ),
              ),
              _buildSegmentedControl(),
            ],
          ),
          const SizedBox(height: 20),
          _buildSearchAndSummary(),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentButton('patient', 'Patients'),
          _buildSegmentButton('attendant', 'Attendants'),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(String type, String label) {
    final isSelected = _attendanceType == type;
    return GestureDetector(
      onTap: () {
        if (_attendanceType != type) {
          setState(() {
            _attendanceType = type;
            _refreshFutures();
            _fadeCtrl.forward(from: 0);
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  const BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF3B6D11),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndSummary() {
    return StreamBuilder<List<PatientModel>>(
      stream: _patientsStream,
      builder: (context, snapshot) {
        int total = 0;
        int present = 0;
        int absent = 0;

        if (snapshot.hasData) {
          final patients = snapshot.data!
              .where((p) => p.status == 'active' || p.status == 'Paid')
              .toList();
          _allPatients = patients;

          if (_attendanceType == 'patient') {
            total = patients.length;
            for (var p in patients) {
              if (attendanceStatus[p.id] == true) present++;
              if (attendanceStatus[p.id] == false) absent++;
            }
          } else {
            for (var p in patients) {
              if (p.attendants != null) {
                total += p.attendants!.length;
                for (var a in p.attendants!) {
                  final status = attendantAttendanceStatus['${p.id}_${a.name}'];
                  if (status == true) present++;
                  if (status == false) absent++;
                }
              }
            }
          }
        }

        return Column(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  title: 'Total',
                  count: total.toString(),
                  color: const Color(0xFF2E4A1F),
                ),
                _SummaryCard(
                  title: 'Present',
                  count: present.toString(),
                  color: const Color(0xFF3B6D11),
                ),
                _SummaryCard(
                  title: 'Absent',
                  count: absent.toString(),
                  color: const Color(0xFFD32F2F),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF3B6D11)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF4F9F0),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildPillTab(0, 'Daily'),
          _buildPillTab(1, 'Weekly'),
          _buildPillTab(2, 'Monthly'),
        ],
      ),
    );
  }

  Widget _buildPillTab(int index, String label) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B6D11)
                : const Color(0xFFC0DD97),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF639922),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── Daily View ──────────────────────────────────────────────────────────

  Widget _buildDailyView() {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: _allPatients == null
          ? _buildShimmerList()
          : (_attendanceType == 'patient'
                ? _buildPatientList()
                : _buildAttendantList()),
    );
  }

  Widget _buildPatientList() {
    var filtered = _allPatients!.where((p) {
      if (_searchQuery.isEmpty) return true;
      return p.fullName.toLowerCase().contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No active patients found.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final displayList = filtered.take(_currentPatientLimit).toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: displayList.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == displayList.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
            ),
          );
        }
        // return _PatientAttendanceCard(
        //   patient: displayList[index],
        //   status: attendanceStatus[displayList[index].id],
        //   onMarkPresent: () => markAttendance(
        //     displayList[index].id,
        //     displayList[index].fullName,
        //     true,
        //   ),
        //   onMarkAbsent: () => markAttendance(
        //     displayList[index].id,
        //     displayList[index].fullName,
        //     false,
        //   ),
        // );
        return _PatientAttendanceCard(
  patient: displayList[index],
  status: attendanceStatus[displayList[index].id],
  onMarkPresent: () => markAttendance(
    displayList[index].id,
    displayList[index].fullName,
    true,
  ),
  onMarkAbsent: () => markAttendance(
    displayList[index].id,
    displayList[index].fullName,
    false,
  ),
  attendantAttendanceStatus: attendantAttendanceStatus,
  onMarkAttendantPresent: (patientId, attendantName, isPresent) =>
      markAttendantAttendance(patientId, attendantName, isPresent),
);
      },
    );
  }

  Widget _buildAttendantList() {
    List<FlattenedAttendant> allAttendants = [];
    for (var p in _allPatients!) {
      if (p.attendants != null) {
        for (var a in p.attendants!) {
          allAttendants.add(FlattenedAttendant(p, a));
        }
      }
    }

    var filtered = allAttendants.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.attendant.name.toLowerCase().contains(_searchQuery) ||
          item.patient.fullName.toLowerCase().contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No active attendants found.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final displayList = filtered.take(_currentAttendantLimit).toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: displayList.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == displayList.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
            ),
          );
        }
        final item = displayList[index];
        final key = '${item.patient.id}_${item.attendant.name}';
        return _AttendantAttendanceCard(
          item: item,
          status: attendantAttendanceStatus[key],
          onMarkPresent: () => markAttendantAttendance(
            item.patient.id,
            item.attendant.name,
            true,
          ),
          onMarkAbsent: () => markAttendantAttendance(
            item.patient.id,
            item.attendant.name,
            false,
          ),
        );
      },
    );
  }

  // ── Weekly & Monthly Views ──────────────────────────────────────────────

  Widget _buildWeeklyView() {
    return FutureBuilder(
      future: _weeklyData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildTableShimmer();
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading data'));
        }
        final data = snapshot.data as Map<String, Map<String, String>>;
        if (data.isEmpty) {
          return const Center(child: Text('No data found'));
        }
        return FadeTransition(
          opacity: _fadeCtrl,
          child: _buildDataTable(data, getLast7Days()),
        );
      },
    );
  }

  Widget _buildMonthlyView() {
    return FutureBuilder(
      future: _monthlyData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildTableShimmer();
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading data'));
        }
        final data = snapshot.data as Map<String, Map<String, String>>;

        return FadeTransition(
          opacity: _fadeCtrl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Color(0xFF3B6D11),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(
                          _selectedMonth.year,
                          _selectedMonth.month - 1,
                        );
                        _monthlyData = fetchMonthlyAttendance(
                          _selectedMonth,
                          _attendanceType,
                        );
                        _fadeCtrl.forward(from: 0);
                      });
                    },
                  ),
                  Text(
                    _monthTitle(_selectedMonth),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF2E4A1F),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF3B6D11),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(
                          _selectedMonth.year,
                          _selectedMonth.month + 1,
                        );
                        _monthlyData = fetchMonthlyAttendance(
                          _selectedMonth,
                          _attendanceType,
                        );
                        _fadeCtrl.forward(from: 0);
                      });
                    },
                  ),
                ],
              ),
              if (data.isEmpty)
                const Expanded(child: Center(child: Text('No data found')))
              else
                Expanded(
                  child: _buildDataTable(data, getDaysOfMonth(_selectedMonth)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDataTable(
    Map<String, Map<String, String>> data,
    List<String> dates,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E8C8)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F5E9)),
              columnSpacing: 24,
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200),
                verticalInside: BorderSide(color: Colors.grey.shade200),
              ),
              columns: [
                const DataColumn(
                  label: Text(
                    'Name',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E4A1F),
                    ),
                  ),
                ),
                ...dates.map((d) {
                  final dt = DateTime.parse(d);
                  return DataColumn(
                    label: Text(
                      '${dt.day} ${_monthShort(dt.month)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E4A1F),
                      ),
                    ),
                  );
                }),
              ],
              rows: data.entries.map((e) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        e.key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ...dates.map((date) {
                      final s = e.value[date];
                      if (s == null)
                        return const DataCell(
                          Text('-', style: TextStyle(color: Colors.grey)),
                        );
                      return DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: s == 'Present'
                                ? Colors.green.withOpacity(0.15)
                                : Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s == 'Present' ? 'P' : 'A',
                            style: TextStyle(
                              color: s == 'Present' ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shimmers ────────────────────────────────────────────────────────────

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.white,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildTableShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.white,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Components
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String title;
  final String count;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// class _PatientAttendanceCard extends StatelessWidget {
//   final PatientModel patient;
//   final bool? status;
//   final VoidCallback onMarkPresent;
//   final VoidCallback onMarkAbsent;

//   const _PatientAttendanceCard({
//     required this.patient,
//     required this.status,
//     required this.onMarkPresent,
//     required this.onMarkAbsent,
//   });

//   @override
//   Widget build(BuildContext context) {
//     String initials = patient.fullName.isNotEmpty
//         ? patient.fullName[0].toUpperCase()
//         : '?';

//     return Container(
//       margin: const EdgeInsets.only(bottom: 16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(
//           color: status == true
//               ? const Color(0xFF3B6D11).withOpacity(0.5)
//               : status == false
//               ? const Color(0xFFD32F2F).withOpacity(0.5)
//               : const Color(0xFFE8F5E9),
//           width: 1.5,
//         ),
//         boxShadow: const [
//           BoxShadow(
//             color: Colors.black12,
//             blurRadius: 10,
//             offset: Offset(0, 4),
//           ),
//         ],
//       ),
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               CircleAvatar(
//                 radius: 24,
//                 backgroundColor: const Color(0xFFE8F5E9),
//                 child: Text(
//                   initials,
//                   style: const TextStyle(
//                     color: Color(0xFF3B6D11),
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 16),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       patient.fullName,
//                       style: const TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.bold,
//                         color: Color(0xFF2E4A1F),
//                       ),
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                     const SizedBox(height: 4),
//                     Wrap(
//                       spacing: 8,
//                       runSpacing: 4,
//                       children: [
//                         _InfoChip(
//                           Icons.phone,
//                           patient.contactNumber ?? 'No contact',
//                         ),
//                         if (patient.roomNumber != null)
//                           _InfoChip(
//                             Icons.meeting_room,
//                             'Room ${patient.roomNumber}',
//                           ),
//                         if (patient.bedLabels != null &&
//                             patient.bedLabels!.isNotEmpty)
//                           _InfoChip(
//                             Icons.bed,
//                             patient.bedLabels!
//                                 .map(
//                                   (b) => BedHelper.getBedDisplayName(
//                                     b,
//                                     roomIdentifier: patient.roomNumber,
//                                   ),
//                                 )
//                                 .join(', '),
//                           ),
//                         _InfoChip(
//                           Icons.check_circle_outline,
//                           'Present: ${patient.totalPresentDays}',
//                         ),
//                         _InfoChip(
//                           Icons.cancel_outlined,
//                           'Absent: ${patient.totalAbsentDays}',
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//               if (status != null)
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 10,
//                     vertical: 6,
//                   ),
//                   decoration: BoxDecoration(
//                     color: status!
//                         ? Colors.green.withOpacity(0.1)
//                         : Colors.red.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Text(
//                     status! ? 'Present' : 'Absent',
//                     style: TextStyle(
//                       color: status! ? Colors.green : Colors.red,
//                       fontWeight: FontWeight.bold,
//                       fontSize: 12,
//                     ),
//                   ),
//                 ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           Row(
//             children: [
//               Expanded(
//                 child: _AttendanceButton(
//                   label: 'Present',
//                   isSelected: status == true,
//                   activeColor: const Color(0xFF3B6D11),
//                   onTap: onMarkPresent,
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: _AttendanceButton(
//                   label: 'Absent',
//                   isSelected: status == false,
//                   activeColor: const Color(0xFFD32F2F),
//                   onTap: onMarkAbsent,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }
class _PatientAttendanceCard extends StatefulWidget {
  final PatientModel patient;
  final bool? status;
  final VoidCallback onMarkPresent;
  final VoidCallback onMarkAbsent;
  final Map<String, bool> attendantAttendanceStatus;
  final Function(String patientId, String attendantName, bool isPresent) onMarkAttendantPresent;

  const _PatientAttendanceCard({
    required this.patient,
    required this.status,
    required this.onMarkPresent,
    required this.onMarkAbsent,
    required this.attendantAttendanceStatus,
    required this.onMarkAttendantPresent,
  });

  @override
  State<_PatientAttendanceCard> createState() => _PatientAttendanceCardState();
}

class _PatientAttendanceCardState extends State<_PatientAttendanceCard> {
  bool _attendantsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final hasAttendants = widget.patient.attendants != null &&
        widget.patient.attendants!.isNotEmpty;
    String initials = widget.patient.fullName.isNotEmpty
        ? widget.patient.fullName[0].toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.status == true
              ? const Color(0xFF3B6D11).withOpacity(0.5)
              : widget.status == false
              ? const Color(0xFFD32F2F).withOpacity(0.5)
              : const Color(0xFFE8F5E9),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── Patient info row ──
          Row(
            children: [
              // CircleAvatar(
              //   radius: 24,
              //   backgroundColor: const Color(0xFFE8F5E9),
              //   child: Text(
              //     initials,
              //     style: const TextStyle(
              //       color: Color(0xFF3B6D11),
              //       fontSize: 18,
              //       fontWeight: FontWeight.bold,
              //     ),
              //   ),
              // ),
              CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFFE8F5E9),
        backgroundImage: widget.patient.photoDataUrl != null
            ? MemoryImage(base64Decode(
                widget.patient.photoDataUrl!.contains(',')
                    ? widget.patient.photoDataUrl!.split(',').last
                    : widget.patient.photoDataUrl!,
              ))
            : null,
        child: widget.patient.photoDataUrl == null
            ? Text(initials,
                style: const TextStyle(
                  color: Color(0xFF3B6D11),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ))
            : null,
      ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.patient.fullName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E4A1F),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _InfoChip(Icons.phone, widget.patient.contactNumber ?? 'No contact'),
                        if (widget.patient.roomNumber != null)
                          _InfoChip(Icons.meeting_room, 'Room ${widget.patient.roomNumber}'),
                        if (widget.patient.bedLabels != null && widget.patient.bedLabels!.isNotEmpty)
                          _InfoChip(
                            Icons.bed,
                            widget.patient.bedLabels!
                                .map((b) => BedHelper.getBedDisplayName(
                                      b,
                                      roomIdentifier: widget.patient.roomNumber,
                                    ))
                                .join(', '),
                          ),
                        _InfoChip(Icons.check_circle_outline, 'Present: ${widget.patient.totalPresentDays}'),
                        _InfoChip(Icons.cancel_outlined, 'Absent: ${widget.patient.totalAbsentDays}'),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.status != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.status!
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.status! ? 'Present' : 'Absent',
                    style: TextStyle(
                      color: widget.status! ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Patient attendance buttons ──
          Row(
            children: [
              Expanded(
                child: _AttendanceButton(
                  label: 'Present',
                  isSelected: widget.status == true,
                  activeColor: const Color(0xFF3B6D11),
                  onTap: widget.onMarkPresent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AttendanceButton(
                  label: 'Absent',
                  isSelected: widget.status == false,
                  activeColor: const Color(0xFFD32F2F),
                  onTap: widget.onMarkAbsent,
                ),
              ),
            ],
          ),

          // ── Attendants expandable section ──
          if (hasAttendants) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _attendantsExpanded = !_attendantsExpanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F9F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC0DD97)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline, size: 16, color: Color(0xFF3B6D11)),
                    const SizedBox(width: 8),
                    Text(
                      'Attendants (${widget.patient.attendants!.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B6D11),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _attendantsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: const Color(0xFF3B6D11),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_attendantsExpanded) ...[
              const SizedBox(height: 8),
              ...widget.patient.attendants!.map((attendant) {
                final key = '${widget.patient.id}_${attendant.name}';
                final attStatus = widget.attendantAttendanceStatus[key];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F9F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: attStatus == true
                          ? const Color(0xFF3B6D11).withOpacity(0.4)
                          : attStatus == false
                          ? const Color(0xFFD32F2F).withOpacity(0.4)
                          : const Color(0xFFC0DD97),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // CircleAvatar(
                          //   radius: 16,
                          //   backgroundColor: const Color(0xFFE3F2FD),
                          //   child: Text(
                          //     attendant.name.isNotEmpty
                          //         ? attendant.name[0].toUpperCase()
                          //         : '?',
                          //     style: const TextStyle(
                          //       color: Color(0xFF1565C0),
                          //       fontSize: 13,
                          //       fontWeight: FontWeight.bold,
                          //     ),
                          //   ),
                          // ),
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFFE3F2FD),
                            backgroundImage: attendant.photoDataUrl != null
                                ? MemoryImage(base64Decode(
                                    attendant.photoDataUrl!.contains(',')
                                        ? attendant.photoDataUrl!.split(',').last
                                        : attendant.photoDataUrl!,
                                  ))
                                : null,
                            child: attendant.photoDataUrl == null
                                ? Text(
                                    attendant.name.isNotEmpty
                                        ? attendant.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Color(0xFF1565C0),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  attendant.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2E4A1F),
                                  ),
                                ),
                                if (attendant.relation != null)
                                  Text(
                                    attendant.relation!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF639922),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (attStatus != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: attStatus
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                attStatus ? 'Present' : 'Absent',
                                style: TextStyle(
                                  color: attStatus ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _AttendanceButton(
                              label: 'Present',
                              isSelected: attStatus == true,
                              activeColor: const Color(0xFF3B6D11),
                              onTap: () => widget.onMarkAttendantPresent(
                                widget.patient.id,
                                attendant.name,
                                true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _AttendanceButton(
                              label: 'Absent',
                              isSelected: attStatus == false,
                              activeColor: const Color(0xFFD32F2F),
                              onTap: () => widget.onMarkAttendantPresent(
                                widget.patient.id,
                                attendant.name,
                                false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

class _AttendantAttendanceCard extends StatelessWidget {
  final FlattenedAttendant item;
  final bool? status;
  final VoidCallback onMarkPresent;
  final VoidCallback onMarkAbsent;

  const _AttendantAttendanceCard({
    required this.item,
    required this.status,
    required this.onMarkPresent,
    required this.onMarkAbsent,
  });

  @override
  Widget build(BuildContext context) {
    String initials = item.attendant.name.isNotEmpty
        ? item.attendant.name[0].toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status == true
              ? const Color(0xFF3B6D11).withOpacity(0.5)
              : status == false
              ? const Color(0xFFD32F2F).withOpacity(0.5)
              : const Color(0xFFE8F5E9),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE3F2FD),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFF1565C0),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.attendant.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E4A1F),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Attendant of: ${item.patient.fullName}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF639922),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Wrap(
                    //   spacing: 8,
                    //   runSpacing: 4,
                    //   children: [
                    //     if (item.attendant.relation != null &&
                    //         item.attendant.relation!.isNotEmpty)
                    //       _InfoChip(
                    //         Icons.family_restroom,
                    //         item.attendant.relation!,
                    //       ),
                    //     if (item.patient.contactNumber != null &&
                    //         item.patient.contactNumber!.isNotEmpty)
                    //       _InfoChip(Icons.phone, item.patient.contactNumber!),
                    //   ],
                    // ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (item.attendant.relation != null &&
                            item.attendant.relation!.isNotEmpty)
                          _InfoChip(
                            Icons.family_restroom,
                            item.attendant.relation!,
                          ),
                        if (item.patient.contactNumber != null &&
                            item.patient.contactNumber!.isNotEmpty)
                          _InfoChip(Icons.phone, item.patient.contactNumber!),
                        if (item.attendant.aadhaarNumber != null &&
                            item.attendant.aadhaarNumber!.isNotEmpty)
                          _InfoChip(
                            Icons.credit_card,
                            item.attendant.aadhaarNumber!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (status != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: status!
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status! ? 'Present' : 'Absent',
                    style: TextStyle(
                      color: status! ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AttendanceButton(
                  label: 'Present',
                  isSelected: status == true,
                  activeColor: const Color(0xFF3B6D11),
                  onTap: onMarkPresent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AttendanceButton(
                  label: 'Absent',
                  isSelected: status == false,
                  activeColor: const Color(0xFFD32F2F),
                  onTap: onMarkAbsent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF639922)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF639922)),
          ),
        ],
      ),
    );
  }
}

class _AttendanceButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _AttendanceButton({
    required this.label,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
