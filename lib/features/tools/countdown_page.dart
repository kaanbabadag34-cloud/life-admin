import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/confirm_dialog.dart';
import '../../utils/error_messages.dart';

class CountdownPage extends StatefulWidget {
  const CountdownPage({super.key});

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

enum _CountdownSort { newest, upcoming }

class _CountdownPageState extends State<CountdownPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _countdowns = [];

  // Referanstaki "En Yeni" açılır menüsü — sunucudan yeni bir sorgu
  // ATMADAN, zaten çekilmiş _countdowns listesini yerel olarak sıralar.
  _CountdownSort _sort = _CountdownSort.newest;

  List<Map<String, dynamic>> get _sortedCountdowns {
    final list = List<Map<String, dynamic>>.from(_countdowns);

    if (_sort == _CountdownSort.newest) {
      list.sort((a, b) {
        final aCreated = a['created_at']?.toString() ?? '';
        final bCreated = b['created_at']?.toString() ?? '';
        return bCreated.compareTo(aCreated);
      });
    } else {
      list.sort((a, b) {
        final aDate = a['target_date']?.toString() ?? '';
        final bDate = b['target_date']?.toString() ?? '';
        return aDate.compareTo(bDate);
      });
    }

    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadCountdowns();
  }

  Future<void> _loadCountdowns() async {
    final user = _supabase.auth.currentUser;

    // Kullanıcı yoksa dahi loading state kapanmalı — aksi halde ekran
    // sonsuza kadar spinner'da takılı kalır.
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    try {
      final response = await _supabase
          .from('countdowns')
          .select()
          .eq('user_id', user.id)
          .order('target_date', ascending: true);

      if (!mounted) return;

      setState(() {
        _countdowns = List<Map<String, dynamic>>.from(response);
      });
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Sayaçlar yüklenemedi. Tekrar deneyin.',
            ),
          ),
        ),
      );
    } finally {
      // Başarı, hata veya erken çıkış — loading state her durumda kapanır.
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');

    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

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

    final today = DateTime(now.year, now.month, now.day);

    final targetDay = DateTime(target.year, target.month, target.day);

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

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sayaç oluşturuldu.')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Sayaç oluşturulamadı. Tekrar deneyin.',
            ),
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

  Future<void> _deleteCountdown(String id) async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    final confirmed = await showPremiumConfirmDialog(
      context,
      title: 'Sayacı sil',
      message: 'Bu sayaç silinecek. Bu işlem geri alınamaz.',
    );

    if (!confirmed) return;

    try {
      await _supabase
          .from('countdowns')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id);

      await _loadCountdowns();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sayaç silindi.')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Sayaç silinemedi. Tekrar deneyin.'),
          ),
        ),
      );
    }
  }

  Future<void> _showAddCountdown({
    String initialTitle = '',
    DateTime? initialDate,
  }) async {
    final controller = TextEditingController(text: initialTitle);

    DateTime? selectedDate = initialDate;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Yeni Sayaç',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Sayaç adı',
                      hintText: 'Örn. Tatil',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();

                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            selectedDate ?? now.add(const Duration(days: 30)),
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 15),
                      );

                      if (picked == null) {
                        return;
                      }

                      setSheetState(() {
                        selectedDate = picked;
                      });
                    },
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(
                      selectedDate == null
                          ? 'Tarih Seç'
                          : _prettyDate(selectedDate!),
                    ),
                  ),

                  const SizedBox(height: 18),

                  FilledButton(
                    onPressed: () async {
                      final title = controller.text.trim();

                      if (title.isEmpty || selectedDate == null) {
                        return;
                      }

                      Navigator.of(context).pop();

                      await _createCountdown(
                        title: title,
                        targetDate: selectedDate!,
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Sayaç Oluştur'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Sheet'in kapanış (reverse) animasyonu bittiğinde controller hâlâ
    // TextField tarafından kullanılıyor olabilir — showModalBottomSheet'in
    // Future'ı pop() anında tamamlanır, animasyon bitmeden. Hemen dispose
    // etmek "TextEditingController was used after being disposed" hatasını
    // (Flutter kırmızı hata ekranı) tetikliyordu. Animasyon süresinden
    // sonra dispose ederek bu race condition'ı ortadan kaldırıyoruz.
    Future.delayed(const Duration(milliseconds: 300), controller.dispose);
  }

  // Referanstaki "Öne Çıkan Sayaçlar" kartı — eskiden sayfada satır içi
  // yatay kaydırmalı bir şerit olan hızlı-ekle önerileri artık burada,
  // tek bir özet kart + bunu açan bir alt sayfa olarak sunuluyor. Altta
  // yatan işlev (mevcut _quickCountdowns listesi + _showAddCountdown)
  // birebir aynı, sadece giriş noktası değişti.
  void _openFeaturedCountdowns() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FeaturedCountdownsSheet(
        items: _quickCountdowns,
        onSelect: (quick) {
          Navigator.of(context).pop();
          _showAddCountdown(initialTitle: quick.title, initialDate: quick.date);
        },
      ),
    );
  }

  // "Sayaçlarım" listesindeki her kart aynı jenerik kum saati ikonunu
  // gösteriyordu (placeholder gibi duruyordu). Sayaç, hazır önerilerden
  // biriyle (aynı başlıkla) oluşturulduysa artık o önerinin kendi emojisini
  // gösteriyor; eşleşme yoksa mevcut kum saati ikonu fallback olarak kalıyor.
  String? _emojiForCountdownTitle(String title) {
    final normalized = title.trim().toLowerCase();

    for (final quick in _quickCountdowns) {
      if (quick.title.trim().toLowerCase() == normalized) {
        return quick.emoji;
      }
    }

    return null;
  }

  List<_QuickCountdown> get _quickCountdowns {
    return [
      _QuickCountdown(
        emoji: '❤️',
        title: 'Sevgililer Günü',
        date: DateTime(2027, 2, 14),
      ),

      _QuickCountdown(
        emoji: '👩',
        title: 'Anneler Günü',
        date: DateTime(2027, 5, 9),
      ),

      _QuickCountdown(
        emoji: '🐑',
        title: 'Kurban Bayramı',
        date: DateTime(2027, 5, 16),
      ),

      _QuickCountdown(
        emoji: '👨',
        title: 'Babalar Günü',
        date: DateTime(2027, 6, 20),
      ),

      _QuickCountdown(
        emoji: '🎓',
        title: 'YKS 2027',
        date: DateTime(2027, 6, 19),
      ),

      _QuickCountdown(
        emoji: '🎄',
        title: 'Yılbaşı',
        date: DateTime(2027, 1, 1),
      ),

      _QuickCountdown(
        emoji: '🌙',
        title: 'Ramazan Bayramı',
        date: DateTime(2027, 3, 9),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF0B0B0D)
        : const Color(0xFFF7F7FA);
    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : Colors.black12;
    final secondaryText = isDark ? const Color(0xFFA7A9B0) : Colors.black54;
    final titleColor = isDark ? Colors.white : const Color(0xFF17171A);
    final accent = colors.primary;

    final sorted = _sortedCountdowns;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          'Sayaç',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: titleColor,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: titleColor),
            onSelected: (value) {
              if (value == 'refresh') _loadCountdowns();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'refresh', child: Text('Yenile')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),

      floatingActionButton: _GlowingAddButton(
        accent: accent,
        onPressed: _showAddCountdown,
      ),

      body: RefreshIndicator(
        onRefresh: _loadCountdowns,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
          children: [
            Text(
              'Zamana değer kat. Her şeyin bir sayacı olsun.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryText,
                fontSize: 14.5,
              ),
            ),

            const SizedBox(height: 20),

            _FeaturedCountdownsCard(
              accent: accent,
              items: _quickCountdowns,
              onTap: _openFeaturedCountdowns,
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sayaçlarım',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                PopupMenuButton<_CountdownSort>(
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _CountdownSort.newest,
                      child: Text('En Yeni'),
                    ),
                    PopupMenuItem(
                      value: _CountdownSort.upcoming,
                      child: Text('Yaklaşan'),
                    ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _sort == _CountdownSort.newest ? 'En Yeni' : 'Yaklaşan',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (sorted.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 36,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.hourglass_empty_rounded,
                        size: 28,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Henüz sayaç yok.',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hayatındaki önemli günleri takip etmek için ilk sayacını oluştur.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

            ...sorted.map((countdown) {
              final target = DateTime.parse(
                countdown['target_date'].toString(),
              );
              final title = countdown['title'].toString();
              final matchedEmoji = _emojiForCountdownTitle(title);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: accent.withValues(
                                alpha: isDark ? 0.16 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: matchedEmoji != null
                                ? Text(
                                    matchedEmoji,
                                    style: const TextStyle(fontSize: 24),
                                  )
                                : Icon(
                                    Icons.hourglass_bottom_rounded,
                                    color: accent,
                                  ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _countdownText(target),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _prettyDate(target),
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Küçük, sade, iOS tarzı silme butonu — kartın sağ üst
                    // köşesinde. Görsel çap ~30dp ama InkWell'in tap alanı
                    // da aynı boyutta olduğu için yanlışlıkla basılmayacak
                    // kadar erişilebilir kalıyor.
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Material(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            _deleteCountdown(countdown['id'].toString());
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 15,
                              color: secondaryText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// Referanstaki büyük, mor glow'lu "+ Sayaç Ekle" CTA'sı — Material'ın
// varsayılan FloatingActionButton.extended görünümü yerine.
class _GlowingAddButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onPressed;

  const _GlowingAddButton({required this.accent, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.45),
            blurRadius: 26,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: accent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Sayaç Ekle',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Referanstaki "Öne Çıkan Sayaçlar" özet kartı — solda ilk 3 hızlı-ekle
// önerisinin emoji önizlemesi + bir "..." karosu, sağda açıklama ve ok
// butonu. Dokununca TÜM önerileri listeleyen bir alt sayfa açılır;
// mevcut hızlı-ekle işlevi (_showAddCountdown ile) birebir korunuyor.
class _FeaturedCountdownsCard extends StatelessWidget {
  final Color accent;
  final List<_QuickCountdown> items;
  final VoidCallback onTap;

  const _FeaturedCountdownsCard({
    required this.accent,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF17171A);
    final descColor = isDark
        ? const Color(0xFFB9BAC2)
        : const Color(0xFF5B5B66);
    final preview = items.take(3).toList();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.22 : 0.12),
                accent.withValues(alpha: isDark ? 0.08 : 0.05),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.4 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                blurRadius: 24,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: GridView.count(
                  crossAxisCount: 2,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: [
                    for (final quick in preview)
                      _EmojiTile(
                        emoji: quick.emoji,
                        accent: accent,
                        isDark: isDark,
                      ),
                    _EmojiTile(emoji: null, accent: accent, isDark: isDark),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Öne Çıkan Sayaçlar',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Senin için önemli olan günleri tek ekranda gör.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: descColor,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ArrowCircle(accent: accent, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  final String? emoji;
  final Color accent;
  final bool isDark;

  const _EmojiTile({
    required this.emoji,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.3 : 0.18),
        ),
      ),
      alignment: Alignment.center,
      child: emoji == null
          ? Icon(Icons.more_horiz_rounded, size: 18, color: accent)
          : Text(emoji!, style: const TextStyle(fontSize: 18)),
    );
  }
}

class _ArrowCircle extends StatelessWidget {
  final Color accent;
  final bool isDark;

  const _ArrowCircle({required this.accent, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white,
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.4 : 0.25),
        ),
      ),
      child: Icon(Icons.chevron_right_rounded, size: 20, color: accent),
    );
  }
}

// "Öne Çıkan Sayaçlar" kartına dokununca açılan, TÜM hızlı-ekle
// önerilerini listeleyen alt sayfa.
class _FeaturedCountdownsSheet extends StatelessWidget {
  final List<_QuickCountdown> items;
  final ValueChanged<_QuickCountdown> onSelect;

  const _FeaturedCountdownsSheet({required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF17171A);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Öne Çıkan Sayaçlar',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final quick = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(
                      quick.emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(
                      quick.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    onTap: () => onSelect(quick),
                  );
                },
              ),
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
