import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();

  DateTime _selectedDate = DateTime.now();

  bool _loading = true;
  bool _saving = false;

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
    } catch (_) {}
  }

  Future<void> _loadEntryForSelectedDate() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    setState(() {
      _loading = true;
    });

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
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _controller.clear();
        _loading = false;
      });
    }
  }

  Future<void> _saveEntry() async {
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
          content: Text('Kaydedilemedi: $error'),
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
  }

  Future<void> _openEntry(DateTime date) async {
    setState(() {
      _selectedDate = date;
    });

    await _loadEntryForSelectedDate();
  }

  Future<void> _deleteEntry() async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

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
          content: Text('Silinemedi: $error'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Günlük',
          style: TextStyle(
            fontWeight: FontWeight.w700,
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
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _prettyDate(_selectedDate),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.black12,
                ),
              ),
              child: TextField(
                controller: _controller,
                minLines: 12,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText:
                      'Bugün ne oldu? Aklından geçenleri buraya yaz...',
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

          const Text(
            'Geçmiş Günlükler',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 12),

          if (_entries.isEmpty)
            const Text(
              'Henüz günlük kaydın yok.',
              style: TextStyle(
                color: Colors.black54,
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
                  color: Colors.white,
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
                          color: Colors.black12,
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
                                  style: const TextStyle(
                                    fontWeight:
                                        FontWeight.w700,
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
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.black38,
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