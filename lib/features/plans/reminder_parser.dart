// Kullanıcının doğal dil mesajından hatırlatma isteğini çıkarır. Görev
// tarihi/saati AI'dan (parse-plan) gelir; bu sınıf yalnızca "ne kadar önce
// hatırlat" bilgisini ayıklar. Belirsiz ifadelerde rastgele saat UYDURMAZ.
import 'plan_text_parser.dart';

enum ReminderIntentKind {
  none, // hatırlatma istenmemiş
  offset, // "1 saat önce hatırlat"
  atTaskTime, // "tam saatinde" veya "9'da hatırlat"
  ambiguous, // "yarın sabah hatırlat" — saat belirsiz
  afterDelay, // "yarım saat sonra beni uyar" — şimdiden itibaren gecikme
}

class ReminderIntent {
  final ReminderIntentKind kind;
  final int? minutesBefore;

  const ReminderIntent(this.kind, [this.minutesBefore]);

  static const none = ReminderIntent(ReminderIntentKind.none);
}

const Map<String, int> _numberWords = {
  'on beş': 15,
  'yirmi beş': 25,
  'kırk beş': 45,
  'yarım': 0, // özel: saat için 30 dk
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
  'yirmi': 20,
  'otuz': 30,
  'kırk': 40,
};

String _normalize(String text) {
  return text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
}

final RegExp _reminderWord = RegExp(r'hatırla|hatirla|bildir|uyar|haber ver|alarm');

final RegExp _exactTimePhrase = RegExp(r'tam saatinde|tam zamanında|vaktinde|tam vaktinde');

// "20 dk önce", "20dk önceden", "10 dakika öncesinde", "1 saat önce",
// "çeyrek saat önce", "yarım saat önce", "iki gün önce"
final RegExp _offsetPattern = RegExp(
  r'(\d+|on beş|yirmi beş|kırk beş|çeyrek|yarım|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on|yirmi|otuz|kırk)'
  r'\s*(dakika|dak|dk|saat|sa|gün)\s*(?:önceden|öncesinde|önce|evvel|kala)',
);

// "yarım saat sonra", "20 dk sonra", "iki saat sonra"
final RegExp _delayPattern = RegExp(
  r'(\d+|on beş|yirmi beş|kırk beş|çeyrek|yarım|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on|yirmi|otuz|kırk)'
  r'\s*(dakika|dak|dk|saat|sa)\s*sonra',
);

ReminderIntent parseReminderIntent(String rawText) {
  final text = _normalize(rawText);

  final delayMatch = _delayPattern.firstMatch(text);
  if (delayMatch != null && _reminderWord.hasMatch(text)) {
    final token = delayMatch.group(1)!;
    final unit = delayMatch.group(2)!;
    final isHour = unit == 'saat' || unit == 'sa';

    int? minutes;
    if (token == 'yarım' && isHour) {
      minutes = 30;
    } else if (token == 'çeyrek' && isHour) {
      minutes = 15;
    } else if (token != 'yarım' && token != 'çeyrek') {
      final amount = int.tryParse(token) ?? _numberWords[token];
      if (amount != null) minutes = amount * (isHour ? 60 : 1);
    }

    if (minutes != null && minutes > 0 && minutes <= 24 * 60) {
      return ReminderIntent(ReminderIntentKind.afterDelay, minutes);
    }

    return const ReminderIntent(ReminderIntentKind.ambiguous);
  }

  final offsetMatch = _offsetPattern.firstMatch(text);
  final hasReminderWord = _reminderWord.hasMatch(text);

  if (offsetMatch != null && hasReminderWord) {
    final token = offsetMatch.group(1)!;
    final unit = offsetMatch.group(2)!;

    int? amount = int.tryParse(token);
    final isHalf = token == 'yarım';

    if (isHalf || token == 'çeyrek') {
      // "yarım saat" = 30 dk, "çeyrek saat" = 15 dk; başka birimler belirsiz.
      if (unit != 'saat' && unit != 'sa') {
        return const ReminderIntent(ReminderIntentKind.ambiguous);
      }
      return ReminderIntent(ReminderIntentKind.offset, isHalf ? 30 : 15);
    }

    amount ??= _numberWords[token];
    if (amount == null) return const ReminderIntent(ReminderIntentKind.ambiguous);

    final factor = switch (unit) {
      'saat' || 'sa' => 60,
      'gün' => 1440,
      _ => 1,
    };

    final minutes = amount * factor;

    if (minutes <= 0) return const ReminderIntent(ReminderIntentKind.atTaskTime, 0);
    if (minutes > 7 * 1440) return const ReminderIntent(ReminderIntentKind.ambiguous);

    return ReminderIntent(ReminderIntentKind.offset, minutes);
  }

  if (_exactTimePhrase.hasMatch(text)) {
    return const ReminderIntent(ReminderIntentKind.atTaskTime, 0);
  }

  if (!hasReminderWord) return ReminderIntent.none;

  // "9'da bana su içmeyi hatırlat" — açık bir saat var, ofset yok: görev
  // saatinde hatırlat. Saat ifadesi yoksa ("yarın sabah hatırlat") saat
  // uydurmuyoruz.
  if (findClock(rawText) != null || findClockRange(rawText) != null) {
    return const ReminderIntent(ReminderIntentKind.atTaskTime, 0);
  }

  return const ReminderIntent(ReminderIntentKind.ambiguous);
}
