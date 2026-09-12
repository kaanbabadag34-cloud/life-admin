import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CountdownPage extends StatefulWidget {
  const CountdownPage({super.key});

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _countdowns = [];

  @override
  void initState() {
    super.initState();
    _loadCountdowns();
  }

  Future<void> _loadCountdowns() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    try {
      final response = await _supabase
          .from('countdowns')
          .select()
          .eq('user_id', user.id)
          .order(
            'target_date',
            ascending: true,
          );

      if (!mounted) return;

      setState(() {
        _countdowns =
            List<Map<String, dynamic>>.from(response);

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sayaçlar yüklenemedi: $error',
          ),
        ),
      );
    }
  }

  String _dateKey(DateTime date) {
    final year =
        date.year.toString().padLeft(4, '0');

    final month =
        date.month.toString().padLeft(2, '0');

    final day =
        date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  String _prettyDate(DateTime date) {
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

  int _daysDifference(DateTime target) {
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final targetDay = DateTime(
      target.year,
      target.month,
      target.day,
    );

    return targetDay.difference(today).inDays;
  }

  String _countdownText(DateTime target) {
    final days = _daysDifference(target);

    if (days > 1) {
      return '$days gün kaldı';
    }

    if (days == 1) {
      return 'Yarın';
    }

    if (days == 0) {
      return 'Bugün 🎉';
    }

    if (days == -1) {
      return 'Dün';
    }

    return '${days.abs()} gün önceydi';
  }

  Future<void> _createCountdown({
    required String title,
    required DateTime targetDate,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null || _saving) return;

    setState(() {
      _saving = true;
    });

    try {
      await _supabase.from('countdowns').insert({
        'user_id': user.id,
        'title': title,
        'target_date': _dateKey(targetDate),
      });

      await _loadCountdowns();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sayaç oluşturuldu.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sayaç oluşturulamadı: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteCountdown(
    String id,
  ) async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    try {
      await _supabase
          .from('countdowns')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id);

      await _loadCountdowns();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sayaç silindi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sayaç silinemedi: $error',
          ),
        ),
      );
    }
  }

  Future<void> _showAddCountdown({
    String initialTitle = '',
    DateTime? initialDate,
  }) async {
    final controller = TextEditingController(
      text: initialTitle,
    );

    DateTime? selectedDate = initialDate;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context)
                        .viewInsets
                        .bottom +
                    24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Yeni Sayaç',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                  TextField(
                    controller: controller,
                    decoration:
                        const InputDecoration(
                      labelText: 'Sayaç adı',
                      hintText: 'Örn. Tatil',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(
                    height: 14,
                  ),

                  OutlinedButton.icon(
                    onPressed: () async {
                      final now =
                          DateTime.now();

                      final picked =
                          await showDatePicker(
                        context: context,
                        initialDate:
                            selectedDate ??
                                now.add(
                                  const Duration(
                                    days: 30,
                                  ),
                                ),
                        firstDate: DateTime(
                          now.year - 1,
                        ),
                        lastDate: DateTime(
                          now.year + 15,
                        ),
                      );

                      if (picked == null) {
                        return;
                      }

                      setSheetState(() {
                        selectedDate = picked;
                      });
                    },
                    icon: const Icon(
                      Icons
                          .calendar_month_rounded,
                    ),
                    label: Text(
                      selectedDate == null
                          ? 'Tarih Seç'
                          : _prettyDate(
                              selectedDate!,
                            ),
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  FilledButton(
                    onPressed: () async {
                      final title =
                          controller.text.trim();

                      if (title.isEmpty ||
                          selectedDate == null) {
                        return;
                      }

                      Navigator.of(context)
                          .pop();

                      await _createCountdown(
                        title: title,
                        targetDate:
                            selectedDate!,
                      );
                    },
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                      child: Text(
                        'Sayaç Oluştur',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  List<_QuickCountdown>
      get _quickCountdowns {
    return [
      _QuickCountdown(
        emoji: '❤️',
        title: 'Sevgililer Günü',
        date: DateTime(
          2027,
          2,
          14,
        ),
      ),

      _QuickCountdown(
        emoji: '👩',
        title: 'Anneler Günü',
        date: DateTime(
          2027,
          5,
          9,
        ),
      ),

      _QuickCountdown(
        emoji: '🐑',
        title: 'Kurban Bayramı',
        date: DateTime(
          2027,
          5,
          16,
        ),
      ),

      _QuickCountdown(
        emoji: '👨',
        title: 'Babalar Günü',
        date: DateTime(
          2027,
          6,
          20,
        ),
      ),

      _QuickCountdown(
        emoji: '🎓',
        title: 'YKS 2027',
        date: null,
      ),

      _QuickCountdown(
        emoji: '🎄',
        title: 'Yılbaşı',
        date: DateTime(
          2027,
          1,
          1,
        ),
      ),

      _QuickCountdown(
        emoji: '🌙',
        title: 'Ramazan Bayramı',
        date: DateTime(
          2027,
          3,
          9,
        ),
      ),
    ];
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sayaç',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () {
          _showAddCountdown();
        },
        icon: const Icon(
          Icons.add_rounded,
        ),
        label: const Text(
          'Sayaç Ekle',
        ),
      ),

      body: RefreshIndicator(
        onRefresh: _loadCountdowns,
        child: ListView(
          padding:
              const EdgeInsets.fromLTRB(
            20,
            10,
            20,
            100,
          ),
          children: [
            const Text(
              'Hızlı Ekle',
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.w700,
              ),
            ),

            const SizedBox(
              height: 6,
            ),

            const Text(
              'Popüler tarihlerden birini seç veya kendi sayacını oluştur.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 13,
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            SizedBox(
              height: 118,
              child:
                  ListView.separated(
                scrollDirection:
                    Axis.horizontal,
                itemCount:
                    _quickCountdowns.length,

                separatorBuilder: (
                  context,
                  index,
                ) {
                  return const SizedBox(
                    width: 10,
                  );
                },

                itemBuilder: (
                  context,
                  index,
                ) {
                  final quick =
                      _quickCountdowns[
                          index];

                  return InkWell(
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                    onTap: () {
                      _showAddCountdown(
                        initialTitle:
                            quick.title,
                        initialDate:
                            quick.date,
                      );
                    },
                    child: Container(
                      width: 150,
                      padding:
                          const EdgeInsets
                              .all(16),
                      decoration:
                          BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius
                                .circular(
                          18,
                        ),
                        border:
                            Border.all(
                          color:
                              Colors.black12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            quick.emoji,
                            style:
                                const TextStyle(
                              fontSize: 25,
                            ),
                          ),

                          const Spacer(),

                          Text(
                            quick.title,
                            maxLines: 2,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(
              height: 30,
            ),

            const Text(
              'Sayaçlarım',
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.w700,
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            if (_loading)
              const Center(
                child: Padding(
                  padding:
                      EdgeInsets.all(30),
                  child:
                      CircularProgressIndicator(),
                ),
              )
            else if (_countdowns.isEmpty)
              Container(
                padding:
                    const EdgeInsets.all(
                  22,
                ),
                decoration:
                    BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                  border: Border.all(
                    color:
                        Colors.black12,
                  ),
                ),
                child:
                    const Column(
                  children: [
                    Icon(
                      Icons
                          .hourglass_empty_rounded,
                      size: 34,
                    ),

                    SizedBox(
                      height: 10,
                    ),

                    Text(
                      'Henüz sayaç yok.',
                      style: TextStyle(
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),

                    SizedBox(
                      height: 5,
                    ),

                    Text(
                      'Yukarıdaki önerilerden birini seçebilir veya yeni sayaç oluşturabilirsin.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            ..._countdowns.map(
              (countdown) {
                final target =
                    DateTime.parse(
                  countdown[
                          'target_date']
                      .toString(),
                );

                return Padding(
                  padding:
                      const EdgeInsets
                          .only(
                    bottom: 12,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets
                            .all(18),
                    decoration:
                        BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius
                              .circular(
                        20,
                      ),
                      border:
                          Border.all(
                        color:
                            Colors.black12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration:
                              BoxDecoration(
                            color:
                                Colors.black
                                    .withValues(
                              alpha:
                                  0.06,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              16,
                            ),
                          ),
                          child:
                              const Icon(
                            Icons
                                .hourglass_bottom_rounded,
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
                                countdown[
                                        'title']
                                    .toString(),
                                style:
                                    const TextStyle(
                                  fontSize:
                                      16,
                                  fontWeight:
                                      FontWeight
                                          .w700,
                                ),
                              ),

                              const SizedBox(
                                height: 5,
                              ),

                              Text(
                                _countdownText(
                                  target,
                                ),
                                style:
                                    const TextStyle(
                                  fontSize:
                                      20,
                                  fontWeight:
                                      FontWeight
                                          .w800,
                                ),
                              ),

                              const SizedBox(
                                height: 4,
                              ),

                              Text(
                                _prettyDate(
                                  target,
                                ),
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.black54,
                                  fontSize:
                                      12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          onPressed: () {
                            _deleteCountdown(
                              countdown['id']
                                  .toString(),
                            );
                          },
                          icon: const Icon(
                            Icons
                                .delete_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCountdown {
  final String emoji;
  final String title;
  final DateTime? date;

  const _QuickCountdown({
    required this.emoji,
    required this.title,
    required this.date,
  });
}