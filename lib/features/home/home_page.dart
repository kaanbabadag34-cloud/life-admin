import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/confirm_dialog.dart';
import '../../utils/error_messages.dart';
import '../plans/event_service.dart';
import '../plans/plan.dart';
import '../profile/premium_page.dart';

enum _HabitType { tap, quantity, duration, count }

class _Habit {
  String id;
  String name;
  String emoji;
  final _HabitType type;
  double target;
  double current;
  String? unit;
  double step;
  bool done = false;

  _Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.type,
    required this.target,
    required this.current,
    this.unit,
    required this.step,
  });
}

const List<Map<String, String>> _habitPresets = [
  {'name': 'Su iç', 'emoji': '💧'},
  {'name': 'Yürüyüş', 'emoji': '🏃'},
  {'name': 'Kitap oku', 'emoji': '📚'},
  {'name': 'Ders çalış', 'emoji': '📖'},
  {'name': 'Dil çalış', 'emoji': '🌐'},
  {'name': 'Meditasyon', 'emoji': '🧘'},
  {'name': 'Erken uyan', 'emoji': '🌅'},
  {'name': 'Sağlıklı kahvaltı', 'emoji': '🥣'},
  {'name': 'Spor', 'emoji': '🏋️'},
  {'name': 'Vitamin al', 'emoji': '💊'},
];

// Özel alışkanlık oluştururken/düzenlerken kullanıcının gerçekten seçtiği
// emoji listesi. Kullanıcı seçim yapmazsa ilk eleman (⭐) varsayılan olarak
// kalır — sistem kendiliğinden farklı bir emoji atamaz.
const List<String> _habitEmojiOptions = [
  '⭐', '💧', '🏃', '🚶', '🧘', '💊', '📚', '📖', '🌐', '🥗',
  '🍎', '🥤', '☕', '🛌', '🌅', '🌙', '🧹', '🧺', '🪥', '🚿',
  '🏋️', '🚴', '🏊', '🎯', '📝', '💰', '🎨', '🎧', '❤️', '🙏',
];

const List<String> _monthNamesTr = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

String _prettyDateTr(DateTime date) =>
    '${date.day} ${_monthNamesTr[date.month - 1]} ${date.year}';

