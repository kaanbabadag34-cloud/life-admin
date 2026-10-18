import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/notification_service.dart';
import '../../utils/reminder_format.dart';
import '../../widgets/reminder_section.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/error_messages.dart';
import '../plans/event_service.dart';
import '../plans/plan.dart';

const List<String> _weekdayLabelsTr = [
  'Pzt',
  'Sal',
  'Çrş',
  'Prş',
  'Cum',
  'Cmt',
  'Paz',
];

const List<String> _monthNamesTr = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

// ==================== Saf yardımcı fonksiyonlar ====================
// Hiçbir State'e bağlı değiller — hem CalendarPageState hem de aşağıdaki
// bağımsız sheet widget'ları (_AddPlanSheet/_EditPlanSheet) tarafından
// ortak kullanılabilsinler diye top-level fonksiyon olarak tutuluyorlar.

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// Saat, kullanıcı tarafından hiç belirlenmemişse dateTime'ın saat/dakikası
// tam 00:00 olarak saklanır — bu, "saat opsiyonel" özelliğini (madde 5)
// Supabase şemasında/EventService'te YENİ BİR KOLON açmadan, mevcut
// `starts_at` alanını bozmadan uygulamanın güvenli yoludur. Gerçekten tam
// gece yarısına kurulan (çok nadir) bir görev de bu sezgiyle "saatsiz"
// görünür — bilinçli ve düşük riskli bir basitleştirme.
bool _hasExplicitTime(DateTime dateTime) {
  return dateTime.hour != 0 || dateTime.minute != 0;
}

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _prettyDate(DateTime date) {
  return '${date.day} ${_monthNamesTr[date.month - 1]} ${date.year}';
}

// Görüntülenen gün gerçek takvim gününe (bugüne) eşitse "Bugün" gösterir;
// aksi halde normal tarihi ("19 Eylül 2026") döner. Build her tetiklendiğinde
// (gün seçimi/swipe ile _selectedDay değiştiğinde) yeniden hesaplandığı için
// her zaman güncel kalır.
String _dayHeaderLabel(DateTime date) {
  if (_sameDay(date, DateTime.now())) {
    return 'Bugün';
  }
  return _prettyDate(date);
}

// Takvim ekranındaki tüm kısa bilgilendirme mesajları (plan eklendi/
// silindi/tamamlandı/taşındı vb.) buradan geçer. Kısa süre (hızlı
// kaybolsun) + tema zaten floating olarak ayarlı (bkz. app_theme.dart)
// — bu sayede SnackBar, sağ alttaki "+" FAB'ını ASLA yukarı itmiyor
// (Material'ın varsayılan "fixed" davranışı, aksi halde SnackBar
// görünürken FAB'ı kaydırıp geri indirir — bu, "+" butonunun
// kapanıyormuş gibi görünmesinin kök nedeniydi).
void _showCalendarSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  // Art arda hızlı işlemlerde (ör. birden fazla görevi hızlıca tamamlama)
  // eski mesajların kuyruğa dizilip üst üste/gecikmeli çakışmasını önlemek
  // için önce mevcut olanı kapat, sonra yenisini göster.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1600),
    ),
  );
}

// Görev tamamlama sesi — Flutter'ın kendi SystemSound API'si sadece
// "click"/"alert" (ve iOS'a özel "tick", bu da tekerlek seçici sesi)
// sunuyor; hiçbiri "tamamlandı" hissi vermiyor. iOS'ta ios/Runner/
// AppDelegate.swift içine eklenen küçük bir MethodChannel köprüsü
// üzerinden AudioToolbox'ın kendi kısa/yumuşak sistem seslerinden birini
// (harici bir ses dosyası GEREKTİRMEDEN) çalıyoruz. Diğer platformlarda
// (Android/masaüstü/web) veya kanal bir sebeple yanıt vermezse sessizce
// mevcut sistem click'ine düşüyor — asla hata fırlatmıyor.
const MethodChannel _taskCompletedSoundChannel = MethodChannel(
  'life_admin/sound',
);

Future<void> _playTaskCompletedSound() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      await _taskCompletedSoundChannel.invokeMethod('playTaskCompleted');
      return;
    } catch (_) {
      // Kanala ulaşılamazsa (ör. eski bir build) sessizce aşağıdaki
      // sistem sesine düş.
    }
  }
  await SystemSound.play(SystemSoundType.click);
}

// ==================== iOS-native Cupertino seçiciler ====================
// home_page.dart'ta zaten kanıtlanmış olan aynı desen (Material
// showDatePicker/showTimePicker yerine kompakt bir bottom sheet içinde
// CupertinoDatePicker) burada da kullanılıyor — dosyalar arası private
// paylaşım mümkün olmadığı için (Dart'ta private üyeler dosyaya özeldir)
// bilinçli olarak birebir kopyalandı; bu, projede zaten yerleşik bir
// kalıptır (_prettyDate gibi küçük yardımcılar da aynı şekilde dosya
// başına ayrı tutulur).
Future<bool> _showCupertinoPickerSheet(
  BuildContext context,
  Widget picker,
) async {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final sheetBg = isDark ? const Color(0xFF1D2026) : Colors.white;
      final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);

      return CupertinoTheme(
        data: CupertinoThemeData(
          brightness: theme.brightness,
          primaryColor: theme.colorScheme.primary,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Vazgeç'),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text(
                          'Tamam',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 216, child: picker),
              ],
            ),
          ),
        ),
      );
    },
  );

  return confirmed == true;
}

Future<TimeOfDay?> _showCupertinoTimePicker(
  BuildContext context,
  TimeOfDay initialTime,
) async {
  final now = DateTime.now();

  var pickedDateTime = DateTime(
    now.year,
    now.month,
    now.day,
    initialTime.hour,
    initialTime.minute,
  );

  final confirmed = await _showCupertinoPickerSheet(
    context,
    CupertinoDatePicker(
      mode: CupertinoDatePickerMode.time,
      use24hFormat: true,
      initialDateTime: pickedDateTime,
      onDateTimeChanged: (value) => pickedDateTime = value,
    ),
  );

  if (!confirmed) return null;
  return TimeOfDay(hour: pickedDateTime.hour, minute: pickedDateTime.minute);
}

Future<DateTime?> _showCupertinoDatePicker(
  BuildContext context,
  DateTime initialDate,
) async {
  var pickedDate = initialDate;

  final confirmed = await _showCupertinoPickerSheet(
    context,
    CupertinoDatePicker(
      mode: CupertinoDatePickerMode.date,
      initialDateTime: initialDate,
      minimumDate: DateTime(2020),
      maximumDate: DateTime(2035),
      onDateTimeChanged: (value) => pickedDate = value,
    ),
  );

  if (!confirmed) return null;
  return DateTime(pickedDate.year, pickedDate.month, pickedDate.day);
}

