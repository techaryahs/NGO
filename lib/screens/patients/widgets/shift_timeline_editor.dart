import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/patient_model.dart';
import '../../../models/stay_model.dart';
import '../../../services/service_locator.dart';
import '../../../services/stay_history_service.dart';

class ShiftTimelineEditor extends StatefulWidget {
  final PatientModel patient;
  final List<StayModel> segments;
  final Map<dynamic, dynamic> summary;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  const ShiftTimelineEditor({
    super.key,
    required this.patient,
    required this.segments,
    required this.summary,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  State<ShiftTimelineEditor> createState() => _ShiftTimelineEditorState();
}

class _ShiftTimelineEditorState extends State<ShiftTimelineEditor> {
  late final List<StayModel> segments;
  late final List<DateTime> starts, ends;
  late final List<TextEditingController> chargeOverrides;
  late final List<double?> originalOverrides;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    segments = [...widget.segments]
      ..sort((a, b) {
        final byStart = a.admissionDate.compareTo(b.admissionDate);
        if (byStart != 0) return byStart;
        if (a.isActive != b.isActive) return a.isActive ? 1 : -1;
        return 0;
      });
    starts = [for (final segment in segments) segment.admissionDate];
    ends = [
      for (final segment in segments)
        segment.isActive
            ? segment.expectedDischargeDate
            : segment.completedAt ?? segment.updatedAt,
    ];
    final charges = widget.summary['segmentCharges'];
    originalOverrides = [for (final segment in segments) segment.costOverride];
    chargeOverrides = [
      for (final segment in segments)
        TextEditingController(
          text:
              (segment.costOverride ??
                      (charges is Map
                          ? (charges[segment.id] as num?)?.toDouble()
                          : null))
                  ?.toStringAsFixed(0) ??
              '0',
        ),
    ];
  }

  @override
  void dispose() {
    for (final controller in chargeOverrides) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(
    int index, {
    required bool start,
    required bool time,
  }) async {
    final current = start ? starts[index] : ends[index];
    if (time) {
      final selected = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
      );
      if (selected == null || !mounted) return;
      setState(() {
        final value = DateTime(
          current.year,
          current.month,
          current.day,
          selected.hour,
          selected.minute,
        );
        if (start) {
          starts[index] = value;
        } else {
          ends[index] = value;
        }
      });
      return;
    }
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected == null || !mounted) return;
    setState(() {
      final value = DateTime(
        selected.year,
        selected.month,
        selected.day,
        current.hour,
        current.minute,
      );
      if (start) {
        starts[index] = value;
      } else {
        ends[index] = value;
      }
    });
  }

  Widget _picker(int index, {required bool start, required bool time}) {
    final value = start ? starts[index] : ends[index];
    return InkWell(
      onTap: saving ? null : () => _pick(index, start: start, time: time),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: time
              ? 'Time'
              : start
              ? 'Start date'
              : 'End date',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD7E5CB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD7E5CB)),
          ),
          suffixIcon: Icon(
            time ? Icons.schedule_rounded : Icons.calendar_month_rounded,
            color: const Color(0xFF527B2C),
          ),
        ),
        child: Text(
          DateFormat(time ? 'hh:mm a' : 'dd MMM yyyy').format(value),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _segmentCard(int index) {
    final segment = segments[index];
    final bed = segment.bedLabel?.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4E6C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B6D11),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Room ${segment.roomNumber}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF214B0B),
                      ),
                    ),
                    if (bed?.isNotEmpty == true)
                      Text(
                        bed!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF647455),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: segment.isActive
                      ? const Color(0xFFE4F2D7)
                      : const Color(0xFFEEF2EA),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  segment.isActive ? 'CURRENT ROOM' : 'PREVIOUS ROOM',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4,
                    color: segment.isActive
                        ? const Color(0xFF3B6D11)
                        : const Color(0xFF647455),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final dateWidth = compact
                  ? (constraints.maxWidth < 520
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2)
                  : 205.0;
              final timeWidth = compact ? dateWidth : 145.0;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: compact ? dateWidth : 190,
                    child: TextField(
                      controller: chargeOverrides[index],
                      enabled: !saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: 'Charged amount',
                        prefixText: '₹ ',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD7E5CB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD7E5CB),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: dateWidth,
                    child: _picker(index, start: true, time: false),
                  ),
                  SizedBox(
                    width: timeWidth,
                    child: _picker(index, start: true, time: true),
                  ),
                  SizedBox(
                    width: dateWidth,
                    child: _picker(index, start: false, time: false),
                  ),
                  SizedBox(
                    width: timeWidth,
                    child: _picker(index, start: false, time: true),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    try {
      final overrides = <double?>[];
      for (var i = 0; i < chargeOverrides.length; i++) {
        final controller = chargeOverrides[i];
        final text = controller.text.trim();
        if (text.isEmpty) {
          overrides.add(null);
          continue;
        }
        final value = double.tryParse(text);
        if (value == null || !value.isFinite || value < 0) {
          throw ArgumentError('Enter a valid charged amount, zero or greater.');
        }
        final charges = widget.summary['segmentCharges'];
        final calculated = charges is Map
            ? (charges[segments[i].id] as num?)?.toDouble()
            : null;
        overrides.add(
          originalOverrides[i] == null &&
                  calculated != null &&
                  (value - calculated).abs() < 0.005
              ? null
              : value,
        );
      }
      setState(() {
        saving = true;
        error = null;
      });
      await StayHistoryService(
        ServiceLocator().rtdbService,
      ).updateShiftTimeline(widget.patient.id, [
        for (var i = 0; i < segments.length; i++)
          (stay: segments[i], start: starts[i], end: ends[i]),
      ], costOverrides: overrides);
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().replaceFirst('Invalid argument(s): ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFC7DDB4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120F2E03),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            _TimelineHeaderIcon(),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit shifting timeline',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF214B0B),
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Review room charges and keep each shift date connected.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF647455)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < segments.length; i++) ...[
          _segmentCard(i),
          if (i < segments.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7, horizontal: 17),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: 20,
                  color: Color(0xFF86A96A),
                ),
              ),
            ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: saving ? null : widget.onCancel,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B6D11),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (saving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.check_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(saving ? 'Saving…' : 'Save timeline'),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TimelineHeaderIcon extends StatelessWidget {
  const _TimelineHeaderIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: const Color(0xFFE7F2DC),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Icon(Icons.route_rounded, color: Color(0xFF3B6D11), size: 24),
  );
}
