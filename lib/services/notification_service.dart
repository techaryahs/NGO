import 'dart:async';
import '../models/notification_model.dart';
import '../models/patient_model.dart';
import 'patient_service.dart';

class NotificationService {
  final PatientService _patientService;
  final Set<String> _readIds = {};
  final Set<String> _deletedIds = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  NotificationService({required PatientService patientService})
    : _patientService = patientService;

  /// Stream of active notifications generated dynamically from patients
  Stream<List<NotificationModel>> getNotificationsStream() {
    return Stream.multi((controller) {
      List<PatientModel>? currentPatients;

      void emitNotifications() {
        if (currentPatients != null) {
          controller.add(_buildNotifications(currentPatients!));
        }
      }

      final patientSubscription = _patientService.getPatientsStream().listen((
        patients,
      ) {
        currentPatients = patients;
        emitNotifications();
      }, onError: controller.addError);
      final changesSubscription = _changes.stream.listen((_) {
        emitNotifications();
      });

      controller.onCancel = () async {
        await patientSubscription.cancel();
        await changesSubscription.cancel();
      };
    });
  }

  List<NotificationModel> _buildNotifications(List<PatientModel> patients) {
    final List<NotificationModel> notifications = [];
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    for (var patient in patients) {
      // Skip discharged patients
      if (patient.status == 'discharged') continue;

      // 1. Check for Overdue Payments
      if ((patient.currentDueAmount ?? 0) > 0 &&
          patient.paymentDueDate != null) {
        final dueDateOnly = DateTime(
          patient.paymentDueDate!.year,
          patient.paymentDueDate!.month,
          patient.paymentDueDate!.day,
        );

        if (dueDateOnly.isBefore(todayDateOnly)) {
          final daysOverdue = todayDateOnly.difference(dueDateOnly).inDays;
          final id = '${patient.id}_payment_overdue';
          if (!_deletedIds.contains(id))
            notifications.add(
              NotificationModel(
                id: id,
                title: 'Payment Overdue',
                message:
                    '${patient.fullName} payment overdue by $daysOverdue days (₹${patient.currentDueAmount})',
                type: NotificationType.paymentPending,
                createdAt: today,
                isRead: _readIds.contains(id),
                patientId: patient.id,
                amount: patient.currentDueAmount,
              ),
            );
        }
      } else if ((patient.currentDueAmount ?? 0) > 0) {
        // Fallback if currentDueAmount > 0 but no due date, maybe treat as pending
        final id = '${patient.id}_payment_pending';
        if (!_deletedIds.contains(id))
          notifications.add(
            NotificationModel(
              id: id,
              title: 'Payment Pending',
              message:
                  '${patient.fullName} has pending payment of ₹${patient.currentDueAmount}',
              type: NotificationType.paymentPending,
              createdAt: today,
              isRead: _readIds.contains(id),
              patientId: patient.id,
              amount: patient.currentDueAmount,
            ),
          );
      }

      // 2. Check for Stay Ending (uses PRESENT days only)
      final int allowedDays =
          (patient.maxStayDays ?? 60) + (patient.extensionDays ?? 0);
      final int presentDays = patient.totalPresentDays;
      final int remainingDays = allowedDays - presentDays;

      if (remainingDays <= 10 && remainingDays >= 0) {
        final id = '${patient.id}_stay_ending';
        if (!_deletedIds.contains(id))
          notifications.add(
            NotificationModel(
              id: id,
              title: 'Stay Ending Soon',
              message:
                  '${patient.fullName} stay period ending in $remainingDays present days',
              type: NotificationType.stayEnding,
              createdAt: today,
              isRead: _readIds.contains(id),
              patientId: patient.id,
            ),
          );
      } else if (remainingDays < 0) {
        final id = '${patient.id}_stay_ended';
        if (!_deletedIds.contains(id))
          notifications.add(
            NotificationModel(
              id: id,
              title: 'Stay Limit Exceeded',
              message:
                  '${patient.fullName} has exceeded the $allowedDays present days limit by ${remainingDays.abs()} days',
              type: NotificationType
                  .stayEnding, // Use same visual type (orange/red)
              createdAt: today,
              isRead: _readIds.contains(id),
              patientId: patient.id,
            ),
          );
      }
    }

    // Sort notifications: unread first, then payment pending, then stay ending
    notifications.sort((a, b) {
      if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
      if (a.type != b.type) return a.type.index.compareTo(b.type.index);
      return 0;
    });

    return notifications;
  }

  void markAsRead(String id) {
    _readIds.add(id);
    _changes.add(null);
  }

  void markAllAsRead(List<String> ids) {
    _readIds.addAll(ids);
    _changes.add(null);
  }

  void deleteNotification(String id) {
    _deletedIds.add(id);
    _changes.add(null);
  }
}
