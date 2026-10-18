// Kullanıcının doğal dil mesajındaki SAAT ifadelerini ve başlığı ayıklar.
// Görev tarihi AI'dan (parse-plan) gelir; saat ifadesi metinde açıkça varsa
// (17.30, 13:40, 1.40'da, 9'da, saat 5, 1 buçuk...) güvenilir olan bu
// ayrıştırma kullanılır. Belirsiz saatlerde (ör. "1.40": 01:40 mı 13:40 mı?)
// tahmin yürütülmez, ayrıca sorulur.

String normalizeTr(String text) {
  return text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
}

class ClockMention {
  // Çözümlenmiş 24 saatlik saat (belirsizse "sabah" adayı).
  final int hour;
  final int minute;

  // true: 1-6 arası saat, gün bölümü belirtilmemiş (01:40 mı 13:40 mı?).
  final bool ambiguous;

  const ClockMention(this.hour, this.minute, {this.ambiguous = false});

  // Belirsizse iki aday saat (sabah, öğleden sonra); değilse tek aday.
  List<int> get candidateHours => ambiguous ? [hour, hour + 12] : [hour];

  @override
  bool operator ==(Object other) =>
      other is ClockMention &&
      other.hour == hour &&
      other.minute == minute &&
      other.ambiguous == ambiguous;

  @override
  int get hashCode => Object.hash(hour, minute, ambiguous);
}

const String _notLetter = r'(?![\p{L}\d])';
const String _suffix = r"""\s*['’]?\s*(?:da|de|ta|te)""";

// 17.30 / 13:40 / 1.40 (+ isteğe bağlı "'da")
final RegExp _hhmm = RegExp(
  r'(?<![\d.:,])(\d{1,2})[:.](\d{2})(?![\d:])(?!\.\d)',
);

// saat 5 / saat 5.30 / saat 1 buçuk
final RegExp _saatN = RegExp(
  r'saat\s*(\d{1,2})(?:[:.](\d{2}))?(\s*buçuk)?' + _notLetter,
  unicode: true,
);

// 9'da / 9 da / 1 buçukta / 1 buçuk'ta
final RegExp _hourSuffix = RegExp(
  r'(?<![\d.:,])(\d{1,2})(\s*buçuk)?' + _suffix + _notLetter,
  unicode: true,
);

// 1 buçuk (ek olmadan)
final RegExp _halfHour = RegExp(
  r'(?<![\d.:,])(\d{1,2})\s*buçuk' + _notLetter,
  unicode: true,
);

// "üçte", "dörtte", "altıda", "on ikide", "bir buçukta" (yazıyla saatler;
// konuşma tanıma çoğu zaman rakam verir ama kelime de döndürebilir).
const Map<String, int> _hourWords = {
  'on iki': 12,
  'on bir': 11,
  'bir': 1,
  'iki': 2,
  'üç': 3,
  'dört': 4,
  'beş': 5,
  'altı': 6,
  'yedi': 7,
  'sekiz': 8,
  'dokuz': 9,
  'on': 10,
};

final RegExp _wordHour = RegExp(
  r"(?<![\p{L}])(on\s+iki|on\s+bir|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on)(\s*buçuk)?\s*['’]?(?:de|da|te|ta)(?![\p{L}\d])",
  unicode: true,
);

final RegExp _suffixAfter = RegExp(
  r"""^\s*['’]?\s*(?:da|de|ta|te)(?![\p{L}\d])""",
  unicode: true,
);
final RegExp _saatBefore = RegExp(r'saat\s*$');

String? _period(String text) {
  if (RegExp(r'öğleden\s+sonra').hasMatch(text)) return 'ogleden_sonra';
  if (RegExp(r'sabah').hasMatch(text)) return 'sabah';
  if (RegExp(r'öğle|öğlen').hasMatch(text)) return 'ogle';
  if (RegExp(r'akşam').hasMatch(text)) return 'aksam';
  if (RegExp(r'gece').hasMatch(text)) return 'gece';
  return null;
}

