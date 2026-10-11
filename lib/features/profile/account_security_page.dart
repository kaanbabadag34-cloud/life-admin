import 'package:flutter/material.dart';

// "Hesap ve Güvenlik" — Profil ekranındaki ilgili satırdan açılıyor.
// Şu an sadece gerçek çalışan "Çıkış Yap" (ProfilePage'in kendi _signOut'u,
// burada sadece çağrılıyor, mantık burada TEKRARLANMIYOR) ve ayrı, açıkça
// destructive gösterilen ama gerçek bir silme işlemi YAPMAYAN "Hesabı Sil"
// satırını içeriyor. Gerçek hesap silme, güvenli sunucu taraflı (Supabase
// Edge Function / service role ile) bir akış gerektiriyor — bu henüz yok,
// bu yüzden burada sahte bir "silindi" akışı ÇALIŞTIRILMIYOR.
class AccountSecurityPage extends StatelessWidget {
  final Future<void> Function() onSignOut;

  const AccountSecurityPage({super.key, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
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
                onTap: () => _showNotAvailableDialog(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotAvailableDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hesap silme yakında'),
          content: const Text(
            'Hesabını güvenli şekilde silebilmek için sunucu tarafında '
            '(Supabase service role / Edge Function ile) ek bir silme akışı '
            'gerekiyor. Bu özellik henüz aktif değil.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tamam'),
            ),
          ],
        );
      },
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
