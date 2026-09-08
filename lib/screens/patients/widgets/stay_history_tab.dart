import 'package:flutter/material.dart';
import '../../../models/patient_model.dart';
import '../../../models/stay_model.dart';
import '../../../services/service_locator.dart';
import '../../../utils/stay_billing.dart';
import 'edit_patient_dialog.dart';
import 'refund_dialog.dart';
import 'stay_history_card.dart';

class StayHistoryTab extends StatefulWidget {
  final PatientModel patient;
  final VoidCallback onPayments;
  const StayHistoryTab({
    super.key,
    required this.patient,
    required this.onPayments,
  });
  @override
  State<StayHistoryTab> createState() => _StayHistoryTabState();
}

class _StayHistoryTabState extends State<StayHistoryTab> {
  late final Stream<List<StayModel>> stream;
  @override
  void initState() {
    super.initState();
    stream = ServiceLocator().roomService.getStaysByPatientStream(
      widget.patient.id,
    );
    ServiceLocator().paymentService
        .recalculatePatientAttendanceAndBilling(widget.patient.id)
        .catchError((Object _) {});
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF27500A),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<List<StayModel>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Center(
          child: Text('Could not load stay history: ${snapshot.error}'),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final stays = [...snapshot.data!]
        ..sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
      if (stays.isEmpty)
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No saved stays. Assign a room or lobby to start stay history.',
              ),
              TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => EditPatientDialog(patient: widget.patient),
                ),
                child: const Text('Edit patient details'),
              ),
            ],
          ),
        );
      final currentCycle = StayBilling.currentCycle(widget.patient);
      final activeAdmission =
          widget.patient.status.toLowerCase() != 'discharged';
      final groups = <String, List<StayModel>>{};
      for (final stay in stays) {
        final cycle = StayBilling.cycleFor(stay, widget.patient);
        groups.putIfAbsent(cycle, () => []).add(stay);
      }
      for (final group in groups.values) {
        group.sort((a, b) => a.admissionDate.compareTo(b.admissionDate));
      }
      final currentAdmissionSegments = activeAdmission
          ? groups.remove(currentCycle) ?? const <StayModel>[]
          : const <StayModel>[];
      final historyGroups = groups.entries.toList()
        ..sort(
          (a, b) => b.value.first.admissionDate.compareTo(
            a.value.first.admissionDate,
          ),
        );
      Widget card(List<StayModel> segments, {required bool isCurrent}) {
        final primary = isCurrent
            ? segments.where((segment) => segment.isActive).firstOrNull ??
                  segments.last
            : segments.last;
        final cycle = StayBilling.cycleFor(primary, widget.patient);
        final saved = widget.patient.admissionBalances[cycle];
        return Padding(
          key: ValueKey(cycle),
          padding: const EdgeInsets.only(bottom: 16),
          child: StayHistoryCard(
            stay: primary,
            patient: widget.patient,
            summary: saved is Map ? saved : primary.billingSummary,
            currentAdmission: isCurrent,
            multipleSegments: segments.length > 1,
            admissionSegments: segments,
            onPayments: widget.onPayments,
            onRefund: () =>
                showRefundDialog(context, widget.patient, cycleId: cycle),
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (currentAdmissionSegments.isNotEmpty) ...[
            _heading('Current Stay'),
            card(currentAdmissionSegments, isCurrent: true),
            const SizedBox(height: 16),
          ],
          if (historyGroups.isNotEmpty) ...[
            _heading('Stay History'),
            ...historyGroups.map(
              (entry) => card(entry.value, isCurrent: false),
            ),
          ],
        ],
      );
    },
  );
}