// ==================== Premium iOS-native sheet chrome ====================
// Madde 4: görev ekleme/düzenleme ekranlarındaki "Android/Material hissi"
// (floating-label TextField, SwitchListTile, FilledButton/OutlinedButton
// bloğu) tamamen kaldırılıp, iOS'un kendi "Yeni Hatırlatıcı" sayfasına
// benzeyen bir çatı ile değiştirildi: üstte Vazgeç/başlık/Kaydet çubuğu,
// altında gruplu, borderless satırlar. Bu ÇATI hem _AddPlanSheet hem de
// _EditPlanSheet tarafından ortak kullanılıyor.
Widget _iosSheetChrome(
  BuildContext context, {
  required String title,
  required String trailingLabel,
  required VoidCallback? onTrailing,
  required VoidCallback onCancel,
  required Widget body,
  bool trailingLoading = false,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final sheetBg = isDark ? const Color(0xFF1D2026) : Colors.white;
  final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);
  final handleColor = isDark
      ? const Color(0xFF3A3E46)
      : const Color(0xFFD8DADF);

  return CupertinoTheme(
    data: CupertinoThemeData(
      brightness: theme.brightness,
      primaryColor: theme.colorScheme.primary,
    ),
    child: Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border)),
              ),
              // KRİTİK: başlık önceden bir Row içinde [Vazgeç, Expanded(Text),
              // Ekle] olarak diziliydi — "Vazgeç" ve "Ekle" farklı
              // genişlikte olduğu için Expanded'ın ortalandığı alan da
              // kaydırılıyor, başlık gerçek merkeze değil o alanın
              // merkezine oturuyordu (ekran görüntüsüyle doğrulandı: metin
              // sağa kaymış görünüyordu). Stack + üç bağımsız Align ile
              // başlık artık HER ZAMAN sheet'in gerçek yatay merkezine
              // sabitleniyor, yan butonların genişliği onu etkilemiyor.
              //
              // İKİNCİ KÖK NEDEN (bu turda bulundu): CupertinoButton'ın
              // kendi minimum dokunma boyutu (kMinInteractiveDimensionCupertino
              // = 44) + varsayılan padding'i ile doğal yüksekliği zaten TAM
              // 44'e denk geliyordu; Stack'in varsayılan clipBehavior'ı
              // (hardEdge) bu sınırın en ufak taşmasında bile "Vazgeç"/
              // "Ekle" yazılarının üstünü kırpıyordu (ekran görüntüsüyle
              // doğrulandı). Yükseklik rahat bir paya çıkarıldı ve Stack
              // taşmayı SERTÇE kesmek yerine görünmez bırakacak şekilde
              // clipBehavior: Clip.none yapıldı.
              child: SizedBox(
                height: 56,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 64),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: onCancel,
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: onTrailing,
                        child: trailingLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CupertinoActivityIndicator(),
                              )
                            : Text(
                                trailingLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(child: body),
          ],
        ),
      ),
    ),
  );
}

// iOS "gruplu liste" satırı hissi veren, kenarlıksız metin girişi —
// Material'ın floating-label TextField'ı yerine.
Widget _iosField(
  BuildContext context, {
  required TextEditingController controller,
  required String placeholder,
  int minLines = 1,
  int maxLines = 1,
  TextCapitalization textCapitalization = TextCapitalization.sentences,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF23252B) : const Color(0xFFF3F4F7);
  final textColor = isDark ? Colors.white : const Color(0xFF17171A);
  final placeholderColor = isDark ? Colors.white38 : Colors.black38;

  return Container(
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: CupertinoTextField.borderless(
      controller: controller,
      placeholder: placeholder,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      style: TextStyle(
        fontSize: 16,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      placeholderStyle: TextStyle(fontSize: 16, color: placeholderColor),
      cursorColor: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.symmetric(vertical: 12),
    ),
  );
}

// Tarih/saat gibi bir değeri gösterip açan, iOS "settings" satırı.
Widget _iosRowButton(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF23252B) : const Color(0xFFF3F4F7);
  final textColor = isDark ? Colors.white : const Color(0xFF17171A);
  final muted = isDark ? const Color(0xFF6B6E76) : const Color(0xFFB0B3BA);

  return CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 15.5,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 15, color: muted),
        ],
      ),
    ),
  );
}

// Etiket + açıklama + CupertinoSwitch — Material SwitchListTile yerine.
Widget _iosToggleRow(
  BuildContext context, {
  required String label,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
  bool enabled = true,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final textColor = isDark ? Colors.white : const Color(0xFF17171A);
  final muted = isDark ? const Color(0xFFA7A9B0) : const Color(0xFF6B7280);

  return Opacity(
    opacity: enabled ? 1 : 0.5,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12.5, color: muted)),
            ],
          ),
        ),
        CupertinoSwitch(
          value: value,
          activeTrackColor: theme.colorScheme.primary,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    ),
  );
}

