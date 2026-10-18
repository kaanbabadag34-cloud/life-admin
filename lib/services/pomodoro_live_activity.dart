import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Pomodoro oturumunu iOS Live Activity'ye (kilit ekranı + Dynamic Island)
// yansıtır. Bağımsız bir zamanlayıcı YOKTUR: süre PomodoroSession'dan gelir,
// çalışırken iOS'un yerel zamanlayıcısı (bitiş zamanı) ile akar. Cihaz
// desteklemiyorsa veya Live Activities kapalıysa hiçbir şey yapmaz; hiçbir
// çağrı hata fırlatmaz (Pomodoro normal çalışmaya devam eder).
class PomodoroLiveActivity {
  PomodoroLiveActivity._();

  static final PomodoroLiveActivity instance = PomodoroLiveActivity._();

  static const MethodChannel _channel = MethodChannel('life_admin/live_activity');

  bool get _supported => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> sync({
    required bool isBreak,
    required bool isRunning,
    required DateTime? endsAt,
    required int remainingSeconds,
    required int totalSeconds,
  }) async {
    if (!_supported) return;

    try {
      final end = endsAt ??
          DateTime.now().add(Duration(seconds: remainingSeconds));

      await _channel.invokeMethod<bool>('sync', {
        'isBreak': isBreak,
        'isRunning': isRunning,
        'endMillis': end.millisecondsSinceEpoch,
        'remainingSeconds': remainingSeconds,
        'totalSeconds': totalSeconds,
      });
    } catch (error) {
      if (kDebugMode) debugPrint('[LiveActivity] sync failed: $error');
    }
  }

  Future<void> end() async {
    if (!_supported) return;

    try {
      await _channel.invokeMethod<bool>('end');
    } catch (error) {
      if (kDebugMode) debugPrint('[LiveActivity] end failed: $error');
    }
  }
}
