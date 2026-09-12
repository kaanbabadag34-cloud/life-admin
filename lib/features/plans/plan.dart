enum PlanCategory {
  appointment,
  task,
  payment,
  tracking,
  document,
  personal,
  study,
  meeting,
}

enum PlanSource {
  ai,
  manual,
}

class Plan {
  final String id;
  final String title;
  final DateTime? dateTime;
  final PlanCategory category;
  final PlanSource source;
  final bool isCompleted;

  // Hatırlatıcı açık / kapalı
  final bool reminderEnabled;

  // Kaç dakika önce hatırlatılacak?
  // Örn: 15, 30, 45, 60
  final int? reminderMinutesBefore;

  final DateTime createdAt;

  const Plan({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.category,
    required this.source,
    required this.isCompleted,
    required this.reminderEnabled,
    this.reminderMinutesBefore,
    required this.createdAt,
  });
}