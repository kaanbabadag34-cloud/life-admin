import 'package:flutter/material.dart';
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

          // Kullanıcının seçtiği tema
          themeMode: themeController.themeMode,

          // AÇIK TEMA
          theme: AppTheme.light,

          // KOYU TEMA
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,

            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6868AC),
              brightness: Brightness.dark,
            ),

            scaffoldBackgroundColor:
                const Color(0xFF111113),

            cardColor:
                const Color(0xFF1C1C1E),

            dividerColor:
                Colors.white.withValues(
              alpha: 0.08,
            ),

            appBarTheme:
                const AppBarTheme(
              backgroundColor:
                  Color(0xFF111113),
              foregroundColor:
                  Colors.white,
              elevation: 0,
              surfaceTintColor:
                  Colors.transparent,
            ),

            navigationBarTheme:
                NavigationBarThemeData(
              backgroundColor:
                  const Color(0xFF171719),

              indicatorColor:
                  const Color(0xFF6868AC)
                      .withValues(
                alpha: 0.25,
              ),

              labelTextStyle:
                  WidgetStateProperty.resolveWith(
                (states) {
                  return TextStyle(
                    color: states.contains(
                      WidgetState.selected,
                    )
                        ? Colors.white
                        : Colors.white60,
                    fontSize: 12,
                  );
                },
              ),

              iconTheme:
                  WidgetStateProperty.resolveWith(
                (states) {
                  return IconThemeData(
                    color: states.contains(
                      WidgetState.selected,
                    )
                        ? const Color(
                            0xFF9999FF,
                          )
                        : Colors.white60,
                  );
                },
              ),
            ),

            inputDecorationTheme:
                InputDecorationTheme(
              filled: true,
              fillColor:
                  const Color(0xFF1C1C1E),

              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
                borderSide:
                    BorderSide.none,
              ),
            ),

            filledButtonTheme:
                FilledButtonThemeData(
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xFF6868AC,
                ),
                foregroundColor:
                    Colors.white,
              ),
            ),
          ),

          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final session =
        Supabase.instance.client.auth.currentSession;

    if (session != null) {
      return const AppShell();
    }

    return const LoginPage();
  }
}