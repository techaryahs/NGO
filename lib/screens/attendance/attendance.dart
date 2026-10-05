import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/patient_model.dart';
import '../../models/stay_model.dart';
import '../../services/service_locator.dart';
import 'attendance_service.dart';

class Attendance extends StatefulWidget {
  const Attendance({super.key});
  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance>
    with AutomaticKeepAliveClientMixin {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  MonthlyAttendanceEditor? _editor;
  List<PatientModel> _patients = [];
  List<StayModel> _stays = [];
  List<AttendanceRow> _rows = [];
  StreamSubscription<List<PatientModel>>? _patientsSub;
  StreamSubscription<List<StayModel>>? _staysSub;
  final _search = TextEditingController();
  String? _room;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  int _loadVersion = 0;
  final Set<String> _billingRetry = {};
  static const _cellWidth = 48.0;
  static const _rowHeight = 44.0;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _search.addListener(_filterChanged);
    // Shared SSE/cache streams attach once, independently of month selection.
    _patientsSub = ServiceLocator().patientService.getPatientsStream().listen((
      value,
    ) {
      if (!mounted) return;
      setState(() {
        _patients = value;
        _buildRows();
      });
    }, onError: _streamError);
    _staysSub = ServiceLocator().roomService.getStaysStream().listen((value) {
      if (!mounted) return;
      setState(() {
        _stays = value;
        _buildRows();
      });
    }, onError: _streamError);
    _loadMonth();
  }

  void _streamError(Object error) {
    if (mounted) {
      setState(() => _error = 'Could not load patients or stays: $error');
    }
  }

  void _filterChanged() => setState(() {});
  void _buildRows() {
    _rows = _editor?.data.rows(_patients, _stays) ?? [];
    if (_room != null && !_rows.any((row) => row.room == _room)) _room = null;
  }

