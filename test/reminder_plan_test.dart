import 'package:flutter_test/flutter_test.dart';
import 'package:life_admin/services/reminder_plan.dart';

ReminderCandidate candidate(
  String id,
  DateTime at, {
  int minutes = 15,
  String title = 'Görev',
}) {
  return ReminderCandidate(
    planId: id,
    title: title,
    planDateTime: at,
    minutesBefore: minutes,
  );
}

void main() {
  final now = DateTime(2026, 10, 20, 12, 0);

  group('planReminders', () {
    test('geçmişe kalan, saatsiz ve tekrar eden planlar elenir', () {
      final desired = planReminders(
        now: now,
        candidates: [
          candidate('past', DateTime(2026, 10, 20, 12, 10)), // 11:55 -> geçmiş
          candidate('midnight', DateTime(2026, 10, 21)), // saat yok (00:00)
          candidate('ok', DateTime(2026, 10, 21, 9, 0)),
          candidate('ok', DateTime(2026, 10, 21, 9, 0)), // aynı plan
        ],
      );

      expect(desired.map((d) => d.planId), ['ok']);
      expect(desired.single.fireAt, DateTime(2026, 10, 21, 8, 45));
    });

    test('tam saatinde (0 dk) gelecekteyse planlanır', () {
      final desired = planReminders(
        now: now,
        candidates: [candidate('a', DateTime(2026, 10, 20, 13, 0), minutes: 0)],
      );
      expect(desired.single.fireAt, DateTime(2026, 10, 20, 13, 0));
    });

    test('iOS sınırı: en yakın N hatırlatma seçilir', () {
      final candidates = [
        for (var i = 0; i < 100; i++)
          candidate('p$i', DateTime(2026, 10, 21, 9, 15).add(Duration(minutes: 30 * i))),
      ];

      final desired = planReminders(now: now, candidates: candidates);

      expect(desired.length, maxScheduledReminders);
      expect(desired.first.planId, 'p0');
      expect(desired.last.planId, 'p${maxScheduledReminders - 1}');
    });

    test('bildirim kimliği plan başına sabit ve benzersiz', () {
      expect(reminderNotificationId('abc'), reminderNotificationId('abc'));
      expect(reminderNotificationId('abc'), isNot(reminderNotificationId('abd')));
    });
  });

  group('payload', () {
    test('başlıkta | olsa bile gidiş-dönüş', () {
      const payload = ReminderPayload(
        ownerId: 'u1',
        planId: 'p1',
        fireAtMs: 123456,
        minutesBefore: 20,
        scheduledAtMs: 99,
        title: 'A | B | C',
      );

      final decoded = decodeReminderPayload(encodeReminderPayload(payload));
      expect(decoded, isNotNull);
      expect(decoded!.title, 'A | B | C');
      expect(decoded.ownerId, 'u1');
      expect(decoded.fireAtMs, 123456);
    });

    test('eski/bozuk payload null döner', () {
      expect(decodeReminderPayload(null), isNull);
      expect(decodeReminderPayload('rastgele'), isNull);
      expect(decodeReminderPayload('lar1|u|p|x|1|2|t'), isNull);
    });
  });

  group('diffReminders', () {
    DesiredReminder desiredOf(String id, DateTime fire, {int minutes = 15}) {
      return DesiredReminder(
        planId: id,
        notificationId: reminderNotificationId(id),
        title: 'Görev',
        minutesBefore: minutes,
        fireAt: fire,
      );
    }

    PendingReminder pendingFor(
      DesiredReminder d, {
      String owner = 'u1',
      int? scheduledAtMs,
      DateTime? fire,
      String title = 'Görev',
    }) {
      return PendingReminder(
        d.notificationId,
        encodeReminderPayload(
          ReminderPayload(
            ownerId: owner,
            planId: d.planId,
            fireAtMs: (fire ?? d.fireAt).millisecondsSinceEpoch,
            minutesBefore: d.minutesBefore,
            scheduledAtMs: scheduledAtMs ?? 0,
            title: title,
          ),
        ),
      );
    }

    test('aynı bildirim iki kez planlanmaz (idempotent)', () {
      final d = desiredOf('a', DateTime(2026, 10, 21, 9));

      final diff = diffReminders(
        ownerId: 'u1',
        desired: [d],
        pending: [pendingFor(d)],
        now: now,
      );

      expect(diff.schedule, isEmpty);
      expect(diff.cancelIds, isEmpty);
    });

    test('eksik bildirim planlanır', () {
      final d = desiredOf('a', DateTime(2026, 10, 21, 9));
      final diff = diffReminders(ownerId: 'u1', desired: [d], pending: [], now: now);
      expect(diff.schedule.single.planId, 'a');
    });

    test('zamanı veya başlığı değişen yeniden planlanır', () {
      final d = desiredOf('a', DateTime(2026, 10, 21, 9));

      final movedPending = pendingFor(d, fire: DateTime(2026, 10, 21, 8));
      final renamedPending = pendingFor(d, title: 'Eski ad');

      for (final p in [movedPending, renamedPending]) {
        final diff = diffReminders(ownerId: 'u1', desired: [d], pending: [p], now: now);
        expect(diff.schedule, hasLength(1));
        expect(diff.cancelIds, isEmpty);
      }
    });

    test('başka kullanıcıya ait bildirim yeniden yazılır, istenmeyen iptal edilir', () {
      final d = desiredOf('a', DateTime(2026, 10, 21, 9));
      final foreign = pendingFor(d, owner: 'baska');
      const orphan = PendingReminder(777, null); // eski sürümden kalan kimlik

      final diff = diffReminders(
        ownerId: 'u1',
        desired: [d],
        pending: [foreign, orphan],
        now: now,
      );

      expect(diff.schedule.single.planId, 'a');
      expect(diff.cancelIds, [777]);
    });

    test('silinmiş plana ait eski bildirim iptal edilir', () {
      final gone = desiredOf('gone', DateTime(2026, 10, 21, 9));

      final diff = diffReminders(
        ownerId: 'u1',
        desired: [],
        pending: [pendingFor(gone)],
        now: now,
      );

      expect(diff.cancelIds, [gone.notificationId]);
    });

    test('çok yeni (eşzamanlı eklenen) kendi bildirimine dokunulmaz', () {
      final fresh = desiredOf('new', DateTime(2026, 10, 21, 9));

      final diff = diffReminders(
        ownerId: 'u1',
        desired: [],
        pending: [pendingFor(fresh, scheduledAtMs: now.millisecondsSinceEpoch - 5000)],
        now: now,
      );

      expect(diff.cancelIds, isEmpty);
    });

    test('başka kullanıcının yeni bildirimi bile iptal edilir', () {
      final other = desiredOf('x', DateTime(2026, 10, 21, 9));

      final diff = diffReminders(
        ownerId: 'u1',
        desired: [],
        pending: [
          pendingFor(other, owner: 'baska', scheduledAtMs: now.millisecondsSinceEpoch - 1000),
        ],
        now: now,
      );

      expect(diff.cancelIds, [other.notificationId]);
    });
  });
}
