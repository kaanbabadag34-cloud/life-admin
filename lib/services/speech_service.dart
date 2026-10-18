import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum SpeechPermission { granted, notDetermined, denied, unavailable }

// iOS Speech framework (tr-TR) köprüsü. Ses dosyaya yazılmaz ve sunucumuza
// gönderilmez; yalnızca tanıma motoruna beslenir. Hiçbir metot hata
// fırlatmaz.
class SpeechService {
  SpeechService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static final SpeechService instance = SpeechService._();

  static const MethodChannel _channel = MethodChannel('life_admin/speech');

  void Function(double level)? onLevel;
  void Function(String text)? onPartial;
  void Function(String text, double confidence)? onFinal;
  void Function(String code)? onError;

  bool get _supported => defaultTargetPlatform == TargetPlatform.iOS;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'level':
        onLevel?.call((call.arguments as num).toDouble());
      case 'partial':
        onPartial?.call(call.arguments as String);
      case 'final':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        onFinal?.call(
          data['text'] as String? ?? '',
          (data['confidence'] as num?)?.toDouble() ?? 0,
        );
      case 'error':
        onError?.call(call.arguments as String? ?? 'error');
    }
  }

  SpeechPermission _parse(String? value) {
    switch (value) {
      case 'granted':
        return SpeechPermission.granted;
      case 'notDetermined':
        return SpeechPermission.notDetermined;
      default:
        return SpeechPermission.denied;
    }
  }

  Future<SpeechPermission> permissionStatus() async {
    if (!_supported) return SpeechPermission.unavailable;

    try {
      return _parse(await _channel.invokeMethod<String>('permissionStatus'));
    } catch (_) {
      return SpeechPermission.unavailable;
    }
  }

  Future<SpeechPermission> requestPermissions() async {
    if (!_supported) return SpeechPermission.unavailable;

    try {
      return _parse(await _channel.invokeMethod<String>('requestPermissions'));
    } catch (_) {
      return SpeechPermission.unavailable;
    }
  }

  Future<bool> start() async {
    if (!_supported) return false;

    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      return false;
    }
  }

  // Parmak kalktı: ses girişini bitirir; SON sonuç onFinal ile gelir.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  // Mikrofonu hemen serbest bırakır; hiçbir sonuç üretilmez.
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<bool>('cancel');
    } catch (_) {}
  }
}
