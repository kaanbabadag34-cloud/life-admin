import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../features/calendar/calendar_page.dart';
import '../../features/home/home_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/tools/tools_page.dart';

// KRİTİK KÖK NEDEN (iki turda bulundu): (1) önceki sürüm seçili/seçili
// olmayan durumlar için FARKLI Material glyph'leri kullanıyordu (ör.
// home_outlined ↔ home_rounded) — bu ikisinin çizimi farklı optik ağırlığa
// sahip olduğundan geçişte "zıplama" gibi algılanıyordu; (2) seçili ikona
// eklenen hafif "büyüme" (scale) animasyonu bile istenmiyor — kullanıcı
// icon boyutunun HİÇBİR durumda değişmemesini istiyor. Artık HER sekme
// için TEK, sabit bir Cupertino (SF Symbols tarzı) glyph kullanılıyor;
// seçili/seçili-olmayan ayrımı SADECE renk + çok hafif opacity ile
// yapılıyor — glyph, boyutu ve konumu HİÇBİR ZAMAN değişmiyor. Etiketler
// (label) kaldırıldı: gönderilen referans tasarım (ikon-only, kompakt,
// yüzen pill) birebir örnek olarak işaret edildiği için sadece o
// yapı/oran referans alındı — ikonların kendisi/renkleri KOPYALANMADI,
// uygulamanın kendi 4 sekmesi ve accent rengi korundu.
class _NavItem {
  final IconData icon;

  const _NavItem({required this.icon});
}

const List<_NavItem> _navItems = [
  _NavItem(icon: CupertinoIcons.house_fill),
  _NavItem(icon: CupertinoIcons.calendar),
  _NavItem(icon: CupertinoIcons.square_grid_2x2_fill),
  _NavItem(icon: CupertinoIcons.person_fill),
];

class _PillBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  // Kompakt bir çubuk — önceki 64'lük yüksekliğe göre ~%30 daha kısa.
  static const double _barHeight = 46;

  // İkonun arkasında kayan tek "premium active state" rozeti — küçük,
  // sabit boyutlu bir daire. Bu boyut HİÇBİR ZAMAN değişmiyor (zıplama/
  // büyüme/taşma yapısal olarak imkansız); değişen tek şey rozetin
  // sekmeler arasındaki YATAY KONUMU (akıcı kayma) ve rengi.
  static const double _badgeSize = 34;

  const _PillBottomNavBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final mutedIcon = isDark
        ? const Color(0xFF7A7D85)
        : const Color(0xFF9AA0AC);

    final activeBg = colors.primary.withValues(alpha: isDark ? 0.20 : 0.13);

    final count = _navItems.length;

    // KRİTİK KÖK NEDEN (bu turda bulundu): önceki sürümde her ikonu bir
    // Material+InkWell sarıyordu — InkWell'in KENDİ varsayılan splash/
    // highlight rengi (temadan gelen gri/siyah yarı saydam) mor rozetle
    // ÇAKIŞAN, "iki ayrı seçim efekti" gibi algılanan İKİNCİ bir görsel
    // katman yaratıyordu. Artık dokunma tamamen sade bir GestureDetector
    // ile ele alınıyor — HİÇBİR splash/highlight/ripple katmanı yok, tek
    // görsel efekt tek bir mor rozettir. Rozetin kendisi de artık TEK bir
    // AnimatedAlign ile sekmeler arasında akıcı şekilde kayıyor (önceki
    // "geniş pill" ile karıştırılmasın: bu rozet HER ZAMAN küçük/sabit
    // 34x34 boyutunda, sadece App Store kalitesindeki uygulamalardaki gibi
    // konumu akıcı şekilde değişiyor).
    return SizedBox(
      height: _barHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment(-1 + (2 * selectedIndex) / (count - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: activeBg,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: _badgeSize, height: _badgeSize),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(i),
                    child: _NavTapTarget(
                      item: _navItems[i],
                      selected: i == selectedIndex,
                      selectedColor: colors.primary,
                      mutedColor: mutedIcon,
                      barHeight: _barHeight,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavTapTarget extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final Color selectedColor;
  final Color mutedColor;
  final double barHeight;

  const _NavTapTarget({
    required this.item,
    required this.selected,
    required this.selectedColor,
    required this.mutedColor,
    required this.barHeight,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : mutedColor;

    // Icon boyutu (22) ve bu tap target'ın kendi yüksekliği (barHeight)
    // HİÇBİR durumda değişmiyor — seçili/seçili olmayan ayrımı sadece
    // rengin yumuşak geçişi ile yapılıyor (arka plan rozeti artık üstteki
    // paylaşılan kayan katmanda, burada tekrar edilmiyor — "iki ayrı
    // seçim görünümü" riskini ortadan kaldırmak için).
    return SizedBox(
      height: barHeight,
      child: Center(
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 200),
          tween: ColorTween(end: color),
          builder: (context, animatedColor, child) {
            return Icon(item.icon, color: animatedColor, size: 22);
          },
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final GlobalKey<CalendarPageState> _calendarKey =
      GlobalKey<CalendarPageState>();

  final GlobalKey<ProfilePageState> _profileKey = GlobalKey<ProfilePageState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      HomePage(
        onAiUsageChanged: () async {
          await _profileKey.currentState?.refreshProfile();
        },
      ),

      CalendarPage(key: _calendarKey),

      const ToolsPage(),

      ProfilePage(key: _profileKey),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color:
              theme.navigationBarTheme.backgroundColor ??
              theme.colorScheme.surface,

          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 0.8),
          ),
        ),

        child: SafeArea(
          top: false,
          child: _PillBottomNavBar(
            selectedIndex: _selectedIndex,
            onSelected: (index) async {
              setState(() {
                _selectedIndex = index;
              });

              if (index == 1) {
                await _calendarKey.currentState?.refreshPlans();
              }

              if (index == 3) {
                await _profileKey.currentState?.refreshProfile();
              }
            },
          ),
        ),
      ),
    );
  }
}
