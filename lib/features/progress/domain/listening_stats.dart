class DailyListening {
  const DailyListening({required this.date, required this.seconds});

  factory DailyListening.fromJson(Map<String, dynamic> json) {
    return DailyListening(
      date: DateTime.parse(json['date'] as String),
      seconds: json['seconds'] as int,
    );
  }

  final DateTime date;
  final int seconds;
}

class ListeningStats {
  const ListeningStats({
    required this.todaySeconds,
    required this.totalSeconds,
    required this.streakDays,
    required this.daily,
  });

  factory ListeningStats.fromJson(Map<String, dynamic> json) {
    return ListeningStats(
      todaySeconds: json['today_seconds'] as int,
      totalSeconds: json['total_seconds'] as int,
      streakDays: json['streak_days'] as int,
      daily: (json['daily'] as List<dynamic>)
          .map((item) => DailyListening.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  static const empty = ListeningStats(
    todaySeconds: 0,
    totalSeconds: 0,
    streakDays: 0,
    daily: [],
  );

  final int todaySeconds;
  final int totalSeconds;
  final int streakDays;
  final List<DailyListening> daily;

  ListeningStats addLocalSecond(DateTime today) {
    final updated = daily
        .map(
          (day) => _sameDay(day.date, today)
              ? DailyListening(date: day.date, seconds: day.seconds + 1)
              : day,
        )
        .toList();
    return ListeningStats(
      todaySeconds: todaySeconds + 1,
      totalSeconds: totalSeconds + 1,
      streakDays: todaySeconds == 0 ? streakDays + 1 : streakDays,
      daily: updated,
    );
  }

  static bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