ClockMention? _resolve(int hour, int minute, String? period) {
  if (minute < 0 || minute > 59 || hour < 0 || hour > 24) return null;

  if (hour == 24) return ClockMention(0, minute);
  if (hour >= 13 || hour == 0) return ClockMention(hour, minute);

  switch (period) {
    case 'sabah':
      return ClockMention(hour == 12 ? 0 : hour, minute);
    case 'ogleden_sonra':
    case 'ogle':
    case 'aksam':
      return ClockMention(hour == 12 ? 12 : hour + 12, minute);
    case 'gece':
      if (hour == 12) return ClockMention(0, minute);
      return ClockMention(hour >= 6 ? hour + 12 : hour, minute);
  }

  // Gün bölümü yok: 7-12 sabah/öğle varsayılır, 1-6 belirsizdir.
  if (hour >= 7) return ClockMention(hour, minute);
  return ClockMention(hour, minute, ambiguous: true);
}

// "saat on yedi otuzda", "saat beşte", "saat dokuz buçuk" gibi YAZIYLA saatler
// (konuşma tanıma sayıları çoğu zaman kelime olarak döndürür).
const Map<String, int> _unitWords = {
  'bir': 1,
  'iki': 2,
  'üç': 3,
  'dört': 4,
  'beş': 5,
  'altı': 6,
  'yedi': 7,
  'sekiz': 8,
  'dokuz': 9,
};

const Map<String, int> _tensWords = {
  'on': 10,
  'yirmi': 20,
  'otuz': 30,
  'kırk': 40,
  'elli': 50,
};

const Set<String> _followingUnits = {
  'dakika', 'dk', 'dak', 'saat', 'gün', 'kez', 'kişi', 'tane', 'defa', 'lira',
  'tl', 'ay', 'hafta', 'yıl', 'sene', 'önce', 'sonra',
};

String _numberToken(String token) {
  if (_unitWords.containsKey(token) ||
      _tensWords.containsKey(token) ||
      token == 'sıfır' ||
      token == 'buçuk') {
    return token;
  }

  // Ek almış sözcük: beşte, dörtte, altıda, yedide, otuzda, kırkta, onda...
  for (final suffix in ['te', 'ta', 'de', 'da']) {
    if (token.endsWith(suffix) && token.length > suffix.length) {
      final base = token.substring(0, token.length - suffix.length);
      if (_unitWords.containsKey(base) || _tensWords.containsKey(base)) {
        return base;
      }
    }
  }

  return token;
}

// (değer, tüketilen token sayısı) veya null
(int, int)? _readNumber(List<String> tokens, int i) {
  if (i >= tokens.length) return null;

  final first = _numberToken(tokens[i]);

  if (first == 'sıfır') return (0, 1);

  if (_tensWords.containsKey(first)) {
    final tens = _tensWords[first]!;

    if (i + 1 < tokens.length) {
      final second = _numberToken(tokens[i + 1]);
      if (_unitWords.containsKey(second)) {
        return (tens + _unitWords[second]!, 2);
      }
    }

    return (tens, 1);
  }

  if (_unitWords.containsKey(first)) return (_unitWords[first]!, 1);

  return null;
}

final RegExp _numberish = RegExp(
  r'^(?:\d+|yarım|çeyrek|buçuk|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on|yirmi|otuz|kırk|elli)$',
  unicode: true,
);

List<(int, int, int)> _wordClocks(String text) {
  final matches = RegExp(r'[^\s,.;:!?]+').allMatches(text).toList();
  final tokens = matches.map((m) => m.group(0)!).toList();
  final results = <(int, int, int)>[];

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] != 'saat') continue;

    // "iki saat on dakika", "yarım saat" gibi süreler saat değildir.
    if (i > 0 && _numberish.hasMatch(tokens[i - 1])) continue;

    final hourRead = _readNumber(tokens, i + 1);
    if (hourRead == null) continue;

    var next = i + 1 + hourRead.$2;
    var minute = 0;

    if (next < tokens.length && tokens[next].startsWith('buçuk')) {
      minute = 30;
      next++;
    } else {
      final minuteRead = _readNumber(tokens, next);
      if (minuteRead != null) {
        minute = minuteRead.$1;
        next += minuteRead.$2;
      }
    }

    if (next < tokens.length && _followingUnits.contains(tokens[next])) continue;
    if (hourRead.$1 > 24 || minute > 59) continue;

    results.add((hourRead.$1, minute, matches[i].start));
  }

  return results;
}

