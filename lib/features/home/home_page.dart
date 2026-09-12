
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/theme_controller.dart';
import '../plans/event_service.dart';
import '../plans/plan.dart';

class HomePage extends StatefulWidget {
  final Future<void> Function()? onAiUsageChanged;

  const HomePage({
    super.key,
    this.onAiUsageChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  final EventService _eventService = EventService();

  List<Plan> _plans = [];
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPlans();
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
        _errorMessage = 'Planlar yüklenemedi: $error';
      });
    }
  }

  Future<void> _addPlan() async {
    final text = _controller.text.trim();

    if (text.isEmpty || _saving) return;

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

      _controller.clear();
      await _loadPlans();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Plan oluşturulamadı: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deletePlan(Plan plan) async {
    try {
      await _eventService.deletePlan(plan.id);

      if (!mounted) return;

      Navigator.of(context).pop();
      await _loadPlans();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan silindi.')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan silinemedi: $error')),
      );
    }
  }

  Future<void> _completePlan(Plan plan) async {
    try {
      await _eventService.setCompleted(
        id: plan.id,
        completed: true,
      );

      if (!mounted) return;

      Navigator.of(context).pop();
      await _loadPlans();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan tamamlandı.')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan güncellenemedi: $error')),
      );
    }
  }

  void _showPlanDetails(Plan plan) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  plan.title,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  plan.dateTime == null
                      ? 'Tarih henüz belirlenmedi'
                      : _formatDate(plan.dateTime!),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Kategori: ${_categoryLabel(plan.category)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _completePlan(plan),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                  ),
                  label: const Text('Tamamlandı'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _deletePlan(plan),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Sil'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(
                      color: colors.error.withValues(alpha: 0.45),
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

  void _showMainMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(8, 0, 8, 14),
                    child: Text(
                      'Life Admin',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _MenuTile(
                  icon: Icons.palette_outlined,
                  title: 'Temalar',
                  subtitle: 'Uygulamanın görünümünü değiştir',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showThemeOptions();
                  },
                ),
                _MenuTile(
                  icon: Icons.language_rounded,
                  title: 'Dil',
                  subtitle: 'Türkçe',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showLanguageOptions();
                  },
                ),
                _MenuTile(
                  icon: Icons.favorite_border_rounded,
                  title: 'Bizi Takip Edin',
                  subtitle: 'Sosyal medya hesaplarımız',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showSocialOptions();
                  },
                ),
                _MenuTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Geri Bildirim / Yardım',
                  subtitle: 'Sorun bildir veya bize ulaş',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showHelpOptions();
                  },
                ),
                const Divider(height: 28),
                _MenuTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Uygulama Hakkında',
                  subtitle: 'Life Admin • v1.0',
                  showArrow: false,
                  onTap: () {
                    Navigator.pop(sheetContext);

                    showAboutDialog(
                      context: context,
                      applicationName: 'Life Admin',
                      applicationVersion: '1.0',
                      applicationLegalese: '© 2026 Life Admin',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showThemeOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: themeController,
          builder: (context, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Text(
                        'Tema',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text('Görünüm tercihini seç'),
                    ),
                    _ThemeTile(
                      icon: Icons.light_mode_outlined,
                      title: 'Açık',
                      selected:
                          themeController.themeMode == ThemeMode.light,
                      onTap: () {
                        themeController.setThemeMode(
                          ThemeMode.light,
                        );
                        Navigator.pop(sheetContext);
                      },
                    ),
                    _ThemeTile(
                      icon: Icons.dark_mode_outlined,
                      title: 'Koyu',
                      selected:
                          themeController.themeMode == ThemeMode.dark,
                      onTap: () {
                        themeController.setThemeMode(
                          ThemeMode.dark,
                        );
                        Navigator.pop(sheetContext);
                      },
                    ),
                    _ThemeTile(
                      icon: Icons.settings_suggest_outlined,
                      title: 'Sistem',
                      subtitle: 'Cihaz ayarını kullan',
                      selected:
                          themeController.themeMode == ThemeMode.system,
                      onTap: () {
                        themeController.setThemeMode(
                          ThemeMode.system,
                        );
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLanguageOptions() {
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
                const ListTile(
                  title: Text(
                    'Dil',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text('Uygulama dilini seç'),
                ),
                ListTile(
                  leading: const Text(
                    '🇹🇷',
                    style: TextStyle(fontSize: 24),
                  ),
                  title: const Text('Türkçe'),
                  trailing: const Icon(Icons.check_rounded),
                  onTap: () => Navigator.pop(sheetContext),
                ),
                ListTile(
                  leading: const Text(
                    '🇬🇧',
                    style: TextStyle(fontSize: 24),
                  ),
                  title: const Text('English'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('English');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSocialOptions() {
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
                const ListTile(
                  title: Text(
                    'Bizi Takip Edin',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Life Admin gelişmelerini takip et',
                  ),
                ),
                _MenuTile(
                  icon: Icons.camera_alt_outlined,
                  title: 'Instagram',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Instagram bağlantısı');
                  },
                ),
                _MenuTile(
                  icon: Icons.alternate_email_rounded,
                  title: 'Diğer sosyal hesaplar',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Sosyal medya bağlantıları');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHelpOptions() {
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
                const ListTile(
                  title: Text(
                    'Yardım & Geri Bildirim',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _MenuTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Geri Bildirim Gönder',
                  subtitle: 'Fikrini bizimle paylaş',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Geri bildirim sistemi');
                  },
                ),
                _MenuTile(
                  icon: Icons.bug_report_outlined,
                  title: 'Sorun Bildir',
                  subtitle: 'Bir hata mı buldun?',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Sorun bildirme sistemi');
                  },
                ),
                _MenuTile(
                  icon: Icons.support_agent_rounded,
                  title: 'Yardım',
                  subtitle: 'Life Admin kullanımı hakkında destek',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showComingSoon('Yardım merkezi');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature yakında aktif olacak.'),
      ),
    );
  }

  List<Plan> get _upcomingPlans {
    final plans = _plans
        .where(
          (plan) =>
              plan.dateTime != null &&
              !plan.isCompleted &&
              plan.dateTime!.isAfter(DateTime.now()),
        )
        .toList();

    plans.sort(
      (a, b) => a.dateTime!.compareTo(b.dateTime!),
    );

    return plans;
  }

  List<Plan> get _laterPlans {
    return _plans
        .where(
          (plan) =>
              plan.dateTime == null &&
              !plan.isCompleted,
        )
        .toList();
  }

  String _formatDate(DateTime dateTime) {
    const weekdays = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    final weekday = weekdays[dateTime.weekday - 1];
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$weekday • $day.$month • $hour:$minute';
  }

  String _categoryLabel(PlanCategory category) {
    switch (category) {
      case PlanCategory.appointment:
        return 'Randevu';
      case PlanCategory.task:
        return 'Görev';
      case PlanCategory.payment:
        return 'Ödeme';
      case PlanCategory.tracking:
        return 'Takip';
      case PlanCategory.document:
        return 'Belge';
      case PlanCategory.personal:
        return 'Kişisel';
      case PlanCategory.study:
        return 'Ders';
      case PlanCategory.meeting:
        return 'Toplantı';
    }
  }

  IconData _categoryIcon(PlanCategory category) {
    switch (category) {
      case PlanCategory.appointment:
        return Icons.event_available_rounded;
      case PlanCategory.task:
        return Icons.check_circle_outline_rounded;
      case PlanCategory.payment:
        return Icons.payments_outlined;
      case PlanCategory.tracking:
        return Icons.track_changes_rounded;
      case PlanCategory.document:
        return Icons.description_outlined;
      case PlanCategory.personal:
        return Icons.person_outline_rounded;
      case PlanCategory.study:
        return Icons.school_outlined;
      case PlanCategory.meeting:
        return Icons.groups_outlined;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark
        ? const Color(0xFF171A1F)
        : Colors.white;

    final softSurface = isDark
        ? const Color(0xFF111318)
        : const Color(0xFFF3F4F7);

    final border = isDark
        ? const Color(0xFF2B2F36)
        : const Color(0xFFE5E7EB);

    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    final upcomingPlans = _upcomingPlans;
    final laterPlans = _laterPlans;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPlans,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              18,
              20,
              36,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: _showMainMenu,
                    tooltip: 'Menü',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Life Admin',
                          style: theme.textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Bugün neyi hallediyoruz?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colors.primary.withValues(alpha: 0.16)
                          : colors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.34),
                      ),
                    ),
                    child: Text(
                      'FREE',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 19,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI Asistan',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addPlan(),
                      decoration: InputDecoration(
                        hintText:
                            'Örn. Pazartesi 18:00’de dişçi randevum var',
                        filled: true,
                        fillColor: softSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          onPressed: null,
                          icon: Icon(
                            Icons.mic_none_rounded,
                            color: secondaryText,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _saving ? null : _addPlan,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                ),
                          label: Text(
                            _saving ? 'Kaydediliyor' : 'Ekle',
                          ),
                        ),
                      ],
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

              Text(
                'Yaklaşanlar',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                ),
              ),

              const SizedBox(height: 12),

              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (upcomingPlans.isEmpty)
                _EmptyState(
                  text: 'Yaklaşan bir planın yok.',
                  surface: surface,
                  border: border,
                  textColor: secondaryText,
                ),

              ...upcomingPlans.map(
                (plan) => Padding(
                  padding: const EdgeInsets.only(
                    bottom: 10,
                  ),
                  child: _PlanCard(
                    plan: plan,
                    subtitle: _formatDate(
                      plan.dateTime!,
                    ),
                    icon: _categoryIcon(
                      plan.category,
                    ),
                    onTap: () => _showPlanDetails(
                      plan,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 26),

              Text(
                'Daha Sonra',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                ),
              ),

              const SizedBox(height: 12),

              if (!_loading && laterPlans.isEmpty)
                _EmptyState(
                  text: 'Daha sonrası için kayıt yok.',
                  surface: surface,
                  border: border,
                  textColor: secondaryText,
                ),

              ...laterPlans.map(
                (plan) => Padding(
                  padding: const EdgeInsets.only(
                    bottom: 10,
                  ),
                  child: _PlanCard(
                    plan: plan,
                    subtitle: 'Tarih henüz belirlenmedi',
                    icon: _categoryIcon(
                      plan.category,
                    ),
                    onTap: () => _showPlanDetails(
                      plan,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF171A1F)
                      : const Color(0xFF16181D),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colors.primary.withValues(
                      alpha: 0.42,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(
                          alpha: 0.17,
                        ),
                        borderRadius: BorderRadius.circular(
                          13,
                        ),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Life Admin Premium',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '300 AI işlemi/ay + akıllı hatırlatıcılar',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₺249/ay',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
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

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark
        ? const Color(0xFF171A1F)
        : Colors.white;

    final border = isDark
        ? const Color(0xFF2B2F36)
        : const Color(0xFFE5E7EB);

    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(
                    alpha: isDark ? 0.14 : 0.09,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: colors.primary,
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
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondaryText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  final Color surface;
  final Color border;
  final Color textColor;

  const _EmptyState({
    required this.text,
    required this.surface,
    required this.border,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showArrow;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle:
          subtitle == null ? null : Text(subtitle!),
      trailing: showArrow
          ? const Icon(
              Icons.chevron_right_rounded,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle:
          subtitle == null ? null : Text(subtitle!),
      trailing: selected
          ? const Icon(Icons.check_rounded)
          : null,
      onTap: onTap,
    );
  }
}
