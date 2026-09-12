import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../services/notification_service.dart';
import '../plans/event_service.dart';
import '../plans/plan.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  CalendarPageState createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage> {
  final EventService _eventService = EventService();

  List<Plan> _plans = [];
  bool _loading = true;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    refreshPlans();
  }

  // Aynı plan için her seferinde aynı notification ID üretir.
  int _notificationId(Plan plan) {
    final date =
        plan.dateTime?.toUtc().toIso8601String() ?? '';

    final value =
        '${plan.title}|$date|${plan.category.name}';

    var hash = 2166136261;

    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }

    return hash;
  }

  Future<void> _scheduleReminder(
    Plan plan,
  ) async {
    if (!plan.reminderEnabled ||
        plan.dateTime == null ||
        plan.reminderMinutesBefore == null) {
      return;
    }

    await NotificationService.instance.schedulePlanReminder(
      id: _notificationId(plan),
      title: plan.title,
      planDateTime: plan.dateTime!,
      minutesBefore: plan.reminderMinutesBefore!,
    );
  }

  Future<void> _cancelReminder(
    Plan plan,
  ) async {
    if (!plan.reminderEnabled ||
        plan.dateTime == null) {
      return;
    }

    await NotificationService.instance.cancelReminder(
      _notificationId(plan),
    );
  }

  Future<void> refreshPlans() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final plans = await _eventService.getPlans();

      if (!mounted) return;

      setState(() {
        _plans = plans
            .where(
              (plan) =>
                  plan.dateTime != null &&
                  !plan.isCompleted,
            )
            .toList();

        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deletePlan(
    Plan plan,
  ) async {
    try {
      await _cancelReminder(plan);

      await _eventService.deletePlan(
        plan.id,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      await refreshPlans();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plan silindi.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Plan silinemedi: $error',
          ),
        ),
      );
    }
  }

  Future<void> _completePlan(
    Plan plan,
  ) async {
    try {
      await _cancelReminder(plan);

      await _eventService.setCompleted(
        id: plan.id,
        completed: true,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      await refreshPlans();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Plan tamamlandı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Plan güncellenemedi: $error',
          ),
        ),
      );
    }
  }

  Future<void> _changeTime(
    Plan plan,
  ) async {
    if (plan.dateTime == null) return;

    final oldDateTime = plan.dateTime!;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: oldDateTime.hour,
        minute: oldDateTime.minute,
      ),
    );

    if (pickedTime == null) return;

    final newDateTime = DateTime(
      oldDateTime.year,
      oldDateTime.month,
      oldDateTime.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    try {
      // Eski bildirimi kaldır.
      await _cancelReminder(plan);

      await _eventService.updateDateTime(
        id: plan.id,
        dateTime: newDateTime,
      );

      // Yeni saate bildirim kur.
      final updatedPlan = Plan(
        id: plan.id,
        title: plan.title,
        dateTime: newDateTime,
        category: plan.category,
        source: plan.source,
        isCompleted: plan.isCompleted,
        reminderEnabled: plan.reminderEnabled,
        reminderMinutesBefore:
            plan.reminderMinutesBefore,
        createdAt: plan.createdAt,
      );

      await _scheduleReminder(
        updatedPlan,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      await refreshPlans();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saat güncellendi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saat güncellenemedi: $error',
          ),
        ),
      );
    }
  }

  Future<void> _movePlanToDay(
    Plan plan,
    DateTime targetDay,
  ) async {
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

      await _eventService.updateDateTime(
        id: plan.id,
        dateTime: newDateTime,
      );

      // Yeni güne bildirim kur.
      final updatedPlan = Plan(
        id: plan.id,
        title: plan.title,
        dateTime: newDateTime,
        category: plan.category,
        source: plan.source,
        isCompleted: plan.isCompleted,
        reminderEnabled: plan.reminderEnabled,
        reminderMinutesBefore:
            plan.reminderMinutesBefore,
        createdAt: plan.createdAt,
      );

      await _scheduleReminder(
        updatedPlan,
      );

      if (!mounted) return;

      setState(() {
        _selectedDay = targetDay;
        _focusedDay = targetDay;
      });

      await refreshPlans();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${plan.title} yeni tarihe taşındı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tarih değiştirilemedi: $error',
          ),
        ),
      );
    }
  }

  Future<void> _showAddPlanSheet() async {
    final titleController =
        TextEditingController();

    DateTime selectedDate =
        _selectedDay;

    TimeOfDay selectedTime =
        TimeOfDay.now();

    PlanCategory selectedCategory =
        PlanCategory.task;

    bool reminderEnabled = false;

    int reminderMinutesBefore = 15;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme =
            Theme.of(context);

        final isDark =
            theme.brightness ==
                Brightness.dark;

        final surface = isDark
            ? const Color(0xFF171A1F)
            : Colors.white;

        final border = isDark
            ? const Color(0xFF2B2F36)
            : const Color(0xFFE5E7EB);

        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            return Padding(
              padding:
                  EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context)
                        .viewInsets
                        .bottom +
                    24,
              ),
              child:
                  SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [
                    Text(
                      'Yeni Plan',
                      style: theme
                          .textTheme
                          .titleLarge,
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    TextField(
                      controller:
                          titleController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Başlık',
                        hintText:
                            'Örn. Dişçi randevusu',
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    OutlinedButton.icon(
                      onPressed:
                          () async {
                        final picked =
                            await showDatePicker(
                          context:
                              context,
                          initialDate:
                              selectedDate,
                          firstDate:
                              DateTime(2020),
                          lastDate:
                              DateTime(2035),
                        );

                        if (picked ==
                            null) {
                          return;
                        }

                        setSheetState(
                          () {
                            selectedDate =
                                picked;
                          },
                        );
                      },
                      icon: const Icon(
                        Icons
                            .calendar_month_rounded,
                      ),
                      label: Text(
                        _prettyDate(
                          selectedDate,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    OutlinedButton.icon(
                      onPressed:
                          () async {
                        final picked =
                            await showTimePicker(
                          context:
                              context,
                          initialTime:
                              selectedTime,
                        );

                        if (picked ==
                            null) {
                          return;
                        }

                        setSheetState(
                          () {
                            selectedTime =
                                picked;
                          },
                        );
                      },
                      icon: const Icon(
                        Icons
                            .schedule_rounded,
                      ),
                      label: Text(
                        _formatTimeOfDay(
                          selectedTime,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    DropdownButtonFormField<
                        PlanCategory>(
                      initialValue:
                          selectedCategory,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Kategori',
                      ),
                      items: [
                        PlanCategory.task,
                        PlanCategory
                            .appointment,
                        PlanCategory
                            .meeting,
                        PlanCategory.study,
                        PlanCategory.payment,
                        PlanCategory
                            .personal,
                      ].map(
                        (category) {
                          return DropdownMenuItem<
                              PlanCategory>(
                            value:
                                category,
                            child: Text(
                              _categoryLabel(
                                category,
                              ),
                            ),
                          );
                        },
                      ).toList(),
                      onChanged:
                          (value) {
                        if (value ==
                            null) {
                          return;
                        }

                        setSheetState(
                          () {
                            selectedCategory =
                                value;
                          },
                        );
                      },
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Container(
                      padding:
                          const EdgeInsets
                              .fromLTRB(
                        14,
                        4,
                        14,
                        12,
                      ),
                      decoration:
                          BoxDecoration(
                        color: surface,
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                        border:
                            Border.all(
                          color:
                              border,
                        ),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                EdgeInsets
                                    .zero,
                            title:
                                const Text(
                              'Hatırlatıcı',
                            ),
                            subtitle:
                                Text(
                              reminderEnabled
                                  ? 'Ne kadar önce hatırlatayım?'
                                  : 'Hatırlatıcı kapalı',
                            ),
                            value:
                                reminderEnabled,
                            onChanged:
                                (value) {
                              setSheetState(
                                () {
                                  reminderEnabled =
                                      value;
                                },
                              );
                            },
                          ),

                          if (reminderEnabled)
                            ...[
                              const SizedBox(
                                height: 4,
                              ),

                              Align(
                                alignment:
                                    Alignment
                                        .centerLeft,
                                child:
                                    Text(
                                  'Hatırlatma zamanı',
                                  style: theme
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                    fontWeight:
                                        FontWeight
                                            .w600,
                                  ),
                                ),
                              ),

                              const SizedBox(
                                height: 10,
                              ),

                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label:
                                        const Text(
                                      '15 dk',
                                    ),
                                    selected:
                                        reminderMinutesBefore ==
                                            15,
                                    onSelected:
                                        (_) {
                                      setSheetState(
                                        () {
                                          reminderMinutesBefore =
                                              15;
                                        },
                                      );
                                    },
                                  ),

                                  ChoiceChip(
                                    label:
                                        const Text(
                                      '30 dk',
                                    ),
                                    selected:
                                        reminderMinutesBefore ==
                                            30,
                                    onSelected:
                                        (_) {
                                      setSheetState(
                                        () {
                                          reminderMinutesBefore =
                                              30;
                                        },
                                      );
                                    },
                                  ),

                                  ChoiceChip(
                                    label:
                                        const Text(
                                      '45 dk',
                                    ),
                                    selected:
                                        reminderMinutesBefore ==
                                            45,
                                    onSelected:
                                        (_) {
                                      setSheetState(
                                        () {
                                          reminderMinutesBefore =
                                              45;
                                        },
                                      );
                                    },
                                  ),

                                  ChoiceChip(
                                    label:
                                        const Text(
                                      '1 saat',
                                    ),
                                    selected:
                                        reminderMinutesBefore ==
                                            60,
                                    onSelected:
                                        (_) {
                                      setSheetState(
                                        () {
                                          reminderMinutesBefore =
                                              60;
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                        ],
                      ),
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    FilledButton(
                      onPressed:
                          () async {
                        final title =
                            titleController
                                .text
                                .trim();

                        if (title
                            .isEmpty) {
                          return;
                        }

                        final dateTime =
                            DateTime(
                          selectedDate
                              .year,
                          selectedDate
                              .month,
                          selectedDate
                              .day,
                          selectedTime
                              .hour,
                          selectedTime
                              .minute,
                        );

                        final plan =
                            Plan(
                          id: DateTime
                                  .now()
                              .millisecondsSinceEpoch
                              .toString(),
                          title: title,
                          dateTime:
                              dateTime,
                          category:
                              selectedCategory,
                          source:
                              PlanSource
                                  .manual,
                          isCompleted:
                              false,
                          reminderEnabled:
                              reminderEnabled,
                          reminderMinutesBefore:
                              reminderEnabled
                                  ? reminderMinutesBefore
                                  : null,
                          createdAt:
                              DateTime
                                  .now(),
                        );

                        try {
                          // Supabase'e kaydet.
                          await _eventService
                              .addPlan(
                            plan,
                          );

                          // Telefon bildirimini kur.
                          await _scheduleReminder(
                            plan,
                          );

                          if (!context
                              .mounted) {
                            return;
                          }

                          Navigator.of(
                            context,
                          ).pop();

                          setState(
                            () {
                              _selectedDay =
                                  selectedDate;
                              _focusedDay =
                                  selectedDate;
                            },
                          );

                          await refreshPlans();

                          if (!mounted) {
                            return;
                          }

                          ScaffoldMessenger
                                  .of(
                            this.context,
                          ).showSnackBar(
                            SnackBar(
                              content:
                                  Text(
                                reminderEnabled
                                    ? 'Plan eklendi • ${_reminderLabel(reminderMinutesBefore)} önce hatırlatılacak.'
                                    : 'Plan eklendi.',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!context
                              .mounted) {
                            return;
                          }

                          ScaffoldMessenger
                                  .of(
                            context,
                          ).showSnackBar(
                            SnackBar(
                              content:
                                  Text(
                                'Plan eklenemedi: $error',
                              ),
                            ),
                          );
                        }
                      },
                      child:
                          const Padding(
                        padding:
                            EdgeInsets
                                .symmetric(
                          vertical: 14,
                        ),
                        child: Text(
                          'Planı Kaydet',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
  }

  void _showPlanDetails(
    Plan plan,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme =
            Theme.of(context);

        final colors =
            theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets
                    .fromLTRB(
              20,
              8,
              20,
              24,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment
                      .stretch,
              children: [
                Text(
                  plan.title,
                  style: theme
                      .textTheme
                      .titleLarge,
                ),

                const SizedBox(
                  height: 8,
                ),

                Text(
                  plan.dateTime ==
                          null
                      ? 'Tarih henüz belirlenmedi'
                      : '${_prettyDate(plan.dateTime!)} • ${_formatTime(plan.dateTime!)}',
                  style: theme
                      .textTheme
                      .bodyMedium,
                ),

                const SizedBox(
                  height: 6,
                ),

                Text(
                  'Kategori: ${_categoryLabel(plan.category)}',
                  style: theme
                      .textTheme
                      .bodyMedium,
                ),

                if (plan.reminderEnabled &&
                    plan.reminderMinutesBefore !=
                        null) ...[
                  const SizedBox(
                    height: 8,
                  ),

                  Row(
                    children: [
                      Icon(
                        Icons
                            .notifications_active_outlined,
                        size: 18,
                        color:
                            colors.primary,
                      ),

                      const SizedBox(
                        width: 6,
                      ),

                      Text(
                        '${_reminderLabel(plan.reminderMinutesBefore!)} önce hatırlat',
                        style: theme
                            .textTheme
                            .bodyMedium,
                      ),
                    ],
                  ),
                ],

                const SizedBox(
                  height: 24,
                ),

                if (plan.dateTime !=
                    null) ...[
                  OutlinedButton.icon(
                    onPressed: () =>
                        _changeTime(
                      plan,
                    ),
                    icon: const Icon(
                      Icons
                          .schedule_rounded,
                    ),
                    label:
                        const Text(
                      'Saat Değiştir',
                    ),
                  ),

                  const SizedBox(
                    height: 10,
                  ),
                ],

                FilledButton.icon(
                  onPressed: () =>
                      _completePlan(
                    plan,
                  ),
                  icon: const Icon(
                    Icons
                        .check_circle_outline_rounded,
                  ),
                  label:
                      const Text(
                    'Tamamlandı',
                  ),
                ),

                const SizedBox(
                  height: 10,
                ),

                OutlinedButton.icon(
                  onPressed: () =>
                      _deletePlan(
                    plan,
                  ),
                  icon: const Icon(
                    Icons
                        .delete_outline_rounded,
                  ),
                  label:
                      const Text(
                    'Sil',
                  ),
                  style:
                      OutlinedButton
                          .styleFrom(
                    foregroundColor:
                        colors.error,
                    side: BorderSide(
                      color: colors
                          .error
                          .withValues(
                        alpha: 0.45,
                      ),
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

  String _reminderLabel(
    int minutes,
  ) {
    if (minutes == 60) {
      return '1 saat';
    }

    return '$minutes dakika';
  }

  bool _sameDay(
    DateTime a,
    DateTime b,
  ) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }

  List<Plan> _plansForDay(
    DateTime day,
  ) {
    final plans =
        _plans.where(
      (plan) {
        final date =
            plan.dateTime;

        if (date == null) {
          return false;
        }

        return _sameDay(
          date,
          day,
        );
      },
    ).toList();

    plans.sort(
      (a, b) =>
          a.dateTime!
              .compareTo(
        b.dateTime!,
      ),
    );

    return plans;
  }

  String _formatTime(
    DateTime date,
  ) {
    final hour =
        date.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minute =
        date.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$hour:$minute';
  }

  String _formatTimeOfDay(
    TimeOfDay time,
  ) {
    final hour =
        time.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minute =
        time.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$hour:$minute';
  }

  String _prettyDate(
    DateTime date,
  ) {
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

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _categoryLabel(
    PlanCategory category,
  ) {
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

  Widget _buildDayCell({
    required DateTime day,
    required bool selected,
    required bool today,
    required bool outside,
  }) {
    return DragTarget<Plan>(
      onAcceptWithDetails:
          (details) {
        _movePlanToDay(
          details.data,
          day,
        );
      },
      builder: (
        context,
        candidateData,
        rejectedData,
      ) {
        final theme =
            Theme.of(context);

        final colors =
            theme.colorScheme;

        final isDark =
            theme.brightness ==
                Brightness.dark;

        final isHovering =
            candidateData
                .isNotEmpty;

        final normalText =
            isDark
                ? const Color(
                    0xFFF4F4F6,
                  )
                : const Color(
                    0xFF17171A,
                  );

        final mutedText =
            isDark
                ? const Color(
                    0xFF666A73,
                  )
                : const Color(
                    0xFFB0B3BA,
                  );

        Color backgroundColor =
            Colors.transparent;

        Color textColor =
            outside
                ? mutedText
                : normalText;

        Border? border;

        if (today) {
          backgroundColor =
              colors.primary
                  .withValues(
            alpha: 0.12,
          );

          textColor =
              colors.primary;
        }

        if (selected) {
          backgroundColor =
              colors.primary;

          textColor =
              Colors.white;
        }

        if (isHovering) {
          backgroundColor =
              colors.primary
                  .withValues(
            alpha: 0.20,
          );

          textColor =
              colors.primary;

          border =
              Border.all(
            color:
                colors.primary,
            width: 2,
          );
        }

        return AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 120,
          ),
          margin:
              const EdgeInsets
                  .all(
            5,
          ),
          decoration:
              BoxDecoration(
            color:
                backgroundColor,
            shape:
                BoxShape.circle,
            border: border,
          ),
          alignment:
              Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(
              color:
                  textColor,
              fontWeight:
                  selected ||
                          today
                      ? FontWeight
                          .w700
                      : FontWeight
                          .w500,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final theme =
        Theme.of(context);

    final colors =
        theme.colorScheme;

    final isDark =
        theme.brightness ==
            Brightness.dark;

    final surface =
        isDark
            ? const Color(
                0xFF171A1F,
              )
            : Colors.white;

    final border =
        isDark
            ? const Color(
                0xFF2B2F36,
              )
            : const Color(
                0xFFE5E7EB,
              );

    final secondaryText =
        isDark
            ? const Color(
                0xFFA7A9B0,
              )
            : const Color(
                0xFF6B7280,
              );

    final selectedPlans =
        _plansForDay(
      _selectedDay,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Takvim',
          style: theme
              .textTheme
              .headlineLarge
              ?.copyWith(
            fontSize: 24,
          ),
        ),
      ),

      floatingActionButton:
          FloatingActionButton
              .extended(
        onPressed:
            _showAddPlanSheet,
        backgroundColor:
            colors.primary,
        foregroundColor:
            Colors.white,
        elevation: 0,
        icon: const Icon(
          Icons.add_rounded,
        ),
        label:
            const Text(
          'Plan Ekle',
        ),
      ),

      body:
          RefreshIndicator(
        onRefresh:
            refreshPlans,
        child: ListView(
          padding:
              const EdgeInsets
                  .fromLTRB(
            16,
            4,
            16,
            100,
          ),
          children: [
            Container(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                10,
                8,
                10,
                12,
              ),
              decoration:
                  BoxDecoration(
                color: surface,
                borderRadius:
                    BorderRadius
                        .circular(
                  18,
                ),
                border:
                    Border.all(
                  color: border,
                ),
              ),
              child:
                  TableCalendar<
                      Plan>(
                locale:
                    'tr_TR',

                firstDay:
                    DateTime.utc(
                  2020,
                  1,
                  1,
                ),

                lastDay:
                    DateTime.utc(
                  2035,
                  12,
                  31,
                ),

                focusedDay:
                    _focusedDay,

                selectedDayPredicate:
                    (day) {
                  return _sameDay(
                    day,
                    _selectedDay,
                  );
                },

                eventLoader:
                    _plansForDay,

                onDaySelected: (
                  selectedDay,
                  focusedDay,
                ) {
                  setState(
                    () {
                      _selectedDay =
                          selectedDay;

                      _focusedDay =
                          focusedDay;
                    },
                  );
                },

                onPageChanged:
                    (focusedDay) {
                  _focusedDay =
                      focusedDay;
                },

                headerStyle:
                    HeaderStyle(
                  formatButtonVisible:
                      false,
                  titleCentered:
                      true,
                  leftChevronIcon:
                      Icon(
                    Icons
                        .chevron_left_rounded,
                    color:
                        secondaryText,
                  ),
                  rightChevronIcon:
                      Icon(
                    Icons
                        .chevron_right_rounded,
                    color:
                        secondaryText,
                  ),
                  titleTextStyle:
                      TextStyle(
                    color: isDark
                        ? const Color(
                            0xFFF4F4F6,
                          )
                        : const Color(
                            0xFF17171A,
                          ),
                    fontSize: 16,
                    fontWeight:
                        FontWeight
                            .w700,
                  ),
                ),

                daysOfWeekStyle:
                    DaysOfWeekStyle(
                  weekdayStyle:
                      TextStyle(
                    color:
                        secondaryText,
                    fontSize: 12,
                    fontWeight:
                        FontWeight
                            .w600,
                  ),
                  weekendStyle:
                      TextStyle(
                    color:
                        secondaryText,
                    fontSize: 12,
                    fontWeight:
                        FontWeight
                            .w600,
                  ),
                ),

                calendarStyle:
                    CalendarStyle(
                  outsideDaysVisible:
                      true,
                  markerDecoration:
                      BoxDecoration(
                    color:
                        colors.primary,
                    shape:
                        BoxShape.circle,
                  ),
                  markersMaxCount:
                      3,
                  markerSize:
                      5,
                  markerMargin:
                      const EdgeInsets
                          .symmetric(
                    horizontal:
                        1,
                  ),
                ),

                calendarBuilders:
                    CalendarBuilders<
                        Plan>(
                  defaultBuilder: (
                    context,
                    day,
                    focusedDay,
                  ) {
                    return _buildDayCell(
                      day: day,
                      selected:
                          false,
                      today:
                          false,
                      outside:
                          false,
                    );
                  },

                  todayBuilder: (
                    context,
                    day,
                    focusedDay,
                  ) {
                    return _buildDayCell(
                      day: day,
                      selected:
                          false,
                      today:
                          true,
                      outside:
                          false,
                    );
                  },

                  selectedBuilder: (
                    context,
                    day,
                    focusedDay,
                  ) {
                    return _buildDayCell(
                      day: day,
                      selected:
                          true,
                      today:
                          false,
                      outside:
                          false,
                    );
                  },

                  outsideBuilder: (
                    context,
                    day,
                    focusedDay,
                  ) {
                    return _buildDayCell(
                      day: day,
                      selected:
                          false,
                      today:
                          false,
                      outside:
                          true,
                    );
                  },
                ),
              ),
            ),

            const SizedBox(
              height: 24,
            ),

            Row(
              children: [
                Expanded(
                  child: Text(
                    _prettyDate(
                      _selectedDay,
                    ),
                    style: theme
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                      fontSize:
                          20,
                    ),
                  ),
                ),

                TextButton.icon(
                  onPressed:
                      _showAddPlanSheet,
                  icon:
                      const Icon(
                    Icons
                        .add_rounded,
                  ),
                  label:
                      const Text(
                    'Ekle',
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 6,
            ),

            Text(
              'Tarihi değiştirmek için plana basılı tutup başka bir güne sürükle.',
              style: theme
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                color:
                    secondaryText,
                fontSize:
                    12,
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            if (_loading)
              const Center(
                child: Padding(
                  padding:
                      EdgeInsets
                          .all(
                    24,
                  ),
                  child:
                      CircularProgressIndicator(),
                ),
              )
            else if (selectedPlans
                .isEmpty)
              Container(
                padding:
                    const EdgeInsets
                        .all(
                  20,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      surface,
                  borderRadius:
                      BorderRadius
                          .circular(
                    16,
                  ),
                  border:
                      Border.all(
                    color:
                        border,
                  ),
                ),
                child: Text(
                  'Bu gün için plan yok.',
                  style: theme
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                    color:
                        secondaryText,
                  ),
                ),
              ),

            ...selectedPlans.map(
              (plan) => Padding(
                padding:
                    const EdgeInsets
                        .only(
                  bottom: 10,
                ),
                child:
                    LongPressDraggable<
                        Plan>(
                  data: plan,

                  feedback:
                      Material(
                    color: Colors
                        .transparent,
                    child:
                        Container(
                      width:
                          260,
                      padding:
                          const EdgeInsets
                              .all(
                        16,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            surface,
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                        border:
                            Border.all(
                          color:
                              colors
                                  .primary,
                        ),
                      ),
                      child:
                          Text(
                        plan.title,
                        style:
                            TextStyle(
                          color: isDark
                              ? const Color(
                                  0xFFF4F4F6,
                                )
                              : const Color(
                                  0xFF17171A,
                                ),
                          fontWeight:
                              FontWeight
                                  .w700,
                        ),
                      ),
                    ),
                  ),

                  childWhenDragging:
                      Opacity(
                    opacity:
                        0.35,
                    child:
                        _CalendarPlanCard(
                      plan:
                          plan,
                      time:
                          _formatTime(
                        plan.dateTime!,
                      ),
                      onTap:
                          () =>
                              _showPlanDetails(
                        plan,
                      ),
                    ),
                  ),

                  child:
                      _CalendarPlanCard(
                    plan:
                        plan,
                    time:
                        _formatTime(
                      plan.dateTime!,
                    ),
                    onTap:
                        () =>
                            _showPlanDetails(
                      plan,
                    ),
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

class _CalendarPlanCard
    extends StatelessWidget {
  final Plan plan;
  final String time;
  final VoidCallback onTap;

  const _CalendarPlanCard({
    required this.plan,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final theme =
        Theme.of(context);

    final colors =
        theme.colorScheme;

    final isDark =
        theme.brightness ==
            Brightness.dark;

    final surface =
        isDark
            ? const Color(
                0xFF171A1F,
              )
            : Colors.white;

    final border =
        isDark
            ? const Color(
                0xFF2B2F36,
              )
            : const Color(
                0xFFE5E7EB,
              );

    final secondaryText =
        isDark
            ? const Color(
                0xFFA7A9B0,
              )
            : const Color(
                0xFF6B7280,
              );

    return Material(
      color: surface,
      borderRadius:
          BorderRadius.circular(
        16,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        child: Container(
          padding:
              const EdgeInsets
                  .all(
            15,
          ),
          decoration:
              BoxDecoration(
            borderRadius:
                BorderRadius
                    .circular(
              16,
            ),
            border:
                Border.all(
              color: border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(
                  color: colors
                      .primary
                      .withValues(
                    alpha:
                        isDark
                            ? 0.14
                            : 0.09,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    12,
                  ),
                ),
                child: Icon(
                  Icons
                      .drag_indicator_rounded,
                  color:
                      colors.primary,
                ),
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      plan.title,
                      style: theme
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontSize:
                            15,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      '$time • ${_categoryLabelStatic(plan.category)}',
                      style: theme
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                        color:
                            secondaryText,
                        fontSize:
                            13,
                      ),
                    ),

                    if (plan.reminderEnabled &&
                        plan.reminderMinutesBefore !=
                            null) ...[
                      const SizedBox(
                        height: 4,
                      ),

                      Row(
                        children: [
                          Icon(
                            Icons
                                .notifications_none_rounded,
                            size: 14,
                            color:
                                colors
                                    .primary,
                          ),

                          const SizedBox(
                            width: 4,
                          ),

                          Text(
                            '${_reminderLabelStatic(plan.reminderMinutesBefore!)} önce',
                            style: theme
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                              color:
                                  secondaryText,
                              fontSize:
                                  11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              Icon(
                Icons
                    .chevron_right_rounded,
                color:
                    secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _reminderLabelStatic(
    int minutes,
  ) {
    if (minutes == 60) {
      return '1 saat';
    }

    return '$minutes dk';
  }

  static String _categoryLabelStatic(
    PlanCategory category,
  ) {
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
}