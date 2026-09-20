import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage>
    with TickerProviderStateMixin {
  Timer? _timer;

  int _focusMinutes = 25;
  int _breakMinutes = 5;

  late int _totalSeconds;
  late int _remainingSeconds;

  bool _isRunning = false;
  bool _isBreak = false;

  int _completedSessions = 0;

  // Çalışırken halka/orta butonun etrafında yavaşça "nefes alan" glow.
  late final AnimationController _glowController;

  // Sayfa açılışında hafif fade + scale giriş — "mockup değil, gerçek
  // production uygulaması" hissi için ucuz ama etkili bir dokunuş.
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();

    _totalSeconds = _focusMinutes * 60;
    _remainingSeconds = _totalSeconds;

    // Route bazlı yön yönetimi: SADECE bu sayfa hem dikey hem yatay
    // dönebilsin diye main.dart'ta kurulan uygulama geneli portraitUp
    // kilidi burada geçici olarak gevşetiliyor. dispose() içinde geri
    // kilitleniyor ki bu sayfadan çıkınca uygulamanın geri kalanı yine
    // sadece portraitUp'ta kalsın.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
  }

  void _startTimer() {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });

        return;
      }

      timer.cancel();
      HapticFeedback.mediumImpact();

      setState(() {
        _isRunning = false;

        if (_isBreak) {
          _isBreak = false;
          _totalSeconds = _focusMinutes * 60;
          _remainingSeconds = _totalSeconds;
        } else {
          _completedSessions++;
          _isBreak = true;
          _totalSeconds = _breakMinutes * 60;
          _remainingSeconds = _totalSeconds;
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();

    setState(() {
      _isRunning = false;
    });
  }

  void _resetTimer() {
    _timer?.cancel();

    setState(() {
      _isRunning = false;
      _totalSeconds = (_isBreak ? _breakMinutes : _focusMinutes) * 60;
      _remainingSeconds = _totalSeconds;
    });
  }

  // Referans tasarımdaki 3. buton ("durdur") mevcut kodda hiç yoktu — en
  // yakın gerçekçi karşılığı budur: zamanlayıcıyı durdurup Pomodoro
  // ekranından çıkmak. Yeni bir zamanlayıcı durumu icat edilmedi.
  void _stopAndExit() {
    _timer?.cancel();
    Navigator.of(context).maybePop();
  }

  void _changeFocusMinutes(int minutes) {
    _timer?.cancel();

    setState(() {
      _focusMinutes = minutes;
      _isRunning = false;

      if (!_isBreak) {
        _totalSeconds = minutes * 60;
        _remainingSeconds = _totalSeconds;
      }
    });
  }

  void _changeBreakMinutes(int minutes) {
    _timer?.cancel();

    setState(() {
      _breakMinutes = minutes;
      _isRunning = false;

      if (_isBreak) {
        _totalSeconds = minutes * 60;
        _remainingSeconds = _totalSeconds;
      }
    });
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double get _progress {
    if (_totalSeconds <= 0) return 0;
    return (_remainingSeconds / _totalSeconds).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _glowController.dispose();
    _entranceController.dispose();

    // Sayfadan çıkınca uygulamanın geri kalanı yine SADECE portraitUp'a
    // dönsün.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    super.dispose();
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PomodoroSettingsSheet(
        focusMinutes: _focusMinutes,
        breakMinutes: _breakMinutes,
        completedSessions: _completedSessions,
        onFocusChanged: _changeFocusMinutes,
        onBreakChanged: _changeBreakMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Referans görsellerle birebir örtüşsün diye bu ekrana özel, saf
    // siyah/beyaz zemin — uygulamanın diğer ekranlarındaki hafif kırık
    // beyaz/antrasit zemin burada BİLEREK kullanılmıyor.
    final backgroundColor = isDark ? const Color(0xFF0B0B0D) : Colors.white;
    final circleBg = isDark ? const Color(0xFF232326) : const Color(0xFFF2F2F5);
    final circleIconColor = isDark ? Colors.white : const Color(0xFF17171A);
    final trackColor = isDark
        ? const Color(0xFF232028)
        : const Color(0xFFEDEAF7);
    final timeColor = isDark ? Colors.white : const Color(0xFF17171A);
    // Mod göstergesi metin rozeti yerine halka rengiyle ifade ediliyor —
    // referansın minimal görünümüne yeni bir öğe eklenmiyor. Mola rengi,
    // uygulamada zaten kullanılan aynı yeşil tonla tutarlı.
    final ringColor = _isBreak ? const Color(0xFF4C9F70) : colors.primary;

    final header = _PomodoroHeader(
      circleBg: circleBg,
      iconColor: circleIconColor,
      textColor: timeColor,
      onClose: () => Navigator.of(context).maybePop(),
      onMore: _openSettingsSheet,
      titleStyle: theme.textTheme.headlineLarge,
    );

    final controlsRow = _PomodoroControls(
      axis: Axis.horizontal,
      isRunning: _isRunning,
      circleBg: circleBg,
      circleIconColor: circleIconColor,
      accentColor: ringColor,
      glowController: _glowController,
      onReset: _resetTimer,
      onPlayPause: _isRunning ? _pauseTimer : _startTimer,
      onStop: _stopAndExit,
    );

    final controlsColumn = _PomodoroControls(
      axis: Axis.vertical,
      isRunning: _isRunning,
      circleBg: circleBg,
      circleIconColor: circleIconColor,
      accentColor: ringColor,
      glowController: _glowController,
      onReset: _resetTimer,
      onPlayPause: _isRunning ? _pauseTimer : _startTimer,
      onStop: _stopAndExit,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        width: double.infinity,
        height: double.infinity,
        color: backgroundColor,
        child: SafeArea(
          child: FadeTransition(
            opacity: _entranceController,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                CurvedAnimation(
                  parent: _entranceController,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: OrientationBuilder(
                builder: (context, orientation) {
                  if (orientation == Orientation.landscape) {
                    return Column(
                      children: [
                        header,
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final diameter = math
                                        .min(
                                          constraints.maxWidth * 0.9,
                                          constraints.maxHeight * 0.92,
                                        )
                                        .clamp(140.0, 300.0);

                                    return Center(
                                      child: _PomodoroRing(
                                        diameter: diameter,
                                        progress: _progress,
                                        trackColor: trackColor,
                                        ringColor: ringColor,
                                        timeColor: timeColor,
                                        timeText: _formattedTime,
                                        glowController: _glowController,
                                        isRunning: _isRunning,
                                        timeStyle:
                                            theme.textTheme.headlineLarge,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 28),
                                child: controlsColumn,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      header,
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final diameter = math
                                .min(
                                  constraints.maxWidth * 0.82,
                                  constraints.maxHeight * 0.62,
                                )
                                .clamp(200.0, 320.0);

                            return Center(
                              child: _PomodoroRing(
                                diameter: diameter,
                                progress: _progress,
                                trackColor: trackColor,
                                ringColor: ringColor,
                                timeColor: timeColor,
                                timeText: _formattedTime,
                                glowController: _glowController,
                                isRunning: _isRunning,
                                timeStyle: theme.textTheme.headlineLarge,
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32, top: 8),
                        child: controlsRow,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PomodoroHeader extends StatelessWidget {
  final Color circleBg;
  final Color iconColor;
  final Color textColor;
  final VoidCallback onClose;
  final VoidCallback onMore;
  final TextStyle? titleStyle;

  const _PomodoroHeader({
    required this.circleBg,
    required this.iconColor,
    required this.textColor,
    required this.onClose,
    required this.onMore,
    required this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CircleIconButton(
            icon: Icons.close_rounded,
            background: circleBg,
            iconColor: iconColor,
            onTap: onClose,
          ),
          Text(
            'Pomodoro',
            style: titleStyle?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          _CircleIconButton(
            icon: Icons.more_horiz_rounded,
            background: circleBg,
            iconColor: iconColor,
            onTap: onMore,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color iconColor;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _CircleIconButton({
    required this.icon,
    required this.background,
    required this.iconColor,
    required this.onTap,
    this.size = 52,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}

// Halka + ortadaki büyük süre metni. Çap dışarıdan (LayoutBuilder ile)
// hesaplanıp veriliyor — bu yüzden hem dikey hem yatay modda, hem de
// farklı iPhone boyutlarında taşma olmadan orantılı şekilde küçülüp
// büyüyor.
class _PomodoroRing extends StatelessWidget {
  final double diameter;
  final double progress;
  final Color trackColor;
  final Color ringColor;
  final Color timeColor;
  final String timeText;
  final AnimationController glowController;
  final bool isRunning;
  final TextStyle? timeStyle;

  const _PomodoroRing({
    required this.diameter,
    required this.progress,
    required this.trackColor,
    required this.ringColor,
    required this.timeColor,
    required this.timeText,
    required this.glowController,
    required this.isRunning,
    required this.timeStyle,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = (diameter * 0.22).clamp(36.0, 72.0);
    final strokeWidth = (diameter * 0.055).clamp(10.0, 18.0);

    return AnimatedBuilder(
      animation: glowController,
      builder: (context, child) {
        final glowStrength = isRunning
            ? 0.55 + 0.45 * glowController.value
            : 0.4;

        return SizedBox(
          width: diameter,
          height: diameter,
          child: CustomPaint(
            painter: _PomodoroRingPainter(
              progress: progress,
              trackColor: trackColor,
              progressColor: ringColor,
              strokeWidth: strokeWidth,
              glowStrength: glowStrength,
            ),
            child: child,
          ),
        );
      },
      child: Center(
        child: Text(
          timeText,
          textAlign: TextAlign.center,
          style: timeStyle?.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
            color: timeColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _PomodoroRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  final double glowStrength;

  _PomodoroRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.glowStrength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (sweep <= 0) return;

    const startAngle = -math.pi / 2;

    // Halkanın arkasında yumuşak, bulanık bir glow katmanı — sonra
    // üzerine net halka çizilir. Bu, referanstaki "neon" hissini verir.
    final glowPaint = Paint()
      ..color = progressColor.withValues(alpha: 0.5 * glowStrength)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 16
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawArc(rect, startAngle, sweep, false, glowPaint);

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _PomodoroRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.glowStrength != glowStrength;
  }
}

// 3 kontrol butonu — dikeyde yatay sıra, yatay modda dikey sıra (aynı
// buton bileşenleri, sadece eksen değişiyor) ki "aynı tasarım dili"
// korunsun.
class _PomodoroControls extends StatelessWidget {
  final Axis axis;
  final bool isRunning;
  final Color circleBg;
  final Color circleIconColor;
  final Color accentColor;
  final AnimationController glowController;
  final VoidCallback onReset;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;

  const _PomodoroControls({
    required this.axis,
    required this.isRunning,
    required this.circleBg,
    required this.circleIconColor,
    required this.accentColor,
    required this.glowController,
    required this.onReset,
    required this.onPlayPause,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final gap = axis == Axis.horizontal
        ? const SizedBox(width: 22)
        : const SizedBox(height: 22);

    final children = <Widget>[
      _CircleIconButton(
        icon: Icons.refresh_rounded,
        background: circleBg,
        iconColor: circleIconColor,
        onTap: onReset,
        size: 58,
        iconSize: 22,
      ),
      gap,
      _PlayPauseButton(
        isRunning: isRunning,
        color: accentColor,
        glowController: glowController,
        onTap: onPlayPause,
      ),
      gap,
      _CircleIconButton(
        icon: Icons.stop_rounded,
        background: circleBg,
        iconColor: circleIconColor,
        onTap: onStop,
        size: 58,
        iconSize: 22,
      ),
    ];

    return axis == Axis.horizontal
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: children,
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: children,
          );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isRunning;
  final Color color;
  final AnimationController glowController;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.isRunning,
    required this.color,
    required this.glowController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowController,
      builder: (context, child) {
        final t = isRunning ? glowController.value : 0.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35 + 0.25 * t),
                blurRadius: 22 + 14 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 88,
            height: 88,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(isRunning),
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// "..." menüsünün açtığı, mevcut süre seçimi + tamamlanan oturum sayacı
// işlevini barındıran alt sayfa — referans görselde bu buton dekoratif
// değil, gerçek bir seçenekler menüsü olarak duruyordu; hiçbir işlev
// kaybedilmedi, sadece ana ekrandan buraya taşındı.
class _PomodoroSettingsSheet extends StatefulWidget {
  final int focusMinutes;
  final int breakMinutes;
  final int completedSessions;
  final ValueChanged<int> onFocusChanged;
  final ValueChanged<int> onBreakChanged;

  const _PomodoroSettingsSheet({
    required this.focusMinutes,
    required this.breakMinutes,
    required this.completedSessions,
    required this.onFocusChanged,
    required this.onBreakChanged,
  });

  @override
  State<_PomodoroSettingsSheet> createState() => _PomodoroSettingsSheetState();
}

class _PomodoroSettingsSheetState extends State<_PomodoroSettingsSheet> {
  late int _focusMinutes;
  late int _breakMinutes;

  @override
  void initState() {
    super.initState();
    _focusMinutes = widget.focusMinutes;
    _breakMinutes = widget.breakMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : Colors.black12;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Odak Süresi',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final minutes in [15, 25, 45, 60])
                  ChoiceChip(
                    label: Text('$minutes dk'),
                    selected: _focusMinutes == minutes,
                    onSelected: (_) {
                      setState(() => _focusMinutes = minutes);
                      widget.onFocusChanged(minutes);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              'Mola Süresi',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final minutes in [5, 10, 15])
                  ChoiceChip(
                    label: Text('$minutes dk'),
                    selected: _breakMinutes == minutes,
                    onSelected: (_) {
                      setState(() => _breakMinutes = minutes);
                      widget.onBreakChanged(minutes);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department_outlined),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Tamamlanan odak',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${widget.completedSessions}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