// Metindeki TEK, net saat ifadesi. Hiç yoksa veya birbirinden farklı birden
// fazla saat varsa (ör. "9'da başla, 17:30'a kadar") null — o durumda AI'nın
// verdiği saate dokunulmaz.
List<(int, ClockMention)> _collectClocks(String rawText) {
  final text = normalizeTr(rawText);
  final period = _period(text);
  final found = <(int, ClockMention)>[];
  final consumed = <int>{};

  void add(Match match, int hour, int minute) {
    if (consumed.contains(match.start)) return;
    final mention = _resolve(hour, minute, period);
    if (mention == null) return;
    consumed.add(match.start);
    found.add((match.start, mention));
  }

  for (final m in _saatN.allMatches(text)) {
    final minute = m.group(2) != null
        ? int.parse(m.group(2)!)
        : (m.group(3) != null ? 30 : 0);
    add(m, int.parse(m.group(1)!), minute);
  }

  for (final m in _hhmm.allMatches(text)) {
    if (consumed.any((s) => s >= m.start - 6 && s <= m.start)) continue;

    final hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    final after = text.substring(m.end);
    final before = text.substring(0, m.start);

    // 15.03 gibi gün.ay'a benzeyenler yalnızca "'da" eki / "saat" ile saattir.
    final dateLike = minute >= 1 && minute <= 12 && hour <= 31;
    if (dateLike &&
        !_suffixAfter.hasMatch(after) &&
        !_saatBefore.hasMatch(before) &&
        period == null) {
      continue;
    }

    add(m, hour, minute);
  }

  for (final m in _hourSuffix.allMatches(text)) {
    if (found.isNotEmpty && consumed.any((s) => (s - m.start).abs() < 2)) {
      continue;
    }
    add(m, int.parse(m.group(1)!), m.group(2) != null ? 30 : 0);
  }

  for (final m in _wordHour.allMatches(text)) {
    final hour = _hourWords[m.group(1)!.replaceAll(RegExp(r'\s+'), ' ')];
    if (hour == null) continue;
    add(m, hour, m.group(2) != null ? 30 : 0);
  }

  for (final m in _halfHour.allMatches(text)) {
    if (consumed.any((s) => (s - m.start).abs() < 2)) continue;
    add(m, int.parse(m.group(1)!), 30);
  }

  for (final (hour, minute, position) in _wordClocks(text)) {
    final mention = _resolve(hour, minute, period);
    if (mention != null) found.add((position, mention));
  }

  found.sort((a, b) => a.$1.compareTo(b.$1));
  return found;
}

List<ClockMention> _distinctClocks(String rawText) {
  final seen = <ClockMention>{};
  final ordered = <ClockMention>[];

  for (final (_, mention) in _collectClocks(rawText)) {
    if (seen.add(mention)) ordered.add(mention);
  }

  return ordered;
}

ClockMention? findClock(String rawText) {
  final clocks = _distinctClocks(rawText);
  return clocks.length == 1 ? clocks.first : null;
}

class ClockRange {
  final ClockMention start;
  final ClockMention end;

  const ClockRange(this.start, this.end);
}

final RegExp _rangeMarker = RegExp(
  r'bit(?:ecek|er|iş|mesi|ir)|kadar|arası|arasında|sona\s+er',
);

// "14.00'te başlayıp 16.30'da bitecek", "14:00'dan 16:30'a kadar": tam iki
// farklı saat + bitiş işareti. Aksi halde null.
ClockRange? findClockRange(String rawText) {
  final clocks = _distinctClocks(rawText);
  if (clocks.length != 2) return null;
  if (!_rangeMarker.hasMatch(normalizeTr(rawText))) return null;

  return ClockRange(clocks[0], clocks[1]);
}

// Başlangıç bellidir; bitiş saati belirsizse (ör. "4") başlangıçtan sonraki
// EN YAKIN aday seçilir. Dakika cinsinden süre, yoksa null.
int? minutesBetween(DateTime start, ClockMention end) {
  int? best;

  for (final hour in end.candidateHours) {
    final endAt = DateTime(start.year, start.month, start.day, hour % 24, end.minute);
    var diff = endAt.difference(start).inMinutes;
    if (diff <= 0) diff += 1440;

    if (best == null || diff < best) best = diff;
  }

  if (best == null || best < 1 || best > 1440) return null;
  return best;
}

