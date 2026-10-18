import '../utils/reminder_format.dart';

// Hatırlatma bildirimlerinin SAF (plugin'siz) planlama mantığı: hangi
// bildirimler olmalı, bekleyenlerle farkı ne? Test edilebilir olsun diye
// bildirim eklentisinden ve Supabase'den bağımsızdır.

// iOS aynı anda en fazla 64 bekleyen yerel bildirim tutar (fazlası sessizce
// düşer). Güvenlik payı bırakıp yalnızca en yakın 60 hatırlatma planlanır;
// kalanlar uygulama açıldıkça/öne geldikçe (reconcile) sırayla planlanır.
const int maxScheduledReminders = 60;

// Plan başına SABİT bildirim kimliği: aynı plan için tekrar planlama aynı
// kimliğin üzerine yazar, çift bildirim oluşmaz.
int reminderNotificationId(String planId) {
  var hash = 2166136261;

  for (final codeUnit in 'plan-reminder|$planId'.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 16777619) & 0x7fffffff;
  }

  return hash;
}

class ReminderPayload {
  final String ownerId;
  final String planId;
  final int fireAtMs;
  final int minutesBefore;
  final int scheduledAtMs;
  final String title;

  const ReminderPayload({
    required this.ownerId,
    required this.planId,
    required this.fireAtMs,
    required this.minutesBefore,
    required this.scheduledAtMs,
    required this.title,
  });
}

const String _payloadVersion = 'lar1';

// Bildirimin payload'ı: kime ait olduğu (başka kullanıcının bildirimini
// ayırt etmek için), hangi plan, ne zaman çalacak. Başlık EN SONDA; içinde
// '|' olabilir.
String encodeReminderPayload(ReminderPayload payload) {
  return [
    _payloadVersion,
    payload.ownerId,
    payload.planId,
    payload.fireAtMs,
    payload.minutesBefore,
    payload.scheduledAtMs,
    payload.title,
  ].join('|');
}

ReminderPayload? decodeReminderPayload(String? raw) {
  if (raw == null || !raw.startsWith('$_payloadVersion|')) return null;

  final parts = <String>[];
  var start = 0;

  for (var i = 0; i < 6; i++) {
    final index = raw.indexOf('|', start);
    if (index == -1) return null;
    parts.add(raw.substring(start, index));
    start = index + 1;
  }

  final title = raw.substring(start);

  final fireAt = int.tryParse(parts[3]);
  final minutes = int.tryParse(parts[4]);
  final scheduledAt = int.tryParse(parts[5]);

  if (fireAt == null || minutes == null || scheduledAt == null) return null;

  return ReminderPayload(
    ownerId: parts[1],
    planId: parts[2],
    fireAtMs: fireAt,
    minutesBefore: minutes,
    scheduledAtMs: scheduledAt,
    title: title,
  );
}

class ReminderCandidate {
  final String planId;
  final String title;
  final DateTime planDateTime;
  final int minutesBefore;

  const ReminderCandidate({
    required this.planId,
    required this.title,
    required this.planDateTime,
    required this.minutesBefore,
  });
}

class DesiredReminder {
  final String planId;
  final int notificationId;
  final String title;
  final int minutesBefore;
  final DateTime fireAt;

  const DesiredReminder({
    required this.planId,
    required this.notificationId,
    required this.title,
    required this.minutesBefore,
    required this.fireAt,
  });

  bool matches(ReminderPayload payload, String ownerId) {
    return payload.ownerId == ownerId &&
        payload.planId == planId &&
        payload.fireAtMs == fireAt.millisecondsSinceEpoch &&
        payload.minutesBefore == minutesBefore &&
        payload.title == title;
  }
}

class PendingReminder {
  final int id;
  final String? payload;

  const PendingReminder(this.id, this.payload);
}

class ReminderDiff {
  final List<int> cancelIds;
  final List<DesiredReminder> schedule;

  const ReminderDiff(this.cancelIds, this.schedule);
}

// Gelecekteki, geçerli hatırlatmalar: geçmişe kalanlar atılır, aynı plan bir
// kez sayılır, en yakın [limit] tanesi (zamana göre) seçilir.
List<DesiredReminder> planReminders({
  required List<ReminderCandidate> candidates,
  required DateTime now,
  int limit = maxScheduledReminders,
}) {
  final byPlan = <String, DesiredReminder>{};

  for (final candidate in candidates) {
    if (!hasExplicitTime(candidate.planDateTime)) continue;

    final fireAt = reminderTimeFor(candidate.planDateTime, candidate.minutesBefore);
    if (!fireAt.isAfter(now)) continue;

    byPlan[candidate.planId] = DesiredReminder(
      planId: candidate.planId,
      notificationId: reminderNotificationId(candidate.planId),
      title: candidate.title,
      minutesBefore: candidate.minutesBefore,
      fireAt: fireAt,
    );
  }

  final sorted = byPlan.values.toList()
    ..sort((a, b) => a.fireAt.compareTo(b.fireAt));

  return sorted.length <= limit ? sorted : sorted.sublist(0, limit);
}

// Bekleyen bildirimlerle istenen liste arasındaki fark:
//  - schedule: eksik veya içeriği farklı (başka kullanıcıya ait / eski / değişmiş)
//  - cancelIds: istenmeyen (silinmiş plan, kapatılmış hatırlatma, başka
//    kullanıcı, eski sürümden kalan kimlik). Çok yeni (grace içinde) ve bu
//    kullanıcıya ait olanlara dokunulmaz: eşzamanlı eklenen görevin
//    bildirimi yanlışlıkla iptal edilmesin.
ReminderDiff diffReminders({
  required String ownerId,
  required List<DesiredReminder> desired,
  required List<PendingReminder> pending,
  required DateTime now,
  Duration grace = const Duration(minutes: 2),
}) {
  final pendingById = {for (final p in pending) p.id: p};
  final desiredIds = {for (final d in desired) d.notificationId};

  final schedule = <DesiredReminder>[];

  for (final item in desired) {
    final existing = pendingById[item.notificationId];
    final payload = decodeReminderPayload(existing?.payload);

    if (existing == null || payload == null || !item.matches(payload, ownerId)) {
      schedule.add(item);
    }
  }

  final cancelIds = <int>[];

  for (final item in pending) {
    if (desiredIds.contains(item.id)) continue;

    final payload = decodeReminderPayload(item.payload);
    final isFreshOwn = payload != null &&
        payload.ownerId == ownerId &&
        now.millisecondsSinceEpoch - payload.scheduledAtMs <
            grace.inMilliseconds;

    if (!isFreshOwn) cancelIds.add(item.id);
  }

  return ReminderDiff(cancelIds, schedule);
}
