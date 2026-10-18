// Hatırlatma ofseti = görev saatinden KAÇ DAKİKA ÖNCE bildirim gönderileceği.
// 0 = tam görev saatinde. Görev saati ile bildirim saati burada ayrı
// kavramlar olarak ele alınır.

String reminderOffsetLabel(int minutes) {
  if (minutes <= 0) return 'Tam saatinde';

  if (minutes % 1440 == 0) return '${minutes ~/ 1440} gün önce';

  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours saat önce' : '$hours saat $rest dakika önce';
  }

  return '$minutes dakika önce';
}

// Gün katı ofsetlerde takvim aritmetiği kullanılır (yaz/kış saati geçişinde
// bile bildirim aynı duvar saatine denk gelir); diğerlerinde mutlak süre.
DateTime reminderTimeFor(DateTime taskTime, int minutesBefore) {
  if (minutesBefore > 0 && minutesBefore % 1440 == 0) {
    return DateTime(
      taskTime.year,
      taskTime.month,
      taskTime.day - minutesBefore ~/ 1440,
      taskTime.hour,
      taskTime.minute,
    );
  }

  return taskTime.subtract(Duration(minutes: minutesBefore));
}

// "00:00" = saat belirlenmemiş (bkz. calendar_page.dart'taki aynı kural).
bool hasExplicitTime(DateTime dateTime) {
  return dateTime.hour != 0 || dateTime.minute != 0;
}