// -------------------------------------------------------------------------
// Etkinlik süresi
// -------------------------------------------------------------------------

const Set<String> _afterWords = {
  'önce', 'önceden', 'öncesinde', 'öncesi', 'sonra', 'sonrası', 'kala', 'evvel',
};

String _cleanToken(String token) {
  return token.replaceAll(RegExp(r'^[,.;:!?]+|[,.;:!?]+$'), '');
}

double? _numericToken(String token) {
  if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(token)) return null;
  return double.tryParse(token.replaceAll(',', '.'));
}

// tokens[end]'de biten sayı (rakam veya yazıyla), yoksa null.
double? _numberEndingAt(List<String> tokens, int end) {
  if (end < 0 || end >= tokens.length) return null;

  final numeric = _numericToken(tokens[end]);
  if (numeric != null) return numeric;

  for (final start in [end - 1, end]) {
    if (start < 0) continue;
    final read = _readNumber(tokens, start);
    if (read != null && start + read.$2 == end + 1) return read.$1.toDouble();
  }

  return null;
}

enum _DurationUnit { hour, minute }

_DurationUnit? _unitOf(String token) {
  if (token == 'saat' || token == 'sa') return _DurationUnit.hour;
  if (token == 'dakika' || token == 'dk' || token == 'dak') {
    return _DurationUnit.minute;
  }
  return null;
}

// Etkinlik SÜRESİ (dakika): "2 saat sürecek", "30 dakika", "1 buçuk saat",
// "45 dk sürer", "2 saat 15 dakika". "20 dk ÖNCE" / "yarım saat SONRA" gibi
// hatırlatma ofsetleri ve gecikmeler süre sayılmaz. Birbirinden farklı birden
// fazla süre varsa belirsizdir (null).
int? parseDurationMinutes(String rawText) {
  final tokens = normalizeTr(rawText)
      .split(RegExp(r'\s+'))
      .map(_cleanToken)
      .where((t) => t.isNotEmpty)
      .toList();

  final found = <int>{};

  for (var i = 0; i < tokens.length; i++) {
    final unit = _unitOf(tokens[i]);
    if (unit == null) continue;

    double? amount;

    if (i >= 1 && tokens[i - 1] == 'buçuk' && unit == _DurationUnit.hour) {
      final base = _numberEndingAt(tokens, i - 2);
      if (base != null) amount = base + 0.5;
    } else if (i >= 1 && tokens[i - 1] == 'yarım' && unit == _DurationUnit.hour) {
      amount = 0.5;
    } else if (i >= 1 && tokens[i - 1] == 'çeyrek' && unit == _DurationUnit.hour) {
      amount = 0.25;
    } else {
      amount = _numberEndingAt(tokens, i - 1);
    }

    if (amount == null || amount <= 0) continue;

    var minutes = amount * (unit == _DurationUnit.hour ? 60 : 1);
    var last = i;

    // "2 saat 15 dakika": dakika sayısı saat biriminin HEMEN ardından gelmeli
    // (araya başka sözcük girerse birleştirilmez).
    if (unit == _DurationUnit.hour && i + 1 < tokens.length) {
      final numeric = _numericToken(tokens[i + 1]);
      final read = numeric != null ? (numeric.round(), 1) : _readNumber(tokens, i + 1);

      if (read != null) {
        final unitIndex = i + 1 + read.$2;

        if (unitIndex < tokens.length &&
            _unitOf(tokens[unitIndex]) == _DurationUnit.minute) {
          minutes += (numeric ?? read.$1).toDouble();
          last = unitIndex;
        }
      }
    }

    final skipTo = last;

    if (last + 1 < tokens.length && _afterWords.contains(tokens[last + 1])) {
      i = skipTo;
      continue;
    }

    final rounded = minutes.round();
    if (rounded >= 1 && rounded <= 1440) found.add(rounded);

    i = skipTo;
  }

  return found.length == 1 ? found.first : null;
}

// -------------------------------------------------------------------------
// Başlık temizleme
// -------------------------------------------------------------------------

