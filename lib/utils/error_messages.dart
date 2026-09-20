import 'package:flutter/foundation.dart';

// Kullanıcıya ham Supabase/Postgrest hata metnini göstermek yerine kısa,
// anlaşılır bir mesaj döndürür. Teknik detay debug konsoluna yazılır.
String friendlyErrorMessage(Object error, String fallback) {
  debugPrint('Hata detayı: $error');
  return fallback;
}
