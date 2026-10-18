import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CalendarPermission { granted, denied, notDetermined, unavailable }

// Life Admin görevlerini Apple Takvim'e (EventKit) yansıtır.
//
// - Tüm işlemler sıraya alınır (aynı görev için çakışan ekleme/güncelleme
//   çağrıları çift etkinlik oluşturmasın).
// - Apple etkinlik kimliği (planId -> eventIdentifier), EventKit kimlikleri
//   cihaza özgü olduğu için cihazda (SharedPreferences) saklanır.
// - Entegrasyon KAPALIYSA hiçbir senkronizasyon yapılmaz (mevcut takvim
//   etkinlikleri silinmez/değiştirilmez).
// - Hiçbir metot hata fırlatmaz: takvim sorunları görev kaydetme akışını
//   ASLA bozmaz.
class AppleCalendarService {
  AppleCalendarService._();

  static final AppleCalendarService instance = AppleCalendarService._();

  static const MethodChannel _channel = MethodChannel('life_admin/calendar');
  static const String _enabledKey = 'apple_calendar_sync_enabled';
  static const String _eventIdsKey = 'apple_calendar_event_ids';
  static const int _defaultDurationMinutes = 60;

  Future<void> _queue = Future<void>.value();

  bool get _supported => defaultTargetPlatform == TargetPlatform.iOS;

  Future<T> _enqueue<T>(Future<T> Function() task, T fallback) {
    final completer = _queue.then((_) async {
      try {
        return await task();
      } catch (error) {
        if (kDebugMode) debugPrint('[Calendar] $error');
        return fallback;
      }
    });

    _queue = completer.then((_) {});
    return completer;
  }

  Future<bool> isEnabled() async {
    if (!_supported) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<CalendarPermission> permissionStatus() async {
    if (!_supported) return CalendarPermission.unavailable;

    try {
      final status = await _channel.invokeMethod<String>('authorizationStatus');

      switch (status) {
        case 'granted':
          return CalendarPermission.granted;
        case 'notDetermined':
          return CalendarPermission.notDetermined;
        default:
          return CalendarPermission.denied;
      }
    } catch (_) {
      return CalendarPermission.unavailable;
    }
  }

  // Entegrasyonu açar: izin yoksa sistem iznini ister. İzin verilmezse
  // entegrasyon AÇILMAZ ve false döner (uygulama normal çalışmaya devam eder).
  Future<bool> enable() async {
    if (!_supported) return false;

    try {
      var granted = (await permissionStatus()) == CalendarPermission.granted;

      if (!granted) {
        granted = await _channel.invokeMethod<bool>('requestAccess') ?? false;
      }

      if (!granted) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('[Calendar] enable failed: $error');
      return false;
    }
  }

  // Yalnızca YENİ senkronizasyonu durdurur; takvimdeki mevcut etkinliklere
  // ve saklanan kimliklere dokunmaz.
  Future<void> disable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, false);
    } catch (_) {}
  }

  Future<Map<String, String>> _loadIds(SharedPreferences prefs) async {
    final raw = prefs.getString(_eventIdsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveIds(SharedPreferences prefs, Map<String, String> ids) {
    return prefs.setString(_eventIdsKey, jsonEncode(ids));
  }

  bool _hasExplicitTime(DateTime dateTime) {
    return dateTime.hour != 0 || dateTime.minute != 0;
  }

  // Tarihli VE saatli görevi ekler/günceller. Saat veya tarih kaldırıldıysa
  // (daha önce Life Admin'ın eklediği) karşılığı takvimden kaldırılır.
  Future<void> syncPlan({
    required String planId,
    required String title,
    required DateTime? dateTime,
    String? note,
    int? durationMinutes,
  }) {
    return _enqueue<void>(() async {
      if (!await isEnabled()) return;
      if (await permissionStatus() != CalendarPermission.granted) return;

      final prefs = await SharedPreferences.getInstance();
      final ids = await _loadIds(prefs);
      final existingId = ids[planId];

      if (dateTime == null || !_hasExplicitTime(dateTime)) {
        if (existingId != null) {
          await _channel.invokeMethod<bool>('deleteEvent', {'eventId': existingId});
          ids.remove(planId);
          await _saveIds(prefs, ids);
        }
        return;
      }

      final newId = await _channel.invokeMethod<String>('upsertEvent', {
        'planId': planId,
        'eventId': existingId,
        'title': title,
        'startMillis': dateTime.millisecondsSinceEpoch,
        // Süre belirtilmemişse mevcut varsayılan (60 dk) korunur.
        'durationMinutes': durationMinutes ?? _defaultDurationMinutes,
        'notes': note,
      });

      if (newId != null && newId != existingId) {
        ids[planId] = newId;
        await _saveIds(prefs, ids);
      }
    }, null);
  }

  // Yalnızca Life Admin'ın bu görev için oluşturduğu etkinliği siler
  // (native taraf ayrıca etkinliğin Life Admin işaretini doğrular).
  Future<void> removePlan(String planId) {
    return _enqueue<void>(() async {
      if (!await isEnabled()) return;
      if (await permissionStatus() != CalendarPermission.granted) return;

      final prefs = await SharedPreferences.getInstance();
      final ids = await _loadIds(prefs);
      final existingId = ids[planId];

      if (existingId == null) return;

      await _channel.invokeMethod<bool>('deleteEvent', {'eventId': existingId});
      ids.remove(planId);
      await _saveIds(prefs, ids);
    }, null);
  }
}
