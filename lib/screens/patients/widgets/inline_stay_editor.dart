import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../models/stay_model.dart';
import '../../../models/room_model.dart';
import '../../../models/bed_model.dart';
import '../../../utils/bed_helper.dart';
import '../../../services/service_locator.dart';
import '../../../services/stay_history_service.dart';

class InlineStayEditor extends StatefulWidget {
  final StayModel stay;
  final List<StayModel> admissionSegments;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final Future<List<RoomModel>> Function()? loadRooms;
  final Future<void> Function(Map<String, dynamic>)? saveChanges;
  const InlineStayEditor({
    super.key,
    required this.stay,
    this.admissionSegments = const [],
    required this.onCancel,
    required this.onSaved,
    this.loadRooms,
    this.saveChanges,
  });
  @override
  State<InlineStayEditor> createState() => _InlineStayEditorState();
}

class _StayAttendant {
  final TextEditingController name, relation, age, aadhaar, mobile;
  bool isEmergency;
  String? photo;
  _StayAttendant(Map data)
    : name = TextEditingController(text: data['name']?.toString() ?? ''),
      relation = TextEditingController(
        text: data['relation']?.toString() ?? '',
      ),
      age = TextEditingController(text: data['age']?.toString() ?? ''),
      aadhaar = TextEditingController(
        text: data['aadhaarNumber']?.toString() ?? '',
      ),
      mobile = TextEditingController(
        text: data['mobileNumber']?.toString() ?? '',
      ),
      isEmergency = data['isEmergencyContact'] == true,
      photo = data['photoDataUrl']?.toString();
  Map<String, dynamic> toMap() => {
    'name': name.text.trim(),
    'relation': relation.text.trim(),
    'age': age.text.trim(),
    'aadhaarNumber': aadhaar.text.trim(),
    'photoDataUrl': photo,
    'mobileNumber': mobile.text.trim(),
    'isEmergencyContact': isEmergency,
  };
  void dispose() {
    name.dispose();
    relation.dispose();
    age.dispose();
    aadhaar.dispose();
    mobile.dispose();
  }
}

class _InlineStayEditorState extends State<InlineStayEditor> {
  static const _lobbies = [
    '1D Lobby 1',
    '1D Lobby 2',
    '1B Lobby 1',
    '1B Lobby 2',
    '2E Lobby 1',
    '2E Lobby 2',
    '2B Lobby 1',
    '2B Lobby 2',
  ];
  late final TextEditingController name,
      registration,
      roomNumber,
      bedLabel,
      notes,
      daily,
      longDaily,
      total;
  late DateTime start, end;
  late String roomType, roomId;
  String? bedId, photo;
  final attendants = <_StayAttendant>[];
  List<RoomModel> rooms = [];
  Set<String> occupiedLobbies = {};
  bool loading = true, saving = false;
  String? error;

