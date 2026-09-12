import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'premium_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;

  String _plan = 'free';
  int _aiUsage = 0;
  DateTime? _aiUsageResetAt;

  String get _email =>
      _supabase.auth.currentUser?.email ?? 'E-posta bulunamadı';

  bool get _isPremium => _plan == 'premium';

  int get _aiLimit => _isPremium ? 300 : 20;

  int get _remainingAi {
    final remaining = _aiLimit - _aiUsage;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void initState() {
    super.initState();
    refreshProfile();
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
      final profile = await _supabase
          .from('profiles')
          .select(
            'plan, ai_usage, ai_usage_reset_at',
          )
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      setState(() {
        _plan = profile['plan']?.toString() ?? 'free';

        _aiUsage =
            (profile['ai_usage'] as num?)?.toInt() ?? 0;

        final resetRaw =
            profile['ai_usage_reset_at']?.toString();

        _aiUsageResetAt = resetRaw == null
            ? null
            : DateTime.parse(resetRaw).toLocal();

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
            'Profil yüklenemedi: $error',
          ),
        ),
      );
    }
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

  Future<void> _signOut() async {
    await _supabase.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).popUntil(
      (route) => route.isFirst,
    );
  }

  String _formatResetDate() {
    final date = _aiUsageResetAt;

    if (date == null) {
      return 'Henüz belirlenmedi';
    }

    final day =
        date.day.toString().padLeft(2, '0');

    final month =
        date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final surface =
        isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark
        ? const Color(0xFF2B2F36)
        : const Color(0xFFE5E7EB);
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    final usageProgress = _aiLimit <= 0
        ? 0.0
        : (_aiUsage / _aiLimit).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profil',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 24,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: refreshProfile,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(
                        alpha: isDark ? 0.15 : 0.09,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 25,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hesabım',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                            fontSize: 13,
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
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isPremium
                        ? colors.primary.withValues(alpha: 0.55)
                        : border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.workspace_premium_rounded,
                            color: colors.primary,
                            size: 21,
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
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isPremium
                                    ? 'Premium plan aktif.'
                                    : 'Şu anda Free plandasın.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: secondaryText,
                                  fontSize: 12,
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
                            color: colors.primary.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _isPremium ? 'PREMIUM' : 'FREE',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
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
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '$_aiUsage / $_aiLimit',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: usageProgress,
                        minHeight: 7,
                        backgroundColor: isDark
                            ? const Color(0xFF252930)
                            : const Color(0xFFEDEEF2),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Kalan: $_remainingAi işlem',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          'Sıfırlanma: ${_formatResetDate()}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),

                    if (!_isPremium) ...[
                      const SizedBox(height: 18),
                      SizedBox(
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
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Ayarlar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 10),

              Material(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 4,
                        ),
                        leading: _ProfileIcon(
                          icon: Icons.notifications_none_rounded,
                          color: colors.primary,
                          isDark: isDark,
                        ),
                        title: const Text('Hatırlatıcılar'),
                        subtitle: Text(
                          _isPremium
                              ? 'Premium ile kullanılabilir'
                              : 'Premium özelliği',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: secondaryText,
                        ),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _isPremium
                                    ? 'Hatırlatıcı sistemi yakında bağlanacak.'
                                    : 'Hatırlatıcılar Premium özelliğidir.',
                              ),
                            ),
                          );
                        },
                      ),

                      Divider(height: 1, color: border),

                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 4,
                        ),
                        leading: _ProfileIcon(
                          icon: Icons.info_outline_rounded,
                          color: colors.primary,
                          isDark: isDark,
                        ),
                        title: const Text('Uygulama hakkında'),
                        subtitle: Text(
                          'Life Admin • v1.0.0',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: secondaryText,
                        ),
                        onTap: () {
                          showAboutDialog(
                            context: context,
                            applicationName: 'Life Admin',
                            applicationVersion: '1.0.0',
                            applicationLegalese: '© 2026 Life Admin',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Çıkış Yap'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(
                      color: colors.error.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
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
