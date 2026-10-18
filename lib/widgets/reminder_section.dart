import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/reminder_format.dart';

// Hatırlatıcı seçici — takvim ekleme/düzenleme sheet'leri ve ana sayfa
// görev detayı aynı bileşeni kullanır. "Kapalı / Tam saatinde / 15 dk / 30 dk
// / 1 saat" hazır seçenekleri; AI'nın ayarladığı farklı bir değer (ör. "2 gün
// önce") varsa ayrı, seçili bir chip olarak gösterilir ve korunur.
// `onSelect(null)` = hatırlatıcı kapalı, `onSelect(0)` = tam saatinde.
Widget buildReminderSection(
  BuildContext context, {
  required bool hasTime,
  required bool reminderEnabled,
  required int reminderMinutesBefore,
  required ValueChanged<int?> onSelect,
}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF23252B) : const Color(0xFFF3F4F7);
  final textColor = isDark ? Colors.white : const Color(0xFF17171A);
  final muted = isDark ? const Color(0xFFA7A9B0) : const Color(0xFF6B7280);

  Widget chip(String label, bool selected, VoidCallback? onTap) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.primary : surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.white
                : (onTap == null ? muted : textColor),
          ),
        ),
      ),
    );
  }

  const presets = [0, 15, 30, 60];
  final isCustom = reminderEnabled && !presets.contains(reminderMinutesBefore);

  return Opacity(
    opacity: hasTime ? 1 : 0.55,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hatırlatıcı',
          style: TextStyle(
            fontSize: 13,
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (!hasTime)
          Text(
            'Hatırlatıcı için önce bir saat belirle.',
            style: TextStyle(fontSize: 12.5, color: muted),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Kapalı', !reminderEnabled, () => onSelect(null)),
              chip(
                'Tam saatinde',
                reminderEnabled && reminderMinutesBefore == 0,
                () => onSelect(0),
              ),
              chip(
                '15 dk önce',
                reminderEnabled && reminderMinutesBefore == 15,
                () => onSelect(15),
              ),
              chip(
                '30 dk önce',
                reminderEnabled && reminderMinutesBefore == 30,
                () => onSelect(30),
              ),
              chip(
                '1 saat önce',
                reminderEnabled && reminderMinutesBefore == 60,
                () => onSelect(60),
              ),
              if (isCustom)
                chip(
                  reminderOffsetLabel(reminderMinutesBefore),
                  true,
                  () => onSelect(reminderMinutesBefore),
                ),
            ],
          ),
      ],
    ),
  );
}
