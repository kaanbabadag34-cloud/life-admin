import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/theme_controller.dart';
import '../../utils/error_messages.dart';
import '../../utils/user_name.dart';
import '../../services/apple_calendar_service.dart';
import '../../services/notification_service.dart';
import '../plans/event_service.dart';
import 'account_security_page.dart';
import 'premium_page.dart';
import 'purchase_service.dart';

// Premium kartındaki ikinci, çok düşük opaklıkta ton — "mor/cyan glow
// kontrollü" isteğini karşılamak için sadece premium durumdaki kartın
// gradyanına ÇOK az cyan katıyor. Metin/ikon rengi olarak KULLANILMIYOR;
// tek başına asla neon/oyuncu hissi vermeyecek kadar düşük alpha'da.
const Color _premiumCyan = Color(0xFF4FD1C5);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage>
    with WidgetsBindingObserver {
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<AuthState>? _authSubscription;

  bool _loading = true;
  bool _calendarSyncEnabled = false;
  bool _notificationsOn = false;
  bool _systemNotificationsDenied = false;
  bool _notificationsBusy = false;
  bool _calendarSyncBusy = false;

  String _plan = 'free';
  int _aiUsage = 0;
  DateTime? _aiUsageResetAt;
  Map<String, dynamic>? _profileRow;

  String get _email =>
      _supabase.auth.currentUser?.email ?? 'E-posta bulunamadı';

  // "profiles" tablosunda veya auth metadata'sında bir isim varsa onu
  // gösteriyoruz — aynı çok-kaynaklı arama sırası home_page.dart'taki
  // _userFirstName() ile aynı (orada ilk isme kısaltılıyor, burada Hesabım
  // kartında TAM isim gösterilecek). İsim yoksa null döner ve mevcut
  // e-posta-only görünüm hiçbir şey kaybetmeden korunur.
  String? get _displayName =>
      resolveFullName(_supabase.auth.currentUser, _profileRow);

  bool get _isPremium => _plan == 'premium';

  int get _aiLimit => _isPremium ? 300 : 20;

  int get _remainingAi {
    final remaining = _aiLimit - _aiUsage;
    return remaining < 0 ? 0 : remaining;
  }

  String get _themeModeLabel {
    switch (themeController.themeMode) {
      case ThemeMode.light:
        return 'Açık';
      case ThemeMode.dark:
        return 'Koyu';
      case ThemeMode.system:
        return 'Sistem';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refreshProfile();
    _loadCalendarSyncState();
    _loadNotificationState();
    // Apple adı giriş sonrasında kaydedilince Hesabım kartı kendini yeniler.
    _authSubscription =
        _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.userUpdated && mounted) {
        setState(() {});
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> refreshProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      // "*" ile seçiyoruz ki (home_page.dart'taki aynı yaklaşım gibi)
      // profiles tablosunda bir isim kolonu olsun/olmasın sorgu hiçbir
      // zaman "kolon bulunamadı" hatasıyla çökmesin.
      final profile = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      setState(() {
        _plan = profile['plan']?.toString() ?? 'free';

        _aiUsage = (profile['ai_usage'] as num?)?.toInt() ?? 0;

        final resetRaw = profile['ai_usage_reset_at']?.toString();

        _aiUsageResetAt = resetRaw == null
            ? null
            : DateTime.parse(resetRaw).toLocal();

        _profileRow = Map<String, dynamic>.from(profile);

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Profil yüklenemedi. Aşağı çekerek tekrar deneyebilirsin.',
            ),
          ),
        ),
      );
    }
  }

  // iPhone Ayarlar'dan dönünce izin durumu yeniden kontrol edilir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNotificationState(rescheduleIfNewlyOn: true);
    }
  }

  // Anahtar = uygulama tercihi VE iOS izni. İzin kapalıysa anahtar kapalı
  // görünür ve alt yazı nedenini söyler.
  Future<void> _loadNotificationState({bool rescheduleIfNewlyOn = false}) async {
    final service = NotificationService.instance;
    final appEnabled = await service.isAppEnabled();
    final systemAllowed = await service.notificationsAllowed();
    final effective = appEnabled && systemAllowed;

    if (!mounted) return;

    final newlyOn = effective && !_notificationsOn;

    setState(() {
      _notificationsOn = effective;
      _systemNotificationsDenied = !systemAllowed;
    });

    // Ayarlardan izin verilip dönüldüyse gelecekteki hatırlatmaları yeniden kur.
    if (rescheduleIfNewlyOn && newlyOn) {
      await EventService().rescheduleAllReminders();
    }
  }

  Future<void> _openSystemNotificationSettings() async {
    try {
      await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {}
  }

  Future<void> _showNotificationsDeniedDialog() async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Bildirimler kapalı'),
          content: const Text(
            'Hatırlatmaları alabilmek için iPhone Ayarlar → Life Admin → '
            'Bildirimler bölümünden izin vermen gerekiyor.',
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

    if (open == true) await _openSystemNotificationSettings();
  }

  // Kapatmak YALNIZCA Life Admin'ın yerel bildirimlerini yönetir (iOS sistem
  // izni uygulamadan kapatılamaz). Açarken izin yoksa sistem penceresi,
  // reddedilmişse iPhone ayarlarına yönlendirme gösterilir.
  Future<void> _setNotifications(bool value) async {
    if (_notificationsBusy) return;

    setState(() => _notificationsBusy = true);

    final service = NotificationService.instance;

    if (!value) {
      await service.setAppEnabled(false);
      await service.cancelAll();
    } else {
      await service.setAppEnabled(true);
      final allowed = await service.ensurePermission();

      if (allowed) {
        await EventService().rescheduleAllReminders();
      } else if (mounted) {
        await _showNotificationsDeniedDialog();
      }
    }

    _notificationsBusy = false;
    await _loadNotificationState();
  }

  Future<void> _loadCalendarSyncState() async {
    final service = AppleCalendarService.instance;
    final enabled = await service.isEnabled() &&
        await service.permissionStatus() == CalendarPermission.granted;

    if (!mounted) return;
    setState(() => _calendarSyncEnabled = enabled);
  }

  // Açarken iOS takvim iznini ister; izin verilmezse anahtar kapalı kalır ve
  // uygulama normal çalışmaya devam eder. Kapatmak yalnızca YENİ
  // senkronizasyonu durdurur, mevcut takvim etkinliklerini silmez.
  Future<void> _setCalendarSync(bool value) async {
    if (_calendarSyncBusy) return;

    setState(() => _calendarSyncBusy = true);

    final service = AppleCalendarService.instance;
    var enabled = false;

    if (value) {
      enabled = await service.enable();

      if (!enabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Takvim izni verilmedi. İstersen iPhone Ayarlar → Life Admin '
              'bölümünden izin verebilirsin.',
            ),
          ),
        );
      }
    } else {
      await service.disable();
    }

    if (!mounted) return;

    setState(() {
      _calendarSyncEnabled = enabled;
      _calendarSyncBusy = false;
    });
  }

  Future<void> _openPremiumPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PremiumPage(),
      ),
    );

    if (!mounted) return;

    await refreshProfile();
  }

  // Önce üstteki route'lar (Hesap ve Güvenlik vb.) kapatılıyor, SONRA
  // oturum kapatılıyor: signOut anında AuthGate AppShell'i (ve bu sayfayı)
  // sökeceği için sonrasında `mounted` kontrolüne güvenilemez. Login'e
  // geçişi AuthGate yapıyor.
  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);

    await _supabase.auth.signOut();
  }

  String _formatResetDate() {
    final date = _aiUsageResetAt;

    if (date == null) {
      return 'Henüz belirlenmedi';
    }

    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  // Restore edilen bir satın alma da (yeni satın alma ile TAMAMEN aynı
  // yoldan) verify-purchase Edge Function'a gidip server-side doğrulanıyor
  // — burada hiçbir zaman doğrudan premium açılmıyor. `PurchaseService`
  // "geri yüklenecek satın alma yok" durumunu da garantili şekilde
  // sonuçlandırıyor (bkz. purchase_service.dart:restore), yani bu akış
  // sonsuz beklemede kalamaz.
  Future<void> _restorePurchases() async {
    final service = PurchaseService.instance;
    await service.initialize();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Satın alımlar kontrol ediliyor...')),
    );

    late final VoidCallback onChange;

    onChange = () {
      if (service.status != PurchaseFlowStatus.success &&
          service.status != PurchaseFlowStatus.error) {
        return;
      }

      service.removeListener(onChange);

      final wasSuccess = service.status == PurchaseFlowStatus.success;
      final message = service.statusMessage;
      service.resetStatus();

      if (!mounted) return;

      if (wasSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Satın alımların geri yüklendi.')),
        );
        refreshProfile();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message ?? 'Geri yüklenecek bir satın alma bulunamadı.',
            ),
          ),
        );
      }
    };

    service.addListener(onChange);
    await service.restore();
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature yakında aktif olacak.')),
    );
  }

  bool get _hasActiveAppleSubscription {
    final row = _profileRow;
    if (row == null) return false;

    if (row['subscription_platform'] != 'ios') return false;
    if (row['subscription_status'] != 'active') return false;

    final expiresRaw = row['subscription_expires_at']?.toString();
    if (expiresRaw == null) return true;

    final expires = DateTime.tryParse(expiresRaw);
    return expires == null || expires.isAfter(DateTime.now());
  }

  void _openAccountSecurity() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountSecurityPage(
          onSignOut: _signOut,
          hasActiveSubscription: _hasActiveAppleSubscription,
        ),
      ),
    );
  }

  void _showThemeSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: themeController,
          builder: (context, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Text(
                        'Tema',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('Görünüm tercihini seç'),
                    ),
                    _SettingsSheetTile(
                      icon: Icons.light_mode_outlined,
                      title: 'Açık',
                      selected: themeController.themeMode == ThemeMode.light,
                      onTap: () {
                        themeController.setThemeMode(ThemeMode.light);
                        Navigator.pop(sheetContext);
                      },
                    ),
                    _SettingsSheetTile(
                      icon: Icons.dark_mode_outlined,
                      title: 'Koyu',
                      selected: themeController.themeMode == ThemeMode.dark,
                      onTap: () {
                        themeController.setThemeMode(ThemeMode.dark);
                        Navigator.pop(sheetContext);
                      },
                    ),
                    _SettingsSheetTile(
                      icon: Icons.settings_suggest_outlined,
                      title: 'Sistem',
                      subtitle: 'Cihaz ayarını kullan',
                      selected: themeController.themeMode == ThemeMode.system,
                      onTap: () {
                        themeController.setThemeMode(ThemeMode.system);
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLanguageSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Dil',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Uygulama dilini seç'),
                ),
                ListTile(
                  leading: const Text('🇹🇷', style: TextStyle(fontSize: 24)),
                  title: const Text('Türkçe'),
                  trailing: const Icon(Icons.check_rounded),
                  onTap: () => Navigator.pop(sheetContext),
                ),
                ListTile(
                  leading: const Text('🇬🇧', style: TextStyle(fontSize: 24)),
                  title: const Text('English'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('English');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Yardım & Geri Bildirim',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                _SettingsSheetTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Geri Bildirim Gönder',
                  subtitle: 'Fikrini bizimle paylaş',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Geri bildirim sistemi');
                  },
                ),
                _SettingsSheetTile(
                  icon: Icons.bug_report_outlined,
                  title: 'Sorun Bildir',
                  subtitle: 'Bir hata mı buldun?',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Sorun bildirme sistemi');
                  },
                ),
                _SettingsSheetTile(
                  icon: Icons.support_agent_rounded,
                  title: 'Yardım',
                  subtitle: 'Life Admin kullanımı hakkında destek',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Yardım merkezi');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);
    final titleColor = isDark ? Colors.white : const Color(0xFF17171A);
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    final usageProgress = _aiLimit <= 0
        ? 0.0
        : (_aiUsage / _aiLimit).clamp(0.0, 1.0).toDouble();

    final name = _displayName;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profil',
          style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: refreshProfile,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
          children: [
            // ===================== HESABIM =====================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(
                        alpha: isDark ? 0.16 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: name != null && name.isNotEmpty
                        ? Text(
                            initialsOf(name),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          )
                        : Icon(
                            Icons.person_rounded,
                            size: 25,
                            color: colors.primary,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: name != null
                          ? [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  color: titleColor,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 12.5,
                                ),
                              ),
                            ]
                          : [
                              Text(
                                'Hesabım',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              // ===================== PREMIUM =====================
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isPremium
                        ? [
                            colors.primary.withValues(
                              alpha: isDark ? 0.26 : 0.16,
                            ),
                            _premiumCyan.withValues(
                              alpha: isDark ? 0.12 : 0.06,
                            ),
                          ]
                        : [
                            surface,
                            surface,
                          ],
                  ),
                  border: Border.all(
                    color: _isPremium
                        ? colors.primary.withValues(alpha: isDark ? 0.5 : 0.32)
                        : border,
                  ),
                  boxShadow: _isPremium
                      ? [
                          BoxShadow(
                            color: colors.primary.withValues(
                              alpha: isDark ? 0.24 : 0.14,
                            ),
                            blurRadius: 32,
                            spreadRadius: -10,
                            offset: const Offset(0, 16),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.workspace_premium_rounded,
                            color: colors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isPremium
                                    ? 'Life Admin Premium'
                                    : 'Life Admin Free',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isPremium
                                    ? 'Premium plan aktif.'
                                    : 'Şu anda Free plandasın.',
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            _isPremium ? 'PREMIUM' : 'FREE',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'AI kullanımı',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$_aiUsage / $_aiLimit',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: titleColor,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: usageProgress,
                        minHeight: 8,
                        backgroundColor: isDark
                            ? const Color(0xFF252930)
                            : const Color(0xFFEDEEF2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.primary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _PremiumStat(
                            label: 'KALAN',
                            value: '$_remainingAi işlem',
                            titleColor: titleColor,
                            secondaryText: secondaryText,
                          ),
                        ),
                        Expanded(
                          child: _PremiumStat(
                            label: 'SIFIRLANMA',
                            value: _formatResetDate(),
                            titleColor: titleColor,
                            secondaryText: secondaryText,
                          ),
                        ),
                      ],
                    ),

                    if (!_isPremium) ...[
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openPremiumPage,
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Premium’a Geç • ₺249/ay',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // ===================== AYARLAR =====================
              Text(
                'Ayarlar',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),

              const SizedBox(height: 10),

              AnimatedBuilder(
                animation: themeController,
                builder: (context, _) {
                  return Material(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        children: [
                          _SettingsRow(
                            icon: Icons.event_available_outlined,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Apple Takvim ile Eşzamanla',
                            subtitle: 'Saatli görevler Takvim’e eklenir',
                            secondaryText: secondaryText,
                            border: border,
                            trailing: Switch.adaptive(
                              value: _calendarSyncEnabled,
                              onChanged:
                                  _calendarSyncBusy ? null : _setCalendarSync,
                            ),
                            onTap: () => _setCalendarSync(!_calendarSyncEnabled),
                          ),
                          _SettingsRow(
                            icon: Icons.notifications_none_rounded,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Bildirimler',
                            subtitle: _systemNotificationsDenied
                                ? 'iPhone ayarlarında kapalı'
                                : (_notificationsOn ? 'Açık' : 'Kapalı'),
                            secondaryText: secondaryText,
                            border: border,
                            trailing: Switch.adaptive(
                              value: _notificationsOn,
                              onChanged:
                                  _notificationsBusy ? null : _setNotifications,
                            ),
                            onTap: () => _setNotifications(!_notificationsOn),
                          ),
                          _SettingsRow(
                            icon: Icons.dark_mode_outlined,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Tema',
                            subtitle: _themeModeLabel,
                            secondaryText: secondaryText,
                            border: border,
                            onTap: _showThemeSheet,
                          ),
                          _SettingsRow(
                            icon: Icons.language_rounded,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Dil',
                            subtitle: 'Türkçe',
                            secondaryText: secondaryText,
                            border: border,
                            onTap: _showLanguageSheet,
                          ),
                          _SettingsRow(
                            icon: Icons.help_outline_rounded,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Yardım / Geri bildirim',
                            secondaryText: secondaryText,
                            border: border,
                            onTap: _showHelpSheet,
                          ),
                          _SettingsRow(
                            icon: Icons.info_outline_rounded,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Uygulama hakkında',
                            subtitle: 'Life Admin • v1.0.0',
                            secondaryText: secondaryText,
                            border: border,
                            onTap: () {
                              showAboutDialog(
                                context: context,
                                applicationName: 'Life Admin',
                                applicationVersion: '1.0.0',
                                applicationLegalese: '© 2026 Life Admin',
                              );
                            },
                          ),
                          _SettingsRow(
                            icon: Icons.restore_rounded,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Satın alımları geri yükle',
                            secondaryText: secondaryText,
                            border: border,
                            onTap: _restorePurchases,
                          ),
                          _SettingsRow(
                            icon: Icons.shield_outlined,
                            iconColor: colors.primary,
                            isDark: isDark,
                            title: 'Hesap ve güvenlik',
                            secondaryText: secondaryText,
                            border: border,
                            isLast: true,
                            onTap: _openAccountSecurity,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _signOut,
                  icon: Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: colors.error,
                  ),
                  label: Text(
                    'Çıkış Yap',
                    style: TextStyle(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PremiumStat extends StatelessWidget {
  final String label;
  final String value;
  final Color titleColor;
  final Color secondaryText;

  const _PremiumStat({
    required this.label,
    required this.value,
    required this.titleColor,
    required this.secondaryText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: secondaryText,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: titleColor,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool isDark;
  final String title;
  final String? subtitle;
  final Color secondaryText;
  final Color border;
  final VoidCallback onTap;
  final bool isLast;
  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.isDark,
    required this.title,
    required this.secondaryText,
    required this.border,
    required this.onTap,
    this.subtitle,
    this.isLast = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 4,
          ),
          leading: _ProfileIcon(icon: icon, color: iconColor, isDark: isDark),
          title: Text(title),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
          trailing: trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: secondaryText,
              ),
          onTap: onTap,
        ),
        if (!isLast) Divider(height: 1, color: border),
      ],
    );
  }
}

class _SettingsSheetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsSheetTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
      onTap: onTap,
    );
  }
}

class _ProfileIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;

  const _ProfileIcon({
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        icon,
        color: color,
        size: 20,
      ),
    );
  }
}
