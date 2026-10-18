import 'package:flutter/material.dart';

import 'countdown_page.dart';
import 'journal_page.dart';
import 'pomodoro_page.dart';

// Referans görsellerdeki her araç kartının kendi renk ailesi var —
// Pomodoro (uygulamanın kendi mor/lila accent'i), Günlük (mavi), Sayaç
// (pembe/mor). Bu üç ton, App Theme'in kendi accent'iyle uyumlu, elle
// seçilmiş ama "rastgele" değil — hepsi aynı doygunluk/parlaklık ailesinde.
const Color _journalBlue = Color(0xFF4C8DF0);
const Color _journalBlueDark = Color(0xFF6FA8FF);
const Color _countdownPink = Color(0xFFB15FE0);
const Color _countdownPinkDark = Color(0xFFD08CF5);

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF0B0B0D)
        : const Color(0xFFF7F7FA);
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);
    final accent = colors.primary;
    final journalColor = isDark ? _journalBlueDark : _journalBlue;
    final countdownColor = isDark ? _countdownPinkDark : _countdownPink;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Araçlar',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Hayatını biraz daha kolaylaştır.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondaryText,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 26),

            _ToolCard(
              accent: accent,
              icon: Icons.timer_outlined,
              heroIcon: Icons.timer_rounded,
              title: 'Pomodoro',
              description: 'Odaklan, mola ver, tekrar başla.',
              chips: const ['Odak', 'Verimlilik', 'Disiplin'],
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const PomodoroPage()));
              },
            ),

            const SizedBox(height: 16),

            _ToolCard(
              accent: journalColor,
              icon: Icons.menu_book_outlined,
              heroIcon: Icons.auto_stories_rounded,
              title: 'Günlük',
              description: 'Gününü yaz, geçmiş notlarına dön.',
              chips: const ['Farkındalık', 'Düşünceler', 'Gelişim'],
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const JournalPage()));
              },
            ),

            const SizedBox(height: 16),

            _ToolCard(
              accent: countdownColor,
              icon: Icons.hourglass_bottom_rounded,
              heroIcon: Icons.hourglass_top_rounded,
              title: 'Sayaç',
              description: 'Önemli tarihlere kaç gün kaldığını takip et.',
              chips: const ['Hedefler', 'Planlama', 'Motivasyon'],
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CountdownPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final IconData heroIcon;
  final String title;
  final String description;
  final List<String> chips;
  final VoidCallback onTap;

  const _ToolCard({
    required this.accent,
    required this.icon,
    required this.heroIcon,
    required this.title,
    required this.description,
    required this.chips,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardTopAlpha = isDark ? 0.20 : 0.12;
    final cardBottomAlpha = isDark ? 0.06 : 0.04;
    final borderAlpha = isDark ? 0.38 : 0.22;
    final chipBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.55);
    final chipText = isDark ? const Color(0xFFE9E9EE) : const Color(0xFF3A3A44);
    final titleColor = isDark ? Colors.white : const Color(0xFF17171A);
    final descColor = isDark
        ? const Color(0xFFB9BAC2)
        : const Color(0xFF5B5B66);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: cardTopAlpha),
                accent.withValues(alpha: cardBottomAlpha),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: borderAlpha)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                blurRadius: 28,
                spreadRadius: -6,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.22 : 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 24, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: descColor,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ToolHero(accent: accent, icon: heroIcon, isDark: isDark),
                  const SizedBox(width: 8),
                  _ArrowButton(accent: accent, isDark: isDark),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: accent.withValues(alpha: isDark ? 0.28 : 0.18),
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: chipText,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Referanstaki "3B" görsel objelerin (parlak halka, cilalı kitap, kum
// saati) birebir illüstrasyonu için görsel dosyası gerekiyor — burada
// onun yerine aynı renk/ışıltı hissini veren, saf Flutter widget'larıyla
// (gradient + glow + ikon) oluşturulmuş sade bir "hero" rozet kullanıldı.
class _ToolHero extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final bool isDark;

  const _ToolHero({
    required this.accent,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.65),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.55 : 0.35),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 26, color: Colors.white),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final Color accent;
  final bool isDark;

  const _ArrowButton({required this.accent, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white,
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.4 : 0.25),
        ),
      ),
      child: Icon(Icons.chevron_right_rounded, size: 19, color: accent),
    );
  }
}
