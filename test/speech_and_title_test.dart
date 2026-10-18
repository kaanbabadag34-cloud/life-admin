import 'package:flutter_test/flutter_test.dart';
import 'package:life_admin/features/plans/plan_text_parser.dart';
import 'package:life_admin/features/plans/reminder_parser.dart';
import 'package:life_admin/features/plans/speech_normalizer.dart';

void main() {
  group('başlık', () {
    const original =
        "Yarın deneme sınavına gireceğim 17.30'da 1 saat önceden hatırlat.";

    test('sondaki eksik "için"/"ve" atılır', () {
      expect(cleanPlanTitle('Deneme sınavı için', original), 'Deneme sınavı');
      expect(cleanPlanTitle('Market ve', original), 'Market');
      expect(cleanPlanTitle('Deneme sınavı için -', original), 'Deneme sınavı');
    });

    test('anlamlı kullanımlar korunur', () {
      expect(cleanPlanTitle('Ali ile toplantı', 'Ali ile toplantı yarın'),
          'Ali ile toplantı');
      expect(cleanPlanTitle('Sınav için çalış', 'Sınav için çalış yarın'),
          'Sınav için çalış');
    });

    test('tarih/saat/hatırlatma başlığa karışmaz', () {
      expect(findClock(original), const ClockMention(17, 30));
      final intent = parseReminderIntent(original);
      expect(intent.kind, ReminderIntentKind.offset);
      expect(intent.minutesBefore, 60);
    });
  });

  group('yazıyla saat (sesli)', () {
    test('saat beşte / on yedi otuzda / sekizde', () {
      expect(findClock('Yarın saat beşte dişçiye gideceğim'),
          const ClockMention(5, 0, ambiguous: true));
      expect(findClock('Yarın deneme sınavım var, saat on yedi otuzda.'),
          const ClockMention(17, 30));
      expect(findClock('Bugün saat sekizde ders çalışacağım'),
          const ClockMention(8, 0));
      expect(findClock('saat dokuz buçukta toplantı'), const ClockMention(9, 30));
    });

    test('süreler saat sanılmaz', () {
      expect(findClock('iki saat on dakika sonra uyar'), isNull);
      expect(findClock('yarım saat sonra beni uyar'), isNull);
    });

    test('başlıktan yazıyla saat atılır', () {
      expect(
        cleanPlanTitle(
          'Yarın deneme sınavım var, saat on yedi otuzda.',
          'Yarın deneme sınavım var, saat on yedi otuzda.',
        ),
        'Deneme sınavım',
      );
    });
  });

  group('hatırlatma (sesli örnekler)', () {
    test('yirmi dakika önce', () {
      final intent = parseReminderIntent(
        'Yarın saat üçte toplantım var, yirmi dakika önce hatırlat.',
      );
      expect(intent.kind, ReminderIntentKind.offset);
      expect(intent.minutesBefore, 20);
    });

    test('yarım saat sonra beni uyar: şimdiden gecikme', () {
      final intent = parseReminderIntent('Yarım saat sonra beni uyar.');
      expect(intent.kind, ReminderIntentKind.afterDelay);
      expect(intent.minutesBefore, 30);
      expect(cleanPlanTitle('', 'Yarım saat sonra beni uyar.'), 'Plan');
    });

    test('yarım saat önce hatırlat hâlâ ofset', () {
      expect(parseReminderIntent('Yarın 9.30 randevu yarım saat önce hatırlat').kind,
          ReminderIntentKind.offset);
    });
  });

  group('konuşma normalizasyonu', () {
    test('diakritik ve büyük harf düzeltmesi', () {
      expect(normalizeSpeechText('YARIN SAAT BEŞTE DİŞÇİYE GİDECEĞİM').text,
          'yarın saat beşte dişçiye gideceğim');
      expect(normalizeSpeechText('yarin saat besteydi').text, contains('yarın'));
      expect(normalizeSpeechText('obur gun arkadasima gidecegim').text,
          contains('öbür gün'));
    });

    test('kelime eklenmez', () {
      expect(normalizeSpeechText('  Bugün   saat sekizde ders  ').text,
          'Bugün saat sekizde ders');
    });

    test('yarım ölçü/süre bağlamında doğru, aksi halde belirsiz', () {
      expect(normalizeSpeechText('Yarım saat sonra beni uyar').yarimAmbiguous, isFalse);
      expect(normalizeSpeechText('yarım kilo domates al').yarimAmbiguous, isFalse);

      final ambiguous = normalizeSpeechText('Yarım saat dişçiye gideceğim sınav');
      expect(ambiguous.yarimAmbiguous, isFalse);

      final mis = normalizeSpeechText('Yarım deneme sınavım var');
      expect(mis.yarimAmbiguous, isTrue);
      expect(mis.yarinAlternative, 'Yarın deneme sınavım var');
      expect(mis.text, 'Yarım deneme sınavım var');
    });

    test('metinde yarın varsa yarım belirsiz sayılmaz', () {
      expect(normalizeSpeechText('yarın yarım deneme').yarimAmbiguous, isFalse);
    });
  });
}