const String _units = r'(?:dakika|dak|dk|saat|sa|gün)';
const String _words =
    r'(?:on\s+beş|yirmi\s+beş|kırk\s+beş|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on|yirmi|otuz|kırk)';
const String _before = r'(?:önceden|öncesinde|önce|evvel|kala)';

final RegExp _offsetClause = RegExp(
  r'(?:bana\s+|beni\s+)?(?:\d+\s*' +
      _units +
      r'|çeyrek\s+saat|yarım\s+saat|' +
      _words +
      r'\s+' +
      _units +
      r')\s*' +
      _before +
      _notLetter,
  caseSensitive: false,
  unicode: true,
);

// "yarım saat sonra", "20 dakika sonra" (şimdiden itibaren gecikme)
final RegExp _delayClause = RegExp(
  r'(?:\d+\s*' +
      _units +
      r'|çeyrek\s+saat|yarım\s+saat|' +
      _words +
      r'\s+' +
      _units +
      r')\s*sonra' +
      _notLetter,
  caseSensitive: false,
  unicode: true,
);

// Süre ifadeleri: "2 saat sürecek", "45 dk sürer", "1 buçuk saat sürecek".
// AI başlığında yalnızca fiilli hali (…sürecek) atılır; "2 saatlik ders" gibi
// anlamlı kullanımlar korunur. Mesajdan başlık türetilirken fiilsiz süre de atılır.
const String _durationAmount =
    r'(?:\d+(?:[.,]\d+)?|on\s+beş|yirmi\s+beş|kırk\s+beş|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on|yirmi|otuz|kırk|elli)';
const String _durationUnit = r'(?:saat|sa|dakika|dk|dak)(?![\p{L}\d])';
const String _durationVerb = r'sür(?:ecek|er|üyor|mekte|mesi)\p{L}*';

final RegExp _durationWithVerb = RegExp(
  r'(?:(?:' + _durationAmount + r'(?:\s+buçuk)?|yarım|çeyrek)\s*' + _durationUnit +
      r'(?:\s+' + _durationAmount + r'\s*(?:dakika|dk|dak)(?![\p{L}\d]))?\s*)?' +
      _durationVerb,
  caseSensitive: false,
  unicode: true,
);

final RegExp _durationBare = RegExp(
  r'(?:' + _durationAmount + r'(?:\s+buçuk)?|yarım|çeyrek)\s*' + _durationUnit +
      r'(?:\s+' + _durationAmount + r'\s*(?:dakika|dk|dak)(?![\p{L}\d]))?',
  caseSensitive: false,
  unicode: true,
);

final RegExp _reminderVerbs = RegExp(
  r'(?:bana\s+|beni\s+)?(?<![\p{L}])(?:hatırlat\p{L}*|hatırla\p{L}*|uyar\p{L}*|bildirim\s+gönder\p{L}*|bildirim\s+ver\p{L}*|haber\s+ver\p{L}*|bildir\p{L}*|alarm\s+kur\p{L}*|tam\s+saatinde)',
  caseSensitive: false,
  unicode: true,
);

final RegExp _dateWords = RegExp(
  r'(?<![\p{L}])(?:bugün|yarın|öbür\s+gün|haftaya|pazartesi|salı|çarşamba|perşembe|cuma|cumartesi|pazar|sabah|akşam|öğleden\s+sonra|öğlen|gece)(?![\p{L}])',
  caseSensitive: false,
  unicode: true,
);

final RegExp _fillers = RegExp(
  r'(?<![\p{L}])(?:var|lütfen|saat|başlay\p{L}*|bitecek|biter|bitiş)(?![\p{L}])',
  caseSensitive: false,
  unicode: true,
);

