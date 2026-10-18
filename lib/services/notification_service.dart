import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../utils/reminder_format.dart';
import 'reminder_plan.dart';

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

    // İzin, uygulama açılışında değil kullanıcı ilk kez bir hatırlatıcı
    // kurduğunda istenir (schedulePlanReminder). Böylece açılışta izin
    // bombardımanı olmaz.
  }

  // Plan başına SABİT bildirim kimliği: aynı plan için tekrar planlama aynı
  // kimliğin üzerine yazar (çift bildirim oluşmaz). Plan başlığı/tarihi
  // değişse bile kimlik değişmez.
  static int reminderIdFor(String planId) => reminderNotificationId(planId);

  static const String _appEnabledKey = 'notifications_enabled_by_app';
  static const String _ownerKey = 'notifications_owner_user_id';

  // Bekleyen bildirimlerin hangi kullanıcıya ait olduğu (cihazda). Hesap
  // değişirse eski kullanıcının bildirimleri temizlenir.
  Future<String?> getOwner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_ownerKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> setOwner(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (userId == null) {
        await prefs.remove(_ownerKey);
      } else {
        await prefs.setString(_ownerKey, userId);
      }
    } catch (_) {}
  }

  Future<List<PendingReminder>> pendingReminders() async {
    try {
      final pending = await _notifications.pendingNotificationRequests();
      return [for (final p in pending) PendingReminder(p.id, p.payload)];
    } catch (_) {
      return [];
    }
  }

  // Uygulama içi tercih (iOS sistem iznini DEĞİŞTİRMEZ): kapalıyken Life Admin
  // hiçbir yerel bildirim planlamaz. Varsayılan açık.
  Future<bool> isAppEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_appEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setAppEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_appEnabledKey, value);
    } catch (_) {}
  }

  // Bildirim izni şu an açık mı? (izin PENCERESİ AÇMAZ)
  Future<bool> notificationsAllowed() async {
    try {
      final options = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.checkPermissions();

      // iOS dışında (veya bilgi yoksa) engel olduğunu varsaymayız.
      return options?.isEnabled ?? true;
    } catch (_) {
      return true;
    }
  }

  // Gerekirse izin penceresini açar; sonuç: bildirim gönderilebilir mi?
  Future<bool> ensurePermission() async {
    try {
      final ios = _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();

      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? await notificationsAllowed();
      }

      final android = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
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

  // Bildirim planlandıysa true. Geçmiş zamana asla planlanmaz; izin yoksa
  // planlanmaz (false). [planId] verilirse bildirimin payload'ına sahibi
  // (kullanıcı) ve plan kimliği yazılır; böylece hesap değişiminde başkasının
  // bildirimi ayırt edilip temizlenebilir.
  Future<bool> schedulePlanReminder({
    required int id,
    required String title,
    required DateTime planDateTime,
    required int minutesBefore,
    String? planId,
  }) async {
    // Kullanıcı Bildirimler'i uygulama içinden kapattıysa planlama yapılmaz.
    if (!await isAppEnabled()) return false;

    final reminderTime = reminderTimeFor(planDateTime, minutesBefore);

    if (!reminderTime.isAfter(
      DateTime.now(),
    )) {
      return false;
    }

    // İzin yalnızca kullanıcı gerçekten bir hatırlatıcı kurmak istediğinde
    // istenir (açılışta değil).
    if (!await ensurePermission()) return false;

    final ownerId = Supabase.instance.client.auth.currentUser?.id;

    await scheduleAt(
      id: id,
      title: title,
      minutesBefore: minutesBefore,
      fireAt: reminderTime,
      payload: (ownerId != null && planId != null)
          ? encodeReminderPayload(
              ReminderPayload(
                ownerId: ownerId,
                planId: planId,
                fireAtMs: reminderTime.millisecondsSinceEpoch,
                minutesBefore: minutesBefore,
                scheduledAtMs: DateTime.now().millisecondsSinceEpoch,
                title: title,
              ),
            )
          : null,
    );

    return true;
  }

  // İzin/tercih kontrolü YAPMAZ (çağıran yapmış olmalı); doğrudan planlar.
  Future<void> scheduleAt({
    required int id,
    required String title,
    required int minutesBefore,
    required DateTime fireAt,
    String? payload,
  }) async {
    await _notifications.zonedSchedule(
      id: id,
      title: minutesBefore <= 0 ? title : '$title yaklaşıyor',
      body: null,
      payload: payload,
      scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'plan_reminders',
          'Plan Hatırlatıcıları',
          channelDescription: 'Planlardan önce gönderilen hatırlatıcılar',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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