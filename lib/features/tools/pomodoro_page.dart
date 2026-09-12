import 'dart:async';

import 'package:flutter/material.dart';

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  Timer? _timer;

  int _focusMinutes = 25;
  int _breakMinutes = 5;

  late int _remainingSeconds;

  bool _isRunning = false;
  bool _isBreak = false;

  int _completedSessions = 0;

  @override
  void initState() {
    super.initState();

    _remainingSeconds =
        _focusMinutes * 60;
  }

  void _startTimer() {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (_remainingSeconds > 0) {
          setState(() {
            _remainingSeconds--;
          });

          return;
        }

        timer.cancel();

        setState(() {
          _isRunning = false;

          if (_isBreak) {
            _isBreak = false;

            _remainingSeconds =
                _focusMinutes * 60;
          } else {
            _completedSessions++;

            _isBreak = true;

            _remainingSeconds =
                _breakMinutes * 60;
          }
        });
      },
    );
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

      _remainingSeconds =
          (_isBreak
                  ? _breakMinutes
                  : _focusMinutes) *
              60;
    });
  }

  void _changeFocusMinutes(
    int minutes,
  ) {
    _timer?.cancel();

    setState(() {
      _focusMinutes = minutes;
      _isRunning = false;

      if (!_isBreak) {
        _remainingSeconds =
            minutes * 60;
      }
    });
  }

  void _changeBreakMinutes(
    int minutes,
  ) {
    _timer?.cancel();

    setState(() {
      _breakMinutes = minutes;
      _isRunning = false;

      if (_isBreak) {
        _remainingSeconds =
            minutes * 60;
      }
    });
  }

  String get _formattedTime {
    final minutes =
        _remainingSeconds ~/ 60;

    final seconds =
        _remainingSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pomodoro',
          style: TextStyle(
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ),

      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          const SizedBox(
            height: 12,
          ),

          Center(
            child: Container(
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration:
                  BoxDecoration(
                color: _isBreak
                    ? Colors.green
                        .withValues(
                        alpha: 0.10,
                      )
                    : Colors.black
                        .withValues(
                        alpha: 0.06,
                      ),
                borderRadius:
                    BorderRadius
                        .circular(30),
              ),
              child: Text(
                _isBreak
                    ? 'Mola'
                    : 'Odak',
                style: TextStyle(
                  color: _isBreak
                      ? Colors.green
                      : Colors.black,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 26,
          ),

          Center(
            child: Text(
              _formattedTime,
              style:
                  const TextStyle(
                fontSize: 70,
                fontWeight:
                    FontWeight.w800,
                letterSpacing: -2,
              ),
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Center(
            child: Text(
              _isBreak
                  ? 'Biraz dinlen.'
                  : 'Sadece bu işe odaklan.',
              style:
                  const TextStyle(
                color:
                    Colors.black54,
                fontSize: 15,
              ),
            ),
          ),

          const SizedBox(
            height: 30,
          ),

          Row(
            children: [
              Expanded(
                child:
                    FilledButton.icon(
                  onPressed:
                      _isRunning
                          ? _pauseTimer
                          : _startTimer,
                  icon: Icon(
                    _isRunning
                        ? Icons
                            .pause_rounded
                        : Icons
                            .play_arrow_rounded,
                  ),
                  label: Text(
                    _isRunning
                        ? 'Duraklat'
                        : 'Başlat',
                  ),
                  style:
                      FilledButton
                          .styleFrom(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 16,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              IconButton.filledTonal(
                onPressed:
                    _resetTimer,
                icon: const Icon(
                  Icons
                      .restart_alt_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 32,
          ),

          const Text(
            'Odak Süresi',
            style: TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final minutes
                  in [
                15,
                25,
                45,
                60,
              ])
                ChoiceChip(
                  label: Text(
                    '$minutes dk',
                  ),
                  selected:
                      _focusMinutes ==
                          minutes,
                  onSelected: (_) {
                    _changeFocusMinutes(
                      minutes,
                    );
                  },
                ),
            ],
          ),

          const SizedBox(
            height: 28,
          ),

          const Text(
            'Mola Süresi',
            style: TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final minutes
                  in [
                5,
                10,
                15,
              ])
                ChoiceChip(
                  label: Text(
                    '$minutes dk',
                  ),
                  selected:
                      _breakMinutes ==
                          minutes,
                  onSelected: (_) {
                    _changeBreakMinutes(
                      minutes,
                    );
                  },
                ),
            ],
          ),

          const SizedBox(
            height: 30,
          ),

          Container(
            padding:
                const EdgeInsets
                    .all(18),
            decoration:
                BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius
                      .circular(20),
              border: Border.all(
                color:
                    Colors.black12,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons
                      .local_fire_department_outlined,
                ),

                const SizedBox(
                  width: 12,
                ),

                const Expanded(
                  child: Text(
                    'Tamamlanan odak',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .w600,
                    ),
                  ),
                ),

                Text(
                  '$_completedSessions',
                  style:
                      const TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight
                            .w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}