import 'package:flutter_test/flutter_test.dart';
import 'package:life_admin/features/plans/plan_text_parser.dart';
import 'package:life_admin/features/plans/reminder_parser.dart';

void main() {
  group('süre ifadeleri', () {
    int? d(String text) => parseDurationMinutes(text);

    test('örnek: 2 saat sürecek', () {
      expect(d("Yarın toplantım var 15.00'te, 2 saat sürecek."), 120);
    });

    test('saat, dakika ve karışık biçimler', () {
      expect(d('Toplantı 1 saat sürecek'), 60);
      expect(d('Randevu 30 dakika sürecek'), 30);
      expect(d('Toplantı 1 buçuk saat sürecek'), 90);
      expect(d('Antrenman 45 dk sürer'), 45);
      expect(d('Ders 2 saat 15 dakika'), 135);
      expect(d('Toplantı iki saat sürecek'), 120);
      expect(d('Toplantı 1,5 saat sürecek'), 90);
      expect(d('Görüşme yarım saat sürecek'), 30);
      expect(d('Film iki buçuk saat sürecek'), 150);
    });

    test('hatırlatma ofseti ve gecikme süre sayılmaz', () {
      expect(d('Yarın 15.00 toplantı 20 dk önce hatırlat'), isNull);
      expect(d('Yarım saat sonra beni uyar'), isNull);
      expect(d('1 saat önceden hatırlat'), isNull);
    });

    test('süre + hatırlatma birlikte', () {
      const text = "Yarın 15.00'te toplantı, 2 saat sürecek, 20 dk önce hatırlat";
      expect(d(text), 120);
      expect(parseReminderIntent(text).minutesBefore, 20);
      expect(findClock(text), const ClockMention(15, 0));
    });

    test('süre yoksa null, farklı süreler belirsizdir', () {
      expect(d('Yarın 15.00 toplantı'), isNull);
      expect(d('1 saat sürecek ama 3 saat de sürebilir'), isNull);
    });
  });

  group('başlangıç-bitiş aralığı', () {
    test("14.00'te başlayıp 16.30'da bitecek", () {
      const text = "Yarın 14.00'te başlayıp 16.30'da bitecek toplantı";
      final range = findClockRange(text);
      expect(range, isNotNull);
      expect(range!.start, const ClockMention(14, 0));
      expect(range.end, const ClockMention(16, 30));

      final start = DateTime(2026, 10, 21, 14, 0);
      expect(minutesBetween(start, range.end), 150);
      expect(findClock(text), isNull);
    });

    test('belirsiz bitiş saati başlangıçtan sonraki en yakın adayı seçer', () {
      final start = DateTime(2026, 10, 21, 14, 0);
      expect(minutesBetween(start, const ClockMention(4, 0, ambiguous: true)), 120);
      expect(minutesBetween(DateTime(2026, 10, 21, 22, 0), const ClockMention(1, 0, ambiguous: true)), 180);
    });

    test('bitiş işareti olmayan iki saat aralık sayılmaz', () {
      expect(findClockRange('9.00 ve 17.00 olmak üzere iki toplantı'), isNull);
    });

    test('hatırlatma: aralık da açık saat sayılır', () {
      expect(
        parseReminderIntent("14.00'te başlayıp 16.30'da bitecek, hatırlat").kind,
        ReminderIntentKind.atTaskTime,
      );
    });
  });

  group('süre başlığa karışmaz', () {
    test('süre ve saat ifadeleri başlıktan atılır', () {
      const original = "Yarın toplantım var 15.00'te, 2 saat sürecek.";
      expect(cleanPlanTitle('Toplantı', original), 'Toplantı');
      expect(cleanPlanTitle('Toplantı 2 saat sürecek', original), 'Toplantı');
      expect(cleanPlanTitle(original, original), 'Toplantım');
    });

    test('anlamlı süre kullanımı korunur', () {
      expect(cleanPlanTitle('2 saatlik ders', 'Yarın 2 saatlik ders'), '2 saatlik ders');
    });

    test('başlangıç-bitiş ifadesi başlıktan atılır', () {
      const original = "Yarın 14.00'te başlayıp 16.30'da bitecek toplantı";
      expect(cleanPlanTitle(original, original), 'Toplantı');
    });
  });
}
