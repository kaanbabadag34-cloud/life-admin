import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/perf_trace.dart';

import '../features/plans/speech_normalizer.dart';
import '../services/speech_service.dart';

enum _VoicePhase { idle, starting, listening, canceling, processing }

class _VoiceUi {
  final _VoicePhase phase;
  final String text;

  const _VoiceUi(this.phase, [this.text = '']);
}

// AI giriş alanındaki "basılı tut ve konuş" mikrofon butonu. Parmağı kaldırınca
// konuşma tamamlanır ve metin [onTranscript] ile mevcut AI görev akışına verilir
// (ayrı bir AI mantığı yoktur). Sola/yukarı kaydırıp bırakmak iptal eder.
class VoiceMicButton extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String> onTranscript;

  // Parmak kalkınca true (metin bekleniyor), iş bitince/iptalde false.
  final ValueChanged<bool>? onBusyChanged;

  const VoiceMicButton({
    super.key,
    required this.enabled,
    required this.onTranscript,
    this.onBusyChanged,
  });

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton>
    with WidgetsBindingObserver {
  static const Duration _minHold = Duration(milliseconds: 600);
  static const Duration _maxDuration = Duration(seconds: 45);
  static const double _cancelDistance = 70;

  final SpeechService _speech = SpeechService.instance;
  final ValueNotifier<_VoiceUi> _ui =
      ValueNotifier(const _VoiceUi(_VoicePhase.idle));
  final ValueNotifier<double> _level = ValueNotifier(0);

  OverlayEntry? _overlay;
  Offset _downPosition = Offset.zero;
  DateTime? _startedAt;
  bool _pointerDown = false;
  bool _delivered = false;
  bool _hintShown = false;
  bool _busyReported = false;
  PerfTrace? _voicePerf;
  Timer? _maxTimer;
  Timer? _processingGuard;

  _VoicePhase get _phase => _ui.value.phase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _abort();
    _ui.dispose();
    _level.dispose();
    super.dispose();
  }

  // Uygulama arka plana geçerse mikrofon hemen durdurulur.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase != _VoicePhase.idle) {
      _abort();
      _releaseBusy();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _attachCallbacks() {
    _speech.onLevel = (value) => _level.value = value;
    _speech.onPartial = (text) {
      if (_phase == _VoicePhase.listening || _phase == _VoicePhase.canceling) {
        _ui.value = _VoiceUi(_phase, text);
      }
    };
    _speech.onFinal = _handleFinal;
    _speech.onError = _handleError;
  }

  void _detachCallbacks() {
    _speech.onLevel = null;
    _speech.onPartial = null;
    _speech.onFinal = null;
    _speech.onError = null;
  }

  void _setBusy(bool value) {
    if (_busyReported == value) return;
    _busyReported = value;
    widget.onBusyChanged?.call(value);
  }

  void _showOverlay() {
    _overlay?.remove();
    _overlay = OverlayEntry(
      builder: (_) => _VoiceOverlay(ui: _ui, level: _level),
    );
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  // Her çıkış yolunda: mikrofonu bırak, overlay'i kaldır, durumu sıfırla.
  void _abort() {
    _maxTimer?.cancel();
    _processingGuard?.cancel();
    _maxTimer = null;
    _processingGuard = null;

    if (_phase != _VoicePhase.idle) {
      _speech.cancel();
    }

    _detachCallbacks();
    _overlay?.remove();
    _overlay = null;
    _level.value = 0;
    _ui.value = const _VoiceUi(_VoicePhase.idle);
  }

  // Görev akışı devraldı veya iş iptal oldu: busy göstergesini kapat.
  void _releaseBusy() => _setBusy(false);

  Future<void> _onDown(PointerDownEvent event) async {
    if (!widget.enabled || _phase != _VoicePhase.idle) return;

    _pointerDown = true;
    _downPosition = event.position;
    _delivered = false;
    _ui.value = const _VoiceUi(_VoicePhase.starting);

    var status = await _speech.permissionStatus();

    if (status == SpeechPermission.notDetermined) {
      // Sistem izin penceresi bu dokunuşu böler; izin sonrası yeniden basılır.
      status = await _speech.requestPermissions();
      _ui.value = const _VoiceUi(_VoicePhase.idle);

      if (status == SpeechPermission.granted) {
        _snack('İzin verildi. Mikrofona basılı tutarak konuşabilirsin.');
      } else {
        _showDeniedDialog();
      }
      return;
    }

    if (status != SpeechPermission.granted) {
      _ui.value = const _VoiceUi(_VoicePhase.idle);
      _showDeniedDialog();
      return;
    }

    if (!_pointerDown) {
      _ui.value = const _VoiceUi(_VoicePhase.idle);
      return;
    }

    _attachCallbacks();

    final started = await _speech.start();

    if (!mounted) return;

    if (!started) {
      _abort();
      _snack('Ses algılama başlatılamadı. Lütfen tekrar dene.');
      return;
    }

    // Haptic ve overlay mikrofon GERÇEKTEN hazır olduktan sonra gelir: bu
    // işaret "şimdi konuş" demektir, böylece ilk kelimeler kesilmez.
    HapticFeedback.lightImpact();
    _startedAt = DateTime.now();
    _ui.value = const _VoiceUi(_VoicePhase.listening);
    _showOverlay();
    _maxTimer = Timer(_maxDuration, _finishRecording);

    // Başlatma sürerken parmak zaten kalktıysa kısa dokunuş olarak ele al.
    if (!_pointerDown) _finishRecording();
  }

  void _onMove(PointerMoveEvent event) {
    if (_phase != _VoicePhase.listening && _phase != _VoicePhase.canceling) {
      return;
    }

    final delta = event.position - _downPosition;
    final shouldCancel =
        delta.dx < -_cancelDistance || delta.dy < -_cancelDistance;
    final next = shouldCancel ? _VoicePhase.canceling : _VoicePhase.listening;

    if (next != _phase) {
      HapticFeedback.selectionClick();
      _ui.value = _VoiceUi(next, _ui.value.text);
    }
  }

  void _onUp(PointerEvent event) {
    _pointerDown = false;
    _finishRecording();
  }

  void _finishRecording() {
    if (_phase != _VoicePhase.listening && _phase != _VoicePhase.canceling) {
      if (_phase == _VoicePhase.starting) _ui.value = const _VoiceUi(_VoicePhase.idle);
      return;
    }

    final held = DateTime.now().difference(_startedAt ?? DateTime.now());
    final canceled = _phase == _VoicePhase.canceling;

    _maxTimer?.cancel();

    if (canceled) {
      _abort();
      HapticFeedback.selectionClick();
      return;
    }

    if (held < _minHold) {
      _abort();
      if (!_hintShown) {
        _hintShown = true;
        _snack('Konuşmak için mikrofona basılı tut.');
      }
      return;
    }

    // Parmak kalktı: dinleme ekranı HEMEN kapanır; son sonuç arka planda
    // beklenir (metin erken kesilmez) ve bu sürede yalnızca tek bir yükleniyor
    // göstergesi (gönder butonu) görünür. Native taraf sonuç gelmezse kısa
    // bir zaman aşımıyla eldeki metni döndürür.
    final lastPartial = _ui.value.text;
    _overlay?.remove();
    _overlay = null;
    _level.value = 0;
    _ui.value = _VoiceUi(_VoicePhase.processing, lastPartial);
    _voicePerf = PerfTrace('voice')..mark('listen');
    _setBusy(true);
    _speech.stop();
    _processingGuard = Timer(const Duration(seconds: 5), () {
      if (_phase == _VoicePhase.processing) {
        final text = _ui.value.text;
        _abort();
        _deliver(text, 0);
      }
    });
  }

  void _handleFinal(String text, double confidence) {
    if (_phase != _VoicePhase.processing) return;
    _abort();
    _deliver(text, confidence);
  }

  void _handleError(String code) {
    if (_phase == _VoicePhase.idle) return;

    final partial = _ui.value.text;
    final wasProcessing = _phase == _VoicePhase.processing;
    _abort();

    if (wasProcessing && partial.trim().isNotEmpty) {
      _deliver(partial, 0);
    } else {
      _releaseBusy();
      _snack('Ses algılanamadı. Lütfen tekrar dene.');
    }
  }

  Future<void> _deliver(String text, double confidence) async {
    if (_delivered) return;
    _delivered = true;

    _voicePerf?.mark('recognition-final');
    _voicePerf?.finish();
    _voicePerf = null;

    final normalized = normalizeSpeechText(text);
    var cleaned = normalized.text.trim();

    // Sessizlik / çok kısa kayıt: görev oluşturma.
    if (cleaned.length < 3) {
      _releaseBusy();
      _snack('Konuşma algılanamadı. Lütfen tekrar dene.');
      return;
    }

    // Belirsiz ("yarın" mı "yarım" mı?) veya düşük güvenli tanımada görevi
    // sessizce yanlış oluşturmak yerine kullanıcıdan onay istenir.
    final lowConfidence = confidence > 0 && confidence < 0.45;

    if (normalized.yarimAmbiguous || lowConfidence) {
      final choice = await _confirmTranscript(
        cleaned,
        yarinAlternative: normalized.yarimAmbiguous
            ? normalized.yarinAlternative
            : null,
      );

      if (choice == null) {
        _releaseBusy();
        return;
      }
      cleaned = choice;
    }

    HapticFeedback.mediumImpact();
    // Aynı karede busy kapanır ve görev akışı kendi yükleniyor durumunu açar.
    _releaseBusy();
    widget.onTranscript(cleaned);
  }

  Future<String?> _confirmTranscript(String text, {String? yarinAlternative}) {
    if (!mounted) return Future.value(null);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            yarinAlternative != null
                ? '“Yarın” mı demek istedin?'
                : 'Şunu mu dedin?',
          ),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            if (yarinAlternative != null)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(yarinAlternative),
                child: const Text('Yarın'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(text),
              child: Text(yarinAlternative != null ? 'Olduğu gibi' : 'Oluştur'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeniedDialog() async {
    if (!mounted) return;

    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Mikrofon ve konuşma tanıma gerekli'),
          content: const Text(
            'Sesle görev eklemek için iPhone Ayarlar → Life Admin bölümünden '
            'Mikrofon ve Konuşma Tanıma izinlerini vermen gerekiyor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Ayarları Aç'),
            ),
          ],
        );
      },
    );

    if (open == true) {
      try {
        await launchUrl(Uri.parse('app-settings:'));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;

    return Semantics(
      button: true,
      label: 'Sesle görev ekle, basılı tut ve konuş',
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        child: Opacity(
          opacity: active ? 1 : 0.5,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.mic_none_rounded,
              size: 22,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }
}

// Konuşurken ekranın ortasında beliren, hafif blur'lu ses dalgası kartı.
class _VoiceOverlay extends StatefulWidget {
  final ValueListenable<_VoiceUi> ui;
  final ValueListenable<double> level;

  const _VoiceOverlay({required this.ui, required this.level});

  @override
  State<_VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<_VoiceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  double _smoothed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1B1D22) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF17171A);
    final muted = isDark ? const Color(0xFFA7A9B0) : const Color(0xFF6B7280);

    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.28),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ValueListenableBuilder<_VoiceUi>(
              valueListenable: widget.ui,
              builder: (context, ui, _) {
                final canceling = ui.phase == _VoicePhase.canceling;
                final processing = ui.phase == _VoicePhase.processing;
                final accent = canceling
                    ? theme.colorScheme.error
                    : const Color(0xFF8B7CF6);

                final title = processing
                    ? 'Anlaşılıyor…'
                    : (canceling ? 'Bırak: iptal' : 'Dinliyorum…');
                final hint = processing
                    ? 'Görev hazırlanıyor'
                    : (canceling
                        ? 'Parmağını bırakınca kayıt silinir'
                        : 'Bitince bırak • İptal için sola kaydır');

                return Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 380),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: canceling ? accent : textColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 64,
                        child: processing
                            ? Center(
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: accent,
                                  ),
                                ),
                              )
                            : AnimatedBuilder(
                                animation: _ticker,
                                builder: (context, _) {
                                  _smoothed = _smoothed * 0.65 +
                                      widget.level.value * 0.35;
                                  return CustomPaint(
                                    size: const Size(double.infinity, 64),
                                    painter: _WavePainter(
                                      level: _smoothed,
                                      time: _ticker.value,
                                      color: accent,
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 42),
                        child: Text(
                          ui.text.isEmpty ? ' ' : ui.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hint,
                        style: TextStyle(color: muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double level;
  final double time;
  final Color color;

  const _WavePainter({
    required this.level,
    required this.time,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 31;
    final gap = 5.0;
    final barWidth = math.min(5.0, (size.width - gap * (bars - 1)) / bars);
    final total = bars * barWidth + (bars - 1) * gap;
    final startX = (size.width - total) / 2;
    final centerY = size.height / 2;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < bars; i++) {
      // Ortada yüksek, kenarlara doğru alçalan zarf; ses seviyesiyle ölçeklenir.
      final position = (i - (bars - 1) / 2) / ((bars - 1) / 2);
      final envelope = math.pow(1 - position.abs(), 1.4).toDouble();
      final wobble =
          0.5 + 0.5 * math.sin(time * 2 * math.pi * 2 + i * 0.55);
      final amplitude = 0.08 + level * 0.92 * wobble;
      final half = math.max(2.5, (size.height / 2) * envelope * amplitude);

      paint.color = color.withValues(alpha: 0.35 + 0.65 * envelope);

      final x = startX + i * (barWidth + gap) + barWidth / 2;
      canvas.drawLine(Offset(x, centerY - half), Offset(x, centerY + half), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => true;
}