String _formatTimeOfDayTr(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

// iOS-native saat seçici (Material saat dialogu yerine). Bottom sheet
// içinde kompakt bir CupertinoDatePicker (wheel) gösterir. CupertinoTheme
// burada elle uygulamanın KENDİ light/dark tema seçimiyle kuruluyor —
// aksi halde cihazın ham sistem parlaklığını kullanır ve uygulama içi
// tema seçimiyle uyuşmayabilir.
// Saat ve tarih seçiciler için ortak iOS-native bottom sheet çatısı
// (Vazgeç/Tamam üst çubuğu + kompakt wheel picker alanı). CupertinoTheme
// burada elle uygulamanın KENDİ light/dark tema seçimiyle kuruluyor —
// aksi halde cihazın ham sistem parlaklığını kullanır ve uygulama içi
// tema seçimiyle uyuşmayabilir. Material takvim/saat dialogu yerine.
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
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
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

// Alışkanlık sayısal alanları için sabit min/max/artış değerleri — Slider/
// divisions temelli eski yaklaşım belirli kombinasyonlarda geçersiz
// aralıklara yol açıp çöküyordu. Basit +/- stepper'lar bu risk sınıfını
// tamamen ortadan kaldırır. "Adım miktarı" artık kullanıcıya gösterilmiyor;
// her tip için sabit, dahili bir artış değeri kullanılır.
({double min, double max, double increment}) _habitTargetBounds(
  _HabitType type,
) {
  switch (type) {
    case _HabitType.duration:
      return (min: 5, max: 300, increment: 5);
    case _HabitType.quantity:
      return (min: 0.25, max: 20, increment: 0.25);
    case _HabitType.count:
      return (min: 1, max: 100, increment: 1);
    case _HabitType.tap:
      return (min: 0, max: 0, increment: 0);
  }
}

String _formatHabitNumber(_HabitType type, double value) {
  if (type == _HabitType.quantity) {
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0$'), '')
        .replaceFirst(RegExp(r'\.$'), '.0');
  }
  return value.round().toString();
}

String _habitTargetLabel(_Habit habit, double current) {
  if (habit.type == _HabitType.quantity) {
    final currentLabel = current
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0$'), '')
        .replaceFirst(RegExp(r'\.$'), '.0');
    return '$currentLabel / ${habit.target.toStringAsFixed(1)} ${habit.unit}';
  }
  return '${current.round()} / ${habit.target.round()} ${habit.unit}';
}

Widget _buildStepperRow({
  required String label,
  required String valueLabel,
  required VoidCallback onDecrement,
  required VoidCallback onIncrement,
  required Color border,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onDecrement,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  valueLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: onIncrement,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildEmojiGrid({
  required BuildContext context,
  required String selected,
  required ValueChanged<String> onSelect,
}) {
  final primary = Theme.of(context).colorScheme.primary;

  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _habitEmojiOptions.map((emoji) {
      final isSelected = emoji == selected;
      return GestureDetector(
        onTap: () => onSelect(emoji),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? primary.withValues(alpha: 0.16) : Colors.transparent,
            border: Border.all(
              color: isSelected ? primary : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      );
    }).toList(),
  );
}

// Görev silme onayı, sheet kapandıktan SONRA (parent'ın kendi, her zaman
// geçerli context'i ile) gösterilmesi için sheet bu sentinel'i pop eder —
// silme işlemini sheet'in kendi (geçici) context'i üzerinden yapmaktan
// kaçınır.
class _TaskDeleteRequested {
  const _TaskDeleteRequested();
}

const _taskDeleteRequested = _TaskDeleteRequested();

// Alışkanlık düzenleme sheet'inin sonucu — kaydetme ve silme isteğini ayrı
// ayrı taşır. Silme de aynı nedenle (bkz. yukarısı) sheet kapandıktan sonra
// parent'ta onaylanıp uygulanır.
class _HabitEditResult {
  final bool delete;
  final String? name;
  final String? emoji;
  final double? target;
  final String? unit;

  const _HabitEditResult.save({
    required this.name,
    required this.emoji,
    this.target,
    this.unit,
  }) : delete = false;

  const _HabitEditResult.deleteRequested()
      : delete = true,
        name = null,
        emoji = null,
        target = null,
        unit = null;
}

class HomePage extends StatefulWidget {
  final Future<void> Function()? onAiUsageChanged;

  const HomePage({
    super.key,
    this.onAiUsageChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final EventService _eventService = EventService();
  // AI hero'nun etrafındaki ambient glow'a hafif bir "nefes alma" hareketi
  // vermek için — sadece bu küçük AnimatedBuilder alt ağacı tick başına
  // yeniden çiziliyor, tüm sayfa değil.
  late final AnimationController _glowController;

  List<Plan> _plans = [];
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  bool _aiUsageLoading = true;
  int _aiUsage = 0;
  bool _isPremium = false;
  // "profiles" tablosundan gelen ham satır — greeting'teki gerçek kullanıcı
  // adını (varsa) buradan okumak için tutulur.
  Map<String, dynamic>? _profile;
  // Bir habit slider'ı gerçekten yatay sürüklenirken true — ana ListView'ın
  // scroll'unu kilitlemek için kullanılır (sürükleme bitince geri açılır).
  bool _isHabitDragging = false;

  int get _aiLimit => _isPremium ? 300 : 20;

  // Alışkanlıklar bu iterasyonda sadece UI + local state — Supabase'e
  // bağlanmıyor, uygulama yeniden başlatıldığında sıfırlanır.
  final List<_Habit> _habits = [
    _Habit(
      id: 'water',
      name: 'Su iç',
      emoji: '💧',
      type: _HabitType.quantity,
      target: 3.0,
      current: 1.75,
      unit: 'L',
      step: 0.25,
    ),
    _Habit(
      id: 'read',
      name: 'Kitap oku',
      emoji: '📚',
      type: _HabitType.duration,
      target: 30,
      current: 20,
      unit: 'Sf',
      step: 5,
    ),
    _Habit(
      id: 'meditate',
      name: 'Meditasyon',
      emoji: '🧘',
      type: _HabitType.tap,
      target: 1,
      current: 0,
      step: 1,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _loadPlans();
    _loadAiUsage();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await _eventService.getPlans();

      if (!mounted) return;

      setState(() {
        _plans = plans;
        _loading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = friendlyErrorMessage(
          error,
          'Planlar yüklenemedi. Aşağı çekerek tekrar deneyebilirsin.',
        );
      });
    }
  }

  Future<void> _loadAiUsage() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => _aiUsageLoading = false);
      return;
    }

    try {
      // "*" ile seçiyoruz ki profiles tablosunda hangi kolonlar olursa
      // olsun (ör. bir isim kolonu) sorgu asla "kolon bulunamadı" hatasıyla
      // çökmesin — var olan her şeyi güvenle alıp greeting'te (varsa)
      // kullanabiliyoruz.
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      setState(() {
        _isPremium = profile['plan']?.toString() == 'premium';
        _aiUsage = (profile['ai_usage'] as num?)?.toInt() ?? 0;
        _profile = Map<String, dynamic>.from(profile);
        _aiUsageLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiUsageLoading = false);
    }
  }

  Future<void> _addPlan() async {
    final text = _controller.text.trim();

    if (text.isEmpty || _saving) return;

    // Gönderim tetiklenir tetiklenmez klavye kapanır ve odak input'tan
    // ayrılır — AI isteği/loading akışı klavye kapalıyken devam eder.
    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'parse-plan',
        body: {'text': text},
      );

      if (response.data == null) {
        throw Exception('AI servisi boş cevap verdi.');
      }

      final responseData = Map<String, dynamic>.from(
        response.data as Map,
      );

      if (responseData['success'] != true) {
        throw Exception(
          responseData['error'] ?? 'Plan analiz edilemedi.',
        );
      }

      final rawPlan = responseData['plan'];

      if (rawPlan is! Map) {
        throw Exception('AI geçersiz plan verisi döndürdü.');
      }

      final planData = Map<String, dynamic>.from(rawPlan);

      final String title =
          planData['title']?.toString().trim().isNotEmpty == true
              ? planData['title'].toString().trim()
              : text;

      final String eventType =
          planData['event_type']?.toString() ?? 'task';

      final dynamic startsAtRaw = planData['starts_at'];

      DateTime? startsAt;

      if (startsAtRaw != null &&
          startsAtRaw.toString().trim().isNotEmpty) {
        startsAt = DateTime.parse(
          startsAtRaw.toString(),
        ).toLocal();
      }

      final parsedPlan = Plan(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        dateTime: startsAt,
        category: PlanCategory.values.firstWhere(
          (category) => category.name == eventType,
          orElse: () => PlanCategory.task,
        ),
        source: PlanSource.ai,
        isCompleted: false,
        reminderEnabled: false,
        createdAt: DateTime.now(),
      );

      await _eventService.addPlan(parsedPlan);

      if (widget.onAiUsageChanged != null) {
        await widget.onAiUsageChanged!();
      }

      await _loadAiUsage();

      _controller.clear();
      await _loadPlans();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = friendlyErrorMessage(
          error,
          'Plan oluşturulamadı. Lütfen tekrar deneyin.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // Yanlışlıkla veri kaybını önlemek için kritik silme işlemlerinden önce
  // onay ister (Apple tarzı premium confirmation — bkz. utils/confirm_dialog.dart).
  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showPremiumConfirmDialog(
      context,
      title: title,
      message: message,
    );
  }

  // Bugün kartındaki checkbox'tan doğrudan iki yönlü tamamlama/geri alma.
  Future<void> _toggleTodayCheckbox(Plan plan) async {
    try {
      await _eventService.setCompleted(
        id: plan.id,
        completed: !plan.isCompleted,
      );

      if (!mounted) return;
      await _loadPlans();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Plan güncellenemedi. Tekrar deneyin.',
            ),
          ),
        ),
      );
    }
  }

  // Sheet kendi lifecycle'ını (controller/context) tamamen kendi yönetir;
  // burada sadece sonucu (değişti mi / silme istendi mi) uyguluyoruz. Silme
  // onayı ve gerçek silme işlemi BİLEREK burada, sheet tamamen kapandıktan
  // SONRA yapılıyor — sheet'in kendi (geçici) context'i üzerinden async bir
  // işlem yapıp ardından tekrar o context'i kullanmak eski kod tabanında
  // lifecycle hatalarının kök nedeniydi.
  Future<void> _showPlanDetails(Plan plan) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TaskDetailSheet(plan: plan, eventService: _eventService),
    );

    if (!mounted) return;

    if (result is _TaskDeleteRequested) {
      final confirmed = await _confirmDelete(
        title: 'Planı sil',
        message: '"${plan.title}" silinecek. Bu işlem geri alınamaz.',
      );

      if (!confirmed || !mounted) return;

      try {
        await _eventService.deletePlan(plan.id);

        if (!mounted) return;
        HapticFeedback.mediumImpact();
        await _loadPlans();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan silindi.')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(error, 'Plan silinemedi. Tekrar deneyin.'),
            ),
          ),
        );
      }
      return;
    }

    if (result == true) {
      await _loadPlans();
    }
  }

  Future<void> _showQuickAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickAddTaskSheet(eventService: _eventService),
    );

    if (!mounted) return;

    // Sheet'in kendi TextField'ı kapanırken unfocus edilse bile, Flutter
    // sheet route'u pop olunca Home'da önceden odaklı olan alanın (ör. AI
    // input) focus'unu otomatik geri yükleyebiliyor — bu da Ana Sayfa'ya
    // dönünce klavyenin tekrar açılmasına yol açıyordu. Home'a döndükten
    // sonra burada da açıkça unfocus ediyoruz.
    FocusScope.of(context).unfocus();

    if (added == true) {
      await _loadPlans();
    }
  }

  // ==================== Alışkanlıklar (yalnızca local state) ====================

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _habitsSummaryText() {
    final total = _habits.length;
    final done = _habits.where((h) => h.done).length;

    if (done == 0) return 'Bugün henüz alışkanlık tamamlanmadı.';
    if (total == 1 && done == 1) return 'Alışkanlık tamamlandı.';
    if (done == total) return 'Bugünkü alışkanlıklar tamamlandı.';
    return 'Bugün $done alışkanlık tamamlandı.';
  }

  // Tamamlanmamış alışkanlıklar her zaman önce, tamamlananlar en altta.
  // `.where().toList()` kaynak sırayı KORUDUĞU için (Dart'ın `List.sort`'unun
  // aksine, ki o stabil olduğu garanti değildir) her grup kendi içinde
  // stabil kalır — rastgele yer değiştirme olmaz.
  List<_Habit> get _orderedHabits {
    final incomplete = _habits.where((h) => !h.done).toList();
    final complete = _habits.where((h) => h.done).toList();
    return [...incomplete, ...complete];
  }

  // AnimatedSwitcher'ı tetiklemek için sıra + tamamlanma durumunun imzası —
  // bu değiştiğinde (bir habit tamamlanıp gruplar arası taşındığında) liste
  // yumuşak bir cross-fade ile yeniden düzenlenir.
  String get _habitsOrderSignature =>
      _orderedHabits.map((h) => '${h.id}:${h.done}').join(',');

  void _openHabitActionSheet(_Habit habit) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Text(
                      '${habit.emoji} ${habit.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _MenuTile(
                  icon: Icons.edit_outlined,
                  title: 'Düzenle',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openHabitEditSheet(habit);
                  },
                ),
                _MenuTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Alışkanlığı sil',
                  onTap: () async {
                    Navigator.pop(sheetContext);

                    final confirmed = await _confirmDelete(
                      title: 'Alışkanlığı sil',
                      message:
                          '"${habit.name}" alışkanlığı silinecek. Bu işlem geri alınamaz.',
                    );

                    if (!confirmed || !mounted) return;

                    setState(() {
                      _habits.removeWhere((h) => h.id == habit.id);
                    });
                    _showSnack('Alışkanlık silindi.');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Alışkanlık düzenleme sheet'i kendi lifecycle'ını tam olarak yönetir
  // (controller/context oluşturma-dispose etme, sayısal alan sınırları hep
  // widget'ın kendi State'inde). Burada sadece sonucu (kaydet/sil) tek bir
  // setState ile — sheet TAMAMEN kapandıktan sonra — uyguluyoruz.
  Future<void> _openHabitEditSheet(_Habit habit) async {
    final result = await showModalBottomSheet<_HabitEditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditHabitSheet(habit: habit),
    );

    if (result == null || !mounted) return;

    if (result.delete) {
      final confirmed = await _confirmDelete(
        title: 'Alışkanlığı sil',
        message:
            '"${habit.name}" alışkanlığı silinecek. Bu işlem geri alınamaz.',
      );

      if (!confirmed || !mounted) return;

      setState(() {
        _habits.removeWhere((h) => h.id == habit.id);
      });
      _showSnack('Alışkanlık silindi.');
      return;
    }

    setState(() {
      habit.name = result.name!;
      habit.emoji = result.emoji!;

      if (result.target != null) {
        habit.target = result.target!;
        if (habit.current > habit.target) {
          habit.current = habit.target;
        }
        habit.done = habit.target > 0 && habit.current >= habit.target;
      }

      if (result.unit != null) {
        habit.unit = result.unit;
      }
    });
  }

  // Alışkanlık ekleme sheet'i de tamamen kendi kendine yeten bir
  // StatefulWidget — sonucu (yeni habit ya da null) burada TEK bir setState
  // ile uyguluyoruz.
  Future<void> _openAddHabitSheet() async {
    final newHabit = await showModalBottomSheet<_Habit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddHabitSheet(),
    );

    if (newHabit == null || !mounted) return;

    setState(() => _habits.add(newHabit));
    _showSnack('Alışkanlık eklendi.');
  }

  Widget _buildHabitRow(_Habit habit) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);
    final iconBg = isDark ? const Color(0xFF23252B) : const Color(0xFFF3F4F7);

    final leadingIcon = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: habit.done
            ? colors.primary.withValues(alpha: 0.16)
            : iconBg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(habit.emoji, style: const TextStyle(fontSize: 15)),
    );

    final moreButton = IconButton(
      icon: const Icon(Icons.more_horiz_rounded),
      color: secondaryText,
      onPressed: () => _openHabitActionSheet(habit),
    );

    if (habit.type == _HabitType.tap) {
      return InkWell(
        key: ValueKey('habit-${habit.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => habit.done = !habit.done);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              leadingIcon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  habit.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: habit.done ? secondaryText : null,
                  ),
                ),
              ),
              if (habit.done)
                Icon(
                  Icons.check_circle_rounded,
                  color: colors.primary,
                  size: 20,
                ),
              moreButton,
            ],
          ),
        ),
      );
    }

    return Padding(
      // Kararlı key: liste eleman eklenip/çıkarıldığında Flutter'ın yanlış
      // elemente yanlış RenderObject/State atamasını (drag sırasında
      // "hit test edilemeyen render box" sınıfı hatalar) önler.
      key: ValueKey('habit-${habit.id}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      // Başlık/etiket + track tek bir _HabitCard'a taşındı: sürükleme
      // sırasında "1.25 / 3.0 L" gibi canlı güncellenen etiket, SADECE bu
      // küçük kartın kendi State'ini günceller — _HomePageState'i (ve
      // dolayısıyla tüm Home ağacını) her drag karesinde tekrar inşa etmez.
      // Kalıcı commit (Supabase'e yansıyan `habit.current`/`habit.done`)
      // yine sadece sürükleme bitince, tek bir `onCommit` ile yapılır.
      child: _HabitCard(
        key: ValueKey('habit-card-${habit.id}'),
        habit: habit,
        onOpenEdit: () => _openHabitEditSheet(habit),
        onOpenActions: () => _openHabitActionSheet(habit),
        onCommit: (current, done) {
          setState(() {
            habit.current = current;
            habit.done = done;
          });
        },
        onDragActiveChanged: (active) {
          if (!mounted || _isHabitDragging == active) return;
          setState(() => _isHabitDragging = active);
        },
      ),
    );
  }

  // ==================== Plan yardımcıları ====================

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<Plan> get _todayPlans {
    final now = DateTime.now();

    final plans = _plans
        .where(
          (plan) => plan.dateTime != null && _isSameDay(plan.dateTime!, now),
        )
        .toList();

    plans.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return a.dateTime!.compareTo(b.dateTime!);
    });

    return plans;
  }

  List<Plan> get _laterPlans {
    return _plans
        .where((plan) => plan.dateTime == null && !plan.isCompleted)
        .toList();
  }

  String _greetingBase() {
    final hour = DateTime.now().hour;

    if (hour >= 5 && hour < 11) return 'Günaydın';
    if (hour >= 11 && hour < 18) return 'Tünaydın';
    if (hour >= 18 && hour < 23) return 'İyi akşamlar';
    return 'İyi geceler';
  }

  // Ekran okuyucular için düz metin karşılığı — görsel Text.rich (iki renkli
  // isim) burayı kullanır.
  String _greetingText() {
    final name = _userFirstName();
    return name == null ? '${_greetingBase()}.' : '${_greetingBase()}, $name.';
  }

  // İsim varsa temanın accent rengiyle ve hafif bir glow ile öne çıkarılır
  // — abartısız, premium bir vurgu (light/dark'a göre glow şiddeti ayrı
  // ayarlanır). İsim yoksa düz tek renkli metne düşer.
  Widget _buildGreeting(ThemeData theme, ColorScheme colors, bool isDark) {
    final userName = _userFirstName();
    final baseStyle = theme.textTheme.headlineLarge?.copyWith(
      fontSize: 23,
      fontWeight: FontWeight.w700,
    );

    if (userName == null) {
      return Text(
        '${_greetingBase()}.',
        style: baseStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );
    }

    // maxLines/overflow/softWrap BİLEREK eklendi: isim uzun olduğunda veya
    // ekran dar olduğunda satır sarabiliyor, bu da ismin görsel olarak
    // "aşağı" bir satıra düşmüş gibi görünmesine yol açıyordu. Artık
    // greeting HER ZAMAN tek satırda kalıyor, konumu değişmiyor.
    return Semantics(
      label: _greetingText(),
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              TextSpan(text: '${_greetingBase()}, '),
              TextSpan(
                text: '$userName.',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(
                      color: colors.primary.withValues(
                        alpha: isDark ? 0.55 : 0.28,
                      ),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
  }

  String? _userFirstName() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    final metadata = user.userMetadata;
    final profile = _profile;

    // Önce "profiles" tablosundaki (varsa) gerçek profil adı, sonra auth
    // metadata — hangi Supabase auth sağlayıcısına göre isim farklı
    // anahtarlarda gelebilir (ör. Google/Apple ile girişte "given_name"
    // doldurulur).
    final nameCandidates = <String?>[
      profile?['full_name']?.toString(),
      profile?['name']?.toString(),
      profile?['display_name']?.toString(),
      metadata?['full_name']?.toString(),
      metadata?['name']?.toString(),
      metadata?['display_name']?.toString(),
      metadata?['given_name']?.toString(),
      metadata?['first_name']?.toString(),
    ];

    for (final candidate in nameCandidates) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        // Sadece İLK isim — "Ahmet Yılmaz" -> "Ahmet". RegExp ile birden
        // fazla/garip boşluk karakterine karşı da güvenli.
        return trimmed.split(RegExp(r'\s+')).first;
      }
    }

    // Kolon/anahtar adı bizim tahmin ettiğimizden farklı olabilir (ör.
    // "ad_soyad", "username") — spesifik bir isim UYDURMUYORUZ ama "name"
    // geçen herhangi bir alanı (profil önce, sonra metadata) genel olarak
    // tarıyoruz. "last"/"surname"/"soyad" içeren alanlar BİLEREK hariç
    // tutuluyor — aksi halde bir "last_name" alanı yanlışlıkla soyadı
    // "ilk isim" olarak göstermiş olurdu.
    for (final source in [profile, metadata]) {
      if (source == null) continue;
      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (!key.contains('name')) continue;
        if (key.contains('last') ||
            key.contains('surname') ||
            key.contains('soyad')) {
          continue;
        }
        final trimmed = entry.value?.toString().trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          return trimmed.split(RegExp(r'\s+')).first;
        }
      }
    }

    // Hiçbir yerde gerçek bir isim yoksa (ör. hesap sadece e-posta/şifre ile,
    // isim hiç girilmeden oluşturulmuş), e-posta kullanıcı adından okunabilir
    // bir isim türetiyoruz ki greeting tamamen isimsiz kalmasın. Bu tam bir
    // "ilk isim" olmayabilir (ör. "kaanbabadag" ayrılamaz) ama kullanıcının
    // gerçek hesap verisinden geliyor, hardcode değil.
    final email = user.email;
    if (email != null && email.contains('@')) {
      final localPart = email.split('@').first;
      final namePart = localPart
          .split(RegExp(r'[._+0-9-]+'))
          .firstWhere((part) => part.isNotEmpty, orElse: () => '');

      if (namePart.isNotEmpty) {
        return namePart[0].toUpperCase() + namePart.substring(1).toLowerCase();
      }
    }

    return null;
  }

  String _headerDateLabel() {
    const weekdays = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    const months = [
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

    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]} ${weekdays[now.weekday - 1]}';
  }

  String _avatarInitials() {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) return '?';
    return email.substring(0, email.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildPlanRow(Plan plan, Color secondaryText) {
    final theme = Theme.of(context);
    final timeLabel =
        plan.dateTime == null ? 'Tarih yok' : _formatTime(plan.dateTime!);

    return InkWell(
      key: ValueKey('plan-${plan.id}'),
      onTap: () => _showPlanDetails(plan),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                _toggleTodayCheckbox(plan);
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: plan.isCompleted
                          ? const Color(0xFF4C7A5E)
                          : Colors.transparent,
                      border: Border.all(
                        color: plan.isCompleted
                            ? const Color(0xFF4C7A5E)
                            : secondaryText.withValues(alpha: 0.5),
                        width: 1.6,
                      ),
                    ),
                    child: plan.isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    plan.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      decoration:
                          plan.isCompleted ? TextDecoration.lineThrough : null,
                      color: plan.isCompleted ? secondaryText : null,
                    ),
                  ),
                  if (plan.note != null && plan.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      plan.note!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: plan.isCompleted
                    ? secondaryText
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _glowController.dispose();
    super.dispose();
  }

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

    final todayPlans = _todayPlans;
    final laterPlans = _laterPlans;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadPlans();
            await _loadAiUsage();
          },
          child: ListView(
            // Bir habit slider'ı gerçekten yatay sürüklenirken sayfa
            // scroll'unu kilitliyoruz — sürükleme bitince (veya iptal
            // olunca) normal davranışa (null = platform varsayılanı)
            // otomatik dönüyor.
            physics: _isHabitDragging
                ? const NeverScrollableScrollPhysics()
                : null,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGreeting(theme, colors, isDark),
                        const SizedBox(height: 3),
                        Text(
                          _headerDateLabel(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A6B87), Color(0xFF2C4356)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _avatarInitials(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // AI Asistan — always-dark hero card (tasarımdaki gibi tema
              // değişiminden bağımsız). Ambient glow ~%25 güçlendirildi ve
              // mor/cyan/mavi üç katmanlı, yavaş "nefes alan" bir harekete
              // sahip (AnimatedBuilder sadece bu küçük alt ağacı, tick
              // başına, tüm sayfayı değil yeniden çiziyor).
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  final t = _glowController.value;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF23252C), Color(0xFF131418)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C7CF7).withValues(
                            alpha: 0.20 + 0.05 * t,
                          ),
                          blurRadius: 30 + 6 * t,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: const Color(0xFF33C7E8).withValues(
                            alpha: 0.05 + 0.04 * t,
                          ),
                          blurRadius: 36 + 8 * t,
                          offset: const Offset(-5, 8),
                        ),
                        BoxShadow(
                          color: const Color(0xFF5B7FFF).withValues(
                            alpha: 0.04 + 0.03 * t,
                          ),
                          blurRadius: 40 + 10 * t,
                          offset: const Offset(5, 14),
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 3,
                            style: const TextStyle(
                              color: Color(0xFFF4F3F0),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addPlan(),
                            decoration: InputDecoration(
                              hintText: 'Bugün ne planlıyoruz?',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.46),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isCollapsed: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _saving ? null : _addPlan,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF6C7CF7),
                                  Color(0xFF9B6EF3),
                                  Color(0xFF33C7E8),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_upward_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _aiUsageLoading
                            ? 'AI kullanımı yükleniyor…'
                            : 'Bu ay $_aiUsage/$_aiLimit istek kullanıldı',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!_isPremium)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PremiumPage(),
                            ),
                          );
                        },
                        child: const Text(
                          "Premium'da 300",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.error.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bugün',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showQuickAddSheet,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (todayPlans.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Column(
                    children: [
                      // Sade, temanın accent rengine uyumlu takvim+ekle
                      // rozeti — sadece görsel bir vurgu, metinler/diğer
                      // tasarım değişmedi.
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary.withValues(
                            alpha: isDark ? 0.18 : 0.10,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              size: 28,
                              color: colors.primary,
                            ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.primary,
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Bugün için planın yok',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Yukarıdaki alana yazarak hemen bir şeyler planlayabilirsin.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondaryText,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < todayPlans.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: border),
                        _buildPlanRow(todayPlans[i], secondaryText),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Günlük Alışkanlıklar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (_habits.isNotEmpty)
                    TextButton.icon(
                      onPressed: _openAddHabitSheet,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Ekle'),
                    ),
                ],
              ),

              if (_habits.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _habitsSummaryText(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondaryText,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                // Tamamlanan alışkanlık en alt gruba taşındığında (veya
                // geri tamamlanmamış hale geldiğinde) liste yumuşak bir
                // cross-fade ile yeniden düzenlenir — fiziksel "kayma"
                // yerine (ki bunun için AnimatedList/manuel offset hesabı
                // gerekir ve mevcut, çalışan liste yapısını riske atardı),
                // düşük riskli ama gerçekten akıcı hissettiren bir geçiş.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Container(
                    key: ValueKey(_habitsOrderSignature),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border),
                    ),
                    child: Builder(
                      builder: (context) {
                        final ordered = _orderedHabits;
                        return Column(
                          children: [
                            for (var i = 0; i < ordered.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: border),
                              _buildHabitRow(ordered[i]),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ] else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 26,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Henüz günlük alışkanlık eklemedin.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Düzenli takip etmek istediğin şeyleri buraya ekleyebilirsin.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondaryText,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _openAddHabitSheet,
                        child: const Text('Alışkanlık ekle'),
                      ),
                    ],
                  ),
                ),

              // Tarihsiz planlar HTML tasarımında yok (o ekranda "Bugün" +
              // "Alışkanlıklar" var) ama mevcut CRUD ile oluşturulmuş
              // tarihsiz görevlerin erişilebilir kalması için korunuyor.
              if (!_loading && laterPlans.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  'Daha Sonra',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < laterPlans.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: border),
                        _buildPlanRow(laterPlans[i], secondaryText),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Alışkanlık ilerleme çubuğu.
