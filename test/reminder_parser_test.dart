import 'package:flutter_test/flutter_test.dart';
import 'package:life_admin/features/plans/reminder_parser.dart';
import 'package:life_admin/utils/reminder_format.dart';

void main() {
  ReminderIntent parse(String text) => parseReminderIntent(text);

  test('offset: 1 saat önce hatırlat', () {
    final intent = parse('Yarın 17.00 dişçi, 1 saat önce hatırlat');
    expect(intent.kind, ReminderIntentKind.offset);
    expect(intent.minutesBefore, 60);
  });

  test('offset: dakika, gün ve yazıyla sayılar', () {
    expect(parse('Toplantı yarın 10.00, 10 dakika önce hatırlat').minutesBefore, 10);
    expect(parse('Cuma 14:00 sunum 2 gün önce hatırlat').minutesBefore, 2880);
    expect(parse('Yarın 9.30 randevu, yarım saat önce bildirim ver').minutesBefore, 30);
    expect(parse('Pazartesi 18.00 maç, on beş dakika önce hatırlat').minutesBefore, 15);
  });

  test('tam saatinde ve açık saatli hatırlat', () {
    final exact = parse('Yarın 15.00 ilaç, tam saatinde hatırlat');
    expect(exact.kind, ReminderIntentKind.atTaskTime);
    expect(exact.minutesBefore, 0);

    final clock = parse("Yarın 9'da bana su içmeyi hatırlat");
    expect(clock.kind, ReminderIntentKind.atTaskTime);
    expect(clock.minutesBefore, 0);
  });

  test('belirsiz: saat yok, rastgele saat uydurulmaz', () {
    expect(parse('Yarın sabah hatırlat').kind, ReminderIntentKind.ambiguous);
    expect(parse('Haftaya bana faturayı hatırlat').kind, ReminderIntentKind.ambiguous);
  });

  test('hatırlatma istenmemişse none', () {
    expect(parse('Yarın 17.30 dişçiye git').kind, ReminderIntentKind.none);
    expect(parse('15.03.2026 tarihinde vergi').kind, ReminderIntentKind.none);
  });

  test('tarih saat gibi algılanmaz', () {
    expect(parse('15.03.2026 vergi hatırlat').kind, ReminderIntentKind.ambiguous);
  });

  test('etiket ve zaman hesabı', () {
    expect(reminderOffsetLabel(0), 'Tam saatinde');
    expect(reminderOffsetLabel(60), '1 saat önce');
    expect(reminderOffsetLabel(2880), '2 gün önce');
    expect(reminderOffsetLabel(90), '1 saat 30 dakika önce');

    final task = DateTime(2026, 10, 20, 17, 0);
    expect(reminderTimeFor(task, 60), DateTime(2026, 10, 20, 16, 0));
    expect(reminderTimeFor(task, 1440), DateTime(2026, 10, 19, 17, 0));
    expect(reminderTimeFor(task, 0), task);
  });
}
