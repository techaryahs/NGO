import 'package:flutter/material.dart';

import '../../../models/bed_model.dart';
import '../../../models/patient_model.dart';
import '../../../models/room_model.dart';
import '../../../models/stay_model.dart';
import '../../../services/service_locator.dart';
import '../../../utils/bed_helper.dart';
import '../../../utils/pricing_helper.dart';

class _Placement {
  final RoomModel? room;
  final BedModel? bed;
  final String? lobby;
  final bool occupied;
  const _Placement.bed(this.room, this.bed) : lobby = null, occupied = false;
  const _Placement.lobby(this.lobby, {this.occupied = false})
    : room = null,
      bed = null;

  String get label => room != null
      ? '${room!.roomIdentifier} · ${BedHelper.getBedDisplayName(bed!.bedLabel, roomIdentifier: room!.roomIdentifier)} · Floor ${room!.floor}'
      : '$lobby${occupied ? ' — Occupied' : ''}';
}

Future<bool> showShiftPatientDialog(
  BuildContext context,
  PatientModel patient,
) async {
  final roomService = ServiceLocator().roomService;
  final results = await Future.wait<dynamic>([
    roomService.getRoomsStream().first,
    roomService.getStaysStream().first,
  ]);
  final rooms = results[0] as List<RoomModel>;
  final stays = results[1] as List<StayModel>;
  final occupiedLobbies = {
    for (final stay in stays)
      if (stay.isActive &&
          stay.roomType == 'lobby' &&
          stay.patientId != patient.id)
        stay.roomNumber,
  };
  const lobbies = [
    '1D Lobby 1',
    '1D Lobby 2',
    '1B Lobby 1',
    '1B Lobby 2',
    '2E Lobby 1',
    '2E Lobby 2',
    '2B Lobby 1',
    '2B Lobby 2',
  ];
  final placements = <_Placement>[
    for (final room in rooms)
      if (room.status != 'maintenance' && room.status != 'unavailable')
        for (final bed in BedHelper.selectableAvailableBeds(room))
          _Placement.bed(room, bed),
    for (final lobby in lobbies)
      _Placement.lobby(lobby, occupied: occupiedLobbies.contains(lobby)),
  ];
  if (!context.mounted) return false;
  _Placement? selected;
  final choice = await showDialog<_Placement>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Shift ${patient.fullName}'),
        content: SizedBox(
          width: 560,
          height: 430,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: ${patient.lobby ?? patient.roomNumber ?? 'Unassigned'}${patient.bedLabels?.isNotEmpty == true ? ' · ${patient.bedLabels!.map((b) => BedHelper.getBedDisplayName(b, roomIdentifier: patient.roomNumber)).join(', ')}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('Select the new available room, bed, or lobby.'),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: [
                    const Text(
                      'AVAILABLE ROOM BEDS',
                      style: TextStyle(
                        color: Color(0xFF3B6D11),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final placement in placements.where(
                      (p) => p.room != null,
                    ))
                      RadioListTile<_Placement>(
                        value: placement,
                        groupValue: selected,
                        onChanged: (value) => setState(() => selected = value),
                        title: Text(placement.label),
                      ),
                    const Divider(),
                    const Text(
                      'LOBBIES',
                      style: TextStyle(
                        color: Color(0xFF3B6D11),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    for (final placement in placements.where(
                      (p) => p.lobby != null,
                    ))
                      RadioListTile<_Placement>(
                        value: placement,
                        groupValue: selected,
                        onChanged: placement.occupied
                            ? null
                            : (value) => setState(() => selected = value),
                        title: Text(placement.label),
                        secondary: placement.occupied
                            ? const Icon(Icons.lock_outline, color: Colors.grey)
                            : const Icon(Icons.weekend_outlined),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: selected == null
                ? null
                : () => Navigator.pop(dialogContext, selected),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;

  final total = patient.advanceBilledAmount + patient.attendanceCharges;
  final paid = patient.totalPaidAmount ?? 0;
  final pending = (total - paid).clamp(0.0, double.infinity);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Confirm room shift'),
      content: Text(
        '${pending > 0 ? '₹${pending.toStringAsFixed(0)} from the current admission remains unpaid. It will remain in the admission balance and new room charges will be added.\n\n' : ''}'
        'Shift to ${choice.label}?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Shift patient'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final shiftTime = DateTime.now();
  final activeStays = stays
      .where((stay) => stay.patientId == patient.id && stay.isActive)
      .toList();
  for (final stay in activeStays) {
    await roomService.completeStay(stay.id, completedAt: shiftTime);
  }
  final labels = (patient.attendants ?? const <AttendantModel>[])
      .map(
        (a) => a.relation?.trim().isNotEmpty == true
            ? '${a.name} (${a.relation})'
            : a.name,
      )
      .toList();
  final from = patient.lobby ?? patient.roomNumber ?? 'Unassigned';
  if (choice.room != null) {
    await roomService.createStay(
      patientId: patient.id,
      patientName: patient.fullName,
      roomId: choice.room!.id,
      roomNumber: choice.room!.roomIdentifier,
      roomType: choice.room!.roomType,
      admissionDate: shiftTime,
      durationDays: PricingHelper.advanceDays,
      attendantCount: patient.attendants?.length ?? 0,
      attendantLabels: labels,
      bedId: choice.bed!.id,
      bedLabel: choice.bed!.bedLabel,
      notes: 'Shifted from $from to ${choice.label}',
      createdBy: ServiceLocator().authRestService.currentUser?.uid ?? 'system',
    );
    await ServiceLocator().patientService.updatePatient(patient.id, {
      'roomId': choice.room!.id,
      'roomNumber': choice.room!.roomIdentifier,
      'floor': choice.room!.floor,
      'bedIds': [choice.bed!.id],
      'bedLabels': [choice.bed!.bedLabel],
      'lobby': null,
      'billingAmountOverride': null,
    });
  } else {
    await roomService.createLobbyStay(
      patientId: patient.id,
      patientName: patient.fullName,
      lobbyName: choice.lobby!,
      admissionDate: shiftTime,
      durationDays: PricingHelper.advanceDays,
      attendantCount: patient.attendants?.length ?? 0,
      attendantLabels: labels,
      createdBy: ServiceLocator().authRestService.currentUser?.uid ?? 'system',
    );
    await ServiceLocator().patientService.updatePatient(patient.id, {
      'roomId': null,
      'roomNumber': null,
      'floor': int.tryParse(choice.lobby![0]),
      'bedIds': null,
      'bedLabels': null,
      'lobby': choice.lobby,
      'billingAmountOverride': null,
    });
  }
  await ServiceLocator().paymentService.recalculatePatientAttendanceAndBilling(
    patient.id,
  );
  return true;
}
