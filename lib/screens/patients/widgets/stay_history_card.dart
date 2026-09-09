import 'dart:convert';
import 'package:flutter/material.dart';
import 'photo_preview_dialog.dart';
import 'package:intl/intl.dart';
import '../../../models/patient_model.dart';
import '../../../models/stay_model.dart';
import '../../../utils/bed_helper.dart';
import '../../../models/room_model.dart';
import '../../../services/service_locator.dart';
import '../../../services/stay_history_service.dart';
import 'inline_stay_editor.dart';
import 'shift_timeline_editor.dart';

class StayHistoryCard extends StatefulWidget {
  final StayModel stay;
  final PatientModel patient;
  final Map<dynamic, dynamic> summary;
  final bool currentAdmission, multipleSegments;
  final List<StayModel> admissionSegments;
  final VoidCallback onPayments, onRefund;
  final Future<List<RoomModel>> Function()? loadRooms;
  final Future<void> Function(Map<String, dynamic>)? saveChanges;
  const StayHistoryCard({
    super.key,
    required this.stay,
    required this.patient,
    required this.summary,
    required this.currentAdmission,
    required this.multipleSegments,
    this.admissionSegments = const [],
    required this.onPayments,
    required this.onRefund,
    this.loadRooms,
    this.saveChanges,
  });
  @override
  State<StayHistoryCard> createState() => _StayHistoryCardState();
}

class _StayHistoryCardState extends State<StayHistoryCard> {
  StayModel? _draftSource;
  bool _editingTimeline = false;
  bool _deleting = false;

  Future<void> _deleteAdmission() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete stay card?'),
        content: Text(
          widget.admissionSegments.length > 1
              ? 'This deletes this admission and all ${widget.admissionSegments.length} room-shifting records. This cannot be undone.'
              : 'This deletes this stay record. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete stay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await StayHistoryService(
        ServiceLocator().rtdbService,
      ).deleteAdmission(widget.patient.id, widget.admissionSegments);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Stay card deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editingTimeline) {
      return ShiftTimelineEditor(
        patient: widget.patient,
        segments: widget.admissionSegments,
        summary: widget.summary,
        onCancel: () => setState(() => _editingTimeline = false),
        onSaved: () {
          if (!mounted) return;
          setState(() => _editingTimeline = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shifting timeline saved.')),
          );
        },
      );
    }
    if (_draftSource != null)
      return InlineStayEditor(
        key: ValueKey('edit-${_draftSource!.id}'),
        stay: _draftSource!,
        admissionSegments: widget.admissionSegments,
        loadRooms: widget.loadRooms,
        saveChanges: widget.saveChanges,
        onCancel: () => setState(() => _draftSource = null),
        onSaved: () {
          if (!mounted) return;
          setState(() => _draftSource = null);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Stay saved.')));
        },
      );
    return _StayHistoryCardView(
      stay: widget.stay,
      patient: widget.patient,
      summary: widget.summary,
      currentAdmission: widget.currentAdmission,
      multipleSegments: widget.multipleSegments,
      admissionSegments: widget.admissionSegments,
      onPayments: widget.onPayments,
      onRefund: widget.onRefund,
      onEdit: (stay) => setState(() => _draftSource = stay),
      onEditTimeline: () => setState(() => _editingTimeline = true),
      onDelete: _deleting ? null : _deleteAdmission,
    );
  }
}

/// The original stay-card layout, with the newer actions kept in its header.
class _StayHistoryCardView extends StatelessWidget {
  final StayModel stay;
  final PatientModel patient;
  final Map<dynamic, dynamic> summary;
  final bool currentAdmission;
  final bool multipleSegments;
  final List<StayModel> admissionSegments;
  final ValueChanged<StayModel> onEdit;
  final VoidCallback onEditTimeline;
  final VoidCallback? onDelete;
  final VoidCallback onPayments;
  final VoidCallback onRefund;
  const _StayHistoryCardView({
    required this.stay,
    required this.patient,
    required this.summary,
    required this.currentAdmission,
    required this.multipleSegments,
    required this.admissionSegments,
    required this.onEdit,
    required this.onEditTimeline,
    required this.onDelete,
    required this.onPayments,
    required this.onRefund,
  });

