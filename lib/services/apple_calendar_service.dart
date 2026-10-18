import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CalendarPermission { granted, denied, notDetermined, unavailable }

// Life Admin görevlerini Apple Takvim'e (EventKit) yansıtır.
//
// - Tüm işlemler sıraya alınır (aynı görev için çakışan ekleme/güncelleme
//   çağrıları çift etkinlik oluşturmasın).
// - Apple etkinlik kimliği (planId -> eventIdentifier) ve "entegrasyon açık"
//   tercihi KULLANICI BAŞINA (hesaba göre) cihazda saklanır; EventKit kimlikleri
//   cihaza özgü olduğu için Supabase'e taşınmaz. Farklı hesaplar birbirinin
//   eşleşmesini görmez/değiştirmez.
// - Eşleşme kaybolursa (uygulama yeniden yüklendi vb.) Life Admin'ın
//   `lifeadmin://plan/<id>` işaretli etkinlikleri takvimde aranır ve yeniden
//   bağlanır/yeniden kullanılır; aynı görev ikinci kez eklenmez.
// - Entegrasyon KAPALIYSA hiçbir senkronizasyon yapılmaz (mevcut takvim
//   etkinlikleri silinmez/değiştirilmez).
// - Hesap silinince Life Admin'ın eklediği etkinlikler takvimde KALIR
//   (silinmez); yalnızca Life Admin tarafındaki eşleşme ve tercih temizlenir.
// - Hiçbir metot hata fırlatmaz: takvim sorunları görev kaydetme akışını
//   ASLA bozmaz.
class AppleCalendarService {
  AppleCalendarService._({String? Function()? userIdProvider})
    : _userIdProvider = userIdProvider ?? _defaultUserId;

  static final AppleCalendarService instance = AppleCalendarService._();

  @visibleForTesting
  factory AppleCalendarService.forTest({String? Function()? userIdProvider}) {
    return AppleCalendarService._(userIdProvider: userIdProvider);
  }

  static String? _defaultUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  final String? Function() _userIdProvider;

  static const MethodChannel _channel = MethodChannel('life_admin/calendar');

  // Eski (hesaptan bağımsız) anahtarlar — ilk kullanımda mevcut kullanıcıya
  // taşınır, sonra silinir.
  static const String _legacyEnabledKey = 'apple_calendar_sync_enabled';
  static const String _legacyEventIdsKey = 'apple_calendar_event_ids';

  static const int _defaultDurationMinutes = 60;

  @visibleForTesting
  static String enabledKeyFor(String userId) =>
      'apple_calendar_sync_enabled:$userId';

  @visibleForTesting
  static String eventIdsKeyFor(String userId) =>
      'apple_calendar_event_ids:$userId';

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

  // Eski global anahtarları, bu cihazdaki ilk kullanıcıya bir kez taşır.
  Future<void> _migrateLegacy(SharedPreferences prefs, String userId) async {
    final hasLegacy =
        prefs.containsKey(_legacyEnabledKey) ||
        prefs.containsKey(_legacyEventIdsKey);
    if (!hasLegacy) return;

    final enabledKey = enabledKeyFor(userId);
    final idsKey = eventIdsKeyFor(userId);

    if (!prefs.containsKey(enabledKey) && prefs.containsKey(_legacyEnabledKey)) {
      await prefs.setBool(enabledKey, prefs.getBool(_legacyEnabledKey) ?? false);
    }

    if (!prefs.containsKey(idsKey) && prefs.containsKey(_legacyEventIdsKey)) {
      final legacy = prefs.getString(_legacyEventIdsKey);
      if (legacy != null) await prefs.setString(idsKey, legacy);
    }

    await prefs.remove(_legacyEnabledKey);
    await prefs.remove(_legacyEventIdsKey);
  }

  Future<bool> isEnabled() async {
    if (!_supported) return false;

    final userId = _userIdProvider();
    if (userId == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs, userId);
      return prefs.getBool(enabledKeyFor(userId)) ?? false;
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

  // Entegrasyonu (bu hesap için) açar: izin yoksa sistem iznini ister. İzin
  // verilmezse entegrasyon AÇILMAZ ve false döner (uygulama normal çalışmaya
  // devam eder).
  Future<bool> enable() async {
    if (!_supported) return false;

    final userId = _userIdProvider();
    if (userId == null) return false;

    try {
      var granted = (await permissionStatus()) == CalendarPermission.granted;

      if (!granted) {
        granted = await _channel.invokeMethod<bool>('requestAccess') ?? false;
      }

      if (!granted) return false;

      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs, userId);
      await prefs.setBool(enabledKeyFor(userId), true);
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('[Calendar] enable failed: $error');
      return false;
    }
  }