String _stripClocks(String text) {
  return text
      .replaceAll(
        RegExp(
          r"(?<![\p{L}])saat\s+(?:(?:on|yirmi|otuz|kırk|elli|sıfır|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|buçuk)(?:te|ta|de|da)?(?![\p{L}])\s*)+",
          caseSensitive: false,
          unicode: true,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r"(?<![\p{L}])(?:saat\s+)?(?:on\s+iki|on\s+bir|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on)(?:\s*buçuk)?\s*['’]?(?:de|da|te|ta)(?![\p{L}\d])",
          caseSensitive: false,
          unicode: true,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r"""saat\s*\d{1,2}(?:[:.]\d{2})?(?:\s*buçuk)?(?:\s*['’]?\s*(?:da|de|ta|te))?""",
          caseSensitive: false,
          unicode: true,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r"""(?<![\d.:,])\d{1,2}[:.]\d{2}(?![\d:])(?:\s*['’]?\s*(?:da|de|ta|te)(?![\p{L}\d]))?""",
          caseSensitive: false,
          unicode: true,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r"""(?<![\d.:,])\d{1,2}(?:\s*buçuk)?\s*['’]?\s*(?:da|de|ta|te)(?![\p{L}\d])""",
          caseSensitive: false,
          unicode: true,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(r'(?<![\d.:,])\d{1,2}\s*buçuk(?:ta|te|da|de)?(?![\p{L}\d])',
            caseSensitive: false, unicode: true),
        ' ',
      );
}

String _capitalize(String text) {
  if (text.isEmpty) return text;
  final first = text.substring(0, 1);
  final upper = first == 'i' ? 'İ' : first.toUpperCase();
  return upper + text.substring(1);
}

// Başlığın SONUNDA kalan eksik bağlaç/edatlar ("Deneme sınavı için", "Market ve").
// Yalnızca sondaki; cümle içindeki kullanımlara dokunulmaz.
final RegExp _danglingTail = RegExp(
  r'(?:^|\s)(?:için|ve|ile|veya|ya\s+da|ama|ki)$',
  caseSensitive: false,
  unicode: true,
);

String _dropDanglingTail(String text) {
  var result = text;

  while (_danglingTail.hasMatch(result)) {
    result = _tidy(result.replaceFirst(_danglingTail, ''));
  }

  return result;
}

String _tidy(String text) {
  return text
      .replaceAll(RegExp(r'\s+'), ' ')
      // Baştaki/sondaki ayırıcılar (her türlü tire: - – — ‒ −); kelime içindeki
      // anlamlı tirelere ("e-posta") dokunulmaz.
      .replaceAll(
        RegExp(r'^[\s,.;:!?\p{Pd}\u2212]+|[\s,.;:!?\p{Pd}\u2212]+$', unicode: true),
        '',
      )
      .trim();
}

String _removeCommands(String text, {required bool stripDatesAndFillers}) {
  var result = text.replaceAll(_offsetClause, ' ');
  result = result.replaceAll(_delayClause, ' ');
  result = result.replaceAll(_durationWithVerb, ' ');
  if (stripDatesAndFillers) result = result.replaceAll(_durationBare, ' ');
  result = result.replaceAll(_reminderVerbs, ' ');
  result = _stripClocks(result);

  if (stripDatesAndFillers) {
    result = result.replaceAll(_dateWords, ' ').replaceAll(_fillers, ' ');
  }

  return _tidy(result);
}

bool _looksLikeFullMessage(String title, String original) {
  final normalizedTitle = normalizeTr(title);

  if (_reminderVerbs.hasMatch(title) || _offsetClause.hasMatch(title)) {
    return true;
  }

  if (findClock(title) != null) return true;

  return original.length > 30 &&
      normalizedTitle.length >= original.length * 0.8;
}

// Kısa, doğal başlık: AI başlığı kullanılır; ama içinde "20 dk önce hatırlat"
// gibi komutlar / saat ifadeleri varsa veya kullanıcının tüm mesajını
// kopyaladıysa, komutlar ve tarih/saat ifadeleri atılarak mesajdan türetilir.
String cleanPlanTitle(String aiTitle, String originalText) {
  var title = aiTitle.trim();

  if (title.isEmpty || _looksLikeFullMessage(title, originalText)) {
    title = _removeCommands(
      title.isEmpty ? originalText : title,
      stripDatesAndFillers: true,
    );

    if (title.isEmpty) {
      title = _removeCommands(originalText, stripDatesAndFillers: true);
    }
  } else {
    title = _removeCommands(title, stripDatesAndFillers: false);
  }

  title = _dropDanglingTail(title);

  if (title.isEmpty) return 'Plan';

  if (title.length > 60) {
    final cut = title.substring(0, 60);
    final space = cut.lastIndexOf(' ');
    title = space > 20 ? cut.substring(0, space) : cut;
  }

  return _capitalize(title);
}
