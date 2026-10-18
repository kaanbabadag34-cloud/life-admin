import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/apple_calendar_service.dart';
import '../../services/notification_service.dart';
import '../../utils/reminder_format.dart';

import 'plan.dart';

class EventService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Supabase'de henüz `events.note` migration'ı uygulanmamışsa PostgREST
  // "Could not find the 'note' column" hatası fırlatır. Migration
  // uygulanana kadar görev ekleme/güncelleme tamamen çökmesin diye bu
  // durumda note alanı olmadan tekrar deneriz.
  bool _isMissingColumn(Object error, String column) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    return message.contains(column) && message.contains('column');
  }

  bool _isMissingNoteColumn(Object error) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    return message.contains('note') && message.contains('column');
  }

  // Eklenen görevin DB kimliğini döndürür (yoksa null).
  Future<String?> addPlan(Plan plan) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    final payload = {
      'user_id': user.id,
      'title': plan.title,
      'event_type': plan.category.name,
      'starts_at': plan.dateTime?.toUtc().toIso8601String(),
      'completed': plan.isCompleted,
      'reminder_enabled': plan.reminderEnabled,
      'reminder_minutes_before':
          plan.reminderEnabled ? plan.reminderMinutesBefore : null,
      'source': plan.source.name,
      'note': plan.note,
      'duration_minutes': ?plan.durationMinutes,
    };

    Map<String, dynamic>? inserted;

    // Eksik kolonlar (note / duration_minutes migration'ları uygulanmamışsa)
    // tek tek çıkarılarak yeniden denenir; görev kaydı asla bunun yüzünden
    // başarısız olmaz.
    for (var attempt = 0; attempt < 3 && inserted == null; attempt++) {
      try {
        inserted =
            await _supabase.from('events').insert(payload).select('id').single();
      } catch (error) {
        if (payload.containsKey('duration_minutes') &&
            _isMissingColumn(error, 'duration_minutes')) {
          payload.remove('duration_minutes');
        } else if (payload.containsKey('note') && _isMissingNoteColumn(error)) {
          payload.remove('note');
        } else {
          rethrow;
        }
      }
    }

    if (inserted == null) throw Exception('Plan kaydedilemedi.');

    // Bildirim ve Apple Takvim senkronu kullanıcıyı BEKLETMEZ: kayıt
    // tamamlandığı anda döneriz, senkron arka planda sürer. İkisi de hata
    // fırlatmaz. Hatırlatma, ek bir DB okuması yapmadan eldeki plan
    // verisinden kurulur.
    final insertedId = inserted['id']?.toString();

    if (insertedId != null) {
      unawaited(_syncAfterInsert(insertedId, plan));
    }

    return insertedId;
  }

  Future<void> _syncAfterInsert(String id, Plan plan) async {
    try {
      final notifications = NotificationService.instance;
      final notificationId = NotificationService.reminderIdFor(id);
      final minutes = plan.reminderMinutesBefore;
      final dateTime = plan.dateTime;

      await notifications.cancelReminder(notificationId);

      if (plan.reminderEnabled &&
          !plan.isCompleted &&
          minutes != null &&
          dateTime != null &&
          hasExplicitTime(dateTime)) {
        await notifications.schedulePlanReminder(
          id: notificationId,
          title: plan.title,
          planDateTime: dateTime,
          minutesBefore: minutes,
        );
      }
    } catch (_) {}

    await AppleCalendarService.instance.syncPlan(
      planId: id,
      title: plan.title,
      dateTime: plan.dateTime,
      note: plan.note,
      durationMinutes: plan.durationMinutes,
    );
  }

  // Görevin DB'deki güncel hatırlatma ayarına göre yerel bildirimi yeniden
  // kurar. Plan başına SABİT kimlik kullanıldığı için çift bildirim oluşmaz:
  // önce eskisi iptal edilir, sonra (gerekiyorsa) yenisi planlanır. Görev
  // saati (starts_at) ile bildirim saati (starts_at - ofset) ayrı tutulur.
  // Hiçbir zaman hata fırlatmaz.
  Future<void> _syncReminderFromDb(String id) async {
    try {
      final notifications = NotificationService.instance;
      final notificationId = NotificationService.reminderIdFor(id);

      await notifications.cancelReminder(notificationId);

      final row = await _supabase
          .from('events')
          .select(
            'title, starts_at, completed, reminder_enabled, '
            'reminder_minutes_before',
          )
          .eq('id', id)
          .single();

      final minutes = (row['reminder_minutes_before'] as num?)?.toInt();
      final startsAtRaw = row['starts_at'] as String?;

      if (row['reminder_enabled'] != true ||
          minutes == null ||
          startsAtRaw == null ||
          row['completed'] == true) {
        return;
      }

      final startsAt = DateTime.parse(startsAtRaw).toLocal();

      if (!hasExplicitTime(startsAt)) return;

      await notifications.schedulePlanReminder(
        id: notificationId,
        title: row['title'] as String,
        planDateTime: startsAt,
        minutesBefore: minutes,
      );
    } catch (_) {
      // Bildirim sorunları görev kaydetme akışını asla bozmamalı.
    }
  }

  // Güncelleme sonrası görevin güncel halini okuyup Apple Takvim'e yansıtır.
  Future<void> _syncCalendarFromDb(String id) async {
    try {
      Map<String, dynamic> row;

      try {
        row = await _supabase
            .from('events')
            .select('title, starts_at, note, duration_minutes')
            .eq('id', id)
            .single();
      } catch (error) {
        if (!_isMissingColumn(error, 'duration_minutes')) rethrow;

        row = await _supabase
            .from('events')
            .select('title, starts_at, note')
            .eq('id', id)
            .single();
      }

      await AppleCalendarService.instance.syncPlan(
        planId: id,
        title: row['title'] as String,
        dateTime: row['starts_at'] == null
            ? null
            : DateTime.parse(row['starts_at'] as String).toLocal(),
        note: row['note'] as String?,
        durationMinutes: (row['duration_minutes'] as num?)?.toInt(),
      );
    } catch (_) {
      // Takvim senkronu görev güncellemesini asla bozmamalı.
    }
  }

  Future<void> deletePlan(String id) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id);

    await NotificationService.instance.cancelReminder(
      NotificationService.reminderIdFor(id),
    );

    await AppleCalendarService.instance.removePlan(id);
  }

  Future<void> setCompleted({
    required String id,
    required bool completed,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .update({
          'completed': completed,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);
    await _syncReminderFromDb(id);
  }

  Future<void> updateDateTime({
    required String id,
    required DateTime dateTime,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .update({
          'starts_at':
              dateTime.toUtc().toIso8601String(),
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);

    await _syncReminderFromDb(id);
    await _syncCalendarFromDb(id);
  }

  // Home ekranındaki görev detay sayfası başlık, tarih, saat ve notu tek
  // seferde günceller. Mevcut updateDateTime/updateReminder akışlarını
  // bozmamak için ayrı bir metot olarak eklendi.
  Future<void> updatePlanSchedule({
    required String id,
    required DateTime? dateTime,
    String? note,
    String? title,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    final payload = {
      'starts_at': dateTime?.toUtc().toIso8601String(),
      'note': note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'title': ?title,
    };

    try {
      await _supabase
          .from('events')
          .update(payload)
          .eq('id', id)
          .eq('user_id', user.id);
    } catch (error) {
      if (!_isMissingNoteColumn(error)) rethrow;

      payload.remove('note');
      await _supabase
          .from('events')
          .update(payload)
          .eq('id', id)
          .eq('user_id', user.id);
    }

    await _syncReminderFromDb(id);
    await _syncCalendarFromDb(id);
  }

  Future<void> updateReminder({
    required String id,
    required bool enabled,
    int? minutesBefore,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .update({
          'reminder_enabled': enabled,
          'reminder_minutes_before':
              enabled ? minutesBefore : null,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);
    await _syncReminderFromDb(id);
  }

  // Bildirimler yeniden açıldığında: gelecekteki, geçerli tüm hatırlatmaları
  // sabit kimliklerle (çift bildirim oluşmaz) yeniden planlar. Geçmiş
  // hatırlatmalar planlanmaz (schedulePlanReminder bunu zaten engeller).
  Future<void> rescheduleAllReminders() async {
    try {
      final plans = await getPlans();

      for (final plan in plans) {
        final minutes = plan.reminderMinutesBefore;
        final dateTime = plan.dateTime;

        if (!plan.reminderEnabled ||
            plan.isCompleted ||
            minutes == null ||
            dateTime == null ||
            !hasExplicitTime(dateTime)) {
          continue;
        }

        await NotificationService.instance.schedulePlanReminder(
          id: NotificationService.reminderIdFor(plan.id),
          title: plan.title,
          planDateTime: dateTime,
          minutesBefore: minutes,
        );
      }
    } catch (_) {
      // Sessizce geç: bildirim yenileme ana akışı bozmamalı.
    }
  }

  Future<List<Plan>> getPlans() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    final response = await _supabase
        .from('events')
        .select()
        .eq('user_id', user.id)
        .order(
          'starts_at',
          ascending: true,
          nullsFirst: false,
        );

    return response.map<Plan>((row) {
      return Plan(
        id: row['id'] as String,
        title: row['title'] as String,
        dateTime: row['starts_at'] == null
            ? null
            : DateTime.parse(
                row['starts_at'] as String,
              ).toLocal(),
        category: PlanCategory.values.firstWhere(
          (value) =>
              value.name == row['event_type'],
          orElse: () => PlanCategory.task,
        ),
        source: PlanSource.values.firstWhere(
          (value) =>
              value.name == row['source'],
          orElse: () => PlanSource.manual,
        ),
        isCompleted:
            row['completed'] as bool? ?? false,
        reminderEnabled:
            row['reminder_enabled'] as bool? ?? false,
        reminderMinutesBefore:
            (row['reminder_minutes_before'] as num?)
                ?.toInt(),
        note: row['note'] as String?,
        durationMinutes: (row['duration_minutes'] as num?)?.toInt(),
        createdAt: DateTime.parse(
          row['created_at'] as String,
        ).toLocal(),
      );
    }).toList();
  }
}