//
// KRİTİK TASARIM KARARI (v2): Bu widget artık gesture arena'ya (GestureDetector/
// HorizontalDragGestureRecognizer) DEĞİL, ham `Listener` pointer olaylarına
// dayanıyor. Önceki GestureDetector tabanlı sürüm, bu track dikey kaydırılan
// bir ListView içinde yaşadığı için ListView'ın kendi dikey pan/scroll
// recognizer'ı ile aynı "gesture arena"da rekabet ediyordu — parmağın en
// ufak dikey bileşeni olduğunda (gerçek kullanımda neredeyse her zaman VAR),
// bazen scroll recognizer'ı kazanıp sürüklemeyi hiç başlatmıyordu. Bu da
// tekrarlayan "0'da/başlangıçta yakalanamıyor" şikayetlerinin gerçek kök
// nedeniydi. `Listener` gesture arena'ya hiç girmez — bu widget üzerinde
// başlayan HER dokunuş kayıtsız şartsız bu widget'a ait olur (rakip yok),
// bu yüzden yatay sürükleme HER ZAMAN, anında, %100 güvenilir şekilde
// başlar. Bunun kabul edilen tek bedeli: kullanıcı sayfa kaydırmayı TAM OLARAK
// bu bar'ın üzerinden başlatamaz (başka bir yerden kaydırabilir) — habit
// tracker uygulamalarında (Streaks, Way of Life vb.) standart bir davranış.
//
// v3: Artık HİÇBİR "slop"/eşik yok — parmak değdiği (onPointerDown) an
// değer, dokunulan noktaya göre ANINDA güncelleniyor. Defalarca bildirilen
// "en başta seçilemiyor/sürüklenmiyor" sorununun kesin çözümü budur: ilk
// temas bile gecikmesiz bir tepki üretir, tek bir dokunuşun değeri hiç
// değiştirmemesi gerektiği eski kural bilerek kaldırıldı (öncelik artık
// "her zaman anında yakalanabilir olmak"). Canlı değer her hareket
// karesinde `onLiveRatio` ile üste bildiriliyor (parent, SADECE kendi
// küçük alt ağacını — bu habit kartını — güncelliyor, tüm Home'u değil);
// kalıcı commit sadece parmak kalkınca `onChangeEnd` ile bir kez yapılır.

