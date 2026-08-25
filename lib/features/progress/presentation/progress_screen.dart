import 'package:flutter/material.dart';

import '../application/listening_controller.dart';
import '../domain/listening_stats.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.controller});

  final ListeningController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('听力进度'),
        actions: [
          IconButton(
            tooltip: '刷新统计',
            onPressed: controller.isLoading ? null : controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          final stats = controller.stats;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (controller.isLoading && stats.daily.isEmpty)
                const LinearProgressIndicator(),
              _MetricCard(
                icon: Icons.today_rounded,
                label: '今日听力',
                value: _formatDuration(stats.todaySeconds),
              ),
              const SizedBox(height: 12),
              _MetricCard(
                icon: Icons.local_fire_department_rounded,
                label: '连续收听',
                value: '${stats.streakDays} 天',
              ),
              const SizedBox(height: 12),
              _MetricCard(
                icon: Icons.timer_outlined,
                label: '累计听力',
                value: _formatDuration(stats.totalSeconds),
              ),
              const SizedBox(height: 20),
              _WeeklyChart(daily: stats.daily),
              if (controller.pendingSeconds > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '正在记录本次收听…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (controller.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.daily});

  final List<DailyListening> daily;

  @override
  Widget build(BuildContext context) {
    final maximum = daily.fold<int>(
      0,
      (value, day) => day.seconds > value ? day.seconds : value,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近 7 天', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: daily.isEmpty
                  ? const Center(child: Text('还没有听力记录'))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: daily
                          .map(
                            (day) => Expanded(
                              child: _DayBar(day: day, maximum: maximum),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.maximum});

  final DailyListening day;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    final ratio = maximum == 0 ? 0.0 : day.seconds / maximum;
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          day.seconds < 60 ? '${day.seconds}s' : '${day.seconds ~/ 60}m',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 5),
        Container(
          width: 18,
          height: 8 + 92 * ratio,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text('周${weekdays[day.date.weekday - 1]}'),
      ],
    );
  }
}
