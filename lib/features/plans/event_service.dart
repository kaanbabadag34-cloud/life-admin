import 'package:supabase_flutter/supabase_flutter.dart';

import 'plan.dart';

class EventService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> addPlan(Plan plan) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase.from('events').insert({
      'user_id': user.id,
      'title': plan.title,
      'event_type': plan.category.name,
      'starts_at': plan.dateTime?.toUtc().toIso8601String(),
      'completed': plan.isCompleted,
      'reminder_enabled': plan.reminderEnabled,
      'reminder_minutes_before':
          plan.reminderEnabled ? plan.reminderMinutesBefore : null,
      'source': plan.source.name,
    });
  }

  Future<void> deletePlan(String id) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id);
  }

  Future<void> setCompleted({
    required String id,
    required bool completed,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .update({
          'completed': completed,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);
  }

  Future<void> updateDateTime({
    required String id,
    required DateTime dateTime,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .update({
          'starts_at':
              dateTime.toUtc().toIso8601String(),
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);
  }

  Future<void> updateReminder({
    required String id,
    required bool enabled,
    int? minutesBefore,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    await _supabase
        .from('events')
        .update({
          'reminder_enabled': enabled,
          'reminder_minutes_before':
              enabled ? minutesBefore : null,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);
  }

  Future<List<Plan>> getPlans() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Kullanıcı giriş yapmamış.');
    }

    final response = await _supabase
        .from('events')
        .select()
        .eq('user_id', user.id)
        .order(
          'starts_at',
          ascending: true,
          nullsFirst: false,
        );

    return response.map<Plan>((row) {
      return Plan(
        id: row['id'] as String,
        title: row['title'] as String,
        dateTime: row['starts_at'] == null
            ? null
            : DateTime.parse(
                row['starts_at'] as String,
              ).toLocal(),
        category: PlanCategory.values.firstWhere(
          (value) =>
              value.name == row['event_type'],
          orElse: () => PlanCategory.task,
        ),
        source: PlanSource.values.firstWhere(
          (value) =>
              value.name == row['source'],
          orElse: () => PlanSource.manual,
        ),
        isCompleted:
            row['completed'] as bool? ?? false,
        reminderEnabled:
            row['reminder_enabled'] as bool? ?? false,
        reminderMinutesBefore:
            (row['reminder_minutes_before'] as num?)
                ?.toInt(),
        createdAt: DateTime.parse(
          row['created_at'] as String,
        ).toLocal(),
      );
    }).toList();
  }
}