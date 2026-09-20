import 'package:flutter/material.dart';

class PremiumPage extends StatelessWidget {
  const PremiumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : Colors.black12;
    final secondaryText = isDark ? const Color(0xFFA7A9B0) : Colors.black54;
    final tertiaryText = isDark ? const Color(0xFF7A7D85) : Colors.black45;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Life Admin Premium',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 34,
                ),
                SizedBox(height: 16),
                Text(
                  'Life Admin Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Life Admin’i kişisel yaşam asistanına dönüştür.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const _PremiumFeature(
            icon: Icons.auto_awesome_rounded,
            title: '300 AI işlemi / ay',
            description:
                'Planlarını, randevularını ve görevlerini doğal dille ekle.',
          ),

          const SizedBox(height: 12),

          const _PremiumFeature(
            icon: Icons.notifications_active_outlined,
            title: 'Akıllı hatırlatıcılar',
            description:
                'Önemli planlarını doğru zamanda telefon bildirimiyle hatırla.',
          ),

          const SizedBox(height: 12),

          const _PremiumFeature(
            icon: Icons.psychology_alt_outlined,
            title: 'Gelişmiş AI organizasyonu',
            description:
                'Planlarını anlamlandıran gelişmiş AI özelliklerini kullan.',
          ),

          const SizedBox(height: 12),

          const _PremiumFeature(
            icon: Icons.calendar_month_outlined,
            title: 'Daha güçlü planlama',
            description:
                'Takvim ve organizasyon özelliklerinden daha fazla yararlan.',
          ),

          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: border,
              ),
            ),
            child: Column(
              children: [
                const Text(
                  '₺249',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '/ ay',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: null,
              style: ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(
                    vertical: 18,
                  ),
                ),
              ),
              child: Text(
                'Premium’a Geç',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          const TextButton(
            onPressed: null,
            child: Text(
              'Satın Alımları Geri Yükle',
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'Abonelik iptal edilmediği sürece otomatik olarak yenilenir. Satın alma ve abonelik yönetimi App Store üzerinden yapılır.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tertiaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PremiumFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : Colors.black12;
    final secondaryText = isDark ? const Color(0xFFA7A9B0) : Colors.black54;
    final iconBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 22,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 13,
                    height: 1.4,
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