  String _normalRoomType(String value, {String? roomIdentifier}) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('lobby')) return 'lobby';
    if (normalized.contains('private')) return 'private';
    if (normalized.contains('general') || normalized.contains('dorm')) {
      return 'general';
    }
    if (roomIdentifier?.trim().isNotEmpty == true) {
      return RoomModel.getRoomTypeFromIdentifier(roomIdentifier!.trim());
    }
    return normalized;
  }

  @override
  void initState() {
    super.initState();
    final stay = widget.stay;
    name = TextEditingController(text: stay.patientName);
    registration = TextEditingController(
      text: stay.patientSnapshot['registrationNumber']?.toString() ?? '',
    );
    roomNumber = TextEditingController(text: stay.roomNumber);
    bedLabel = TextEditingController(text: stay.bedLabel ?? '');
    notes = TextEditingController(text: stay.notes ?? '');
    daily = TextEditingController(
      text: stay.dailyRate?.toStringAsFixed(2) ?? '',
    );
    longDaily = TextEditingController(
      text: stay.longStayDailyRate?.toStringAsFixed(2) ?? '',
    );
    total = TextEditingController(
      text: (stay.costOverride ?? stay.totalCost).toStringAsFixed(2),
    );
    start = stay.admissionDate;
    end = stay.isActive
        ? stay.expectedDischargeDate
        : stay.completedAt ?? stay.updatedAt;
    roomType = _normalRoomType(stay.roomType, roomIdentifier: stay.roomNumber);
    roomId = stay.roomId;
    bedId = stay.bedId;
    photo = stay.patientSnapshot['photoDataUrl']?.toString();
    final raw = stay.patientSnapshot['attendants'];
    if (raw is List) {
      attendants.addAll(raw.whereType<Map>().map(_StayAttendant.new));
    } else {
      for (var i = 0; i < stay.attendantCount; i++) {
        attendants.add(
          _StayAttendant({
            'name': i < stay.attendantLabels.length
                ? stay.attendantLabels[i]
                : '',
          }),
        );
      }
    }
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    try {
      if (widget.loadRooms != null) {
        rooms = await widget.loadRooms!();
      } else {
        final data = await ServiceLocator().rtdbService.get('rooms');
        if (data is Map)
          rooms = [
            for (final entry in data.entries)
              if (entry.value is Map)
                RoomModel.fromMap(entry.key.toString(), entry.value),
          ];
      }
      final stays = await ServiceLocator().roomService.getStaysStream().first;
      occupiedLobbies = {
        for (final stay in stays)
          if (stay.roomType == 'lobby' &&
              stay.status == 'active' &&
              stay.id != widget.stay.id)
            stay.roomNumber,
      };
      if (roomType != 'lobby') {
        final currentRoom = rooms
            .where(
              (room) =>
                  room.id == roomId ||
                  room.roomIdentifier.trim().toLowerCase() ==
                      roomNumber.text.trim().toLowerCase(),
            )
            .firstOrNull;
        if (currentRoom != null) {
          roomId = currentRoom.id;
          roomNumber.text = currentRoom.roomIdentifier;
          final currentBed = currentRoom.beds
              .where(
                (bed) =>
                    bed.id == bedId ||
                    (bedLabel.text.trim().isNotEmpty &&
                        bed.bedLabel.trim().toLowerCase() ==
                            bedLabel.text.trim().toLowerCase()),
              )
              .firstOrNull;
          if (currentBed != null) {
            bedId = currentBed.id;
            bedLabel.text = currentBed.bedLabel;
          }
        }
      }
    } catch (e) {
      error = 'Could not load rooms: $e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      registration,
      roomNumber,
      bedLabel,
      notes,
      daily,
      longDaily,
      total,
    ]) {
      controller.dispose();
    }
    for (final attendant in attendants) {
      attendant.dispose();
    }
    super.dispose();
  }

  Future<void> _photo(void Function(String?) assign) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null || !mounted) return;
    final file = result.files.single;
    final mime = file.extension?.toLowerCase() == 'png' ? 'png' : 'jpeg';
    setState(
      () => assign('data:image/$mime;base64,${base64Encode(file.bytes!)}'),
    );
  }

  Widget _photoEditor(
    String title,
    String? data,
    void Function(String?) assign,
  ) {
    Widget image = const Icon(
      Icons.person_outline,
      size: 36,
      color: Color(0xFF639922),
    );
    if (data?.isNotEmpty == true) {
      try {
        image = Image.memory(
          base64Decode(data!.split(',').last),
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
        );
      } catch (_) {}
    }
    return SizedBox(
      width: 126,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Change $title photo',
            child: InkWell(
              onTap: saving ? null : () => _photo(assign),
              customBorder: const CircleBorder(),
              child: Stack(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEAF3E1),
                      border: Border.all(color: const Color(0xFFA8CC7B)),
                    ),
                    child: ClipOval(child: image),
                  ),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFF57951B),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF27500A),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (data != null)
            TextButton(
              onPressed: saving ? null : () => setState(() => assign(null)),
              child: const Text('Remove photo'),
            ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF7FAF4),
    labelStyle: const TextStyle(color: Color(0xFF639922), fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE1EDD7)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE1EDD7)),
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool number = false,
    bool phone = false,
  }) => TextField(
    controller: controller,
    enabled: !saving,
    keyboardType: phone
        ? TextInputType.phone
        : number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    maxLength: phone ? 10 : null,
    inputFormatters: phone
        ? [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ]
        : null,
    decoration: _decoration(label).copyWith(counterText: ''),
    style: const TextStyle(
      color: Color(0xFF27500A),
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _grid(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760
          ? 3
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          for (final child in children)
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 12) / columns,
              child: child,
            ),
        ],
      );
    },
  );

  Widget _dateField(String title, bool beginning) {
    final value = beginning ? start : end;
    Widget picker({required bool time}) => InkWell(
      onTap: saving
          ? null
          : () => time ? _pickTime(beginning) : _pickDate(beginning),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decoration(time ? 'Time' : title).copyWith(
          suffixIcon: Icon(
            time ? Icons.schedule_outlined : Icons.calendar_today_outlined,
            size: 18,
          ),
        ),
        child: Text(
          DateFormat(time ? 'hh:mm a' : 'dd MMM yyyy').format(value),
          style: const TextStyle(
            color: Color(0xFF27500A),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Row(
      children: [
        Expanded(flex: 3, child: picker(time: false)),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: picker(time: true)),
      ],
    );
  }

  Future<void> _pickDate(bool beginning) async {
    final current = beginning ? start : end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date == null || !mounted) return;
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        current.hour,
        current.minute,
      );
      if (beginning)
        start = value;
      else
        end = value;
    });
  }

  Future<void> _pickTime(bool beginning) async {
    final current = beginning ? start : end;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      final value = DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      );
      if (beginning) {
        start = value;
      } else {
        end = value;
      }
    });
  }

  Future<void> _save() async {
    double? parse(TextEditingController controller) {
      if (controller.text.trim().isEmpty) return null;
      final value = double.tryParse(controller.text);
      if (value == null || !value.isFinite || value < 0)
        throw ArgumentError('Enter a valid amount, zero or greater');
      return value;
    }

    try {
      if (name.text.trim().isEmpty || roomNumber.text.trim().isEmpty)
        throw ArgumentError('Patient name and room/lobby are required');
      if (roomType != 'lobby' &&
          (bedId == null ||
              bedId!.trim().isEmpty ||
              bedLabel.text.trim().isEmpty)) {
        throw ArgumentError('Select a bed before saving the stay');
      }
      if (attendants.any((a) => a.name.text.trim().isEmpty))
        throw ArgumentError('Enter a name for each attendant');
      for (var i = 0; i < attendants.length; i++) {
        final phone = attendants[i].mobile.text.trim();
        if (phone.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(phone)) {
          throw ArgumentError(
            'Attendant ${i + 1} mobile number must contain exactly 10 digits',
          );
        }
      }
      if (end.isBefore(start)) {
        throw ArgumentError('Exit time cannot be before the start time.');
      }
      _validateShiftTimeline();
      setState(() {
        saving = true;
        error = null;
      });
      final selectedRoom = widget.stay.isActive
          ? rooms.where((r) => r.id == roomId).firstOrNull
          : null;
      final changes = <String, dynamic>{
        'patientName': name.text.trim(),
        'patientSnapshot': {
          ...widget.stay.patientSnapshot,
          'registrationNumber': registration.text.trim(),
          'photoDataUrl': photo,
          'attendants': attendants.map((a) => a.toMap()).toList(),
        },
        'admissionDate': start.millisecondsSinceEpoch,
        if (widget.stay.isActive)
          'expectedDischargeDate': end.millisecondsSinceEpoch,
        if (!widget.stay.isActive) 'completedAt': end.millisecondsSinceEpoch,
        'roomType': roomType,
        'roomId': roomType == 'lobby'
            ? 'lobby:${roomNumber.text.trim()}'
            : roomId,
        'roomNumber': selectedRoom?.roomIdentifier ?? roomNumber.text.trim(),
        'bedId': roomType == 'lobby' ? null : bedId,
        // Persist the visible room-specific label (for example, "Bed 14/15")
        // instead of only the room inventory token (for example, "bed1").
        // Historical cards deliberately read this saved label so missing data
        // is repaired when the user saves Edit Stay.
        'bedLabel': roomType == 'lobby'
            ? null
            : BedHelper.getBedDisplayName(
                bedLabel.text.trim(),
                roomIdentifier:
                    selectedRoom?.roomIdentifier ?? roomNumber.text.trim(),
              ),
        'attendantCount': attendants.length,
        'attendantLabels': attendants.map((a) => a.name.text.trim()).toList(),
        'dailyRate': parse(daily),
        'dailyRateIsManual': parse(daily) != null &&
            (widget.stay.dailyRateIsManual ||
                (parse(daily)! - (widget.stay.dailyRate ?? 0)).abs() > 0.01),
        'longStayDailyRate': parse(longDaily),
        'costOverride': () {
          final entered = parse(total);
          if (entered == null) return null;
          if (widget.stay.costOverride != null) return entered;
          // The calculated charge is shown inside the field for convenience,
          // but merely saving another edit must not freeze that calculation.
          return (entered - widget.stay.totalCost).abs() > 0.01
              ? entered
              : null;
        }(),
        'notes': notes.text.trim(),
      };
      if (widget.saveChanges != null) {
        await widget.saveChanges!(changes);
      } else {
        await StayHistoryService(ServiceLocator().rtdbService).updateStay(
          widget.stay.id,
          changes,
          expectedUpdatedAt: widget.stay.updatedAt,
        );
      }
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _validateShiftTimeline() {
    if (widget.admissionSegments.length < 2) return;
    final originalStart = widget.stay.admissionDate;
    final originalEnd = widget.stay.completedAt ?? widget.stay.updatedAt;
    final startChanged = start != originalStart;
    final endChanged = !widget.stay.isActive && end != originalEnd;
    final others = widget.admissionSegments
        .where((segment) => segment.id != widget.stay.id)
        .toList();

    if (!widget.stay.isActive) {
      final laterSegments =
          others
              .where(
                (segment) =>
                    segment.isActive ||
                    !segment.admissionDate.isBefore(originalStart),
              )
              .toList()
            ..sort((a, b) => a.admissionDate.compareTo(b.admissionDate));
      final next = laterSegments.firstOrNull;
      if (next != null && startChanged && start.isAfter(next.admissionDate)) {
        throw ArgumentError(
          'This previous stay cannot start on ${DateFormat('dd MMM yyyy, hh:mm a').format(start)} because ${next.roomNumber} starts on ${DateFormat('dd MMM yyyy, hh:mm a').format(next.admissionDate)}.',
        );
      }
      if (next != null && endChanged && end.isAfter(next.admissionDate)) {
        throw ArgumentError(
          'This stay must end on or before the shift to ${next.roomNumber} at ${DateFormat('dd MMM yyyy, hh:mm a').format(next.admissionDate)}.',
        );
      }
      return;
    }

    final previous = others.where((segment) => !segment.isActive).toList()
      ..sort((a, b) {
        final aEnd = a.completedAt ?? a.updatedAt;
        final bEnd = b.completedAt ?? b.updatedAt;
        return bEnd.compareTo(aEnd);
      });
    final preceding = previous.firstOrNull;
    if (preceding != null && startChanged) {
      final previousStart = preceding.admissionDate;
      final previousEnd = preceding.completedAt ?? preceding.updatedAt;
      if (start.isBefore(previousStart) || start.isBefore(previousEnd)) {
        throw ArgumentError(
          'The current stay cannot start before the previous ${preceding.roomNumber} stay ends at ${DateFormat('dd MMM yyyy, hh:mm a').format(previousEnd)}.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = rooms
        .where(
          (r) =>
              r.id == roomId ||
              r.roomIdentifier.trim().toLowerCase() ==
                  roomNumber.text.trim().toLowerCase(),
        )
        .firstOrNull;
    final choices = rooms
        .where(
          (r) =>
              _normalRoomType(r.roomType, roomIdentifier: r.roomIdentifier) ==
                  roomType &&
              (!widget.stay.isActive ||
                  r.beds.any(
                    (bed) =>
                        bed.isAvailable || bed.currentStayId == widget.stay.id,
                  ) ||
                  r.id == room?.id),
        )
        .toList();
    final beds = <BedModel>[];
    if (room != null) {
      if (widget.stay.isActive) {
        beds.addAll(
          BedHelper.selectableAvailableBeds(
            room,
            selectedBedIds: {if (bedId != null) bedId!},
          ),
        );
      } else {
        final labels = <String>{};
        for (final bed in room.beds) {
          final label = BedHelper.getBedDisplayName(
            bed.bedLabel,
            roomIdentifier: room.roomIdentifier,
          );
          if (labels.add(label)) beds.add(bed);
        }
      }
    }
    Widget actions() => Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: saving ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: saving || loading ? null : _save,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFA8CC7B)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF27500A).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF315F0C), Color(0xFF57951B)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_outlined, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit stay · ${widget.stay.roomNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const Text(
                        'Changes are saved only when you click Save',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    _photoEditor('Patient', photo, (value) => photo = value),
                  ],
                ),
                const SizedBox(height: 20),
                _grid([
                  _field('Registration number', registration),
                  _field('Patient name', name),
                  DropdownButtonFormField<String>(
                    initialValue: roomType,
                    isExpanded: true,
                    decoration: _decoration('Accommodation'),
                    items: const [
                      DropdownMenuItem(
                        value: 'private',
                        child: Text('Private room'),
                      ),
                      DropdownMenuItem(
                        value: 'general',
                        child: Text('Dormitory / general room'),
                      ),
                      DropdownMenuItem(value: 'lobby', child: Text('Lobby')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setState(() {
                            roomType = value!;
                            roomId = '';
                            bedId = null;
                            roomNumber.clear();
                            bedLabel.clear();
                            daily.clear();
                            longDaily.clear();
                          }),
                  ),
                  if (roomType != 'lobby')
                    DropdownButtonFormField<String>(
                      key: ValueKey('$roomType-$roomId'),
                      initialValue: choices.any((r) => r.id == room?.id)
                          ? room?.id
                          : null,
                      isExpanded: true,
                      decoration: _decoration('Room'),
                      items: choices
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.roomIdentifier),
                            ),
                          )
                          .toList(),
                      onChanged: saving || loading
                          ? null
                          : (value) => setState(() {
                              roomId = value!;
                              bedId = null;
                              roomNumber.text = choices
                                  .firstWhere((r) => r.id == value)
                                  .roomIdentifier;
                              bedLabel.clear();
                              daily.clear();
                              longDaily.clear();
                            }),
                    ),
                  if (roomType == 'lobby')
                    DropdownButtonFormField<String>(
                      key: ValueKey('lobby-${roomNumber.text}'),
                      initialValue: _lobbies.contains(roomNumber.text.trim())
                          ? roomNumber.text.trim()
                          : null,
                      isExpanded: true,
                      decoration: _decoration('Lobby'),
                      items: _lobbies
                          .map(
                            (lobby) => DropdownMenuItem(
                              value: lobby,
                              enabled:
                                  !widget.stay.isActive ||
                                  !occupiedLobbies.contains(lobby),
                              child: Text(
                                widget.stay.isActive &&
                                        occupiedLobbies.contains(lobby)
                                    ? '$lobby — Occupied'
                                    : lobby,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: saving || loading
                          ? null
                          : (value) => setState(() {
                              roomNumber.text = value ?? '';
                              roomId = value == null ? '' : 'lobby:$value';
                              bedId = null;
                              bedLabel.clear();
                            }),
                    ),
                  if (room != null && roomType != 'lobby')
                    DropdownButtonFormField<String>(
                      key: ValueKey('$roomId-$bedId'),
                      initialValue: beds.any((b) => b.id == bedId)
                          ? bedId
                          : null,
                      isExpanded: true,
                      decoration: _decoration('Bed'),
                      items: beds
                          .map(
                            (b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(
                                BedHelper.getBedDisplayName(
                                  b.bedLabel,
                                  roomIdentifier: room.roomIdentifier,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) => setState(() {
                              bedId = value;
                              bedLabel.text = beds
                                  .firstWhere((b) => b.id == value)
                                  .bedLabel;
                            }),
                    ),
                  _dateField('Admission date', true),
                  _dateField(
                    widget.stay.isActive ? 'Expected exit date' : 'Exit date',
                    false,
                  ),
                ]),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F9F0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD5E8C4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stay charge',
                        style: TextStyle(
                          color: Color(0xFF27500A),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'This amount is the charge for this room or lobby segment. Changing it overrides the automatic calculation.',
                        style: TextStyle(color: Color(0xFF66735D), fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      _grid([
                        _field('Charged amount', total, number: true),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Attendants',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF27500A),
                          fontSize: 15,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: saving
                          ? null
                          : () => setState(() {
                              attendants.add(_StayAttendant({}));
                              daily.clear();
                              longDaily.clear();
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add attendant'),
                    ),
                  ],
                ),
                for (final attendant in attendants)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F9F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _photoEditor(
                              attendant.name.text.trim().isEmpty
                                  ? 'Attendant'
                                  : attendant.name.text.trim(),
                              attendant.photo,
                              (value) => attendant.photo = value,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _grid([
                            _field('Attendant name', attendant.name),
                            _field('Relation', attendant.relation),
                            _field('Aadhaar number', attendant.aadhaar),
                            _field(
                              'Mobile number',
                              attendant.mobile,
                              phone: true,
                            ),
                          ]),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: attendant.isEmergency,
                            title: const Text('Emergency contact'),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: saving
                                ? null
                                : (value) => setState(() {
                                    for (final item in attendants) {
                                      item.isEmergency = false;
                                    }
                                    attendant.isEmergency = value ?? false;
                                  }),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: saving
                                  ? null
                                  : () => setState(() {
                                      attendants.remove(attendant);
                                      attendant.dispose();
                                      daily.clear();
                                      longDaily.clear();
                                    }),
                              icon: const Icon(
                                Icons.person_remove_outlined,
                                size: 18,
                              ),
                              label: const Text('Remove attendant'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                _field('Notes', notes),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const Divider(color: Color(0xFFE1EDD7)),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
