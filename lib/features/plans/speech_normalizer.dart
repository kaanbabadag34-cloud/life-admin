// Konuşma tanıma çıktısını AI'ya göndermeden önce GÜVENLİ biçimde düzeltir.
// Yalnızca yazım/diakritik düzeltmesi yapar; kullanıcının söylemediği kelime
// EKLEMEZ. "yarın" / "yarım" gibi gerçekten belirsiz durumlar sessizce
// düzeltilmez, [SpeechNormalization.yarimAmbiguous] ile işaretlenir.

class SpeechNormalization {
  final String text;

  // "yarım" geçiyor ama ölçü/süre bağlamında değil (muhtemelen "yarın").
  final bool yarimAmbiguous;

  // "yarım"ın "yarın" yapıldığı hali (yalnızca belirsizse anlamlı).
  final String? yarinAlternative;

  const SpeechNormalization(
    this.text, {
    this.yarimAmbiguous = false,
    this.yarinAlternative,
  });
}

// "yarım" + bu kelimeler gerçek bir ifadedir (yarım saat, yarım kilo...).
const List<String> _measurePrefixes = [
  'saat', 'gün', 'dakika', 'dk', 'kilo', 'kg', 'litre', 'lt', 'ekmek',
  'porsiyon', 'bardak', 'kaşık', 'paket', 'demet', 'tane', 'ay', 'yıl',
  'sene', 'hafta', 'lira', 'tl', 'metre', 'santim', 'gram', 'gr', 'çay',
  'simit', 'pide', 'somun', 'boy', 'gün', 'öğün',
];

final RegExp _yarim = RegExp(
  r'(?<![\p{L}])yarım(?![\p{L}])(\s+)?(\p{L}+)?',
  caseSensitive: false,
  unicode: true,
);

String _lowerTr(String text) {
  return text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
}

// Hepsi büyük harfle gelen çıktıyı (ör. "YARIN SAAT BEŞTE") küçültür.
String _fixCase(String text) {
  final letters = text.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  if (letters.length > 3 && letters == letters.toUpperCase()) {
    return _lowerTr(text);
  }
  return text;
}

// Diakritiği düşmüş yaygın zaman sözcüklerini düzeltir (yarin -> yarın).
final Map<RegExp, String> _foldFixes = {
  for (final entry in {
    'yarin': 'yarın',
    'bugun': 'bugün',
    'obur gun': 'öbür gün',
    'öbür gun': 'öbür gün',
    'obur gün': 'öbür gün',
    'persembe': 'perşembe',
    'carsamba': 'çarşamba',
    'aksam': 'akşam',
    'ogleden': 'öğleden',
    'dakıka': 'dakika',
  }.entries)
    RegExp(
      '(?<![\\p{L}])${entry.key}(?![\\p{L}])',
      caseSensitive: false,
      unicode: true,
    ): entry.value,
};

SpeechNormalization normalizeSpeechText(String raw) {
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = _fixCase(text);

  _foldFixes.forEach((pattern, replacement) {
    text = text.replaceAll(pattern, replacement);
  });

  final lower = _lowerTr(text);
  final hasYarin = RegExp(r'(?<![\p{L}])yarın(?![\p{L}])', unicode: true)
      .hasMatch(lower);

  var ambiguous = false;

  for (final match in _yarim.allMatches(lower)) {
    final next = match.group(2);
    final isMeasure = next != null &&
        _measurePrefixes.any((prefix) => next.startsWith(prefix));

    if (!isMeasure && !hasYarin) {
      ambiguous = true;
      break;
    }
  }

  if (!ambiguous) return SpeechNormalization(text);

  final alternative = text.replaceAllMapped(
    RegExp(r'(?<![\p{L}])yarım(?![\p{L}])', caseSensitive: false, unicode: true),
    (m) => m.group(0)![0] == 'Y' ? 'Yarın' : 'yarın',
  );

  return SpeechNormalization(
    text,
    yarimAmbiguous: true,
    yarinAlternative: alternative,
  );
}
