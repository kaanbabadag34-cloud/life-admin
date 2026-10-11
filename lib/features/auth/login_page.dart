import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _appleLoading = false;
  bool _googleLoading = false;
  String? _errorMessage;

  bool get _busy => _loading || _appleLoading || _googleLoading;

  Future<void> _signInWithApple() async {
    if (_busy) return;

    setState(() {
      _appleLoading = true;
      _errorMessage = null;
    });

    try {
      // Başarılı girişte AuthGate oturumu görüp AppShell'e geçer; iptal
      // edilirse (SocialAuthResult.canceled) hata gösterilmez.
      await SocialAuthService.instance.signInWithApple();
    } on SocialAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;

    setState(() {
      _googleLoading = true;
      _errorMessage = null;
    });

    try {
      await SocialAuthService.instance.signInWithGoogle();
    } on SocialAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_busy) return;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'E-posta ve şifreyi doldur.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // Yönlendirmeyi AuthGate yapıyor (auth state tek kaynak).
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyAuthError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Giriş sırasında bir hata oluştu.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _friendlyAuthError(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'E-posta veya şifre hatalı.';
    }

    if (message.contains('email not confirmed')) {
      return 'E-posta adresini onaylaman gerekiyor.';
    }

    if (message.contains('network')) {
      return 'İnternet bağlantını kontrol et.';
    }

    return 'Giriş sırasında bir hata oluştu. Tekrar deneyin.';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark ? const Color(0xFFA7A9B0) : Colors.black54;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Life Admin',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hayatını tek yerde yönet.',
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 32),

                  _SocialButton(
                    label: 'Apple ile Devam Et',
                    icon: Icon(
                      Icons.apple,
                      size: 24,
                      color: isDark ? Colors.black : Colors.white,
                    ),
                    background: isDark ? Colors.white : Colors.black,
                    foreground: isDark ? Colors.black : Colors.white,
                    loading: _appleLoading,
                    onPressed: _busy ? null : _signInWithApple,
                  ),
                  const SizedBox(height: 12),
                  _SocialButton(
                    label: 'Google ile Devam Et',
                    icon: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CustomPaint(painter: _GoogleLogoPainter()),
                    ),
                    background: isDark ? const Color(0xFF171A1F) : Colors.white,
                    foreground: isDark ? Colors.white : Colors.black87,
                    borderColor: isDark
                        ? const Color(0xFF2B2F36)
                        : const Color(0xFFD9DCE1),
                    loading: _googleLoading,
                    onPressed: _busy ? null : _signInWithGoogle,
                  ),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: isDark
                              ? const Color(0xFF2B2F36)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'veya',
                          style: TextStyle(color: secondaryText, fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: isDark
                              ? const Color(0xFF2B2F36)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Şifre',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _login(),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Giriş Yap'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final bool loading;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.loading,
    required this.onPressed,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.6),
          disabledForegroundColor: foreground.withValues(alpha: 0.6),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: borderColor == null
                ? BorderSide.none
                : BorderSide(color: borderColor!),
          ),
        ),
        onPressed: onPressed,
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// Google "G" işareti: dört renkli halka + mavi çubuk (resmî logonun
// basitleştirilmiş çizimi; harici asset/paket gerektirmiyor).
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final center = Offset(12 * unit, 12 * unit);
    final stroke = 4 * unit;
    final radius = 8 * unit;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double rad(double deg) => deg * 3.141592653589793 / 180;

    void arc(Color color, double startDeg, double endDeg) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..isAntiAlias = true;
      canvas.drawArc(rect, rad(startDeg), rad(endDeg - startDeg), false, paint);
    }

    arc(const Color(0xFFEA4335), -145, -45);
    arc(const Color(0xFFFBBC05), 135, 215);
    arc(const Color(0xFF34A853), 45, 135);
    arc(const Color(0xFF4285F4), 0, 45);

    canvas.drawRect(
      Rect.fromLTRB(12 * unit, 10 * unit, 22 * unit, 14 * unit),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
