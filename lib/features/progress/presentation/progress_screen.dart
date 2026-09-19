import 'package:flutter/material.dart';

import '../../../core/widgets/glass_surface.dart';
import '../application/listening_controller.dart';
import '../domain/listening_stats.dart';
import '../domain/review_sentence.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({
    super.key,
    required this.controller,
    this.onReviewSentence,
  });

  final ListeningController controller;
  final void Function(ReviewSentence sentence)? onReviewSentence;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          final stats = controller.stats;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                automaticallyImplyLeading: false,
                toolbarHeight: 52,
                actions: [
                  IconButton(
                    tooltip: '刷新统计',
                    onPressed: controller.isLoading ? null : controller.load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  hazeScreenInset,
                  0,
                  hazeScreenInset,
                  130,
                ),
                sliver: SliverList.list(
                  children: [
                    if (controller.isLoading && stats.daily.isEmpty)
                      const LinearProgressIndicator(),
                    GlassSurface(
                      borderRadius: BorderRadius.circular(26),
                      blur: 24,
                      tint: Colors.white.withValues(alpha: 0.62),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Row(
                          children: [
                            _MetricCard(
                              icon: _CalendarDayIcon(day: DateTime.now().day),
                              value: _formatDuration(stats.todaySeconds),
                            ),
                            const _MetricDivider(),
                            _MetricCard(
                              icon: const Icon(
                                Icons.local_fire_department_rounded,
                              ),
                              value: '${stats.streakDays} 天',
                            ),
                            const _MetricDivider(),
                            _MetricCard(
                              icon: const Icon(Icons.timer_outlined),
                              value: _formatDuration(stats.totalSeconds),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _MonthHeatmap(month: DateTime.now(), daily: stats.daily),
                    const SizedBox(height: 14),
                    GlassSurface(
                      borderRadius: BorderRadius.circular(26),
                      blur: 24,
                      tint: Colors.white.withValues(alpha: 0.62),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '需要再听的句子',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '单句循环听完一次，就会自动记在这里。点一句回到原音频。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (controller.reviewSentences.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Text('还没有反复听过的句子'),
                              ),
                            for (final sentence in controller.reviewSentences)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  sentence.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${sentence.episodeTitle} · 循环 ${sentence.repeatCount} 次',
                                ),
                                onTap: onReviewSentence == null
                                    ? null
                                    : () => onReviewSentence!(sentence),
                                trailing: IconButton(
                                  tooltip: '从复习列表移除',
                                  icon: const Icon(Icons.check_rounded),
                                  onPressed: () =>
                                      controller.removeReviewSentence(sentence),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '$minutes 分钟';
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.value});

  final Widget icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          IconTheme(
            data: IconThemeData(size: 25, color: colors.primary),
            child: icon,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CalendarDayIcon extends StatelessWidget {
  const _CalendarDayIcon({required this.day});

  final int day;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 29,
      height: 27,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.72), width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.82),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(5),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 64,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _MonthHeatmap extends StatelessWidget {
  const _MonthHeatmap({required this.month, required this.daily});

  final DateTime month;
  final List<DailyListening> daily;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmptyCells = firstDay.weekday - 1;
    final cellCount = leadingEmptyCells + daysInMonth;
    final secondsByDay = {
      for (final item in daily)
        if (item.date.year == month.year && item.date.month == month.month)
          item.date.day: item.seconds,
    };
    return GlassSurface(
      borderRadius: BorderRadius.circular(26),
      blur: 24,
      tint: Colors.white.withValues(alpha: 0.62),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '听力日历',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const _WeekdayHeader(),
            const SizedBox(height: 5),
            GridView.builder(
              padding: EdgeInsets.zero,
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.18,
              ),
              itemBuilder: (context, index) {
                final day = index - leadingEmptyCells + 1;
                if (day < 1 || day > daysInMonth) {
                  return const SizedBox.shrink();
                }
                return _HeatDay(
                  date: DateTime(month.year, month.month, day),
                  seconds: secondsByDay[day] ?? 0,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const ['一', '二', '三', '四', '五', '六', '日']
          .map(
            (day) => Expanded(
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _HeatDay extends StatelessWidget {
  const _HeatDay({required this.date, required this.seconds});

  final DateTime date;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isFuture = date.isAfter(DateTime(now.year, now.month, now.day));
    final intensity = _heatIntensity(seconds);
    final colors = Theme.of(context).colorScheme;
    final glassColor = isFuture
        ? Colors.white.withValues(alpha: 0.20)
        : Color.lerp(
            Colors.white.withValues(alpha: 0.50),
            const Color(0xFF85858B).withValues(alpha: 0.76),
            intensity,
          )!;
    final foreground = intensity >= 0.65
        ? colors.onPrimary
        : colors.onSurfaceVariant;
    return Tooltip(
      message: seconds == 0
          ? '${date.month}月${date.day}日：未收听'
          : '${date.month}月${date.day}日：${_shortDuration(seconds)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: isFuture ? 0.30 : 0.68),
              glassColor,
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isSameDay(date, now)
                ? colors.onSurface.withValues(alpha: 0.76)
                : Colors.white.withValues(alpha: 0.76),
            width: _isSameDay(date, now) ? 1.8 : 0.7,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: intensity * 0.10),
              blurRadius: 8,
              spreadRadius: -3,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  color: foreground,
                  fontWeight: _isSameDay(date, now)
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
              if (seconds > 0)
                Text(
                  seconds < 60 ? '<1m' : '${seconds ~/ 60}m',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: foreground),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

double _heatIntensity(int seconds) {
  if (seconds <= 0) return 0;
  if (seconds < 5 * 60) return 0.25;
  if (seconds < 15 * 60) return 0.45;
  if (seconds < 30 * 60) return 0.65;
  if (seconds < 60 * 60) return 0.82;
  return 1;
}

bool _isSameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _shortDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '$minutes 分钟';
  return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
}