// Madde 3: hatırlatıcı artık saatten TAMAMEN ayrı, kendi başlığı olan bir
// bölüm — "Kapalı / 15 dk önce / 30 dk önce / 1 saat önce" tek bir
// seçenek grubu olarak sunulur (ayrı bir aç/kapa anahtarı + koşullu chip
// listesi yerine). Saat henüz seçilmediyse seçenekler pasif/soluk
// gösterilir ama bölümün kendisi HER ZAMAN görünür kalır.
Widget _iosReminderSection(
  BuildContext context, {
  required bool hasTime,
  required bool reminderEnabled,
  required int reminderMinutesBefore,
  required ValueChanged<int?> onSelect,
}) {
  return buildReminderSection(
    context,
    hasTime: hasTime,
    reminderEnabled: reminderEnabled,
    reminderMinutesBefore: reminderMinutesBefore,
    onSelect: onSelect,
  );
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  CalendarPageState createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin {
  final EventService _eventService = EventService();

  List<Plan> _plans = [];
  bool _loading = true;
  // İlk yükleme tamamlandıktan sonra artık BİR DAHA ASLA true olmuyor —
  // bkz. refreshPlans() içindeki kritik açıklama.
  bool _hasLoadedOnce = false;
  bool _isCalendarDragging = false;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  late final AnimationController _fabGlowController;

  @override
  void initState() {
    super.initState();
    _fabGlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    refreshPlans();
  }

  @override
  void dispose() {
    _fabGlowController.dispose();
    super.dispose();
  }

  // ESKİ kimlik (başlık|tarih|kategori hash'i) — yalnızca bu sürümden önce
  // kurulmuş bildirimleri iptal edebilmek için tutuluyor.
  int _legacyNotificationId(Plan plan) {
    final date = plan.dateTime?.toUtc().toIso8601String() ?? '';

    final value = '${plan.title}|$date|${plan.category.name}';

    var hash = 2166136261;

    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }

    return hash;
  }

  Future<void> _scheduleReminder(Plan plan) async {
    if (!plan.reminderEnabled ||
        plan.dateTime == null ||
        plan.reminderMinutesBefore == null) {
      return;
    }

    final scheduled = await NotificationService.instance.schedulePlanReminder(
      id: NotificationService.reminderIdFor(plan.id),
      title: plan.title,
      planDateTime: plan.dateTime!,
      minutesBefore: plan.reminderMinutesBefore!,
      planId: plan.id,
    );

    if (!scheduled &&
        mounted &&
        !await NotificationService.instance.notificationsAllowed()) {
      if (!mounted) return;
      _showCalendarSnack(
        context,
        'Bildirim izni kapalı. Hatırlatma için iPhone Ayarlar → Bildirimler '
        '→ Life Admin bölümünden izin ver.',
      );
    }
  }

  Future<void> _cancelReminder(Plan plan) async {
    final notifications = NotificationService.instance;

    await notifications.cancelReminder(
      NotificationService.reminderIdFor(plan.id),
    );

    if (plan.reminderEnabled && plan.dateTime != null) {
      await notifications.cancelReminder(_legacyNotificationId(plan));
    }
  }

  // ACİL BUG DÜZELTMESİ — KÖK NEDEN: bu metot HER çağrıldığında (yani
  // checkbox'a her basışta, çünkü _toggleCompleted sonunda refreshPlans()
  // çağırıyor) koşulsuz olarak `_loading = true` yapıyordu. build()
  // içinde `if (_loading) CircularProgressIndicator() else ...liste...`
  // olduğu için bu, görev listesini bir ağ isteği süresince (~birkaç yüz
  // ms) tek satırlık bir spinner'a küçültüyor, sonra veri gelince tekrar
  // tam listeye genişletiyordu — ListView'ın içerik yüksekliği bu kadar
  // ani değişince scroll konumu otomatik düzeltiliyor, tam olarak
  // "sayfa yukarı çıkıp geri geliyor" hissi budur. Artık spinner SADECE
  // gerçek ilk yüklemede gösteriliyor; sonraki tüm refreshPlans()
  // çağrıları (complete/delete/move/add sonrası) listeyi ESKİ haliyle
  // görünür tutarak sessizce günceller — hiçbir çökme/genişleme,
  // dolayısıyla hiçbir scroll sıçraması olmuyor.
  Future<void> refreshPlans() async {
    final isInitialLoad = !_hasLoadedOnce;

    if (mounted && isInitialLoad) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final plans = await _eventService.getPlans();

      if (!mounted) return;

      setState(() {
        // Madde 1: tamamlanan görevler artık listeden ELENMİYOR — sadece
        // tarihi olan planlar tutuluyor. Tamamlanmış/tamamlanmamış ayrımı
        // ve sıralaması _plansForDay içinde yapılıyor.
        _plans = plans.where((plan) => plan.dateTime != null).toList();

        _loading = false;
        _hasLoadedOnce = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deletePlan(Plan plan) async {
    final confirmed = await showPremiumConfirmDialog(
      context,
      title: 'Planı sil',
      message: '"${plan.title}" silinecek. Bu işlem geri alınamaz.',
    );

    if (!confirmed) return;

    try {
      await _cancelReminder(plan);

      await _eventService.deletePlan(plan.id);

      if (!mounted) return;

      Navigator.of(context).pop();

      await refreshPlans();

      if (!mounted) return;

      _showCalendarSnack(context, 'Plan silindi.');
    } catch (error) {
      if (!mounted) return;

      _showCalendarSnack(
        context,
        friendlyErrorMessage(error, 'Plan silinemedi. Tekrar deneyin.'),
      );
    }
  }

  // Madde 1: tamamlama artık GERİ ALINABİLİR bir toggle. `popSheet`:
  // checkbox doğrudan liste satırından çağrıldığında açık bir sheet
  // YOKTUR — bu durumda Navigator.pop() çağrısı yanlış rotayı (Takvim
  // sayfasının kendisini) kapatırdı. Sheet içindeki buton ise varsayılan
  // (true) davranışı kullanmaya devam eder. Tamamlanınca hatırlatıcı
  // iptal edilir; geri alınınca (hâlâ gelecekte bir saati varsa) yeniden
  // kurulur — _cancelReminder/_scheduleReminder zaten kendi güvenli
  // koşullarını (reminderEnabled/dateTime/geçmiş zaman) kontrol ediyor.
  Future<void> _toggleCompleted(Plan plan, {bool popSheet = true}) async {
    final newCompleted = !plan.isCompleted;

    if (newCompleted) {
      // Kısa, premium bir "task completed" sesi — SADECE tamamlama
      // yönünde (geri alırken hiç çalmıyor), mevcut haptic (checkbox'ın
      // onTap'inde) ile aynı anda tetiklenir ki ikisi "uyumlu" hissettirsin.
      _playTaskCompletedSound();
    }

    try {
      if (newCompleted) {
        await _cancelReminder(plan);
      }

      await _eventService.setCompleted(id: plan.id, completed: newCompleted);

      if (!newCompleted) {
        await _scheduleReminder(plan);
      }

      if (!mounted) return;

      if (popSheet) {
        Navigator.of(context).pop();
      }

      await refreshPlans();

      if (!mounted) return;

      _showCalendarSnack(
        context,
        newCompleted ? 'Plan tamamlandı.' : 'Plan geri alındı.',
      );
    } catch (error) {
      if (!mounted) return;

      _showCalendarSnack(
        context,
        friendlyErrorMessage(error, 'Plan güncellenemedi. Tekrar deneyin.'),
      );
    }
  }

  Future<void> _movePlanToDay(Plan plan, DateTime targetDay) async {
    if (plan.dateTime == null) return;

    final oldDateTime = plan.dateTime!;

    final newDateTime = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      oldDateTime.hour,
      oldDateTime.minute,
    );

    try {
      // Eski güne ait bildirimi kaldır.
      await _cancelReminder(plan);

      await _eventService.updateDateTime(id: plan.id, dateTime: newDateTime);

      // Yeni güne bildirim kur.
      final updatedPlan = Plan(
        id: plan.id,
        title: plan.title,
        dateTime: newDateTime,
        category: plan.category,
        source: plan.source,
        isCompleted: plan.isCompleted,
        reminderEnabled: plan.reminderEnabled,
        reminderMinutesBefore: plan.reminderMinutesBefore,
        note: plan.note,
        createdAt: plan.createdAt,
      );

      await _scheduleReminder(updatedPlan);

      if (!mounted) return;

      setState(() {
        _selectedDay = targetDay;
        _focusedDay = targetDay;
      });

      await refreshPlans();

      if (!mounted) return;

      _showCalendarSnack(context, '${plan.title} yeni tarihe taşındı.');
    } catch (error) {
      if (!mounted) return;

      _showCalendarSnack(
        context,
        friendlyErrorMessage(error, 'Tarih değiştirilemedi. Tekrar deneyin.'),
      );
    }
  }

  // Düzenleme sheet'inin "Kaydet" butonu tarafından çağrılır — başlık,
  // tarih, saat (opsiyonel) ve not TEK bir updatePlanSchedule çağrısıyla
  // güncellenir (bu metot zaten title/note/dateTime'ı birlikte destekliyor
  // ve `note` kolonu eksikse bile güvenli şekilde geri düşüyor). Reminder
  // yeniden kurma mantığı _changeTime/_movePlanToDay ile birebir aynı
  // kalıbı izler: önce eskisini iptal et, güncelle, sonra yenisini kur.
  Future<void> _saveEditedPlan(
    Plan original, {
    required String title,
    required DateTime dateTime,
    required String? note,
    required bool reminderEnabled,
    required int? reminderMinutesBefore,
  }) async {
    try {
      await _cancelReminder(original);

      // Hatırlatma ayarı DB'ye de yazılır (eskiden yalnızca yerel bildirim
      // kuruluyordu); bildirimi EventService de bu değerlere göre kurar.
      await _eventService.updateReminder(
        id: original.id,
        enabled: reminderEnabled,
        minutesBefore: reminderMinutesBefore,
      );

      await _eventService.updatePlanSchedule(
        id: original.id,
        dateTime: dateTime,
        note: note,
        title: title,
      );

      final updatedPlan = Plan(
        id: original.id,
        title: title,
        dateTime: dateTime,
        category: original.category,
        source: original.source,
        isCompleted: original.isCompleted,
        reminderEnabled: reminderEnabled,
        reminderMinutesBefore: reminderEnabled ? reminderMinutesBefore : null,
        note: note,
        createdAt: original.createdAt,
      );

      await _scheduleReminder(updatedPlan);

      if (!mounted) return;

      Navigator.of(context).pop();

      await refreshPlans();

      if (!mounted) return;

      _showCalendarSnack(context, 'Plan güncellendi.');
    } catch (error) {
      if (!mounted) return;

      _showCalendarSnack(
        context,
        friendlyErrorMessage(error, 'Plan güncellenemedi. Tekrar deneyin.'),
      );
    }
  }

  Future<void> _openAddPlanSheet() async {
    final result = await showModalBottomSheet<_AddPlanResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPlanSheet(
        initialDate: _selectedDay,
        eventService: _eventService,
        scheduleReminder: _scheduleReminder,
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedDay = result.date;
      _focusedDay = result.date;
    });

    await refreshPlans();

    if (!mounted) return;

    _showCalendarSnack(
      context,
      result.reminderEnabled
          ? 'Plan eklendi • ${reminderOffsetLabel(result.reminderMinutesBefore!)} hatırlatılacak.'
          : 'Plan eklendi.',
    );
  }

  void _openEditPlanSheet(Plan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPlanSheet(
        plan: plan,
        onSave:
            (title, dateTime, note, reminderEnabled, reminderMinutesBefore) {
              return _saveEditedPlan(
                plan,
                title: title,
                dateTime: dateTime,
                note: note,
                reminderEnabled: reminderEnabled,
                reminderMinutesBefore: reminderMinutesBefore,
              );
            },
        onToggleComplete: () => _toggleCompleted(plan),
        onDelete: () => _deletePlan(plan),
      ),
    );
  }

  List<Plan> _plansForDay(DateTime day) {
    final plans = _plans.where((plan) {
      final date = plan.dateTime;

      if (date == null) {
        return false;
      }

      return _sameDay(date, day);
    }).toList();

    // Madde 1: tamamlanan görevler listede KALIR ama en alta taşınır;
    // her iki grup kendi içinde saate göre sıralı.
    plans.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return a.dateTime!.compareTo(b.dateTime!);
    });

    return plans;
  }

  void _onDaySelected(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDay = day;
      _focusedDay = day;
    });
  }

  void _onSwipeWeek(int direction) {
    setState(() {
      _focusedDay = _focusedDay.add(Duration(days: 7 * direction));
    });
  }

  void _onSwipeMonth(int direction) {
    setState(() {
      _focusedDay = DateTime(
        _focusedDay.year,
        _focusedDay.month + direction,
        1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colors = theme.colorScheme;

    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;

    final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);

    final selectedPlans = _plansForDay(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Takvim',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 24,
            letterSpacing: -0.4,
          ),
        ),
      ),

      // Madde 4: sağ alttaki "+" butonuna mor/cyan, hafif nefes alan bir
      // glow — home_page.dart'taki AI hero glow ile AYNI iki renk
      // (0xFF6C7CF7 mor, 0xFF33C7E8 cyan) kullanılarak uygulama genelinde
      // görsel tutarlılık korunuyor. Sabit renk + yavaş 3sn döngü: "gamer
      // RGB" hissi vermesin diye rengarenk döngü YOK.
      floatingActionButton: AnimatedBuilder(
        animation: _fabGlowController,
        builder: (context, child) {
          final t = _fabGlowController.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C7CF7)
                      .withValues(alpha: 0.24 + 0.14 * t),
                  blurRadius: 20 + 10 * t,
                  spreadRadius: 1 + 1.5 * t,
                ),
                BoxShadow(
                  color: const Color(0xFF33C7E8)
                      .withValues(alpha: 0.16 + 0.10 * (1 - t)),
                  blurRadius: 16 + 8 * (1 - t),
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: child,
          );
        },
        child: FloatingActionButton(
          onPressed: _openAddPlanSheet,
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          child: const Icon(Icons.add_rounded),
        ),
      ),

      body: RefreshIndicator(
        onRefresh: refreshPlans,
        child: ListView(
          // Ay↔hafta genişleme/sayfa geçişi jesti sırasında bu ListView'ın
          // kendi dikey scroll'u ile çakışmasın diye (habit progress
          // bar'da daha önce kanıtlanan aynı kilit yöntemi): jest aktifken
          // scroll tamamen kilitleniyor, bitince serbest bırakılıyor.
          physics: _isCalendarDragging
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: border),
              ),
              child: _ExpandableCalendar(
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                hasPlans: (day) => _plansForDay(day).isNotEmpty,
                onDaySelected: _onDaySelected,
                onSwipeWeek: _onSwipeWeek,
                onSwipeMonth: _onSwipeMonth,
                onPlanDropped: _movePlanToDay,
                onDragActiveChanged: (active) {
                  if (!mounted || _isCalendarDragging == active) return;
                  setState(() => _isCalendarDragging = active);
                },
              ),
            ),

            const SizedBox(height: 22),

            Text(
              _dayHeaderLabel(_selectedDay),
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),

            const SizedBox(height: 16),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (selectedPlans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary.withValues(
                          alpha: isDark ? 0.18 : 0.10,
                        ),
                      ),
                      child: Icon(
                        Icons.calendar_month_rounded,
                        size: 24,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bugün için planın yok.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),

            ...selectedPlans.map(
              (plan) => Padding(
                // Kararlı key: tamamlanan bir görev listenin altına
                // taşındığında (sıralama değiştiğinde) Flutter'ın aynı
                // pozisyondaki YANLIŞ elemente yanlış widget/State'i
                // yeniden atamasını önler.
                key: ValueKey('plan-${plan.id}'),
                padding: const EdgeInsets.only(bottom: 10),
                child: LongPressDraggable<Plan>(
                  data: plan,

                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 260,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: colors.primary),
                      ),
                      child: Text(
                        plan.title,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFF4F4F6)
                              : const Color(0xFF17171A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  childWhenDragging: Opacity(
                    opacity: 0.35,
                    child: _CalendarPlanCard(
                      plan: plan,
                      onTap: () => _openEditPlanSheet(plan),
                      onToggleComplete: () =>
                          _toggleCompleted(plan, popSheet: false),
                    ),
                  ),

                  child: _CalendarPlanCard(
                    plan: plan,
                    onTap: () => _openEditPlanSheet(plan),
                    onToggleComplete: () =>
                        _toggleCompleted(plan, popSheet: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sabit 6 satırlık ay grid'i (42 gün) — bu, ayın gerçek satır sayısından
// (4-6 arası değişebilir) bilerek bağımsızlaştırılmış BİLİNÇLİ bir
// basitleştirme: hem hafta↔ay genişleme animasyonunun her ayda AYNI
// yükseklikte çalışmasını, hem de aşağıdaki yatay ay/hafta sayfa geçişinin
// (madde 1) komşu sayfalar arasında yükseklik sıçraması olmadan akıcı
// çalışmasını sağlar (Google/Apple takvimlerinde de yaygın bir yaklaşım).
class _ExpandableCalendar extends StatefulWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final bool Function(DateTime day) hasPlans;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<int> onSwipeWeek;
  final ValueChanged<int> onSwipeMonth;
  final void Function(Plan plan, DateTime day) onPlanDropped;
  final ValueChanged<bool> onDragActiveChanged;

  const _ExpandableCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.hasPlans,
    required this.onDaySelected,
    required this.onSwipeWeek,
    required this.onSwipeMonth,
    required this.onPlanDropped,
    required this.onDragActiveChanged,
  });

  @override
  State<_ExpandableCalendar> createState() => _ExpandableCalendarState();
}

class _ExpandableCalendarState extends State<_ExpandableCalendar>
    with TickerProviderStateMixin {
  static const double _rowHeight = 46;
  static const double _gridHeight = _rowHeight * 6;

  // _vController: hafta (0) <-> ay (1) genişleme ilerlemesi.
  // _hController: -1..1 arası, sayfa (hafta/ay) geçişinin canlı/animasyonlu
  // yatay ofseti. 0 = mevcut sayfa tam görünür.
  late final AnimationController _vController;
  late final AnimationController _hController;

  Offset? _downPosition;
  double _dragStartV = 0;
  double _dragStartH = 0;
  bool? _isVerticalGesture;
  VelocityTracker? _velocityTracker;

  // Her yeni dokunuşta artan bir jeton — bir önceki jestin gecikmeli
  // (whenComplete) tamamlanma callback'i, ARADA yeni bir jest başlamışsa
  // devreye girip YANLIŞ bir sayfa geçişi tetiklemesin diye kullanılır.
  int _gestureToken = 0;

  @override
  void initState() {
    super.initState();
    _vController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _hController = AnimationController(
      vsync: this,
      lowerBound: -1.0,
      upperBound: 1.0,
      value: 0.0,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    // Güvenlik ağı: widget aktif bir sürükleme sırasında ağaçtan
    // kaldırılırsa scroll kilidi sonsuza kadar açık kalmasın.
    if (_downPosition != null) {
      widget.onDragActiveChanged(false);
    }
    _vController.dispose();
    _hController.dispose();
    super.dispose();
  }

  List<List<DateTime>> _weeksFor(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final gridStart = firstOfMonth.subtract(
      Duration(days: firstOfMonth.weekday - 1),
    );

    return List.generate(
      6,
      (w) => List.generate(7, (d) => gridStart.add(Duration(days: w * 7 + d))),
    );
  }

  bool get _isMonthMode => _vController.value > 0.5;

  DateTime get _previousReferenceDay => _isMonthMode
      ? DateTime(widget.focusedDay.year, widget.focusedDay.month - 1, 1)
      : widget.focusedDay.subtract(const Duration(days: 7));

  DateTime get _nextReferenceDay => _isMonthMode
      ? DateTime(widget.focusedDay.year, widget.focusedDay.month + 1, 1)
      : widget.focusedDay.add(const Duration(days: 7));

  void _onPointerDown(PointerDownEvent event) {
    _gestureToken++;
    _downPosition = event.localPosition;
    _dragStartV = _vController.value;
    _hController.stop();
    _dragStartH = _hController.value;
    _isVerticalGesture = null;
    _velocityTracker = VelocityTracker.withKind(event.kind);
    _velocityTracker!.addPosition(event.timeStamp, event.localPosition);
    // Kilit anında, yön belli olmadan önce devreye girer — bu sayede
    // ListView'ın kendi scroll recognizer'ı, takvim alanında başlayan
    // bir dokunuşu asla önden kapamaz (habit bar'daki "sıfır slop"
    // stratejisiyle aynı mantık).
    widget.onDragActiveChanged(true);
  }

  void _onPointerMove(
    PointerMoveEvent event,
    double dragRangeV,
    double pageWidth,
  ) {
    if (_downPosition == null) return;
    _velocityTracker?.addPosition(event.timeStamp, event.localPosition);

    final dx = event.localPosition.dx - _downPosition!.dx;
    final dy = event.localPosition.dy - _downPosition!.dy;

    if (_isVerticalGesture == null) {
      if (dx.abs() < 8 && dy.abs() < 8) return;
      _isVerticalGesture = dy.abs() > dx.abs();
    }

    if (_isVerticalGesture == true && dragRangeV > 0) {
      _vController.value = (_dragStartV + dy / dragRangeV).clamp(0.0, 1.0);
    } else if (_isVerticalGesture == false && pageWidth > 0) {
      _hController.value = (_dragStartH + dx / pageWidth).clamp(-1.0, 1.0);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_downPosition == null) return;

    if (_isVerticalGesture == true) {
      final velocityY = _velocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0;

      double target;
      if (velocityY.abs() > 300) {
        target = velocityY > 0 ? 1.0 : 0.0;
      } else {
        target = _vController.value > 0.5 ? 1.0 : 0.0;
      }

      _vController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else if (_isVerticalGesture == false) {
      final velocityX = _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0;

      double target;
      if (velocityX.abs() > 300) {
        target = velocityX > 0 ? 1.0 : -1.0;
      } else if (_hController.value.abs() > 0.35) {
        target = _hController.value > 0 ? 1.0 : -1.0;
      } else {
        target = 0.0;
      }

      final isMonthMode = _isMonthMode;
      final token = _gestureToken;

      _hController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            // Bu callback tetiklendiğinde ARADA yeni bir jest başlamışsa
            // (token değişmişse) hiçbir şey yapma — aksi halde eski,
            // yarım kalmış bir animasyonun tamamlanması yanlışlıkla
            // fazladan bir sayfa geçişi tetikleyebilirdi.
            if (!mounted || token != _gestureToken) return;

            if (target == 1.0) {
              if (isMonthMode) {
                widget.onSwipeMonth(-1);
              } else {
                widget.onSwipeWeek(-1);
              }
            } else if (target == -1.0) {
              if (isMonthMode) {
                widget.onSwipeMonth(1);
              } else {
                widget.onSwipeWeek(1);
              }
            }

            if (target != 0.0) {
              _hController.value = 0.0;
            }
          });
    }

    _downPosition = null;
    _isVerticalGesture = null;
    _velocityTracker = null;
    widget.onDragActiveChanged(false);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _downPosition = null;
    _isVerticalGesture = null;
    _velocityTracker = null;
    widget.onDragActiveChanged(false);
  }

  Widget _buildCell(
    DateTime day,
    DateTime referenceDay,
    ColorScheme colors,
    bool isDark,
  ) {
    final isSelected = _sameDay(day, widget.selectedDay);
    final isToday = _sameDay(day, DateTime.now());
    final isOutside = day.month != referenceDay.month;
    final hasTasks = widget.hasPlans(day);

    final normalText = isDark
        ? const Color(0xFFF4F4F6)
        : const Color(0xFF17171A);

    final mutedText = isDark
        ? const Color(0xFF53565E)
        : const Color(0xFFC7C9CE);

    return DragTarget<Plan>(
      onAcceptWithDetails: (details) => widget.onPlanDropped(details.data, day),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        var bg = Colors.transparent;
        var textColor = isOutside ? mutedText : normalText;
        Border? border;

        if (isToday && !isSelected) {
          textColor = colors.primary;
          border = Border.all(
            color: colors.primary.withValues(alpha: 0.55),
            width: 1.4,
          );
        }

        if (isSelected) {
          bg = colors.primary;
          textColor = Colors.white;
          border = null;
        }

        if (isHovering) {
          bg = colors.primary.withValues(alpha: 0.20);
          textColor = colors.primary;
          border = Border.all(color: colors.primary, width: 2);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onDaySelected(day),
          child: SizedBox(
            height: _rowHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: border,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: isSelected || isToday
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !hasTasks
                        ? Colors.transparent
                        : isSelected
                        ? colors.primary
                        : colors.primary.withValues(
                            alpha: isOutside ? 0.35 : 0.9,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Tek bir sayfanın (hafta ya da ay grid'i) tamamı — hafta↔ay genişleme
  // için OverflowBox+Transform.translate ile "pinned" (odaklanmış) satırı
  // sabit tutan, diğer satırları küçültülmüş yükseklikte gizleyen kalıp.
  Widget _page(
    DateTime referenceDay,
    double progress,
    double height,
    ColorScheme colors,
    bool isDark,
  ) {
    final weeks = _weeksFor(referenceDay);

    var pinnedIndex = weeks.indexWhere(
      (week) => week.any((d) => _sameDay(d, referenceDay)),
    );
    if (pinnedIndex < 0) pinnedIndex = 0;

    final translateY = -pinnedIndex * _rowHeight * (1 - progress);

    return ClipRect(
      child: SizedBox(
        height: height,
        // KRİTİK: SizedBox'ın küçültülmüş height'ı doğrudan Transform
        // üzerinden Column'a sıkı (tight) constraint olarak sızardı —
        // Column'un satırları küçülmediği için bu, gerçek bir RenderFlex
        // overflow hatasına yol açardı (izole bir önizleme testiyle
        // yakalanıp düzeltildi). OverflowBox, Column'un HER ZAMAN tam
        // grid yüksekliğinde layout almasını sağlar; görsel kırpma
        // tamamen dıştaki ClipRect'e bırakılır.
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: _gridHeight,
          maxHeight: _gridHeight,
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Column(
              children: [
                for (var w = 0; w < weeks.length; w++)
                  Opacity(
                    opacity: w == pinnedIndex ? 1 : progress,
                    child: Row(
                      children: weeks[w]
                          .map(
                            (day) => Expanded(
                              child: _buildCell(
                                day,
                                referenceDay,
                                colors,
                                isDark,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    const dragRangeV = _gridHeight - _rowHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Madde 1: ay adı değişirken yumuşak bir cross-fade — ani sıçrama
        // yerine kısa, iOS-native bir geçiş hissi.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            '${_monthNamesTr[widget.focusedDay.month - 1]} ${widget.focusedDay.year}',
            key: ValueKey(
              '${widget.focusedDay.year}-${widget.focusedDay.month}',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _weekdayLabelsTr
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 2),
        LayoutBuilder(
          builder: (context, constraints) {
            final pageWidth = constraints.maxWidth;

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: (event) =>
                  _onPointerMove(event, dragRangeV, pageWidth),
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: AnimatedBuilder(
                animation: Listenable.merge([_vController, _hController]),
                builder: (context, _) {
                  final progress = _vController.value;
                  final height =
                      _rowHeight + (_gridHeight - _rowHeight) * progress;
                  final hOffset = _hController.value;

                  return ClipRect(
                    child: SizedBox(
                      width: pageWidth,
                      height: height,
                      // Aynı OverflowBox tekniği burada YATAY eksende: 3
                      // sayfa (önceki/mevcut/sonraki) yan yana her zaman
                      // tam genişliklerinde layout alır; görünen tek bir
                      // sayfa genişliği kadar alan, kırpma dıştaki
                      // ClipRect'e bırakılır.
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: pageWidth * 3,
                        maxWidth: pageWidth * 3,
                        minHeight: height,
                        maxHeight: height,
                        child: Transform.translate(
                          offset: Offset(-pageWidth + hOffset * pageWidth, 0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: pageWidth,
                                child: _page(
                                  _previousReferenceDay,
                                  progress,
                                  height,
                                  colors,
                                  isDark,
                                ),
                              ),
                              SizedBox(
                                width: pageWidth,
                                child: _page(
                                  widget.focusedDay,
                                  progress,
                                  height,
                                  colors,
                                  isDark,
                                ),
                              ),
                              SizedBox(
                                width: pageWidth,
                                child: _page(
                                  _nextReferenceDay,
                                  progress,
                                  height,
                                  colors,
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: secondaryText.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// _AddPlanSheet'in sonucu — bir plan gerçekten kaydedildiyse dönülür.
class _AddPlanResult {
  final DateTime date;
  final bool reminderEnabled;
  final int? reminderMinutesBefore;

  const _AddPlanResult({
    required this.date,
    required this.reminderEnabled,
    required this.reminderMinutesBefore,
  });
}

// Kendi kendine yeten, kendi controller yaşam döngüsünü yöneten StatefulWidget
// — daha önce bu dosyada (ve home_page.dart'ta) kırmızı/sarı Flutter
// hatalarına yol açtığı belirlenen "closure + StatefulBuilder + dışarıda
// yaşayan controller" kalıbı (madde 3) burada TAMAMEN terk edildi.
class _AddPlanSheet extends StatefulWidget {
  final DateTime initialDate;
  final EventService eventService;
  final Future<void> Function(Plan) scheduleReminder;

  const _AddPlanSheet({
    required this.initialDate,
    required this.eventService,
    required this.scheduleReminder,
  });

  @override
  State<_AddPlanSheet> createState() => _AddPlanSheetState();
}

class _AddPlanSheetState extends State<_AddPlanSheet> {
  late final TextEditingController _titleController;
  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  bool _reminderEnabled = false;
  int _reminderMinutesBefore = 15;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _selectedDate = widget.initialDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) return;

    setState(() => _saving = true);

    // Madde 5: saat opsiyonel — kullanıcı seçmediyse 00:00 (saat yok
    // sentineli) olarak saklanır, Plan.dateTime null'a düşürülmez (aksi
    // halde görev hiçbir günün altında görünmezdi).
    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime?.hour ?? 0,
      _selectedTime?.minute ?? 0,
    );

    final reminderEnabled = _selectedTime != null && _reminderEnabled;

    final plan = Plan(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      dateTime: dateTime,
      // Madde 2: kategori seçimi kullanıcıya gösterilmiyor — model/backend
      // alanı bozulmasın diye sabit bir varsayımla (Görev) dolduruluyor.
      category: PlanCategory.task,
      source: PlanSource.manual,
      isCompleted: false,
      reminderEnabled: reminderEnabled,
      reminderMinutesBefore: reminderEnabled ? _reminderMinutesBefore : null,
      createdAt: DateTime.now(),
    );

    try {
      final insertedId = await widget.eventService.addPlan(plan);

      // Bildirim, DB kimliğiyle (EventService'in kurduğuyla AYNI kimlik)
      // yeniden kurulur: yerel geçici kimlikle kurulsaydı çift bildirim olurdu.
      if (insertedId != null) {
        await widget.scheduleReminder(
          Plan(
            id: insertedId,
            title: plan.title,
            dateTime: plan.dateTime,
            category: plan.category,
            source: plan.source,
            isCompleted: plan.isCompleted,
            reminderEnabled: plan.reminderEnabled,
            reminderMinutesBefore: plan.reminderMinutesBefore,
            note: plan.note,
            createdAt: plan.createdAt,
          ),
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(
        _AddPlanResult(
          date: _selectedDate,
          reminderEnabled: reminderEnabled,
          reminderMinutesBefore: plan.reminderMinutesBefore,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() => _saving = false);

      _showCalendarSnack(
        context,
        friendlyErrorMessage(error, 'Plan eklenemedi. Tekrar deneyin.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _iosSheetChrome(
      context,
      title: 'Yeni Plan',
      trailingLabel: 'Ekle',
      trailingLoading: _saving,
      onTrailing: _saving ? null : _save,
      onCancel: () => Navigator.of(context).pop(),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _iosField(
                context,
                controller: _titleController,
                placeholder: 'Ne yapmak istersiniz?',
              ),

              const SizedBox(height: 10),

              _iosRowButton(
                context,
                icon: CupertinoIcons.calendar,
                label: _prettyDate(_selectedDate),
                onTap: () async {
                  final picked = await _showCupertinoDatePicker(
                    context,
                    _selectedDate,
                  );
                  if (picked == null) return;
                  setState(() => _selectedDate = picked);
                },
              ),

              const SizedBox(height: 10),

              // Madde 3: saat alanı SADECE görev saatini ayarlar — hatırlatıcı
              // ile hiçbir otomatik bağı yok.
              _iosToggleRow(
                context,
                label: 'Saat belirle',
                subtitle: _selectedTime == null
                    ? 'Saat belirtilmedi'
                    : _formatTimeOfDay(_selectedTime!),
                value: _selectedTime != null,
                onChanged: (value) {
                  setState(() {
                    _selectedTime = value ? TimeOfDay.now() : null;
                    if (!value) _reminderEnabled = false;
                  });
                },
              ),
              if (_selectedTime != null) ...[
                const SizedBox(height: 10),
                _iosRowButton(
                  context,
                  icon: CupertinoIcons.clock,
                  label: _formatTimeOfDay(_selectedTime!),
                  onTap: () async {
                    final picked = await _showCupertinoTimePicker(
                      context,
                      _selectedTime!,
                    );
                    if (picked == null) return;
                    setState(() => _selectedTime = picked);
                  },
                ),
              ],

              const SizedBox(height: 18),

              _iosReminderSection(
                context,
                hasTime: _selectedTime != null,
                reminderEnabled: _reminderEnabled,
                reminderMinutesBefore: _reminderMinutesBefore,
                onSelect: (minutes) {
                  setState(() {
                    if (minutes == null) {
                      _reminderEnabled = false;
                    } else {
                      _reminderEnabled = true;
                      _reminderMinutesBefore = minutes;
                    }
                  });
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// Madde 6: bir göreve basınca açılan, mevcut mantığı (updatePlanSchedule +
// reminder yeniden kurma) kullanan kapsamlı düzenleme ekranı — başlık,
// tarih, saat (opsiyonel, kaldırılabilir) ve not birlikte değiştirilebilir.
class _EditPlanSheet extends StatefulWidget {
  final Plan plan;
  final Future<void> Function(
    String title,
    DateTime dateTime,
    String? note,
    bool reminderEnabled,
    int? reminderMinutesBefore,
  )
  onSave;
  final VoidCallback onToggleComplete;
  final VoidCallback onDelete;

  const _EditPlanSheet({
    required this.plan,
    required this.onSave,
    required this.onToggleComplete,
    required this.onDelete,
  });

  @override
  State<_EditPlanSheet> createState() => _EditPlanSheetState();
}

class _EditPlanSheetState extends State<_EditPlanSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  bool _reminderEnabled = false;
  int _reminderMinutesBefore = 15;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;

    _titleController = TextEditingController(text: plan.title);
    _noteController = TextEditingController(text: plan.note ?? '');

    final dt = plan.dateTime ?? DateTime.now();
    _selectedDate = DateTime(dt.year, dt.month, dt.day);
    _selectedTime = plan.dateTime != null && _hasExplicitTime(plan.dateTime!)
        ? TimeOfDay(hour: dt.hour, minute: dt.minute)
        : null;

    _reminderEnabled = plan.reminderEnabled;
    _reminderMinutesBefore = plan.reminderMinutesBefore ?? 15;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) return;

    setState(() => _saving = true);

    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime?.hour ?? 0,
      _selectedTime?.minute ?? 0,
    );

    final note = _noteController.text.trim();
    final reminderEnabled = _selectedTime != null && _reminderEnabled;

    await widget.onSave(
      title,
      dateTime,
      note.isEmpty ? null : note,
      reminderEnabled,
      reminderEnabled ? _reminderMinutesBefore : null,
    );

    // Başarılıysa üst katman zaten sheet'i kapatır (Navigator.pop); hata
    // durumunda sheet açık kalır ve butonun tekrar aktif olması gerekir.
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDone = widget.plan.isCompleted;

    return _iosSheetChrome(
      context,
      title: 'Planı Düzenle',
      trailingLabel: 'Kaydet',
      trailingLoading: _saving,
      onTrailing: _saving ? null : _save,
      onCancel: () => Navigator.of(context).pop(),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _iosField(
                context,
                controller: _titleController,
                placeholder: 'Başlık',
              ),

              const SizedBox(height: 10),

              _iosRowButton(
                context,
                icon: CupertinoIcons.calendar,
                label: _prettyDate(_selectedDate),
                onTap: () async {
                  final picked = await _showCupertinoDatePicker(
                    context,
                    _selectedDate,
                  );
                  if (picked == null) return;
                  setState(() => _selectedDate = picked);
                },
              ),

              const SizedBox(height: 10),

              // Madde 3: saat alanı SADECE görev saatini ayarlar — hatırlatıcı
              // ile hiçbir otomatik bağı yok.
              _iosToggleRow(
                context,
                label: 'Saat belirle',
                subtitle: _selectedTime == null
                    ? 'Saat belirtilmedi'
                    : _formatTimeOfDay(_selectedTime!),
                value: _selectedTime != null,
                onChanged: (value) {
                  setState(() {
                    _selectedTime = value ? TimeOfDay.now() : null;
                    if (!value) _reminderEnabled = false;
                  });
                },
              ),
              if (_selectedTime != null) ...[
                const SizedBox(height: 10),
                _iosRowButton(
                  context,
                  icon: CupertinoIcons.clock,
                  label: _formatTimeOfDay(_selectedTime!),
                  onTap: () async {
                    final picked = await _showCupertinoTimePicker(
                      context,
                      _selectedTime!,
                    );
                    if (picked == null) return;
                    setState(() => _selectedTime = picked);
                  },
                ),
              ],

              const SizedBox(height: 10),

              _iosField(
                context,
                controller: _noteController,
                placeholder: 'Not (opsiyonel)',
                minLines: 2,
                maxLines: 4,
              ),

              const SizedBox(height: 18),

              _iosReminderSection(
                context,
                hasTime: _selectedTime != null,
                reminderEnabled: _reminderEnabled,
                reminderMinutesBefore: _reminderMinutesBefore,
                onSelect: (minutes) {
                  setState(() {
                    if (minutes == null) {
                      _reminderEnabled = false;
                    } else {
                      _reminderEnabled = true;
                      _reminderMinutesBefore = minutes;
                    }
                  });
                },
              ),

              const SizedBox(height: 22),

              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.onToggleComplete,
                child: Row(
                  children: [
                    Icon(
                      isDone
                          ? CupertinoIcons.arrow_uturn_left_circle
                          : CupertinoIcons.checkmark_circle,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isDone ? 'Geri Al' : 'Tamamlandı',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.onDelete,
                child: Row(
                  children: [
                    Icon(CupertinoIcons.trash, size: 19, color: colors.error),
                    const SizedBox(width: 10),
                    Text(
                      'Sil',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: colors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Madde 7: sol tarafta tamamlama checkbox'ı; madde 8: saat belirtilmeyen
// görevlerde alt satırın layout'u bozulmasın diye zaman etiketi null ise
// ayraç ("•") hiç eklenmiyor. Madde 9: daha rafine kart (yumuşak border,
// SF Pro tabanlı tipografi zaten temadan geliyor).
class _CalendarPlanCard extends StatelessWidget {
  final Plan plan;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;

  const _CalendarPlanCard({
    required this.plan,
    required this.onTap,
    required this.onToggleComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colors = theme.colorScheme;

    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;

    final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);

    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    final isDone = plan.isCompleted;

    // Saat yalnızca kullanıcı belirlediyse (00:00 = "saatsiz") gösterilir;
    // AI ve manuel görevler aynı alanı (dateTime) kullandığı için aynı çalışır.
    final planDateTime = plan.dateTime;
    final timeLabel = planDateTime != null && _hasExplicitTime(planDateTime)
        ? _formatTimeOfDay(
            TimeOfDay(hour: planDateTime.hour, minute: planDateTime.minute),
          )
        : null;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onToggleComplete();
                },
                // To-do uygulamalarındaki sade, KARE checkbox — önceki
                // yuvarlak/dairesel tasarım yerine; çok az corner radius
                // ile belirgin şekilde köşeli kalıyor.
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(4),
                    color: isDone ? colors.primary : Colors.transparent,
                    border: Border.all(
                      color: isDone
                          ? colors.primary
                          : colors.primary.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isDone
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: secondaryText,
                        color: isDone ? secondaryText : null,
                      ),
                    ),

                    if (!isDone &&
                        plan.reminderEnabled &&
                        plan.reminderMinutesBefore != null) ...[
                      const SizedBox(height: 4),

                      Row(
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 13,
                            color: colors.primary,
                          ),

                          const SizedBox(width: 4),

                          Text(
                            reminderOffsetLabel(plan.reminderMinutesBefore!),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              if (timeLabel != null) ...[
                const SizedBox(width: 10),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isDone
                        ? secondaryText.withValues(alpha: 0.6)
                        : secondaryText,
                  ),
                ),
              ],

              const SizedBox(width: 4),

              Icon(Icons.chevron_right_rounded, color: secondaryText, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
