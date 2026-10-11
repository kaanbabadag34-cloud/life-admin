import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_page.dart';
import 'navigation/app_shell.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class LifeAdminApp extends StatelessWidget {
  const LifeAdminApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, child) {
        return MaterialApp(
          title: 'Life Admin',
          debugShowCheckedModeBanner: false,

          // Uygulama şu an sadece Türkçe — cihaz dili ne olursa olsun
          // sabit Türkçe kalır. Bu, aynı zamanda Material'ın kendi
          // bileşenlerinin (takvim/saat seçici, "İptal"/"Tamam" butonları
          // vb.) İngilizce yerine Türkçe göstermesini sağlar; aksi halde
          // localizationsDelegates tanımlanmadığında Flutter varsayılan
          // olarak İngilizce'ye düşer.
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          // Kullanıcının seçtiği tema
          themeMode: themeController.themeMode,

          // AÇIK TEMA
          theme: AppTheme.light,

          // KOYU TEMA
          darkTheme: AppTheme.dark,

          home: const AuthGate(),
        );
      },
    );
  }
}

// Auth state TEK kaynak: oturum açılınca/kapanınca (giriş, çıkış, hesap
// silme, başka cihazdan iptal) ekran, restart gerekmeden anında değişir.
// Kimlik doğrulama sonrası hiçbir ekran manuel Navigator ile yönlendirme
// yapmaz. `const AppShell()` aynı instance olduğu için token yenileme gibi
// event'ler AppShell state'ini sıfırlamaz.
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const AppShell();
        }

        return const LoginPage();
      },
    );
  }
}