// Miktar/süre/tekrar tipi bir alışkanlığın başlık satırını (isim + "1.25 /
// 3.0 L" etiketi) ve track'ini birlikte barındırır. Sürükleme sırasında
// canlı değeri (_liveCurrent) SADECE kendi State'inde tutar — bu sayede
// "1.25/3.0 L" etiketi parmakla eşzamanlı güncellenirken bile rebuild
// SADECE bu küçük kart ile sınırlı kalır, _HomePageState'in tamamı değil.
// Kalıcı commit (widget.onCommit) yalnızca sürükleme bitince bir kez
// çağrılır.
class _HabitCard extends StatefulWidget {
  final _Habit habit;
  final VoidCallback onOpenEdit;
  final VoidCallback onOpenActions;
  final void Function(double current, bool done) onCommit;
  final ValueChanged<bool> onDragActiveChanged;

  const _HabitCard({
    super.key,
    required this.habit,
    required this.onOpenEdit,
    required this.onOpenActions,
    required this.onCommit,
    required this.onDragActiveChanged,
  });

  @override
  State<_HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<_HabitCard> {
  double? _liveCurrent;

  // "+0.25 L" gibi hızlı ekle butonuna basıldığında çağrılır. Değer, drag
  // ile aynı `onCommit` yoluyla kalıcı hale getirilir; track'teki
  // AnimatedContainer zaten eski/yeni ratio farkını kendisi akıcı şekilde
  // animasyonlu gösterir (bkz. _HabitProgressTrack) — burada ayrıca bir
  // local state/animasyon yönetimine gerek yok.
  void _quickAdd(_Habit habit) {
    if (habit.step <= 0 || habit.current >= habit.target - 0.0005) return;
    final newCurrent = (habit.current + habit.step).clamp(0.0, habit.target);
    final done = newCurrent >= habit.target - 0.0005;
    HapticFeedback.lightImpact();
    widget.onCommit(newCurrent, done);
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText =
        isDark ? const Color(0xFFA7A9B0) : const Color(0xFF6B7280);
    final iconBg = isDark ? const Color(0xFF23252B) : const Color(0xFFF3F4F7);
    // Track/dolum rengi kart yüzeyinden ve ikon arka planından BİLEREK
    // belirgin şekilde ayrıştırılır — 0 ilerlemede bile track net görünsün
    // diye (defalarca bildirilen bir sorun) kontrast bilinçli olarak
    // AÇIK TEMADA ÖZELLİKLE daha da yükseltildi (önceki ton kart beyazına
    // göre hâlâ çok soluk kalıyordu).
    final trackBg = isDark ? const Color(0xFF3D4453) : const Color(0xFFC9CEDC);
    final trackBorder =
        isDark ? const Color(0xFF6E7690) : const Color(0xFF9AA0B5);

    final displayCurrent = _liveCurrent ?? habit.current;
    final isDone = _liveCurrent == null
        ? habit.done
        : displayCurrent >= habit.target - 0.0005;
    final ratio =
        habit.target > 0 ? (displayCurrent / habit.target).clamp(0.0, 1.0) : 0.0;

    final leadingIcon = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: isDone ? colors.primary.withValues(alpha: 0.16) : iconBg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(habit.emoji, style: const TextStyle(fontSize: 15)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onOpenEdit,
          child: Row(
            children: [
              leadingIcon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _habitTargetLabel(habit, displayCurrent),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondaryText,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Sürüklenebilen (tap dışı) tüm alışkanlıklarda ("Su iç",
              // "Kitap oku" gibi) tek dokunuşla hızlı artış butonu. Etiket
              // UYDURULMUYOR: alışkanlığın kendi yapılandırılmış step/unit
              // değerinden türetiliyor (ör. "Su iç" 0.25 L step'e sahip
              // olduğu için "+0.25 L", "Kitap oku" 5 Sf step'e sahip olduğu
              // için "+5 Sf" gösterir).
              if (habit.type != _HabitType.tap && habit.step > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: isDone ? null : () => _quickAdd(habit),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(
                          alpha: isDone ? 0.08 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '+${_formatHabitNumber(habit.type, habit.step)}'
                        '${(habit.unit == null || habit.unit!.isEmpty) ? '' : ' ${habit.unit}'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isDone
                              ? secondaryText
                              : colors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                color: secondaryText,
                onPressed: widget.onOpenActions,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _HabitProgressTrack(
          ratio: ratio,
          isDone: isDone,
          trackColor: trackBg,
          trackBorderColor: trackBorder,
          fillColor: colors.primary,
          doneColor: const Color(0xFF4C7A5E),
          onDragActiveChanged: widget.onDragActiveChanged,
          // Her post-slop hareket karesinde çağrılır — SADECE bu kartın
          // kendi State'ini günceller (etiket + bar canlı değişsin diye).
          onLiveRatio: (r) {
            final done = r >= 0.995;
            setState(() {
              _liveCurrent = done ? habit.target : r * habit.target;
            });
          },
          // Sürükleme bitince BİR KEZ çağrılır — kalıcı state burada
          // parent'a (_HomePageState) taşınır.
          onChangeEnd: (r) {
            final done = r >= 0.995;
            final finalCurrent = done ? habit.target : r * habit.target;
            setState(() => _liveCurrent = null);
            widget.onCommit(finalCurrent, done);
          },
        ),
      ],
    );
  }
}

class _HabitProgressTrack extends StatefulWidget {
  final double ratio;
  final bool isDone;
  final Color trackColor;
  final Color trackBorderColor;
  final Color fillColor;
  final Color doneColor;
  final ValueChanged<double> onLiveRatio;
  final ValueChanged<double> onChangeEnd;
  // Gerçek bir yatay sürükleme onaylandığında (slop aşılınca) true, bittiğinde
  // false ile çağrılır — üst taraf bunu Home'un ana ListView'ının scroll'unu
  // sürükleme sırasında kilitlemek için kullanır.
  final ValueChanged<bool> onDragActiveChanged;

  const _HabitProgressTrack({
    required this.ratio,
    required this.isDone,
    required this.trackColor,
    required this.trackBorderColor,
    required this.fillColor,
    required this.doneColor,
    required this.onLiveRatio,
    required this.onChangeEnd,
    required this.onDragActiveChanged,
  });

  @override
  State<_HabitProgressTrack> createState() => _HabitProgressTrackState();
}

class _HabitProgressTrackState extends State<_HabitProgressTrack> {
  Offset? _downPosition;
  bool _dragging = false;
  bool _hapticFired = false;

  static const double _trackHeight = 32;
  static const double _draggingTrackHeight = 36;
  // Hit area görsel bardan ÇOK daha büyük (~76pt toplam) — 0 değeri dahil
  // her noktada rahatça yakalanabilsin diye ciddi şekilde büyütüldü.
  static const double _hitPaddingVertical = 22;

  @override
  void dispose() {
    // Güvenlik ağı: bu widget aktif bir sürükleme sırasında ağaçtan
    // kaldırılırsa (ör. habit silinirse) scroll kilidi sonsuza kadar açık
    // kalmasın.
    if (_downPosition != null) {
      widget.onDragActiveChanged(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;

        double ratioFromDx(double dx) => (dx / trackWidth).clamp(0.0, 1.0);

        return Listener(
          behavior: HitTestBehavior.opaque,
          // KRİTİK: Artık hiçbir "slop"/eşik YOK. Parmak değdiği (down)
          // ANDA bile değer, dokunulan noktaya göre ANINDA güncelleniyor —
          // kullanıcının barı "yakalayabilmesi" için önce bir miktar
          // hareket etmesi gerekmiyor. Defalarca bildirilen "en başta
          // sürüklenmiyor/seçilemiyor" sorununun kesin çözümü budur: ilk
          // temas bile anlık, gecikmesiz bir tepki üretir; sonrasında her
          // hareket de aynı şekilde birebir takip eder.
          onPointerDown: (event) {
            _downPosition = event.localPosition;
            final ratio = ratioFromDx(event.localPosition.dx);
            _hapticFired = ratio >= 0.995;

            widget.onDragActiveChanged(true);
            setState(() => _dragging = true);
            widget.onLiveRatio(ratio);
          },
          onPointerMove: (event) {
            if (_downPosition == null) return;

            final ratio = ratioFromDx(event.localPosition.dx);

            if (ratio >= 0.995 && !_hapticFired) {
              _hapticFired = true;
              HapticFeedback.lightImpact();
            } else if (ratio < 0.995 && _hapticFired) {
              _hapticFired = false;
            }

            widget.onLiveRatio(ratio);
          },
          onPointerUp: (event) {
            final wasActive = _downPosition != null;
            final ratio = ratioFromDx(event.localPosition.dx);

            setState(() {
              _dragging = false;
              _downPosition = null;
            });

            if (wasActive) {
              widget.onDragActiveChanged(false);
              widget.onChangeEnd(ratio);
            }
          },
          onPointerCancel: (_) {
            final wasActive = _downPosition != null;

            setState(() {
              _dragging = false;
              _downPosition = null;
            });

            if (wasActive) {
              widget.onDragActiveChanged(false);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: _hitPaddingVertical,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              // KRİTİK KÖK NEDEN DÜZELTMESİ: width AÇIKÇA verilmiyordu. Bu
              // Container'ın tek "positioned olmayan" Stack çocuğu, genişliği
              // `trackWidth * widget.ratio` olan dolum kutusuydu — yani bu
              // dış kutu (arka plan + border, yani "boş track") kendi
              // boyutunu O DOLUM KUTUSUNUN genişliğine göre belirliyordu.
              // Sonuç: ratio 0 iken dış kutu da neredeyse 0 genişliğe
              // küçülüyordu — track rengi/border'ı ne kadar güçlendirilirse
              // güçlendirilsin görünecek hiçbir alan kalmıyordu. Bu, rengin
              // değil GENİŞLİĞİN sorun olduğu, ekran görüntüsüyle doğrulanan
              // gerçek kök nedendir.
              width: trackWidth,
              height: _dragging ? _draggingTrackHeight : _trackHeight,
              decoration: BoxDecoration(
                color: widget.trackColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.trackBorderColor,
                  width: 1.5,
                ),
                // Dolu kısım için yumuşak bir glow — boxShadow, Container'ın
                // KENDİ dekorasyonu olarak çizildiği için aşağıdaki
                // `clipBehavior` bunu KESMEZ (clip sadece child'ı keser).
                // Track tamamen boşken (ratio 0) glow yok — sadece gerçek
                // ilerleme varken beliriyor.
                boxShadow: widget.ratio > 0
                    ? [
                        BoxShadow(
                          color: (widget.isDone
                                  ? widget.doneColor
                                  : widget.fillColor)
                              .withValues(alpha: 0.38),
                          blurRadius: 14,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Sürükleme sırasında dolumun parmakla eşzamanlı
                  // ilerlemesi için animasyon YOK (duration: zero) — aksi
                  // halde dolum her zaman gecikmeli "yetişmeye çalışan" bir
                  // görünüm veriyordu. Sürükleme dışı değişikliklerde (ör.
                  // "+0.25 L" hızlı ekle butonu) ise akıcı bir animasyonla
                  // ilerlemesi için AnimatedContainer kullanılıyor.
                  AnimatedContainer(
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    width: trackWidth * widget.ratio,
                    color: widget.isDone ? widget.doneColor : widget.fillColor,
                  ),
                  if (widget.isDone)
                    const Positioned(
                      right: 10,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    )
                  else
                    // iOS tarzı handle: değer 0 olsa bile barın başında
                    // görünür ve yakalanabilir küçük bir daire — dolum
                    // (yukarıdaki Container) gerçek değere göre 0 genişlikte
                    // kalmaya devam ediyor, sadece bu handle'ın konumu
                    // kenardan biraz içeride tutuluyor ki her zaman tam
                    // görünür ve tutulabilir olsun.
                    _HabitHandle(
                      trackWidth: trackWidth,
                      ratio: widget.ratio,
                      dragging: _dragging,
                      color: widget.fillColor,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Track'in başında (ratio 0 dahil) her zaman görünür ve tutulabilir kalan
// premium bir "grip" tutamacı — küçük dikey çizgili bir ikon içeren, iOS
// tarzı beyaz pill/hap şekli. Sadece görsel bir işaretçidir — gerçek
// ilerleme değerini (dolum genişliğini) etkilemez.
class _HabitHandle extends StatelessWidget {
  final double trackWidth;
  final double ratio;
  final bool dragging;
  final Color color;

  const _HabitHandle({
    required this.trackWidth,
    required this.ratio,
    required this.dragging,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Handle'ı tam kenara (3px) değil, biraz İÇERİYE (10px) yerleştiriyoruz
    // — böylece 0 değerindeyken bile kart kenarına yapışık durmuyor,
    // elle/parmakla rahatça hedeflenebilecek bir konumda duruyor.
    const inset = 10.0;
    final width = dragging ? 24.0 : 20.0;
    final height = dragging ? 28.0 : 24.0;

    final rawLeft = trackWidth * ratio - width / 2;
    final maxLeft = trackWidth - width - inset;
    final left = rawLeft.clamp(inset, maxLeft < inset ? inset : maxLeft);

    return AnimatedPositioned(
      // Aktif sürükleme sırasında animasyon YOK (Duration.zero) — handle
      // parmağı birebir/anlık takip etsin; sürükleme bittiğinde/parent
      // güncellendiğinde ise yumuşak yerleşsin.
      duration: dragging ? Duration.zero : const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      left: left,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(width / 2),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Transform.rotate(
            angle: math.pi / 2,
            child: Icon(
              Icons.drag_handle_rounded,
              size: dragging ? 15 : 13,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _HabitTypeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HabitTypeOption({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

// ==========================================================================
// Görev ekleme/düzenleme sheet'leri — her biri kendi kendine yeten birer
// StatefulWidget. TextEditingController'lar `initState`'te oluşturulur,
// `dispose`'ta kapatılır — Flutter'ın kendi garantilediği sıra dışında,
// elle "await sonrası dispose et" gibi kırılgan bir mantık YOK. Sheet
// kapanırken veya kaydederken hep KENDİ context'ini/kendi `mounted`
// durumunu kontrol eder; asla parent'ın (_HomePageState) state'ini
// doğrudan karıştırmaz — sonucu `Navigator.pop(result)` ile döndürür,
// parent bunu sheet TAMAMEN kapandıktan sonra tek bir `setState` ile uygular.
// ==========================================================================

class _QuickAddTaskSheet extends StatefulWidget {
  final EventService eventService;

  const _QuickAddTaskSheet({required this.eventService});

  @override
  State<_QuickAddTaskSheet> createState() => _QuickAddTaskSheetState();
}

class _QuickAddTaskSheetState extends State<_QuickAddTaskSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _noteController = TextEditingController();
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

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final note = _noteController.text.trim();

    final plan = Plan(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      dateTime: dateTime,
      category: PlanCategory.task,
      source: PlanSource.manual,
      isCompleted: false,
      reminderEnabled: false,
      note: note.isEmpty ? null : note,
      createdAt: DateTime.now(),
    );

    try {
      await widget.eventService.addPlan(plan);

      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error, 'Görev eklenemedi. Tekrar deneyin.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Yeni Görev', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                autofocus: true,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  hintText: 'Görev adı',
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await _showCupertinoDatePicker(
                                context,
                                _selectedDate,
                              );
                              if (picked == null || !mounted) return;
                              setState(() => _selectedDate = picked);
                            },
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(_prettyDateTr(_selectedDate)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await _showCupertinoTimePicker(
                                context,
                                _selectedTime,
                              );
                              if (picked == null || !mounted) return;
                              setState(() => _selectedTime = picked);
                            },
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(_formatTimeOfDayTr(_selectedTime)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 3,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Not',
                  hintText: 'Not yazın',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 4),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Ekle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDetailSheet extends StatefulWidget {
  final Plan plan;
  final EventService eventService;

  const _TaskDetailSheet({required this.plan, required this.eventService});

  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final plan = widget.plan;
    final now = DateTime.now();

    _selectedDate = DateTime(
      plan.dateTime?.year ?? now.year,
      plan.dateTime?.month ?? now.month,
      plan.dateTime?.day ?? now.day,
    );

    _selectedTime = plan.dateTime == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: plan.dateTime!.hour, minute: plan.dateTime!.minute);

    _titleController = TextEditingController(text: plan.title);
    _noteController = TextEditingController(text: plan.note ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Başlık boş olamaz.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final newDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final trimmedNote = _noteController.text.trim();

    try {
      await widget.eventService.updatePlanSchedule(
        id: widget.plan.id,
        dateTime: newDateTime,
        note: trimmedNote.isEmpty ? null : trimmedNote,
        title: title,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            friendlyErrorMessage(error, 'Görev güncellenemedi. Tekrar deneyin.');
      });
    }
  }

  Future<void> _complete() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.eventService.setCompleted(id: widget.plan.id, completed: true);

      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            friendlyErrorMessage(error, 'Plan güncellenemedi. Tekrar deneyin.');
      });
    }
  }

  void _requestDelete() {
    // Silme onayı ve gerçek silme işlemi BİLEREK burada değil, sheet
    // kapandıktan sonra parent'ta yapılır (bkz. _HomePageState.
    // _showPlanDetails) — bu sentinel'i pop ederek sadece isteği iletiyoruz.
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(_taskDeleteRequested);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                maxLength: 60,
                style: theme.textTheme.titleLarge,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await _showCupertinoDatePicker(
                                context,
                                _selectedDate,
                              );
                              if (picked == null || !mounted) return;
                              setState(() => _selectedDate = picked);
                            },
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(_prettyDateTr(_selectedDate)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await _showCupertinoTimePicker(
                                context,
                                _selectedTime,
                              );
                              if (picked == null || !mounted) return;
                              setState(() => _selectedTime = picked);
                            },
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(_formatTimeOfDayTr(_selectedTime)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 3,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Not',
                  hintText: 'Not yazın',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: colors.error, fontSize: 13)),
              ],
              const SizedBox(height: 4),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _saving ? null : _complete,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Tamamlandı olarak işaretle'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _saving ? null : _requestDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Sil'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error,
                  side: BorderSide(color: colors.error.withValues(alpha: 0.45)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================================================
// Alışkanlık ekleme/düzenleme sheet'leri — aynı prensiple (kendi kendine
// yeten StatefulWidget, kendi controller lifecycle'ı, sonucu pop ile
// döndürme).
// ==========================================================================

class _AddHabitSheet extends StatefulWidget {
  const _AddHabitSheet();

  @override
  State<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<_AddHabitSheet> {
  int _step = 0;
  String _tempName = '';
  // Kullanıcı emoji ızgarasından seçim yapmazsa bu varsayılan (⭐) kalır —
  // sistem başka bir emoji atamaz.
  String _tempEmoji = _habitEmojiOptions.first;
  late final TextEditingController _customNameController;

  @override
  void initState() {
    super.initState();
    _customNameController = TextEditingController();
  }

  @override
  void dispose() {
    _customNameController.dispose();
    super.dispose();
  }

  void _finish({
    required _HabitType type,
    double target = 1,
    double step = 1,
    String? unit,
  }) {
    FocusScope.of(context).unfocus();

    final habit = _Habit(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _tempName,
      emoji: _tempEmoji,
      type: type,
      target: target,
      current: 0,
      unit: unit,
      step: step,
    );

    Navigator.of(context).pop(habit);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;

    if (_step == 0) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Yeni alışkanlık', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _habitPresets.map((preset) {
              return ActionChip(
                label: Text('${preset['emoji']} ${preset['name']}'),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _tempName = preset['name']!;
                    _tempEmoji = preset['emoji']!;
                    _step = 1;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            'veya özel bir alışkanlık adı yaz',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customNameController,
            decoration: const InputDecoration(labelText: 'Özel alışkanlık adı'),
          ),
          const SizedBox(height: 14),
          Text(
            'Emoji seç',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildEmojiGrid(
            context: context,
            selected: _tempEmoji,
            onSelect: (emoji) => setState(() => _tempEmoji = emoji),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final name = _customNameController.text.trim();
              if (name.isEmpty) return;
              FocusScope.of(context).unfocus();
              setState(() {
                _tempName = name;
                // _tempEmoji zaten kullanıcının ızgaradan seçtiği (ya da hiç
                // seçmediyse varsayılan ⭐) değeri taşıyor — üzerine
                // yazılmıyor.
                _step = 1;
              });
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('İleri'),
            ),
          ),
        ],
      );
    } else if (_step == 1) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$_tempEmoji $_tempName', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Nasıl takip etmek istersin?', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          _HabitTypeOption(
            title: 'Tek dokunuş',
            subtitle: 'Yapıldı / yapılmadı',
            onTap: () => _finish(type: _HabitType.tap),
          ),
          _HabitTypeOption(
            title: 'Miktar (L)',
            subtitle: 'Örn. su tüketimi',
            onTap: () => setState(() => _step = 2),
          ),
          _HabitTypeOption(
            title: 'Süre (dk)',
            subtitle: 'Örn. okuma, çalışma',
            onTap: () => setState(() => _step = 3),
          ),
          _HabitTypeOption(
            title: 'Tekrar (adet)',
            subtitle: 'Örn. şınav, bardak sayısı',
            onTap: () => setState(() => _step = 4),
          ),
        ],
      );
    } else if (_step == 2) {
      const targets = [1.5, 2.0, 2.5, 3.0, 4.0];
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Günlük hedef', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: targets.map((value) {
              return ActionChip(
                label: Text('${value.toStringAsFixed(1)} L'),
                onPressed: () => _finish(
                  type: _HabitType.quantity,
                  target: value,
                  step: 0.25,
                  unit: 'L',
                ),
              );
            }).toList(),
          ),
        ],
      );
    } else if (_step == 3) {
      const targets = [10.0, 15.0, 20.0, 30.0, 45.0, 60.0];
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Günlük hedef', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: targets.map((value) {
              return ActionChip(
                label: Text('${value.toInt()} dk'),
                onPressed: () => _finish(
                  type: _HabitType.duration,
                  target: value,
                  step: 5,
                  unit: 'dk',
                ),
              );
            }).toList(),
          ),
        ],
      );
    } else {
      const targets = [3.0, 5.0, 8.0, 10.0, 15.0, 20.0];
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Günlük hedef', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: targets.map((value) {
              return ActionChip(
                label: Text('${value.toInt()} adet'),
                onPressed: () => _finish(
                  type: _HabitType.count,
                  target: value,
                  step: 1,
                  unit: 'adet',
                ),
              );
            }).toList(),
          ),
        ],
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(child: body),
      ),
    );
  }
}

