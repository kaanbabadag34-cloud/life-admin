import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../services/pomodoro_live_activity.dart';

// Pomodoro oturumunun TEK sahibi — uygulama ömrü boyunca yaşayan singleton.
// Sayfa kapanıp açılsa, başka sekmeye geçilse bile oturum burada kalır.
// Süre "kalan saniye sayacı" ile değil, çalışırken bitiş ANI (`_endsAt`)
// ile tutulur: uygulama arka plana alınsa/Dart timer'ı askıya alınsa bile
// kalan süre her zaman gerçek saatten hesaplanır. Duraklatılmışsa kalan
// süre `_pausedRemaining`'de saklanır. Oturum SADECE kullanıcı sıfırlayınca
// (veya süre ayarını değiştirince) sıfırlanır.
class PomodoroSession extends ChangeNotifier with WidgetsBindingObserver {
  PomodoroSession._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final PomodoroSession instance = PomodoroSession._();

  int focusMinutes = 25;
  int breakMinutes = 5;
  int completedSessions = 0;
  bool isBreak = false;

  int totalSeconds = 25 * 60;
  int _pausedRemaining = 25 * 60;
  DateTime? _endsAt;
  Timer? _ticker;
  int _lastShownSeconds = 25 * 60;

  bool get isRunning => _endsAt != null;

  // Live Activity: çalışırken/duraklatılmışken güncel durumu yansıtır.
  void _publishLiveActivity() {
    PomodoroLiveActivity.instance.sync(
      isBreak: isBreak,
      isRunning: isRunning,
      endsAt: _endsAt,
      remainingSeconds: remainingSeconds,
      totalSeconds: totalSeconds,
    );
  }

  int get remainingSeconds {
    final endsAt = _endsAt;
    if (endsAt == null) return _pausedRemaining;

    final ms = endsAt.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void start() {
    if (isRunning || _pausedRemaining <= 0) return;

    _endsAt = DateTime.now().add(Duration(seconds: _pausedRemaining));
    _lastShownSeconds = _pausedRemaining;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _tick(haptic: true);
    });

    _publishLiveActivity();
    notifyListeners();
  }

  void pause() {
    if (!isRunning) return;

    _pausedRemaining = remainingSeconds;
    _stopTicker();
    _publishLiveActivity();
    notifyListeners();
  }

  void reset() {
    _stopTicker();
    totalSeconds = (isBreak ? breakMinutes : focusMinutes) * 60;
    _pausedRemaining = totalSeconds;
    PomodoroLiveActivity.instance.end();
    notifyListeners();
  }

  void changeFocusMinutes(int minutes) {
    final remaining = remainingSeconds;
    _stopTicker();
    focusMinutes = minutes;

    if (!isBreak) {
      totalSeconds = minutes * 60;
      _pausedRemaining = totalSeconds;
    } else {
      _pausedRemaining = remaining;
    }

    PomodoroLiveActivity.instance.end();
    notifyListeners();
  }

  void changeBreakMinutes(int minutes) {
    final remaining = remainingSeconds;
    _stopTicker();
    breakMinutes = minutes;

    if (isBreak) {
      totalSeconds = minutes * 60;
      _pausedRemaining = totalSeconds;
    } else {
      _pausedRemaining = remaining;
    }

    PomodoroLiveActivity.instance.end();
    notifyListeners();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
  }

  void _tick({required bool haptic}) {
    if (!isRunning) return;

    final remaining = remainingSeconds;

    if (remaining > 0) {
      if (remaining != _lastShownSeconds) {
        _lastShownSeconds = remaining;
        notifyListeners();
      }
      return;
    }

    _stopTicker();
    if (haptic) HapticFeedback.mediumImpact();

    if (isBreak) {
      isBreak = false;
      totalSeconds = focusMinutes * 60;
    } else {
      completedSessions++;
      isBreak = true;
      totalSeconds = breakMinutes * 60;
    }

    _pausedRemaining = totalSeconds;
    // Faz tamamlandı: oturum durdu, Live Activity sonlandırılır. Kullanıcı
    // sıradaki fazı başlatınca yeni bir Live Activity açılır.
    PomodoroLiveActivity.instance.end();
    notifyListeners();
  }

  // Arka plandan dönüşte kalan süre gerçek saatten yeniden hesaplanır;
  // arka planda süre dolduysa faz geçişi uygulanır.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick(haptic: false);
      if (isRunning) _publishLiveActivity();
      notifyListeners();
    }
  }
}