  Widget _detail(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAF4),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE1EDD7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: const Color(0xFF639922).withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF639922),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? const Color(0xFF27500A),
          ),
        ),
      ],
    ),
  );

  Widget _photo(BuildContext context, String label, dynamic source) {
    if (source is! String || source.isEmpty) return const SizedBox.shrink();
    try {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(50),
            onTap: () => showPhotoPreview(
              context,
              photoBytes: base64Decode(source.split(',').last),
              title: label,
            ),
            child: ClipOval(
              child: Image.memory(
                base64Decode(source.split(',').last),
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Color(0xFF27500A))),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _attendant(BuildContext context, dynamic raw, String fallback) {
    final map = raw is Map ? raw : const {};
    final name = map['name']?.toString().trim();
    final relation = map['relation']?.toString().trim();
    final snapshotMobile = map['mobileNumber']?.toString().trim();
    final aadhaar = map['aadhaarNumber']?.toString().trim();
    AttendantModel? currentAttendant;
    if (currentAdmission && name?.isNotEmpty == true) {
      for (final attendant in patient.attendants ?? const <AttendantModel>[]) {
        if (attendant.name.trim().toLowerCase() == name!.toLowerCase()) {
          currentAttendant = attendant;
          break;
        }
      }
    }
    final currentMobile = currentAttendant?.mobileNumber?.trim();
    final mobile = snapshotMobile?.isNotEmpty == true
        ? snapshotMobile
        : currentMobile?.isNotEmpty == true
        ? currentMobile
        : null;
    final emergency =
        map['isEmergencyContact'] == true ||
        currentAttendant?.isEmergencyContact == true;
    final label = name?.isNotEmpty == true
        ? '$name${relation?.isNotEmpty == true ? ' ($relation)' : ''}'
        : fallback;
    ImageProvider? image;
    final source = map['photoDataUrl']?.toString();
    if (source?.isNotEmpty == true) {
      try {
        image = MemoryImage(base64Decode(source!.split(',').last));
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F0),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: image != null
                ? () => showPhotoPreview(
                    context,
                    photoBytes: base64Decode(source!.split(',').last),
                    title: label,
                  )
                : null,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEAF3E1),
              backgroundImage: image,
              child: image == null
                  ? const Icon(
                      Icons.person_outline,
                      size: 20,
                      color: Color(0xFF639922),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF27500A),
                    ),
                  ),
                  if (emergency) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.emergency_outlined,
                      size: 15,
                      color: Color(0xFFD46B25),
                    ),
                  ],
                ],
              ),
              Text(
                [
                  mobile?.isNotEmpty == true ? mobile! : 'N/A',
                  if (aadhaar?.isNotEmpty == true) 'Aadhaar $aadhaar',
                ].join('  •  '),
                style: const TextStyle(fontSize: 11, color: Color(0xFF647356)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active =
        stay.isActive && patient.status.toLowerCase() != 'discharged';
    final money = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final date = DateFormat('dd MMM yyyy, hh:mm a');
    final orderedSegments = [...admissionSegments]
      ..sort((a, b) {
        final byStart = a.admissionDate.compareTo(b.admissionDate);
        if (byStart != 0) return byStart;
        if (a.isActive != b.isActive) return a.isActive ? 1 : -1;
        return 0;
      });
    final admissionStart = orderedSegments.isEmpty
        ? stay.admissionDate
        : orderedSegments.first.admissionDate;
    final lastSegment = orderedSegments.isEmpty ? stay : orderedSegments.last;
    final exit = active
        ? patient.exitDate
        : lastSegment.completedAt ?? lastSegment.updatedAt;
    final total =
        (summary['total'] as num?)?.toDouble() ??
        (currentAdmission
            ? patient.advanceBilledAmount + patient.attendanceCharges
            : stay.totalCost);
    final paid =
        (summary['netPaid'] as num?)?.toDouble() ??
        (currentAdmission
            ? patient.totalPaidAmount ?? 0
            : stay.paidAmount ?? 0);
    final pending =
        (summary['due'] as num?)?.toDouble() ??
        (total - paid).clamp(0.0, double.infinity);
    final refund =
        (summary['refundDue'] as num?)?.toDouble() ??
        (paid - total).clamp(0.0, double.infinity);
    final refunded = (summary['refunded'] as num?)?.toDouble() ?? 0;
    final registration =
        stay.patientSnapshot['registrationNumber']?.toString() ??
        (currentAdmission ? patient.registrationNumber : null);
    final segmentCharges = summary['segmentCharges'];
    final segmentDays = summary['segmentDays'];
    final attendants = stay.patientSnapshot['attendants'];
    final labels = attendants is List
        ? [
            for (final a in attendants)
              if (a is Map)
                '${a['name'] ?? ''}${a['relation']?.toString().trim().isNotEmpty == true ? ' (${a['relation']})' : ''}',
          ]
        : stay.attendantLabels;
    final hasPatientPhoto =
        stay.patientSnapshot['photoDataUrl']?.toString().isNotEmpty ?? false;
    final isShiftSegment =
        stay.notes?.trim().toLowerCase().startsWith('shifted from ') == true;
    final effectiveBedLabel = stay.bedLabel?.isNotEmpty == true
        ? stay.bedLabel
        : currentAdmission && patient.roomNumber == stay.roomNumber
        ? patient.bedLabels?.firstOrNull
        : null;
    final placement = stay.roomType == 'lobby'
        ? (stay.roomNumber.toLowerCase().contains('lobby')
              ? stay.roomNumber
              : 'Lobby ${stay.roomNumber}')
        : 'Room ${stay.roomNumber} • ${effectiveBedLabel?.isNotEmpty == true ? BedHelper.getBedDisplayName(effectiveBedLabel!, roomIdentifier: stay.roomNumber) : 'Bed not recorded'}';
    String segmentPlacement(StayModel segment) {
      if (segment.roomType == 'lobby') {
        return segment.roomNumber.toLowerCase().contains('lobby')
            ? segment.roomNumber
            : 'Lobby ${segment.roomNumber}';
      }
      final savedOrCurrentBed = segment.bedLabel?.isNotEmpty == true
          ? segment.bedLabel
          : segment.isActive &&
                currentAdmission &&
                patient.roomNumber == segment.roomNumber
          ? patient.bedLabels?.firstOrNull
          : null;
      final bed = savedOrCurrentBed?.isNotEmpty == true
          ? BedHelper.getBedDisplayName(
              savedOrCurrentBed!,
              roomIdentifier: segment.roomNumber,
            )
          : 'Bed not recorded';
      return 'Room ${segment.roomNumber} • $bed';
    }

    double chargeFor(StayModel segment) => segmentCharges is Map
        ? (segmentCharges[segment.id] as num?)?.toDouble() ?? segment.totalCost
        : segment.totalCost;

    int? daysFor(StayModel segment) =>
        segmentDays is Map ? (segmentDays[segment.id] as num?)?.toInt() : null;
    final fields = [
      _detail(
        'Admission date',
        date.format(admissionStart),
        Icons.calendar_today_rounded,
      ),
      _detail(
        active ? 'Planned exit date' : 'Actual discharge date',
        exit == null ? 'Not decided' : date.format(exit),
        Icons.event_available_rounded,
      ),
      _detail('Total amount', money.format(total), Icons.payments_outlined),
      _detail(
        'Paid amount',
        money.format(paid),
        Icons.account_balance_wallet_outlined,
      ),
      _detail(
        'Pending amount',
        money.format(pending),
        Icons.pending_actions_outlined,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? const Color(0xFFA8CC7B) : const Color(0xFFCBD7C1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF27500A).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: active
                    ? const [Color(0xFF315F0C), Color(0xFF57951B)]
                    : const [Color(0xFF526348), Color(0xFF718265)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(19),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    stay.roomType == 'lobby'
                        ? Icons.weekend_outlined
                        : Icons.bed_outlined,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    placement,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Edit stay and payment actions',
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  onSelected: (value) {
                    if (value.startsWith('edit:')) {
                      final id = value.substring(5);
                      final selected = admissionSegments
                          .where((segment) => segment.id == id)
                          .firstOrNull;
                      onEdit(selected ?? stay);
                    }
                    if (value == 'timeline') onEditTimeline();
                    if (value == 'payments') onPayments();
                    if (value == 'refund') onRefund();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (multipleSegments)
                      for (final segment in orderedSegments)
                        PopupMenuItem(
                          value: 'edit:${segment.id}',
                          child: Text(
                            'Edit ${segment.roomType == 'lobby' ? segment.roomNumber : 'Room ${segment.roomNumber}'} details',
                          ),
                        )
                    else
                      PopupMenuItem(
                        value: 'edit:${stay.id}',
                        child: const Text('Edit stay'),
                      ),
                    if (multipleSegments)
                      const PopupMenuItem(
                        value: 'timeline',
                        child: Text('Edit shifting timeline'),
                      ),
                    const PopupMenuItem(
                      value: 'payments',
                      child: Text('Edit payments / receipts'),
                    ),
                    if (refund > 0)
                      const PopupMenuItem(
                        value: 'refund',
                        child: Text('Record refund paid'),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: onDelete != null,
                      child: const Text(
                        'Delete stay card',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    active ? 'ACTIVE OCCUPANCY' : 'DISCHARGED',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasPatientPhoto) ...[
                        _photo(
                          context,
                          stay.patientName,
                          stay.patientSnapshot['photoDataUrl'],
                        ),
                      ] else
                        const CircleAvatar(
                          radius: 32,
                          backgroundColor: Color(0xFFEAF3E1),
                          child: Icon(
                            Icons.person_outline,
                            color: Color(0xFF639922),
                            size: 32,
                          ),
                        ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            stay.patientName,
                            style: const TextStyle(
                              color: Color(0xFF27500A),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF3E1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Registration No. ${registration?.isNotEmpty == true ? registration : 'Not recorded'}',
                              style: const TextStyle(
                                color: Color(0xFF3B6D11),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 720
                        ? 3
                        : constraints.maxWidth >= 440
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 10) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 16,
                      children: [
                        for (final field in fields)
                          SizedBox(width: width, child: field),
                      ],
                    );
                  },
                ),
                if (labels.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        _attendant(
                          context,
                          attendants is List && i < attendants.length
                              ? attendants[i]
                              : null,
                          labels[i],
                        ),
                    ],
                  ),
                ],
                if (isShiftSegment) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF1D39A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.swap_horiz_rounded,
                          color: Color(0xFFB46A00),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            stay.notes!,
                            style: const TextStyle(
                              color: Color(0xFF714400),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (refund > 0) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Payment exceeded · Refund due: ${money.format(refund)}',
                        style: const TextStyle(
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: onRefund,
                        child: const Text('Record refund paid'),
                      ),
                    ],
                  ),
                ],
                if (refunded > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Refunded: ${money.format(refunded)}',
                      style: const TextStyle(color: Color(0xFF27500A)),
                    ),
                  ),
                if (multipleSegments ||
                    stay.notes?.isNotEmpty == true ||
                    stay.extensions.isNotEmpty)
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Stay details',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF27500A),
                        ),
                      ),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F9F0),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE1EDD7)),
                          ),
                          child: multipleSegments
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ROOM SHIFTING HISTORY',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                        color: Color(0xFF639922),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    for (
                                      var index = 0;
                                      index < orderedSegments.length;
                                      index++
                                    ) ...[
                                      Builder(
                                        builder: (context) {
                                          final segment =
                                              orderedSegments[index];
                                          final segmentEnd =
                                              segment.completedAt ??
                                              (segment.isActive
                                                  ? patient.exitDate
                                                  : segment.updatedAt);
                                          final days = daysFor(segment);
                                          final charge = chargeFor(segment);
                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: CircleAvatar(
                                              radius: 15,
                                              backgroundColor: const Color(
                                                0xFFE6F1DC,
                                              ),
                                              child: Text('${index + 1}'),
                                            ),
                                            title: Text(
                                              segmentPlacement(segment),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF27500A),
                                              ),
                                            ),
                                            subtitle: Text(
                                              '${DateFormat('dd MMM, hh:mm a').format(segment.admissionDate)} → ${segmentEnd == null ? 'Current' : DateFormat('dd MMM, hh:mm a').format(segmentEnd)}\n${money.format(charge)}${days == null ? '' : ' · $days day${days == 1 ? '' : 's'}'}',
                                            ),
                                          );
                                        },
                                      ),
                                      if (index < orderedSegments.length - 1)
                                        const Divider(height: 1),
                                    ],
                                  ],
                                )
                              : Wrap(
                                  spacing: 28,
                                  runSpacing: 14,
                                  children: [
                                    _detail(
                                      'PLACEMENT PERIOD',
                                      '${DateFormat('dd MMM, hh:mm a').format(stay.admissionDate)} → ${DateFormat('dd MMM, hh:mm a').format(exit ?? stay.updatedAt)}',
                                      Icons.date_range_outlined,
                                    ),
                                    if (stay.dailyRate != null)
                                      _detail(
                                        'DAILY ROOM RATE',
                                        money.format(stay.dailyRate),
                                        Icons.currency_rupee,
                                      ),
                                    if (stay.notes?.isNotEmpty == true &&
                                        !isShiftSegment)
                                      _detail(
                                        'NOTES',
                                        stay.notes!,
                                        Icons.notes_outlined,
                                      ),
                                  ],
                                ),
                        ),
                        for (final extension in stay.extensions)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history_rounded),
                            title: Text(
                              'Extended by ${extension.additionalDays} days on ${date.format(extension.extendedOn)}',
                            ),
                            subtitle: Text(extension.reason),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