class _EditHabitSheet extends StatefulWidget {
  final _Habit habit;

  const _EditHabitSheet({required this.habit});

  @override
  State<_EditHabitSheet> createState() => _EditHabitSheetState();
}

class _EditHabitSheetState extends State<_EditHabitSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _unitController;
  late String _selectedEmoji;
  late double _target;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _nameController = TextEditingController(text: habit.name);
    _unitController = TextEditingController(text: habit.unit ?? '');
    _selectedEmoji = habit.emoji;
    _target = habit.target;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final habit = widget.habit;
    final showTarget = habit.type != _HabitType.tap;
    final showUnit = habit.type == _HabitType.quantity;
    final unitValue = _unitController.text.trim();

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _HabitEditResult.save(
        name: name,
        emoji: _selectedEmoji,
        target: showTarget ? _target : null,
        unit: showUnit ? (unitValue.isEmpty ? (habit.unit ?? 'L') : unitValue) : null,
      ),
    );
  }

  void _requestDelete() {
    // Silme onayı ve gerçek silme, sheet TAMAMEN kapandıktan sonra parent'ta
    // yapılır (bkz. _HomePageState._openHabitEditSheet) — burada sadece
    // isteği pop ile iletiyoruz.
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(const _HabitEditResult.deleteRequested());
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF2B2F36) : const Color(0xFFE5E7EB);
    final iconBg = isDark ? const Color(0xFF23252B) : const Color(0xFFF3F4F7);

    final showTarget = habit.type != _HabitType.tap;
    final showUnit = habit.type == _HabitType.quantity;
    final targetBounds = _habitTargetBounds(habit.type);

    final unitSuffix = habit.type == _HabitType.duration
        ? ' dk'
        : habit.type == _HabitType.count
            ? ' adet'
            : _unitController.text.trim().isEmpty
                ? ''
                : ' ${_unitController.text.trim()}';

    final targetLabel = habit.type == _HabitType.duration
        ? 'Günlük hedef (dakika)'
        : habit.type == _HabitType.count
            ? 'Günlük hedef (adet)'
            : 'Günlük hedef';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Alışkanlığı düzenle', style: theme.textTheme.titleLarge),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconBg,
                      border: Border.all(color: border),
                    ),
                    alignment: Alignment.center,
                    child: Text(_selectedEmoji, style: const TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Ad',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Emoji seç',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildEmojiGrid(
                context: context,
                selected: _selectedEmoji,
                onSelect: (emoji) => setState(() => _selectedEmoji = emoji),
              ),
              if (showTarget) ...[
                const SizedBox(height: 20),
                _buildStepperRow(
                  label: targetLabel,
                  valueLabel: '${_formatHabitNumber(habit.type, _target)}$unitSuffix',
                  onDecrement: () => setState(() {
                    _target = (_target - targetBounds.increment)
                        .clamp(targetBounds.min, targetBounds.max);
                  }),
                  onIncrement: () => setState(() {
                    _target = (_target + targetBounds.increment)
                        .clamp(targetBounds.min, targetBounds.max);
                  }),
                  border: border,
                ),
              ],
              if (showUnit) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _unitController,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Birim',
                    hintText: 'Örn. L, bardak',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _save,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Kaydet'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _requestDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Sil'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.45)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
