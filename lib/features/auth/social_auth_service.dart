import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase Dashboard > Authentication > URL Configuration > Redirect URLs
// listesine AYNEN eklenmeli; Info.plist'teki CFBundleURLSchemes
// (com.kaan.lifeadmin) ile eşleşir.
const String oauthRedirectUrl = 'com.kaan.lifeadmin://login-callback';

enum SocialAuthResult { success, canceled }

// Kullanıcıya gösterilebilecek, token/OAuth detayı İÇERMEYEN hata.
class SocialAuthException implements Exception {
  final String message;
  const SocialAuthException(this.message);
}

class SocialAuthService {
  SocialAuthService._();

  static final SocialAuthService instance = SocialAuthService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  // Native iOS akışı: Apple'ın ID token'ı Supabase'e signInWithIdToken ile
  // verilir. Apple'a nonce'un SHA-256 hash'i, Supabase'e ham hali gider.
  Future<SocialAuthResult> signInWithApple() async {
    try {
      final rawNonce = _generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;

      if (idToken == null) {
        throw const SocialAuthException(
          'Apple ile giriş yapılamadı. Lütfen tekrar deneyin.',
        );
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      // Apple adı yalnızca İLK yetkilendirmede verir; varsa kaydediyoruz
      // (profil ekranı auth metadata'daki full_name'i okuyor).
      final fullName = [credential.givenName, credential.familyName]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(' ');

      if (fullName.isNotEmpty) {
        try {
          await _supabase.auth.updateUser(
            UserAttributes(data: {'full_name': fullName}),
          );
        } catch (error) {
          if (kDebugMode) debugPrint('apple name save skipped: $error');
        }
      }

      return SocialAuthResult.success;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return SocialAuthResult.canceled;
      }

      if (kDebugMode) debugPrint('apple sign-in error: ${error.code}');
      throw const SocialAuthException(
        'Apple ile giriş yapılamadı. Lütfen tekrar deneyin.',
      );
    } on SocialAuthException {
      rethrow;
    } on AuthException catch (error) {
      if (kDebugMode) debugPrint('apple supabase error: ${error.message}');
      throw SocialAuthException(_messageFor(error, 'Apple'));
    } catch (error) {
      if (kDebugMode) debugPrint('apple sign-in unexpected: $error');
      throw const SocialAuthException(
        'Apple ile giriş yapılamadı. İnternet bağlantını kontrol edip tekrar dene.',
      );
    }
  }

  // Tarayıcı tabanlı OAuth (PKCE). Client secret Flutter'da YOK — Google
  // client id/secret yalnızca Supabase Dashboard'da duruyor. Oturum,
  // deep link ile uygulamaya dönünce AuthGate tarafından yakalanır; bu
  // yüzden burada "başarı"yı beklemiyoruz. Kullanıcı tarayıcıyı kapatırsa
  // hata değil, sessizce giriş ekranında kalır.
  Future<void> signInWithGoogle() async {
    try {
      final launched = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: oauthRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw const SocialAuthException(
          'Google ile giriş yapılamadı. Lütfen tekrar deneyin.',
        );
      }
    } on SocialAuthException {
      rethrow;
    } on AuthException catch (error) {
      if (kDebugMode) debugPrint('google supabase error: ${error.message}');
      throw SocialAuthException(_messageFor(error, 'Google'));
    } catch (error) {
      if (kDebugMode) debugPrint('google sign-in unexpected: $error');
      throw const SocialAuthException(
        'Google ile giriş yapılamadı. İnternet bağlantını kontrol edip tekrar dene.',
      );
    }
  }

  String _messageFor(AuthException error, String provider) {
    final message = error.message.toLowerCase();

    if (message.contains('already') || message.contains('identity')) {
      return 'Bu e-posta başka bir giriş yöntemiyle kayıtlı. '
          'Önceki yöntemle giriş yapmayı dene.';
    }

    if (message.contains('network') || message.contains('socket')) {
      return 'İnternet bağlantını kontrol et.';
    }

    return '$provider ile giriş yapılamadı. Lütfen tekrar deneyin.';
  }
}
