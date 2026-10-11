import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/confirm_dialog.dart';
import '../../utils/error_messages.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  DateTime _selectedDate = DateTime.now();

  bool _loading = true;
  bool _saving = false;
  // Sadece ilk yüklemede spinner göster — sonraki her _loadEntryForSelectedDate
  // çağrısında (tarih değiştirme, geçmiş kayıt açma) tekrar _loading=true
  // yapmak, editör kartını anlık olarak küçültüp büyütüyor ve bu da
  // sayfanın yukarı-aşağı zıplamış gibi görünmesine sebep oluyordu.
  bool _hasLoadedEntryOnce = false;

  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadAllEntries();
    _loadEntryForSelectedDate();
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

  Future<void> _loadAllEntries() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    try {
      final response = await _supabase
          .from('journal_entries')
          .select()
          .eq('user_id', user.id)
          .order('entry_date', ascending: false);

      if (!mounted) return;

      setState(() {
        _entries = List<Map<String, dynamic>>.from(response);
      });
    } catch (error) {
      debugPrint('Hata detayı: $error');
    }
  }

  Future<void> _loadEntryForSelectedDate() async {
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

    if (mounted && !_hasLoadedEntryOnce) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final response = await _supabase
          .from('journal_entries')
          .select()
          .eq('user_id', user.id)
          .eq('entry_date', _dateKey(_selectedDate))
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _controller.text = response?['content']?.toString() ?? '';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _controller.clear();
      });
    } finally {
      // Başarı, hata veya erken çıkış — loading state her durumda kapanır.
      if (mounted) {
        setState(() {
          _loading = false;
          _hasLoadedEntryOnce = true;
        });
      }
    }
  }

  Future<void> _saveEntry() async {
    // Kaydet'e basılır basılmaz klavye kapanmalı — sonucu beklemeden.
    FocusScope.of(context).unfocus();

    final user = _supabase.auth.currentUser;

    if (user == null) return;

    final content = _controller.text.trim();

    setState(() {
      _saving = true;
    });

    try {
      await _supabase.from('journal_entries').upsert(
        {
          'user_id': user.id,
          'entry_date': _dateKey(_selectedDate),
          'content': content,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,entry_date',
      );

      await _loadAllEntries();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Günlük kaydedildi.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Günlük kaydedilemedi. Tekrar deneyin.'),
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked == null) return;

    setState(() {
      _selectedDate = picked;
    });

    await _loadEntryForSelectedDate();
    _scrollEditorIntoView();
  }

  Future<void> _openEntry(DateTime date) async {
    setState(() {
      _selectedDate = date;
    });

    await _loadEntryForSelectedDate();
    _scrollEditorIntoView();
  }

  // "Geçmiş Günlükler" listesinde aşağı kaydırılmışken bir kayıt açıldığında,
  // yüklenen içerik yukarıdaki editör kartına yazılıyor ama kullanıcının
  // scroll pozisyonu hâlâ aşağıdaydı — bu yüzden "hiçbir şey olmuyor" gibi
  // görünüyordu. Yumuşak bir scroll ile editörü görünür hale getiriyoruz.
  void _scrollEditorIntoView() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _deleteEntry() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    final confirmed = await showPremiumConfirmDialog(
      context,
      title: 'Günlüğü sil',
      message: 'Bu tarihteki günlük kaydı silinecek. Bu işlem geri alınamaz.',
    );

    if (!confirmed) return;

    try {
      await _supabase
          .from('journal_entries')
          .delete()
          .eq('user_id', user.id)
          .eq('entry_date', _dateKey(_selectedDate));

      _controller.clear();

      await _loadAllEntries();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Günlük silindi.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Günlük silinemedi. Tekrar deneyin.'),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF171A1F) : Colors.white;
    final border = isDark ? const Color(0xFF2B2F36) : Colors.black12;
    final secondaryText = isDark
        ? const Color(0xFFA7A9B0)
        : const Color(0xFF6B7280);
    final titleColor = isDark ? Colors.white : const Color(0xFF17171A);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Günlük',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: titleColor,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(
              Icons.calendar_month_rounded,
            ),
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _prettyDate(_selectedDate),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: titleColor,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(
                  Icons.edit_calendar_outlined,
                ),
                label: const Text(
                  'Tarih seç',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: border,
                ),
              ),
              child: TextField(
                controller: _controller,
                minLines: 12,
                maxLines: null,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.5,
                  color: titleColor,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Bugün ne oldu? Aklından geçenleri buraya yaz...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: secondaryText,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveEntry,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.save_outlined,
                        ),
                  label: Text(
                    _saving
                        ? 'Kaydediliyor'
                        : 'Kaydet',
                  ),
                ),
              ),

              const SizedBox(width: 10),

              IconButton.filledTonal(
                onPressed: _deleteEntry,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          Text(
            'Geçmiş Günlükler',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: titleColor,
            ),
          ),

          const SizedBox(height: 12),

          if (_entries.isEmpty)
            Text(
              'Henüz günlük kaydın yok.',
              style: TextStyle(
                color: secondaryText,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),

          ..._entries.map(
            (entry) {
              final rawDate = entry['entry_date']?.toString();

              if (rawDate == null) {
                return const SizedBox.shrink();
              }

              final date = DateTime.parse(rawDate);
              final content =
                  entry['content']?.toString() ?? '';

              return Padding(
                padding: const EdgeInsets.only(
                  bottom: 10,
                ),
                child: Material(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openEntry(date),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(18),
                        border: Border.all(
                          color: border,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.menu_book_outlined,
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _prettyDate(date),
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Text(
                                  content.isEmpty
                                      ? 'Boş günlük'
                                      : content,
                                  maxLines: 2,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 12.5,
                                    height: 1.3,
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
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}