import 'package:supabase_flutter/supabase_flutter.dart';

String? _clean(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

// Önce "profiles" satırı (varsa), sonra auth metadata. Apple/Google girişte
// ad `full_name`/`name` yerine yalnızca given_name + family_name olarak da
// gelebilir; bu durumda ikisi birleştirilir.
String? resolveFullName(User? user, Map<String, dynamic>? profile) {
  final metadata = user?.userMetadata;

  for (final candidate in [
    profile?['full_name'],
    profile?['name'],
    profile?['display_name'],
    metadata?['full_name'],
    metadata?['name'],
    metadata?['display_name'],
  ]) {
    final value = _clean(candidate);
    if (value != null) return value;
  }

  final given = _clean(metadata?['given_name'] ?? metadata?['first_name']);
  final family = _clean(metadata?['family_name'] ?? metadata?['last_name']);
  final combined = [given, family].whereType<String>().join(' ');

  if (combined.isNotEmpty) return combined;

  // Son olarak, sağlayıcı kimliklerinde (identities) erişilebilir bir ad
  // alanı var mı? (Apple ID token'ı ad içermediği için çoğu zaman yoktur.)
  for (final identity in user?.identities ?? const <UserIdentity>[]) {
    final data = identity.identityData;
    if (data == null) continue;

    for (final key in ['full_name', 'name']) {
      final value = _clean(data[key]);
      if (value != null) return value;
    }

    final identityName = [
      _clean(data['given_name'] ?? data['first_name']),
      _clean(data['family_name'] ?? data['last_name']),
    ].whereType<String>().join(' ');

    if (identityName.isNotEmpty) return identityName;
  }

  return null;
}

String firstNameOf(String fullName) {
  return fullName.trim().split(RegExp(r'\s+')).first;
}

String _upperLetter(String word) {
  final letter = String.fromCharCode(word.runes.first);
  return letter == 'i' ? 'İ' : letter.toUpperCase();
}

// "Ahmet Aksu" -> "AA", "Kaan Babadağ" -> "KB"; tek kelime -> tek harf.
String initialsOf(String fullName) {
  final words = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  if (words.isEmpty) return '';
  if (words.length == 1) return _upperLetter(words.first);

  return _upperLetter(words.first) + _upperLetter(words.last);
}

// Apple "E-postamı Gizle" aktarma adresleri anlamlı bir isim içermez.
bool isRelayEmail(String? email) {
  return email != null && email.toLowerCase().endsWith('@privaterelay.appleid.com');
}
