
import 'package:flutter/material.dart';

import 'countdown_page.dart';
import 'journal_page.dart';
import 'pomodoro_page.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Araçlar',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 24,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          8,
          20,
          32,
        ),
        children: [
          Text(
            'Hayatını biraz daha kolaylaştır.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondaryText,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 22),

          _ToolCard(
            icon: Icons.timer_outlined,
            title: 'Pomodoro',
            description:
                'Odaklan, mola ver, tekrar başla.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const PomodoroPage(),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          _ToolCard(
            icon: Icons.menu_book_outlined,
            title: 'Günlük',
            description:
                'Gününü yaz, geçmiş notlarına dön.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const JournalPage(),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          _ToolCard(
            icon: Icons.hourglass_bottom_rounded,
            title: 'Sayaç',
            description:
                'Önemli tarihlere kaç gün kaldığını takip et.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const CountdownPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark =
        theme.brightness == Brightness.dark;

    final surface = isDark
        ? const Color(0xFF171A1F)
        : Colors.white;

    final border = isDark
        ? const Color(0xFF2B2F36)
        : const Color(0xFFE5E7EB);

    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(16),
            border: Border.all(
              color: border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary
                      .withValues(
                    alpha: isDark
                        ? 0.14
                        : 0.09,
                  ),
                  borderRadius:
                      BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  size: 23,
                  color: colors.primary,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      description,
                      style: theme
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                        color:
                            secondaryText,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                Icons.chevron_right_rounded,
                color: secondaryText,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