  @override
  void dispose() {
    _patientsSub?.cancel();
    _staysSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadMonth() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AttendanceService(
        ServiceLocator().rtdbService,
      ).loadMonth(_month);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _editor = MonthlyAttendanceEditor(data);
        _buildRows();
        _loading = false;
      });
    } catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _error = 'Could not load attendance: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeMonth(int offset, {DateTime? selected}) async {
    if (_saving) return;
    if (_editor?.dirty.isNotEmpty == true) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved attendance'),
          content: const Text('Discard unsaved changes to change month?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _month = selected == null
          ? DateTime(_month.year, _month.month + offset)
          : DateTime(selected.year, selected.month);
      _editor = null;
      _rows = [];
    });
    await _loadMonth();
  }

  Future<void> _save() async {
    if (_saving || _editor == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _billingRetry.addAll(await _editor!.save(ServiceLocator().rtdbService));
      // Each distinct patient is scheduled once after the entire atomic batch.
      final ids = _billingRetry.toList();
      await Future.wait(
        ids.map((id) async {
          await ServiceLocator().paymentService.schedulePatientBilling(id);
          _billingRetry.remove(id);
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance changes saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _billingRetry.isNotEmpty
              ? 'Attendance saved; billing refresh failed. Use Retry billing. $e'
              : 'Save failed. Your changes are still unsaved. $e',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _cell(AttendanceRow row, DateTime date) {
    final editor = _editor!;
    final enabled = row.enabled(date);
    final status = editor.status(row, date);
    final dirty = editor.isDirty(row, date);
    final color = !enabled
        ? Colors.grey.shade200
        : switch (status) {
            'Present' => const Color(0xFFE8F5E9),
            'Absent' => const Color(0xFFFFEBEE),
            _ => Colors.white,
          };
    return SizedBox(
      width: _cellWidth,
      height: _rowHeight,
      child: Tooltip(
        message: enabled
            ? '${row.name} • ${DateFormat('dd MMM').format(date)} • $status${dirty ? ' (unsaved)' : ''}'
            : 'Outside stay dates',
        child: InkWell(
          onTap: !enabled || _saving
              ? null
              : () => setState(() {
                  editor.edit(row, date, switch (status) {
                    'Present' => 'Absent',
                    'Absent' => 'Unmarked',
                    _ => 'Present',
                  });
                }),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: dirty ? Colors.orange : Colors.grey.shade300,
                width: dirty ? 2 : 0.5,
              ),
            ),
            child: Text(
              !enabled
                  ? '—'
                  : switch (status) {
                      'Present' => 'P',
                      'Absent' => 'A',
                      _ => '·',
                    },
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: !enabled
                    ? Colors.grey
                    : status == 'Present'
                    ? Colors.green.shade800
                    : status == 'Absent'
                    ? Colors.red.shade800
                    : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = _search.text.toLowerCase().trim();
    final matchingPatients = _rows
        .where(
          (row) =>
              (_room == null || row.room == _room) &&
              (query.isEmpty ||
                  row.patientName.toLowerCase().contains(query) ||
                  row.name.toLowerCase().contains(query)),
        )
        .map((row) => row.patientId)
        .toSet();
    final rows = _rows
        .where(
          (row) =>
              matchingPatients.contains(row.patientId) &&
              (_room == null || row.room == _room),
        )
        .toList();
    final rooms =
        _rows
            .map((row) => row.room)
            .where((room) => room.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final dates = _editor?.data.dates ?? <DateTime>[];
    final rowByKey = {for (final row in rows) row.path(_month): row};
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Monthly Attendance',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: _saving || _loading ? null : () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: _saving || _loading
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _month,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(DateTime.now().year + 10, 12, 31),
                        );
                        if (picked != null && mounted)
                          await _changeMonth(0, selected: picked);
                      },
                child: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              IconButton(
                onPressed: _saving || _loading ? null : () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Search patient / attendant',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _room,
                hint: const Text('All rooms'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All rooms'),
                  ),
                  for (final room in rooms)
                    DropdownMenuItem(value: room, child: Text(room)),
                ],
                onChanged: (value) => setState(() => _room = value),
              ),
              FilledButton.icon(
                onPressed:
                    _saving ||
                        _loading ||
                        ((_editor?.dirty.isEmpty ?? true) &&
                            _billingRetry.isEmpty)
                    ? null
                    : _save,
                icon: const Icon(Icons.save),
                label: Text(
                  _saving
                      ? 'Saving…'
                      : _billingRetry.isNotEmpty &&
                            (_editor?.dirty.isEmpty ?? true)
                      ? 'Retry billing'
                      : 'Save Changes (${_editor?.dirty.length ?? 0})',
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Click a cell: Unmarked → Present → Absent → Unmarked.  P = Present • A = Absent • · = Unmarked • Orange border = Unsaved',
            ),
          ),
          if (_error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                if (_editor == null && !_loading)
                  TextButton(onPressed: _loadMonth, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _editor == null
                ? const SizedBox.shrink()
                : rows.isEmpty
                ? const Center(
                    child: Text('No patients with stays in this month.'),
                  )
                : StickyAttendanceTable(
                    data: {
                      for (final key in rowByKey.keys) key: <String, String>{},
                    },
                    dates: dates
                        .map((date) => DateFormat('yyyy-MM-dd').format(date))
                        .toList(),
                    monthLabel: (month) =>
                        DateFormat('EEE').format(DateTime(_month.year, month)),
                    nameBuilder: (key) {
                      final row = rowByKey[key]!;
                      return Container(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.only(
                          left: row.isAttendant ? 28 : 12,
                          right: 8,
                        ),
                        color: row.isAttendant
                            ? Colors.white
                            : const Color(0xFFF1F8E9),
                        child: Tooltip(
                          message: '${row.name} • ${row.room}',
                          child: Text(
                            '${row.isAttendant ? '↳ ' : ''}${row.name}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: row.isAttendant
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                    cellBuilder: (key, date, _) =>
                        _cell(rowByKey[key]!, DateTime.parse(date)),
                  ),
          ),
        ],
      ),
    );
  }
}

class StickyAttendanceTable extends StatefulWidget {
  final Widget Function(String key)? nameBuilder;
  final Map<String, Map<String, String>> data;
  final List<String> dates;
  final String Function(int month) monthLabel;
  final Widget Function(String name, String date, String? status) cellBuilder;

  const StickyAttendanceTable({
    super.key,
    this.nameBuilder,
    required this.data,
    required this.dates,
    required this.monthLabel,
    required this.cellBuilder,
  });

  @override
  State<StickyAttendanceTable> createState() => StickyAttendanceTableState();
}

class StickyAttendanceTableState extends State<StickyAttendanceTable> {
  static const nameWidth = 260.0;
  static const cellWidth = 48.0;
  static const headerHeight = 48.0;
  static const rowHeight = 44.0;
  final horizontalController = ScrollController();
  final verticalController = ScrollController();
  final headerController = ScrollController();
  final namesController = ScrollController();

  @override
  void initState() {
    super.initState();
    horizontalController.addListener(_syncHeader);
    verticalController.addListener(_syncNames);
    namesController.addListener(_syncBody);
  }

  void _syncHeader() {
    if (!headerController.hasClients) return;
    headerController.jumpTo(
      horizontalController.offset.clamp(
        0.0,
        headerController.position.maxScrollExtent,
      ),
    );
  }

  void _syncBody() {
    if (!verticalController.hasClients) return;
    final offset = namesController.offset.clamp(
      0.0,
      verticalController.position.maxScrollExtent,
    );
    if ((verticalController.offset - offset).abs() > 0.5) {
      verticalController.jumpTo(offset);
    }
  }

  void _syncNames() {
    if (!namesController.hasClients) return;
    final offset = verticalController.offset.clamp(
      0.0,
      namesController.position.maxScrollExtent,
    );
    if ((namesController.offset - offset).abs() > 0.5) {
      namesController.jumpTo(offset);
    }
  }

  @override
  void dispose() {
    horizontalController.dispose();
    verticalController.dispose();
    headerController.dispose();
    namesController.dispose();
    super.dispose();
  }

  Widget _borderedCell({
    required double width,
    required Widget child,
    Color? color,
  }) {
    return Container(
      width: width,
      height: rowHeight,
      alignment: Alignment.center,
      padding: widget.nameBuilder == null
          ? const EdgeInsets.symmetric(horizontal: 6)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList();
    if (entries.isEmpty) {
      return const Center(child: Text('No matching attendance records'));
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E8C8)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned(
              left: nameWidth,
              top: headerHeight,
              right: 0,
              bottom: 0,
              child: Scrollbar(
                controller: verticalController,
                interactive: true,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.vertical,
                child: Scrollbar(
                  controller: horizontalController,
                  interactive: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: widget.dates.length * cellWidth,
                      height: (constraints.maxHeight - headerHeight).clamp(
                        0,
                        double.infinity,
                      ),
                      child: ListView.builder(
                        controller: verticalController,
                        itemExtent: rowHeight,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return Row(
                            children: [
                              for (final date in widget.dates)
                                _borderedCell(
                                  width: cellWidth,
                                  child: widget.cellBuilder(
                                    entry.key,
                                    date,
                                    entry.value[date],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: nameWidth,
              top: 0,
              right: 0,
              height: headerHeight,
              child: ClipRect(
                child: SingleChildScrollView(
                  controller: headerController,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      for (final date in widget.dates)
                        Container(
                          width: cellWidth,
                          height: headerHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade200),
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Builder(
                            builder: (context) {
                              final value = DateTime.parse(date);
                              return Text(
                                widget.nameBuilder == null
                                    ? '${value.day} ${widget.monthLabel(value.month)}'
                                    : '${value.day}\n${DateFormat('EEE').format(value)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E4A1F),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: headerHeight,
              width: nameWidth,
              bottom: 0,
              child: ClipRect(
                child: ListView.builder(
                  controller: namesController,
                  itemExtent: rowHeight,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _borderedCell(
                      width: nameWidth,
                      child:
                          widget.nameBuilder?.call(entry.key) ??
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              entry.key,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: nameWidth,
              height: headerHeight,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                color: const Color(0xFFE8F5E9),
                child: const Text(
                  'Patient / Attendant',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E4A1F),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
