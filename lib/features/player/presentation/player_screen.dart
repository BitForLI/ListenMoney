import 'package:flutter/material.dart';

import '../application/playback_controller.dart';
import '../application/playback_engine.dart';
import '../application/transcript_controller.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.transcriptController,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          if (controller.episode == null) return const _EmptyPlayer();
          return _ActivePlayer(
            controller: controller,
            transcriptController: transcriptController,
          );
        },
      ),
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headphones_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text('尚未播放', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('从播客的单集列表中选择一集。'),
          ],
        ),
      ),
    );
  }
}

class _ActivePlayer extends StatelessWidget {
  const _ActivePlayer({
    required this.controller,
    required this.transcriptController,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;

  Future<void> _selectRepeat(
    BuildContext context,
    PlaybackRepeatMode mode,
  ) async {
    try {
      await controller.setRepeatMode(mode);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode = controller.episode!;
    final duration = controller.duration;
    final maximum = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final position = controller.position.inMilliseconds
        .clamp(0, maximum.toInt())
        .toDouble();

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.podcasts_rounded,
                size: 84,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            episode.title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (controller.podcastTitle != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.podcastTitle!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          if (controller.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                controller.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Slider(
            value: position,
            max: maximum,
            onChanged: duration == Duration.zero
                ? null
                : (value) =>
                      controller.seek(Duration(milliseconds: value.round())),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(controller.position)),
                Text(_formatDuration(duration)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '后退 15 秒',
                iconSize: 32,
                onPressed: () => controller.skip(const Duration(seconds: -15)),
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 18),
              IconButton.filled(
                tooltip: controller.playing ? '暂停' : '播放',
                iconSize: 42,
                padding: const EdgeInsets.all(18),
                onPressed:
                    controller.isLoading ||
                        controller.processingState ==
                            EngineProcessingState.loading
                    ? null
                    : controller.togglePlayPause,
                icon: controller.isLoading
                    ? const SizedBox.square(
                        dimension: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Icon(
                        controller.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
              const SizedBox(width: 18),
              IconButton(
                tooltip: '前进 30 秒',
                iconSize: 32,
                onPressed: () => controller.skip(const Duration(seconds: 30)),
                icon: const Icon(Icons.forward_30_rounded),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('循环方式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _repeatChip(context, PlaybackRepeatMode.off, '关闭'),
              _repeatChip(context, PlaybackRepeatMode.sentence, '逐句'),
              _repeatChip(context, PlaybackRepeatMode.paragraph, '逐段'),
              _repeatChip(context, PlaybackRepeatMode.episode, '整集'),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.speed_rounded),
              const SizedBox(width: 10),
              const Text('播放速度'),
              const Spacer(),
              DropdownButton<double>(
                value: controller.speed,
                underline: const SizedBox.shrink(),
                items: const [0.75, 1.0, 1.25, 1.5, 2.0]
                    .map(
                      (speed) => DropdownMenuItem(
                        value: speed,
                        child: Text('${speed}x'),
                      ),
                    )
                    .toList(),
                onChanged: (speed) {
                  if (speed != null) controller.setSpeed(speed);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          _TranscriptPanel(controller: transcriptController),
        ],
      ),
    );
  }

  Widget _repeatChip(
    BuildContext context,
    PlaybackRepeatMode mode,
    String label,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: controller.repeatMode == mode,
      onSelected: (_) => _selectRepeat(context, mode),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({required this.controller});

  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('时间轴字幕', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (controller.document != null)
                  Text(
                    controller.document!.targetLanguage == null
                        ? controller.document!.language.toUpperCase()
                        : '${controller.document!.language.toUpperCase()} → 中文',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (controller.document != null) ...[
              if (controller.document!.targetLanguage == null)
                FilledButton.tonalIcon(
                  onPressed: controller.isTranslating
                      ? null
                      : controller.translate,
                  icon: controller.isTranslating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.translate_rounded),
                  label: Text(controller.isTranslating ? '正在生成中文…' : '生成中文对照'),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    selected: controller.showTranslation,
                    onSelected: (_) => controller.toggleTranslation(),
                    avatar: const Icon(Icons.translate_rounded, size: 18),
                    label: const Text('中英对照'),
                  ),
                ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              _TranscriptList(controller: controller),
            ] else ...[
              if (controller.errorMessage != null)
                Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              Text(
                '播客未提供时间轴时，可以在 Mac 后端使用 Whisper 本地生成。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: controller.isTranscribing
                    ? null
                    : controller.transcribe,
                icon: controller.isTranscribing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(controller.isTranscribing ? '正在本地转写…' : '生成本地字幕'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TranscriptList extends StatelessWidget {
  const _TranscriptList({required this.controller});

  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    final segments = controller.document!.segments;
    return SizedBox(
      height: 360,
      child: ListView.builder(
        itemCount: segments.length,
        itemBuilder: (context, index) {
          final segment = segments[index];
          final isActive = segment.index == controller.activeSegment?.index;
          final startsParagraph =
              index == 0 ||
              segments[index - 1].paragraphIndex != segment.paragraphIndex;
          return Padding(
            padding: EdgeInsets.only(
              top: startsParagraph && index > 0 ? 12 : 0,
            ),
            child: Material(
              color: isActive
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                selected: isActive,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Text(_formatTimestamp(segment.startMs)),
                title: Text(segment.text),
                subtitle:
                    segment.speaker == null &&
                        (!controller.showTranslation ||
                            segment.translation == null)
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (segment.speaker != null)
                            Text(
                              segment.speaker!,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          if (controller.showTranslation &&
                              segment.translation != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              segment.translation!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                onTap: () => controller.select(segment),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTimestamp(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
