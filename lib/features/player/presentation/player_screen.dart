import 'package:flutter/material.dart';

import '../application/playback_controller.dart';
import '../application/playback_engine.dart';
import '../application/on_device_transcriber.dart';
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

class _ActivePlayer extends StatefulWidget {
  const _ActivePlayer({
    required this.controller,
    required this.transcriptController,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;

  @override
  State<_ActivePlayer> createState() => _ActivePlayerState();
}

class _ActivePlayerState extends State<_ActivePlayer> {
  final PageController _pageController = PageController();
  int _page = 0;

  Future<void> _selectRepeat(PlaybackRepeatMode mode) async {
    try {
      await widget.controller.setRepeatMode(mode);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Stack(
        children: [
          PageView(
            key: const ValueKey('player_vertical_pages'),
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              _NowPlayingPage(
                controller: widget.controller,
                onShowTranscript: () => _showPage(1),
              ),
              _TranscriptReadingPage(
                controller: widget.controller,
                transcriptController: widget.transcriptController,
                onSelectRepeat: _selectRepeat,
                onShowPlayer: () => _showPage(0),
              ),
            ],
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: IgnorePointer(child: _PageIndicator(page: _page)),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingPage extends StatelessWidget {
  const _NowPlayingPage({
    required this.controller,
    required this.onShowTranscript,
  });

  final PlaybackController controller;
  final VoidCallback onShowTranscript;

  @override
  Widget build(BuildContext context) {
    final episode = controller.episode!;
    final duration = controller.duration;
    final maximum = _maximumMilliseconds(duration);
    final position = _positionMilliseconds(controller.position, maximum);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 680;
        final artworkSize = compact ? 150.0 : 210.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, compact ? 8 : 18, 24, 8),
          child: Column(
            children: [
              Container(
                width: artworkSize,
                height: artworkSize,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  Icons.podcasts_rounded,
                  size: compact ? 64 : 84,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
              SizedBox(height: compact ? 14 : 24),
              Text(
                episode.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (controller.podcastTitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  controller.podcastTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              if (controller.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    controller.errorMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Slider(
                value: position,
                max: maximum,
                onChanged: duration == Duration.zero
                    ? null
                    : (value) => controller.seek(
                        Duration(milliseconds: value.round()),
                      ),
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
              SizedBox(height: compact ? 6 : 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '后退 15 秒',
                    iconSize: 32,
                    onPressed: () =>
                        controller.skip(const Duration(seconds: -15)),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  const SizedBox(width: 18),
                  _PlayPauseButton(controller: controller),
                  const SizedBox(width: 18),
                  IconButton(
                    tooltip: '前进 30 秒',
                    iconSize: 32,
                    onPressed: () =>
                        controller.skip(const Duration(seconds: 30)),
                    icon: const Icon(Icons.forward_30_rounded),
                  ),
                ],
              ),
              SizedBox(height: compact ? 2 : 8),
              TextButton.icon(
                onPressed: onShowTranscript,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                label: const Text('上滑查看文本'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TranscriptReadingPage extends StatelessWidget {
  const _TranscriptReadingPage({
    required this.controller,
    required this.transcriptController,
    required this.onSelectRepeat,
    required this.onShowPlayer,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;
  final ValueChanged<PlaybackRepeatMode> onSelectRepeat;
  final VoidCallback onShowPlayer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: transcriptController,
      builder: (context, child) {
        final document = transcriptController.document;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回播放封面',
                    onPressed: onShowPlayer,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  Text('文本', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (document != null)
                    Text(
                      document.targetLanguage == null
                          ? document.language.toUpperCase()
                          : '${document.language.toUpperCase()} → 中文',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  if (document != null) const SizedBox(width: 8),
                  if (document != null && document.targetLanguage == null)
                    IconButton(
                      tooltip: '生成中文对照',
                      onPressed: transcriptController.isTranslating
                          ? null
                          : transcriptController.translate,
                      icon: transcriptController.isTranslating
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.translate_rounded),
                    )
                  else if (document?.targetLanguage != null)
                    FilterChip(
                      selected: transcriptController.showTranslation,
                      onSelected: (_) =>
                          transcriptController.toggleTranslation(),
                      avatar: const Icon(Icons.translate_rounded, size: 18),
                      label: const Text('中英'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _TranscriptBody(controller: transcriptController)),
            _ReadingControls(
              controller: controller,
              transcriptController: transcriptController,
              onSelectRepeat: onSelectRepeat,
            ),
          ],
        );
      },
    );
  }
}

class _TranscriptBody extends StatelessWidget {
  const _TranscriptBody({required this.controller});

  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final document = controller.document;
    if (document != null && document.segments.isNotEmpty) {
      return Column(
        children: [
          if (controller.isTranscribing)
            _TranscriptionProgress(controller: controller),
          if (controller.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(child: _TranscriptList(controller: controller)),
        ],
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, size: 48),
            const SizedBox(height: 14),
            if (controller.errorMessage != null) ...[
              Text(
                controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              controller.supportsOnDeviceTranscription
                  ? '播客没有时间轴字幕，可以直接在这部手机上免费离线生成。'
                  : '播客未提供时间轴时，可以在 Mac 后端使用 Whisper 本地生成。',
              textAlign: TextAlign.center,
            ),
            if (controller.supportsOnDeviceTranscription) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('识别模式：'),
                  DropdownButton<DeviceTranscriptionModel>(
                    value: controller.transcriptionModel,
                    onChanged: controller.isTranscribing
                        ? null
                        : (model) {
                            if (model != null) {
                              controller.setTranscriptionModel(model);
                            }
                          },
                    items: DeviceTranscriptionModel.values
                        .map(
                          (model) => DropdownMenuItem(
                            value: model,
                            child: Text(model.label),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              Text(
                controller.transcriptionModel == DeviceTranscriptionModel.fast
                    ? '首次使用会下载较小的英语模型，速度优先。'
                    : '首次使用会下载较大的英语模型，准确度优先。',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (controller.isTranscribing) ...[
              const SizedBox(height: 16),
              _TranscriptionProgress(controller: controller),
            ],
            const SizedBox(height: 16),
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
              label: Text(
                controller.isTranscribing
                    ? '正在本地转写…'
                    : controller.supportsOnDeviceTranscription
                    ? '在手机生成字幕'
                    : '生成本地字幕',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptionProgress extends StatelessWidget {
  const _TranscriptionProgress({required this.controller});

  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: controller.transcriptionProgress),
          const SizedBox(height: 6),
          Text(
            controller.transcriptionStatus ?? '正在生成字幕…',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ReadingControls extends StatelessWidget {
  const _ReadingControls({
    required this.controller,
    required this.transcriptController,
    required this.onSelectRepeat,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;
  final ValueChanged<PlaybackRepeatMode> onSelectRepeat;

  @override
  Widget build(BuildContext context) {
    final duration = controller.duration;
    final maximum = _maximumMilliseconds(duration);
    final position = _positionMilliseconds(controller.position, maximum);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, size: 20),
                const SizedBox(width: 6),
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
                const Spacer(),
                PopupMenuButton<PlaybackRepeatMode>(
                  tooltip: '播放模式',
                  initialValue: controller.repeatMode,
                  onSelected: onSelectRepeat,
                  itemBuilder: (context) => PlaybackRepeatMode.values
                      .map(
                        (mode) => CheckedPopupMenuItem(
                          value: mode,
                          checked: controller.repeatMode == mode,
                          child: Text(_repeatModeLabel(mode)),
                        ),
                      )
                      .toList(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.repeat_rounded, size: 19),
                          const SizedBox(width: 6),
                          Text(_repeatModeLabel(controller.repeatMode)),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SentenceButton(
                  tooltip: '跳到上一句',
                  label: '上一句',
                  icon: Icons.skip_previous_rounded,
                  onPressed: transcriptController.canSelectPrevious
                      ? transcriptController.selectPrevious
                      : null,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PlayPauseButton(controller: controller, compact: true),
                    const SizedBox(height: 2),
                    Text(controller.playing ? '暂停' : '播放'),
                  ],
                ),
                _SentenceButton(
                  tooltip: '跳到下一句',
                  label: '下一句',
                  icon: Icons.skip_next_rounded,
                  onPressed: transcriptController.canSelectNext
                      ? transcriptController.selectNext
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.controller, this.compact = false});

  final PlaybackController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final unavailable =
        controller.isLoading ||
        controller.processingState == EngineProcessingState.loading;
    return IconButton.filled(
      tooltip: controller.playing ? '暂停' : '播放',
      iconSize: compact ? 32 : 42,
      padding: EdgeInsets.all(compact ? 12 : 18),
      onPressed: unavailable ? null : controller.togglePlayPause,
      icon: controller.isLoading
          ? SizedBox.square(
              dimension: compact ? 26 : 36,
              child: const CircularProgressIndicator(strokeWidth: 3),
            )
          : Icon(
              controller.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
    );
  }
}

class _SentenceButton extends StatelessWidget {
  const _SentenceButton({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          disabledForegroundColor: Theme.of(context).disabledColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34),
            const SizedBox(height: 2),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _TranscriptList extends StatelessWidget {
  const _TranscriptList({required this.controller});

  final TranscriptController controller;

  @override
  Widget build(BuildContext context) {
    final segments = controller.document!.segments;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
            bottom: 4,
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
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        2,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 4,
          height: page == index ? 24 : 8,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: page == index
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

String _repeatModeLabel(PlaybackRepeatMode mode) => switch (mode) {
  PlaybackRepeatMode.off => '顺序播放',
  PlaybackRepeatMode.sentence => '单句循环',
  PlaybackRepeatMode.paragraph => '段落循环',
  PlaybackRepeatMode.episode => '整集循环',
};

double _maximumMilliseconds(Duration duration) {
  return duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
}

double _positionMilliseconds(Duration position, double maximum) {
  return position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _formatTimestamp(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
