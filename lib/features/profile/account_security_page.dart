import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const String _deleteAccountEndpoint =
    'https://life-admin-server.vercel.app/api/delete-account';

// "Hesap ve Güvenlik" — Profil ekranındaki ilgili satırdan açılıyor.
// "Çıkış Yap" ProfilePage'in kendi _signOut'unu çağırıyor (mantık burada
// TEKRARLANMIYOR). "Hesabı Sil" iki aşamalı onaydan sonra sunucudaki
// /api/delete-account endpoint'ini çağırıyor; kullanıcı kimliği body'de
// GÖNDERİLMİYOR, sunucu onu access token'dan çıkarıyor. Apple aboneliği
// otomatik iptal EDİLMEZ — kullanıcıya "Aboneliği Yönet" yolu gösterilir.
class AccountSecurityPage extends StatefulWidget {
  final Future<void> Function() onSignOut;
  final bool hasActiveSubscription;

  const AccountSecurityPage({
    super.key,
    required this.onSignOut,
    this.hasActiveSubscription = false,
  });

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  bool _flowOpen = false;

  Future<void> _openManageSubscription() async {
    final uri = Uri.parse('https://apps.apple.com/account/subscriptions');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('manage subscription error: $error');
    }
  }

  Future<bool> _requestDeletion() async {
    try {
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;

      if (accessToken == null) return false;

      final response = await http
          .post(
            Uri.parse(_deleteAccountEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('delete-account failed: ${response.statusCode} '
              '${response.body}');
        }
        return false;
      }

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      return data['success'] == true;
    } catch (error) {
      if (kDebugMode) debugPrint('delete-account error: $error');
      return false;
    }
  }

  Future<void> _startDeleteFlow() async {
    if (_flowOpen) return;
    _flowOpen = true;

    // Context'e bağlı her şey await'lerden ÖNCE yakalanıyor.
    final navigator = Navigator.of(context, rootNavigator: true);

    try {
      final proceed = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _DeleteIntroSheet(
          hasActiveSubscription: widget.hasActiveSubscription,
          onManageSubscription: _openManageSubscription,
        ),
      );

      if (proceed != true || !mounted) return;

      final deleted = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        builder: (_) => _DeleteConfirmSheet(onDelete: _requestDeletion),
      );

      if (deleted != true) return;

      try {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      } catch (error) {
        if (kDebugMode) debugPrint('local sign-out after delete: $error');
      }

      // Login'e geçişi AuthGate yapıyor (signOut → oturum yok). Üstte
      // kalan Profil/Hesap ve Güvenlik route'larını kapatıyoruz.
      navigator.popUntil((route) => route.isFirst);
    } finally {
      _flowOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSignOut = widget.onSignOut;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Hesap ve Güvenlik',
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Material(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 4,
                ),
                leading: _SecurityIcon(
                  icon: Icons.logout_rounded,
                  color: colors.primary,
                  isDark: isDark,
                ),
                title: const Text(
                  'Çıkış Yap',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: secondaryText,
                ),
                onTap: onSignOut,
              ),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            'TEHLİKELİ BÖLGE',
            style: TextStyle(
              color: secondaryText,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),

          const SizedBox(height: 10),

          Material(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.error.withValues(alpha: 0.35)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 4,
                ),
                leading: _SecurityIcon(
                  icon: Icons.delete_outline_rounded,
                  color: colors.error,
                  isDark: isDark,
                ),
                title: Text(
                  'Hesabı Sil',
                  style: TextStyle(
                    color: colors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Bu işlem geri alınamaz.',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: colors.error.withValues(alpha: 0.6),
                ),
                onTap: _startDeleteFlow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;

  const _SecurityIcon({
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
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _DeleteIntroSheet extends StatelessWidget {
  final bool hasActiveSubscription;
  final Future<void> Function() onManageSubscription;

  const _DeleteIntroSheet({
    required this.hasActiveSubscription,
    required this.onManageSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SecurityIcon(
              icon: Icons.delete_outline_rounded,
              color: colors.error,
              isDark: isDark,
            ),
            const SizedBox(height: 14),
            Text(
              'Hesabını silmek istiyor musun?',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Hesabın ve Life Admin’deki verilerin kalıcı olarak silinecek. '
              'Bu işlem geri alınamaz.',
              style: TextStyle(color: secondaryText, fontSize: 14.5, height: 1.4),
            ),
            if (hasActiveSubscription) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: isDark ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hesabını silmek App Store aboneliğini otomatik olarak '
                      'iptal etmez.',
                      style: TextStyle(fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onManageSubscription,
                      child: Text(
                        'Aboneliği Yönet',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Devam Et'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteConfirmSheet extends StatefulWidget {
  final Future<bool> Function() onDelete;

  const _DeleteConfirmSheet({required this.onDelete});

  @override
  State<_DeleteConfirmSheet> createState() => _DeleteConfirmSheetState();
}

class _DeleteConfirmSheetState extends State<_DeleteConfirmSheet> {
  bool _deleting = false;
  bool _failed = false;

  Future<void> _confirm() async {
    if (_deleting) return;

    setState(() {
      _deleting = true;
      _failed = false;
    });

    final ok = await widget.onDelete();

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _deleting = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    return PopScope(
      canPop: !_deleting,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SecurityIcon(
                icon: Icons.warning_amber_rounded,
                color: colors.error,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              Text(
                'Hesabı kalıcı olarak sil',
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Son kez uyarıyoruz: hesabın, planların, sayaçların ve '
                'günlüklerin kalıcı olarak silinecek ve geri getirilemeyecek.',
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
              SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _failed
                      ? Text(
                          'Hesap silinemedi. Lütfen tekrar deneyin.',
                          style: TextStyle(
                            color: colors.error,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _deleting ? null : _confirm,
                child: _deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Hesabımı Sil'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _deleting
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
