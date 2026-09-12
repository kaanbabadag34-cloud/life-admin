import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance =
      NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();

    final timezoneInfo =
        await FlutterTimezone.getLocalTimezone();

    tz.setLocalLocation(
      tz.getLocation(
        timezoneInfo.identifier,
      ),
    );

    const androidSettings =
        AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings =
        DarwinInitializationSettings();

    const initializationSettings =
        InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initializationSettings,
    );

    await requestPermissions();
  }

  Future<void> requestPermissions() async {
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<void> schedulePlanReminder({
    required int id,
    required String title,
    required DateTime planDateTime,
    required int minutesBefore,
  }) async {
    final reminderTime = planDateTime.subtract(
      Duration(
        minutes: minutesBefore,
      ),
    );

    if (reminderTime.isBefore(
      DateTime.now(),
    )) {
      return;
    }

    final scheduledDate =
        tz.TZDateTime.from(
      reminderTime,
      tz.local,
    );

    await _notifications.zonedSchedule(
      id: id,
      title: 'Yaklaşan plan',
      body: title,
      scheduledDate: scheduledDate,
      notificationDetails:
          const NotificationDetails(
        android: AndroidNotificationDetails(
          'plan_reminders',
          'Plan Hatırlatıcıları',
          channelDescription:
              'Planlardan önce gönderilen hatırlatıcılar',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode:
          AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelReminder(
    int id,
  ) async {
    await _notifications.cancel(
      id: id,
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}