  // Yalnızca YENİ senkronizasyonu durdurur; takvimdeki mevcut etkinliklere
  // ve saklanan kimliklere dokunmaz.
  Future<void> disable() async {
    final userId = _userIdProvider();
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs, userId);
      await prefs.setBool(enabledKeyFor(userId), false);
    } catch (_) {}
  }

  // Hesap silindiğinde: Life Admin'ın eklediği takvim etkinlikleri takvimde
  // KALIR (silinmez, kullanıcının takvimine dokunulmaz); yalnızca bu hesaba ait
  // eşleşme ve tercih bu cihazdan temizlenir.
  Future<void> forgetUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(enabledKeyFor(userId));
      await prefs.remove(eventIdsKeyFor(userId));
    } catch (_) {}
  }

  Map<String, String> _loadIds(SharedPreferences prefs, String userId) {
    final raw = prefs.getString(eventIdsKeyFor(userId));
    if (raw == null || raw.isEmpty) return {};

    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveIds(
    SharedPreferences prefs,
    String userId,
    Map<String, String> ids,
  ) {
    return prefs.setString(eventIdsKeyFor(userId), jsonEncode(ids));
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
      final userId = _userIdProvider();
      if (userId == null) return;

      if (!await isEnabled()) return;
      if (await permissionStatus() != CalendarPermission.granted) return;

      final prefs = await SharedPreferences.getInstance();
      final ids = _loadIds(prefs, userId);
      final existingId = ids[planId];

      if (dateTime == null || !_hasExplicitTime(dateTime)) {
        if (existingId != null) {
          await _channel.invokeMethod<bool>('deleteEvent', {
            'eventId': existingId,
            'planId': planId,
          });
          ids.remove(planId);
          await _saveIds(prefs, userId, ids);
        }
        return;
      }

      // eventId yoksa/geçersizse native taraf planId işaretiyle mevcut
      // etkinliği bulup yeniden kullanır (çift etkinlik oluşmaz).
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
        await _saveIds(prefs, userId, ids);
      }
    }, null);
  }

  // Yalnızca Life Admin'ın bu görev için oluşturduğu etkinliği siler
  // (native taraf ayrıca etkinliğin Life Admin işaretini doğrular). Eşleşme
  // kaybolmuşsa etkinlik planId işaretiyle aranır.
  Future<void> removePlan(String planId) {
    return _enqueue<void>(() async {
      final userId = _userIdProvider();
      if (userId == null) return;

      if (!await isEnabled()) return;
      if (await permissionStatus() != CalendarPermission.granted) return;

      final prefs = await SharedPreferences.getInstance();
      final ids = _loadIds(prefs, userId);
      final existingId = ids[planId];

      await _channel.invokeMethod<bool>('deleteEvent', {
        'eventId': existingId,
        'planId': planId,
      });

      if (existingId != null) {
        ids.remove(planId);
        await _saveIds(prefs, userId, ids);
      }
    }, null);
  }

  // Yerel eşleşmeyi takvimdeki Life Admin işaretli etkinliklerden yeniden kurar
  // (uygulama yeniden yüklendiğinde/yeni cihazda). YALNIZCA verilen kullanıcının
  // plan kimlikleri eşleştirilir; başka hesaba ait veya bilinmeyen etkinliklere
  // dokunulmaz ve hiçbir etkinlik silinmez.
  Future<void> reconcileMappings(Set<String> ownPlanIds) {
    return _enqueue<void>(() async {
      final userId = _userIdProvider();
      if (userId == null) return;

      if (!await isEnabled()) return;
      if (await permissionStatus() != CalendarPermission.granted) return;

      final now = DateTime.now();
      final entries = await _channel.invokeMethod<List<dynamic>>('listOurEvents', {
        'startMillis': now
            .subtract(const Duration(days: 365))
            .millisecondsSinceEpoch,
        'endMillis': now.add(const Duration(days: 730)).millisecondsSinceEpoch,
      });

      if (entries == null) return;

      final prefs = await SharedPreferences.getInstance();
      final ids = _loadIds(prefs, userId);
      var changed = false;

      for (final raw in entries) {
        final entry = Map<String, dynamic>.from(raw as Map);
        final planId = entry['planId'] as String?;
        final eventId = entry['eventId'] as String?;

        if (planId == null || eventId == null) continue;
        if (!ownPlanIds.contains(planId)) continue;
        if (ids[planId] == eventId) continue;

        ids[planId] = eventId;
        changed = true;
      }

      if (changed) await _saveIds(prefs, userId, ids);
    }, null);
  }
}
