import 'package:flutter_test/flutter_test.dart';
import 'package:life_admin/features/plans/plan_text_parser.dart';
import 'package:life_admin/features/plans/reminder_parser.dart';

void main() {
  group('saat ayrıştırma', () {
    test('24 saatlik ve noktalı/iki noktalı biçimler', () {
      expect(findClock('Yarın 15.30 dişçi'), const ClockMention(15, 30));
      expect(findClock('Pazartesi 16:45 spor'), const ClockMention(16, 45));
      expect(findClock('Cuma 14.00 ders'), const ClockMention(14, 0));
      expect(findClock('toplantı 13.40'), const ClockMention(13, 40));
    });

    test('ek ve "saat" biçimleri', () {
      expect(findClock("Bugün 18'de toplantım var"), const ClockMention(18, 0));
      expect(findClock("Yarın 9'da ilaç almayı hatırlat"), const ClockMention(9, 0));
      expect(findClock('Yarın saat 10 dişçi'), const ClockMention(10, 0));
      expect(findClock('saat 11.15 randevu'), const ClockMention(11, 15));
    });

    test('1-6 arası ve gün bölümü yok: belirsiz', () {
      final clock = findClock("Dişçi randevum var bugün 1.40'da 20 dk önceden hatırlat.");
      expect(clock, const ClockMention(1, 40, ambiguous: true));
      expect(clock!.candidateHours, [1, 13]);
    });

    test('gün bölümü belirsizliği giderir', () {
      expect(findClock("akşam 6'da yemek"), const ClockMention(18, 0));
      expect(findClock("öğleden sonra 3'te toplantı".replaceAll("3'te", "3'de")),
          const ClockMention(15, 0));
      expect(findClock("sabah 5.30'da koşu"), const ClockMention(5, 30));
    });

    test('buçuk', () {
      expect(findClock('yarın 1 buçukta berber').toString(), isNotNull);
      final clock = findClock('akşam 7 buçukta yemek');
      expect(clock, const ClockMention(19, 30));
    });

    test('yazıyla saatler (konuşma tanıma)', () {
      expect(findClock('Yarın saat üçte dişçiye gideceğim'),
          const ClockMention(3, 0, ambiguous: true));
      expect(findClock('akşam altıda yemek'), const ClockMention(18, 0));
      expect(findClock('cuma dokuzda toplantı'), const ClockMention(9, 0));
      expect(findClock('yarın on ikide görüşme'), const ClockMention(12, 0));
    });

    test('sesli örnek: yirmi dakika önce hatırlat', () {
      const text = 'Yarın saat üçte dişçiye gideceğim, yirmi dakika önce hatırlat';
      expect(parseReminderIntent(text).minutesBefore, 20);
      expect(cleanPlanTitle('Dişçiye gideceğim', text), 'Dişçiye gideceğim');
    });

    test('tarih saat sanılmaz, birden çok saat atlanır', () {
      expect(findClock('15.03.2026 vergi'), isNull);
      expect(findClock('15.03 tarihinde vergi'), isNull);
      expect(findClock("9'da başla 17:30'a kadar çalış"), isNull);
      expect(findClock('Yarın dişçi'), isNull);
    });
  });

  group('hatırlatma ofseti', () {
    int? minutes(String text) => parseReminderIntent(text).minutesBefore;

    test('dk / dakika / dak / bitişik yazım', () {
      expect(minutes('Yarın 15.30 dişçi 10dk önce hatırlat'), 10);
      expect(minutes('Yarın 15.30 dişçi 20 dk önceden hatırlat'), 20);
      expect(minutes('Cuma 14.00 ders 30 dakika öncesinde bildirim gönder'), 30);
      expect(minutes('Yarın 14.00 ders 5 dak önce uyar'), 5);
    });

    test('saat, çeyrek ve yarım', () {
      expect(minutes('Bugün 18\'de toplantım var 1 saat önce uyar'), 60);
      expect(minutes('Pazartesi 16:45 spor, çeyrek saat önce haber ver'), 15);
      expect(minutes('Yarın 9.30 randevu yarım saat önce hatırlat'), 30);
    });

    test('ofset yoksa görev saatinde veya belirsiz', () {
      final atTime = parseReminderIntent("Yarın 9'da ilaç almayı hatırlat");
      expect(atTime.kind, ReminderIntentKind.atTaskTime);
      expect(atTime.minutesBefore, 0);
      expect(parseReminderIntent('Yarın sabah hatırlat').kind,
          ReminderIntentKind.ambiguous);
    });
  });

  group('başlık temizleme', () {
    test('komutlar ve saat başlığa girmez', () {
      expect(
        cleanPlanTitle(
          "Dişçi randevum var bugün 1.40'da 20 dk önceden hatırlat.",
          "Dişçi randevum var bugün 1.40'da 20 dk önceden hatırlat.",
        ),
        'Dişçi randevum',
      );
      expect(
        cleanPlanTitle('Dişçi', 'Yarın 15.30 dişçi 10dk önce hatırlat'),
        'Dişçi',
      );
    });

    test('AI başlığında kalan komut temizlenir', () {
      expect(
        cleanPlanTitle('Dişçi 10dk önce hatırlat', 'Yarın 15.30 dişçi 10dk önce hatırlat'),
        'Dişçi',
      );
      expect(
        cleanPlanTitle('Toplantı 1 saat önce uyar', "Bugün 18'de toplantım var 1 saat önce uyar"),
        'Toplantı',
      );
    });

    test('tüm mesajı kopyalayan başlık kısaltılır', () {
      expect(
        cleanPlanTitle("Yarın 9'da ilaç almayı hatırlat", "Yarın 9'da ilaç almayı hatırlat"),
        'İlaç almayı',
      );
      expect(
        cleanPlanTitle('Spor', 'Pazartesi 16:45 spor, çeyrek saat önce haber ver'),
        'Spor',
      );
    });

    test('sondaki gereksiz tire/ayırıcı temizlenir, kelime içi tire korunur', () {
      const original = 'Yarın arkadaşıma git 20 dk önce hatırlat';
      for (final dash in ['-', ' -', '–', '—', '−', ' - ', '‒']) {
        expect(cleanPlanTitle('Arkadaşıma git$dash', original), 'Arkadaşıma git');
      }
      expect(cleanPlanTitle('E-posta gönder -', original), 'E-posta gönder');
      expect(cleanPlanTitle('Arkadaşıma git - 20 dk önce hatırlat', original),
          'Arkadaşıma git');
    });

    test('boşsa varsayılan', () {
      expect(cleanPlanTitle('', 'Yarın 9 da hatırlat'), 'Plan');
    });
  });
}
