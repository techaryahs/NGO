import 'package:flutter/material.dart';
import '../../../models/notification_model.dart';
import '../../../services/service_locator.dart';

class TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;

  const TopBar({
    super.key,
    required this.title,
    required this.onProfileTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final authService = ServiceLocator().authService;
    final user = authService.currentUser;
    final initials = user?.email.substring(0, 2).toUpperCase() ?? "AD";

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFDf7),
        border: Border(
          bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF27500A),
            ),
          ),
          Row(
            children: [
              const _NotificationBell(),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                offset: const Offset(0, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFC0DD97), width: 1),
                ),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF3B6D11),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEAF3DE),
                    ),
                  ),
                ),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.email ?? "admin@ngo.org",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "Super Admin",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF639922),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Color(0xFFC0DD97)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'profile',
                    child: Row(
                      children: const [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                          color: Color(0xFF3B6D11),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Profile",
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF27500A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: const [
                        Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: Color(0xFF3B6D11),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Settings",
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF27500A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: const [
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: Color(0xFFD32F2F),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Logout",
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFD32F2F),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'logout') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Logout"),
                        content: const Text("Are you sure you want to logout?"),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("Cancel"),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B6D11),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Logout"),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      await authService.signOut();
                    }
                  } else if (value == 'profile') {
                    onProfileTap();
                  } else if (value == 'settings') {
                    onSettingsTap();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void showNotificationPanel(
  BuildContext context,
  List<NotificationModel> notifications,
) {
  showDialog(
    context: context,
    builder: (context) => _NotificationPanel(notifications: notifications),
  );
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({Key? key}) : super(key: key);

  void _showNotificationPanel(
    BuildContext context,
    List<NotificationModel> notifications,
  ) {
    showNotificationPanel(context, notifications);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NotificationModel>>(
      stream: ServiceLocator().notificationService.getNotificationsStream(),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final unreadCount = notifications.where((n) => !n.isRead).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: () => _showNotificationPanel(context, notifications),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3DE),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFC0DD97),
                    width: 0.5,
                  ),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: Color(0xFF3B6D11),
                  size: 18,
                ),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD32F2F),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NotificationPanel extends StatefulWidget {
  final List<NotificationModel> notifications;
  const _NotificationPanel({required this.notifications});

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  late List<NotificationModel> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = List.of(widget.notifications);
  }

  void _markAsRead(NotificationModel notification) {
    if (notification.isRead) return;
    ServiceLocator().notificationService.markAsRead(notification.id);
    setState(() {
      _notifications = _notifications
          .map(
            (item) =>
                item.id == notification.id ? item.copyWith(isRead: true) : item,
          )
          .toList();
    });
  }

  void _markAllAsRead() {
    ServiceLocator().notificationService.markAllAsRead(
      _notifications
          .where((item) => !item.isRead)
          .map((item) => item.id)
          .toList(),
    );
    setState(
      () => _notifications = _notifications
          .map((item) => item.copyWith(isRead: true))
          .toList(),
    );
  }

  Future<void> _delete(NotificationModel notification) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text(
          'This notification will be removed from this session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ServiceLocator().notificationService.deleteNotification(notification.id);
      setState(
        () => _notifications.removeWhere((item) => item.id == notification.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 500),
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F7EA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFC0DD97), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Notifications",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF27500A),
                    ),
                  ),
                  if (_notifications.any((n) => !n.isRead))
                    TextButton(
                      onPressed: _markAllAsRead,
                      child: const Text(
                        "Mark all read",
                        style: TextStyle(color: Color(0xFF3B6D11)),
                      ),
                    ),
                ],
              ),
            ),
            if (_notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40.0),
                child: Text(
                  "No new notifications.",
                  style: TextStyle(color: Color(0xFF639922)),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final isPayment =
                        notification.type == NotificationType.paymentPending;

                    return InkWell(
                      onTap: () {
                        _markAsRead(notification);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: notification.isRead
                              ? Colors.transparent
                              : Colors.white,
                          border: const Border(
                            bottom: BorderSide(
                              color: Color(0xFFC0DD97),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: isPayment
                                  ? const Color(0xFFFFEBEE)
                                  : const Color(0xFFFFF3E0),
                              child: Icon(
                                isPayment
                                    ? Icons.payment_rounded
                                    : Icons.calendar_today_rounded,
                                color: isPayment
                                    ? const Color(0xFFD32F2F)
                                    : const Color(0xFFF57C00),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notification.title,
                                    style: TextStyle(
                                      fontWeight: notification.isRead
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                      color: const Color(0xFF27500A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    notification.message,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF639922),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!notification.isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD32F2F),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 19,
                                color: Color(0xFFD32F2F),
                              ),
                              tooltip: 'Delete notification',
                              onPressed: () => _delete(notification),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
