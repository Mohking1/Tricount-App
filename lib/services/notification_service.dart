import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles local notifications. No realtime subscriptions.
/// Notifications are triggered by DataProvider when it detects
/// new expenses during a sync refresh.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localNotifications.initialize(initSettings);
  }

  /// Show a notification for a new/updated expense.
  Future<void> showExpenseNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'tricount_updates',
      'Tricount Updates',
      channelDescription: 'Notifications for group expenses',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
    );
  }

  /// Show a generic notification.
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    await showExpenseNotification(title: title, body: body);
  }
}
