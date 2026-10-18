import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/plans/event_service.dart';
import '../features/plans/plan.dart';
import '../utils/reminder_format.dart';
import 'notification_service.dart';
import 'reminder_plan.dart';

// Oturum/uygulama yaşam döngüsüne bağlı yerel durumu Supabase ile uzlaştırır:
//  - Çıkış / hesap silme / oturum sona ermesi: bu cihazdaki planlı yerel
//    bildirimler iptal edilir (başka kullanıcının bildirimi görünmesin).
//  - Giriş, uygulamanın yeniden açılması ve öne gelmesi: Supabase'deki gelecek
//    hatırlatmalar yeniden planlanır (eksikler eklenir, çift/eski kayıtlar
//    temizlenir). Bildirim izni veya uygulama içi tercih kapalıysa planlanmaz.
// Tüm işlemler sıraya alınır, hiçbiri hata fırlatmaz.
class SessionSyncService with WidgetsBindingObserver {
  SessionSyncService._();

  static final SessionSyncService instance = SessionSyncService._();

  static const Duration _minInterval = Duration(seconds: 90);

  StreamSubscription<AuthState>? _subscription;
  Future<void> _queue = Future<void>.value();
  DateTime? _lastRun;
  bool _started = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  void start() {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);

    _subscription = _supabase.auth.onAuthStateChange.listen(
      _onAuthChange,
      onError: (_) {},
    );

    // initialSession olayı abonelikten önce yayımlanmış olabilir: açılışta
    // mevcut oturumu doğrudan uzlaştır.
    if (_supabase.auth.currentSession != null) {
      unawaited(reconcile(force: true));
    } else {
      unawaited(clearForSignOut());
    }
  }

  void _onAuthChange(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.signedOut:
        unawaited(clearForSignOut());
      case AuthChangeEvent.initialSession:
        if (state.session == null) {
          unawaited(clearForSignOut());
        } else {
          unawaited(reconcile(force: true));
        }
      case AuthChangeEvent.signedIn:
        unawaited(reconcile(force: true));
      default:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(reconcile());
    }
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) async {
      try {
        await task();
      } catch (_) {}
    });

    _queue = next;
    return next;
  }

  // Çıkış veya hesap silme: bu cihazdaki tüm Life Admin yerel bildirimlerini
  // iptal eder ve sahip kaydını siler. (Apple Takvim'deki etkinliklere
  // DOKUNMAZ.)
  Future<void> clearForSignOut() {
    return _enqueue(() async {
      _lastRun = null;
      await NotificationService.instance.cancelAll();
      await NotificationService.instance.setOwner(null);
    });
  }

  Future<void> reconcile({bool force = false}) {
    return _enqueue(() => _reconcile(force));
  }

  Future<void> _reconcile(bool force) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    if (!force && _lastRun != null && now.difference(_lastRun!) < _minInterval) {
      return;
    }
    _lastRun = now;

    final notifications = NotificationService.instance;

    // Bu cihazdaki bekleyen bildirimler başka bir kullanıcıya aitse (veya
    // sahibi bilinmiyorsa, ör. eski sürümden) önce hepsi temizlenir.
    final owner = await notifications.getOwner();
    if (owner != user.id) {
      await notifications.cancelAll();
      await notifications.setOwner(user.id);
    }

    if (!await notifications.isAppEnabled()) {
      await notifications.cancelAll();
      return;
    }

    // İzin penceresi AÇMAZ: sistem izni yoksa planlama yapılmaz.
    if (!await notifications.notificationsAllowed()) return;

    final List<Plan> plans;

    try {
      plans = await EventService().getPlans();
    } catch (_) {
      return;
    }

    final candidates = <ReminderCandidate>[
      for (final plan in plans)
        if (plan.reminderEnabled &&
            !plan.isCompleted &&
            plan.reminderMinutesBefore != null &&
            plan.dateTime != null &&
            hasExplicitTime(plan.dateTime!))
          ReminderCandidate(
            planId: plan.id,
            title: plan.title,
            planDateTime: plan.dateTime!,
            minutesBefore: plan.reminderMinutesBefore!,
          ),
    ];

    final desired = planReminders(candidates: candidates, now: now);
    final pending = await notifications.pendingReminders();

    final diff = diffReminders(
      ownerId: user.id,
      desired: desired,
      pending: pending,
      now: now,
    );

    for (final id in diff.cancelIds) {
      await notifications.cancelReminder(id);
    }

    for (final item in diff.schedule) {
      await notifications.scheduleAt(
        id: item.notificationId,
        title: item.title,
        minutesBefore: item.minutesBefore,
        fireAt: item.fireAt,
        payload: encodeReminderPayload(
          ReminderPayload(
            ownerId: user.id,
            planId: item.planId,
            fireAtMs: item.fireAt.millisecondsSinceEpoch,
            minutesBefore: item.minutesBefore,
            scheduledAtMs: now.millisecondsSinceEpoch,
            title: item.title,
          ),
        ),
      );
    }
  }

  void dispose() {
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }
}
