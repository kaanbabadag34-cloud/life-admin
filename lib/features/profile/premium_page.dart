import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'purchase_service.dart';

// TODO: Gerçek, yayınlanmış Kullanım Koşulları / Gizlilik Politikası
// sayfaları hazır olduğunda bu iki URL'i değiştir. Apple, abonelik
// paywall'larında bu linklerin ÇALIŞIYOR olmasını zorunlu tutuyor
// (App Store Review Guidelines 3.1.2) — bu yüzden placeholder olarak
// bırakılmamalı.
const String _termsUrl = 'https://applifeadmin.com/terms';
const String _privacyUrl = 'https://applifeadmin.com/privacy';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  PremiumPlan _selectedPlan = PremiumPlan.yearly;

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.initialize();
    PurchaseService.instance.addListener(_onPurchaseServiceChanged);
  }

  @override
  void dispose() {
    PurchaseService.instance.removeListener(_onPurchaseServiceChanged);
    super.dispose();
  }

  void _onPurchaseServiceChanged() {
    if (!mounted) return;

    final service = PurchaseService.instance;

    if (service.status == PurchaseFlowStatus.success) {
      // Success event'i hemen tüket (idle'a döndür) ki bu sayfa tekrar
      // açılıp kapansa bile aynı event ikinci kez pop tetiklemesin.
      service.resetStatus();
      Navigator.of(context).pop();
      return;
    }

    if (service.status == PurchaseFlowStatus.error &&
        service.statusMessage != null) {
      final message = service.statusMessage!;
      service.resetStatus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    setState(() {});
  }

  Future<void> _buy() async {
    await PurchaseService.instance.buy(_selectedPlan);
  }

  Future<void> _restore() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Satın alımlar kontrol ediliyor...')),
    );
    await PurchaseService.instance.restore();
  }

  Future<void> _manageSubscription() async {
    final uri = Uri.parse('https://apps.apple.com/account/subscriptions');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abonelik yönetimi açılamadı.')),
      );
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final service = PurchaseService.instance;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : Colors.black12;
    final secondaryText = isDark ? const Color(0xFFA7A9B0) : Colors.black54;
    final tertiaryText = isDark ? const Color(0xFF7A7D85) : Colors.black45;

    final isBusy = service.status == PurchaseFlowStatus.pending ||
        service.status == PurchaseFlowStatus.verifying;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Life Admin Premium',
          style: TextStyle(fontWeight: FontWeight.w700),
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
            icon: Icons.block_rounded,
            title: 'Reklamsız',
            description: 'Life Admin\'i hiç reklam görmeden kullan.',
          ),

          const SizedBox(height: 12),

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

          _buildPlanSection(service, surface, border, secondaryText, isDark),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (isBusy || service.productFor(_selectedPlan) == null)
                  ? null
                  : _buy,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 18),
                ),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      service.status == PurchaseFlowStatus.verifying
                          ? 'Doğrulanıyor...'
                          : 'Satın Al',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: isBusy ? null : _restore,
            child: const Text('Satın Alımları Geri Yükle'),
          ),

          TextButton(
            onPressed: _manageSubscription,
            child: const Text('Aboneliği Yönet'),
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => _openLink(_termsUrl),
                child: Text(
                  'Kullanım Koşulları',
                  style: TextStyle(color: tertiaryText, fontSize: 12.5),
                ),
              ),
              Text('•', style: TextStyle(color: tertiaryText)),
              TextButton(
                onPressed: () => _openLink(_privacyUrl),
                child: Text(
                  'Gizlilik Politikası',
                  style: TextStyle(color: tertiaryText, fontSize: 12.5),
                ),
              ),
            ],
          ),

          Text(
            'Abonelik iptal edilmediği sürece otomatik olarak yenilenir. '
            'Satın alma ve abonelik yönetimi App Store üzerinden yapılır.',
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

  Widget _buildPlanSection(
    PurchaseService service,
    Color surface,
    Color border,
    Color secondaryText,
    bool isDark,
  ) {
    if (service.loadingProducts && service.productFor(_selectedPlan) == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (service.productsError != null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Text(
              service.productsError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: service.loadProducts,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    final monthly = service.productFor(PremiumPlan.monthly);
    final yearly = service.productFor(PremiumPlan.yearly);

    String? savingsLabel;
    if (monthly != null && yearly != null && monthly.rawPrice > 0) {
      final yearlyMonthlyEquivalent = yearly.rawPrice / 12;
      final savings =
          (1 - (yearlyMonthlyEquivalent / monthly.rawPrice)) * 100;
      if (savings > 1) {
        savingsLabel = '%${savings.round()} tasarruf';
      }
    }

    return Row(
      children: [
        Expanded(
          child: _PlanCard(
            title: 'Aylık',
            priceText: monthly?.price ?? '—',
            periodText: '/ ay',
            selected: _selectedPlan == PremiumPlan.monthly,
            highlighted: false,
            surface: surface,
            border: border,
            secondaryText: secondaryText,
            onTap: () => setState(() => _selectedPlan = PremiumPlan.monthly),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PlanCard(
            title: 'Yıllık',
            priceText: yearly?.price ?? '—',
            periodText: '/ yıl',
            badge: 'EN İYİ DEĞER',
            savingsLabel: savingsLabel,
            selected: _selectedPlan == PremiumPlan.yearly,
            highlighted: true,
            surface: surface,
            border: border,
            secondaryText: secondaryText,
            onTap: () => setState(() => _selectedPlan = PremiumPlan.yearly),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String priceText;
  final String periodText;
  final String? badge;
  final String? savingsLabel;
  final bool selected;
  final bool highlighted;
  final Color surface;
  final Color border;
  final Color secondaryText;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.priceText,
    required this.periodText,
    required this.selected,
    required this.highlighted,
    required this.surface,
    required this.border,
    required this.secondaryText,
    required this.onTap,
    this.badge,
    this.savingsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              priceText,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              periodText,
              style: TextStyle(color: secondaryText, fontSize: 12),
            ),
            if (savingsLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                savingsLabel!,
                style: TextStyle(
                  color: accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
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
