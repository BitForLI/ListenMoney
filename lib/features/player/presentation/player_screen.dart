import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/widgets/glass_surface.dart';
import '../../library/data/podcast_repository.dart';
import '../../library/domain/podcast.dart';
import '../application/playback_controller.dart';
import '../application/playback_engine.dart';
import '../application/transcript_controller.dart';
import '../data/subtitle_exporter.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    required this.transcriptController,
    required this.podcastRepository,
    this.transcriptOnly = false,
    this.onShowProgress,
    this.onShowTranscript,
    this.onClose,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;
  final PodcastRepository podcastRepository;
  final bool transcriptOnly;
  final VoidCallback? onShowProgress;
  final VoidCallback? onShowTranscript;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: controller.episode == null
          ? Colors.transparent
          : const Color(0xFFD8DDE2),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          if (controller.episode == null) return const _EmptyPlayer();
          return _ActivePlayer(
            controller: controller,
            transcriptController: transcriptController,
            podcastRepository: podcastRepository,
            transcriptOnly: transcriptOnly,
            onShowProgress: onShowProgress,
            onShowTranscript: onShowTranscript,
            onClose: onClose,
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
    required this.podcastRepository,
    required this.transcriptOnly,
    this.onShowProgress,
    this.onShowTranscript,
    this.onClose,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;
  final PodcastRepository podcastRepository;
  final bool transcriptOnly;
  final VoidCallback? onShowProgress;
  final VoidCallback? onShowTranscript;
  final VoidCallback? onClose;

  @override
  State<_ActivePlayer> createState() => _ActivePlayerState();
}

class _ActivePlayerState extends State<_ActivePlayer> {
  int? _autoStartedEpisodeId;
  Offset? _pullDownStart;
  bool _closeArmed = false;

  @override
  void initState() {
    super.initState();
    widget.transcriptController.addListener(_maybeStartEnglishTranscription);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeStartEnglishTranscription();
    });
  }

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

  void _startPullDown(PointerDownEvent event, double maximumStartY) {
    if (widget.onClose == null || event.localPosition.dy > maximumStartY) {
      _pullDownStart = null;
      return;
    }
    _pullDownStart = event.localPosition;
    _closeArmed = false;
  }

  void _updatePullDown(PointerMoveEvent event) {
    final start = _pullDownStart;
    if (_closeArmed || start == null || widget.onClose == null) return;
    final movement = event.localPosition - start;
    if (movement.dy < 56 || movement.dy < movement.dx.abs() * 1.2) return;
    _closeArmed = true;
  }

  void _endPullDown(PointerEvent event) {
    final shouldClose = _closeArmed;
    _pullDownStart = null;
    _closeArmed = false;
    if (shouldClose && widget.onClose != null) widget.onClose!();
  }

  void _cancelPullDown(PointerEvent event) {
    _pullDownStart = null;
    _closeArmed = false;
  }

  void _maybeStartEnglishTranscription() {
    final episodeId = widget.controller.episode?.id;
    final transcript = widget.transcriptController;
    if (!widget.transcriptOnly ||
        episodeId == null ||
        transcript.isLoading ||
        transcript.isTranscribing ||
        transcript.hasSynchronizedTranscript ||
        _autoStartedEpisodeId == episodeId) {
      return;
    }
    _autoStartedEpisodeId = episodeId;
    unawaited(transcript.transcribe(language: 'en'));
  }

  void _showPlaybackQueue() {
    final episode = widget.controller.episode;
    if (episode == null) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.52),
      builder: (context) => _PlaybackQueueSheet(
        repository: widget.podcastRepository,
        currentEpisode: episode,
        podcastTitle: widget.controller.podcastTitle,
        artworkUrl: widget.controller.artworkUrl,
        onPlay: (nextEpisode) {
          Navigator.pop(context);
          unawaited(
            widget.controller.loadEpisode(
              nextEpisode,
              fromPodcast: widget.controller.podcastTitle,
              fromArtworkUrl: widget.controller.artworkUrl,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.transcriptController.removeListener(_maybeStartEnglishTranscription);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transcriptOnly) {
      return KeyedSubtree(
        key: const ValueKey('transcript_only_page'),
        child: _TranscriptReadingPage(
          controller: widget.controller,
          transcriptController: widget.transcriptController,
          onSelectRepeat: _selectRepeat,
          onShowPlayer: widget.onClose ?? () {},
        ),
      );
    }
    final maximumCloseGestureStartY = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      top: false,
      bottom: false,
      child: Listener(
        key: const ValueKey('player_pull_down_handle'),
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) =>
            _startPullDown(event, maximumCloseGestureStartY),
        onPointerMove: _updatePullDown,
        onPointerUp: _endPullDown,
        onPointerCancel: _cancelPullDown,
        child: ListenableBuilder(
          listenable: widget.transcriptController,
          builder: (context, child) => _NowPlayingPage(
            controller: widget.controller,
            transcriptController: widget.transcriptController,
            onSelectRepeat: _selectRepeat,
            onShowTranscript: widget.onShowTranscript ?? () {},
            onShowQueue: _showPlaybackQueue,
            onShowProgress: widget.onShowProgress,
            onClose: widget.onClose,
          ),
        ),
      ),
    );
  }
}

class _NowPlayingPage extends StatelessWidget {
  const _NowPlayingPage({
    required this.controller,
    required this.transcriptController,
    required this.onSelectRepeat,
    required this.onShowTranscript,
    required this.onShowQueue,
    this.onShowProgress,
    this.onClose,
  });

  final PlaybackController controller;
  final TranscriptController transcriptController;
  final ValueChanged<PlaybackRepeatMode> onSelectRepeat;
  final VoidCallback onShowTranscript;
  final VoidCallback onShowQueue;
  final VoidCallback? onShowProgress;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final episode = controller.episode!;
    final duration = _displayDuration(
      controller,
      transcriptController.document,
    );
    final maximum = _maximumMilliseconds(duration);
    final position = _positionMilliseconds(controller.position, maximum);
    final remaining = duration > controller.position
        ? duration - controller.position
        : Duration.zero;
    const foreground = Color(0xFF202832);
    const secondary = Color(0xFF536171);
    final paragraphNavigation =
        controller.repeatMode == PlaybackRepeatMode.paragraph;
    final canGoPrevious = paragraphNavigation
        ? transcriptController.canSelectPreviousParagraph
        : transcriptController.canSelectPrevious;
    final canGoNext = paragraphNavigation
        ? transcriptController.canSelectNextParagraph
        : transcriptController.canSelectNext;
    final previousLabel = paragraphNavigation ? '上一段' : '上一句';
    final nextLabel = paragraphNavigation ? '下一段' : '下一句';
    final previousAction = paragraphNavigation
        ? transcriptController.selectPreviousParagraph
        : transcriptController.selectPrevious;
    final nextAction = paragraphNavigation
        ? transcriptController.selectNextParagraph
        : transcriptController.selectNext;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (controller.artworkUrl case final artworkUrl?
            when artworkUrl.isNotEmpty)
          ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: Image.network(
              artworkUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 52, sigmaY: 52),
          child: ColoredBox(
            color: const Color(0xFFD6DADD).withValues(alpha: 0.78),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xA8EEEFF0), Color(0xC8D5DBE0), Color(0xDDB5C2CE)],
              stops: [0, 0.52, 1],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 680;
            final artworkSize = (constraints.maxWidth - (compact ? 150 : 100))
                .clamp(170.0, compact ? 225.0 : 286.0);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  hazeScreenInset,
                  compact ? 0 : 4,
                  hazeScreenInset,
                  hazeScreenInset,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Container(
                            width: 48,
                            height: 5,
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: foreground.withValues(alpha: 0.48),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              tooltip: '返回 BANK',
                              onPressed: onClose,
                              color: foreground,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 0 : 8),
                    KeyedSubtree(
                      key: const ValueKey('player_artwork'),
                      child: _PlayerArtwork(
                        url: controller.artworkUrl,
                        size: artworkSize,
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 8),
                    Row(
                      key: const ValueKey('player_secondary_tools'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _PlaybackModeButton(
                          mode: controller.repeatMode,
                          onSelected: onSelectRepeat,
                        ),
                        const SizedBox(width: 44),
                        _PlainPlayerButton(
                          tooltip: '播放队列',
                          icon: Icons.queue_music_rounded,
                          onPressed: onShowQueue,
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 4 : 10),
                    Align(
                      key: const ValueKey('player_episode_title'),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        episode.title,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          height: 1.18,
                        ),
                      ),
                    ),
                    if (controller.podcastTitle != null) ...[
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          controller.podcastTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: secondary),
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 10 : 16),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: foreground,
                        inactiveTrackColor: Colors.black26,
                        thumbColor: foreground,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        value: position,
                        max: maximum,
                        onChanged: duration == Duration.zero
                            ? null
                            : (value) => controller.seek(
                                Duration(milliseconds: value.round()),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(controller.position),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: secondary),
                          ),
                          Text(
                            '-${_formatDuration(remaining)}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: secondary),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    SizedBox(height: compact ? 2 : 6),
                    SizedBox(
                      height: hazeBottomPanelHeight,
                      child: GlassSurface(
                        key: const ValueKey('player_action_glass'),
                        blur: hazeControlGlassBlur,
                        tint: hazeControlGlassTint,
                        borderRadius: BorderRadius.circular(30),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: compact ? 58 : 62,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _SpeedButton(controller: controller),
                                    _TransportButton(
                                      tooltip: previousLabel,
                                      onPressed: canGoPrevious
                                          ? previousAction
                                          : null,
                                      icon: Icons.skip_previous_rounded,
                                    ),
                                    _PlayPauseButton(
                                      controller: controller,
                                      bare: true,
                                    ),
                                    _TransportButton(
                                      tooltip: nextLabel,
                                      onPressed: canGoNext ? nextAction : null,
                                      icon: Icons.skip_next_rounded,
                                    ),
                                  ],
                                ),
                              ),
                              MainNavigationRow(
                                key: const ValueKey('player_main_navigation'),
                                onProgress: onShowProgress,
                                onLibrary: onClose,
                                onTranscript: onShowTranscript,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final speed = controller.speed == controller.speed.roundToDouble()
        ? controller.speed.toInt().toString()
        : controller.speed.toString();
    return PopupMenuButton<double>(
      tooltip: '播放速度',
      initialValue: controller.speed,
      onSelected: controller.setSpeed,
      itemBuilder: (context) => const [0.75, 1.0, 1.25, 1.5, 2.0]
          .map(
            (value) => CheckedPopupMenuItem(
              value: value,
              checked: controller.speed == value,
              child: Text('$value×'),
            ),
          )
          .toList(),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Center(
          child: Text(
            '$speed×',
            style: const TextStyle(
              color: Color(0xFF202832),
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackModeButton extends StatelessWidget {
  const _PlaybackModeButton({required this.mode, required this.onSelected});

  final PlaybackRepeatMode mode;
  final ValueChanged<PlaybackRepeatMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '切换播放方式',
      onPressed: () => onSelected(_nextRepeatMode(mode)),
      iconSize: 30,
      color: const Color(0xFF202832),
      icon: Icon(_repeatModeIcon(mode)),
    );
  }
}

class _PlainPlayerButton extends StatelessWidget {
  const _PlainPlayerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 30,
      color: const Color(0xFF202832),
      icon: Icon(icon),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 32,
      color: const Color(0xFF202832),
      disabledColor: const Color(0xFF202832).withValues(alpha: 0.28),
      icon: Icon(icon),
    );
  }
}

IconData _repeatModeIcon(PlaybackRepeatMode mode) => switch (mode) {
  PlaybackRepeatMode.sentence => Icons.repeat_one_rounded,
  PlaybackRepeatMode.paragraph => Icons.format_align_left_rounded,
  PlaybackRepeatMode.episode => Icons.all_inclusive_rounded,
  PlaybackRepeatMode.off => Icons.repeat_rounded,
};

PlaybackRepeatMode _nextRepeatMode(PlaybackRepeatMode mode) => switch (mode) {
  PlaybackRepeatMode.off => PlaybackRepeatMode.sentence,
  PlaybackRepeatMode.sentence => PlaybackRepeatMode.paragraph,
  PlaybackRepeatMode.paragraph => PlaybackRepeatMode.episode,
  PlaybackRepeatMode.episode => PlaybackRepeatMode.sentence,
};

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.podcasts_rounded,
          size: size * 0.34,
          color: colors.onSecondaryContainer,
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: url == null || url!.isEmpty
            ? fallback
            : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

class _PlaybackQueueSheet extends StatefulWidget {
  const _PlaybackQueueSheet({
    required this.repository,
    required this.currentEpisode,
    required this.onPlay,
    this.podcastTitle,
    this.artworkUrl,
  });

  final PodcastRepository repository;
  final Episode currentEpisode;
  final ValueChanged<Episode> onPlay;
  final String? podcastTitle;
  final String? artworkUrl;

  @override
  State<_PlaybackQueueSheet> createState() => _PlaybackQueueSheetState();
}

class _PlaybackQueueSheetState extends State<_PlaybackQueueSheet> {
  late final Future<List<Episode>> _episodes = widget.repository.listEpisodes(
    widget.currentEpisode.podcastId,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        hazeScreenInset,
        0,
        hazeScreenInset,
        hazeScreenInset,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.76,
        child: GlassSurface(
          blur: hazeControlGlassBlur,
          tint: hazeControlGlassTint,
          borderRadius: BorderRadius.circular(28),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 5,
                  margin: const EdgeInsets.only(top: 10, bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF77797E),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.queue_music_rounded,
                        color: Color(0xFF202124),
                        size: 27,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '播放队列',
                              style: TextStyle(
                                color: Color(0xFF202124),
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (widget.podcastTitle?.isNotEmpty == true)
                              Text(
                                widget.podcastTitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF5F6368),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭播放队列',
                        color: const Color(0xFF202124),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: Colors.black12),
                Expanded(
                  child: FutureBuilder<List<Episode>>(
                    future: _episodes,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF303134),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return _QueueMessage(
                          icon: Icons.cloud_off_rounded,
                          message: snapshot.error.toString(),
                        );
                      }
                      final episodes = (snapshot.data ?? const <Episode>[])
                          .where(
                            (episode) => episode.id != widget.currentEpisode.id,
                          )
                          .toList();
                      if (episodes.isEmpty) {
                        return const _QueueMessage(
                          icon: Icons.queue_music_rounded,
                          message: '这个播客暂时没有其他单集',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                        itemCount: episodes.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Colors.black12, indent: 76),
                        itemBuilder: (context, index) {
                          final episode = episodes[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            leading: _QueueArtwork(url: widget.artworkUrl),
                            title: Text(
                              episode.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF202124),
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                            subtitle: Text(
                              _episodeMetadata(episode),
                              style: const TextStyle(color: Color(0xFF5F6368)),
                            ),
                            trailing: const Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFF303134),
                            ),
                            onTap: () => widget.onPlay(episode),
                          );
                        },
                      );
                    },
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

class _QueueArtwork extends StatelessWidget {
  const _QueueArtwork({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: Color(0xFFD6D7DA),
      child: SizedBox.square(
        dimension: 52,
        child: Icon(Icons.podcasts_rounded, color: Color(0xFF4A4C50)),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: url == null || url!.isEmpty
          ? fallback
          : Image.network(
              url!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }
}

class _QueueMessage extends StatelessWidget {
  const _QueueMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Color(0xFF4A4C50)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF4A4C50)),
            ),
          ],
        ),
      ),
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

  Future<void> _exportTranscript(
    BuildContext context,
    TranscriptDocument document,
  ) async {
    final renderBox = context.findRenderObject();
    final origin = renderBox is RenderBox && renderBox.hasSize
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : null;
    try {
      await const SubtitleExporter().export(
        document,
        episodeTitle: controller.episode?.title ?? 'Listen 字幕',
        sharePositionOrigin: origin,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('字幕导出失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: transcriptController,
      builder: (context, child) {
        final document = transcriptController.document;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE7E8E9),
                Color(0xFFDDE1E5),
                Color(0xFFCBD4DC),
                Color(0xFFBECAD5),
              ],
              stops: [0, 0.30, 0.68, 1],
            ),
          ),
          child: SafeArea(
            child: Column(
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
                      if (document != null) ...[
                        const Icon(Icons.subtitles_rounded, size: 22),
                      ],
                      const Spacer(),
                      if (document != null)
                        IconButton(
                          tooltip: '导出字幕',
                          onPressed: () => _exportTranscript(context, document),
                          icon: const Icon(Icons.file_download_outlined),
                        ),
                      if (document != null &&
                          transcriptController.supportsOnDeviceTranscription)
                        IconButton(
                          tooltip: '重新生成字幕',
                          onPressed: transcriptController.isTranscribing
                              ? null
                              : transcriptController.transcribe,
                          icon: const Icon(Icons.auto_fix_high_rounded),
                        ),
                      if (document != null && document.targetLanguage == null)
                        IconButton(
                          tooltip: '生成中文对照',
                          onPressed: transcriptController.isTranslating
                              ? null
                              : transcriptController.translate,
                          icon: transcriptController.isTranslating
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                Expanded(
                  child: _TranscriptBody(controller: transcriptController),
                ),
                if (document != null)
                  _ReadingControls(
                    controller: controller,
                    transcriptController: transcriptController,
                    onSelectRepeat: onSelectRepeat,
                  ),
              ],
            ),
          ),
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
          if (controller.needsAlignment)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('旧字幕尚未匹配当前音频，暂不自动跟随。')),
                  TextButton(
                    onPressed: controller.isTranscribing
                        ? null
                        : controller.transcribe,
                    child: const Text('重新校准'),
                  ),
                ],
              ),
            ),
          if (controller.isTranscribing)
            _TranscriptionProgress(controller: controller),
          Expanded(child: _TranscriptList(controller: controller)),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: controller.isTranscribing
                ? null
                : () => controller.transcribe(language: 'en'),
            icon: controller.isTranscribing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: const Text('转写英语'),
          ),
          if (controller.isTranscribing) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                value: (controller.transcriptionProgress ?? 0) <= 0
                    ? null
                    : controller.transcriptionProgress,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              controller.transcriptionStatus ?? '正在准备转写…',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
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
          LinearProgressIndicator(
            value: (controller.transcriptionProgress ?? 0) <= 0
                ? null
                : controller.transcriptionProgress,
          ),
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
    final duration = _displayDuration(
      controller,
      transcriptController.document,
    );
    final maximum = _maximumMilliseconds(duration);
    final position = _positionMilliseconds(controller.position, maximum);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        hazeScreenInset,
        0,
        hazeScreenInset,
        hazeScreenInset,
      ),
      child: SizedBox(
        height: 120,
        child: GlassSurface(
          key: const ValueKey('transcript_control_glass'),
          blur: hazeControlGlassBlur,
          tint: hazeControlGlassTint,
          borderRadius: BorderRadius.circular(28),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Color(0xFF202124)),
            child: IconTheme(
              data: const IconThemeData(color: Color(0xFF202124)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _SpeedButton(controller: controller),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: 30,
                                  child: Slider(
                                    value: position,
                                    max: maximum,
                                    onChanged: duration == Duration.zero
                                        ? null
                                        : (value) => controller.seek(
                                            Duration(
                                              milliseconds: value.round(),
                                            ),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(controller.position),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _ReadingModeButton(
                            mode: controller.repeatMode,
                            onSelected: onSelectRepeat,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 59,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _SentenceButton(
                            tooltip: '跳到上一句',
                            label: '上一句',
                            icon: Icons.skip_previous_rounded,
                            onPressed: transcriptController.canSelectPrevious
                                ? transcriptController.selectPrevious
                                : null,
                            foregroundColor: const Color(0xFF202124),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PlayPauseButton(
                                controller: controller,
                                compact: true,
                                bare: true,
                              ),
                              Text(
                                controller.playing ? '暂停' : '播放',
                                style: const TextStyle(fontSize: 11, height: 1),
                              ),
                            ],
                          ),
                          _SentenceButton(
                            tooltip: '跳到下一句',
                            label: '下一句',
                            icon: Icons.skip_next_rounded,
                            onPressed: transcriptController.canSelectNext
                                ? transcriptController.selectNext
                                : null,
                            foregroundColor: const Color(0xFF202124),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingModeButton extends StatelessWidget {
  const _ReadingModeButton({required this.mode, required this.onSelected});

  final PlaybackRepeatMode mode;
  final ValueChanged<PlaybackRepeatMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '切换播放方式',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onSelected(_nextRepeatMode(mode)),
        child: SizedBox(
          width: 92,
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_repeatModeIcon(mode), size: 19),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _repeatModeLabel(mode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.controller,
    this.compact = false,
    this.bare = false,
  });

  final PlaybackController controller;
  final bool compact;
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final unavailable =
        controller.isLoading ||
        controller.processingState == EngineProcessingState.loading;
    final icon = controller.isLoading
        ? SizedBox.square(
            dimension: compact ? 24 : 30,
            child: const CircularProgressIndicator(strokeWidth: 3),
          )
        : Icon(
            controller.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          );
    if (bare) {
      return IconButton(
        tooltip: controller.playing ? '暂停' : '播放',
        iconSize: compact ? 32 : 38,
        padding: const EdgeInsets.all(8),
        onPressed: unavailable ? null : controller.togglePlayPause,
        icon: icon,
      );
    }
    return IconButton.filled(
      tooltip: controller.playing ? '暂停' : '播放',
      iconSize: compact ? 32 : 42,
      padding: EdgeInsets.all(compact ? 12 : 18),
      onPressed: unavailable ? null : controller.togglePlayPause,
      icon: icon,
    );
  }
}

class _SentenceButton extends StatelessWidget {
  const _SentenceButton({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor:
              foregroundColor ?? Theme.of(context).colorScheme.onSurface,
          disabledForegroundColor: Theme.of(context).disabledColor,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            Text(label, style: const TextStyle(fontSize: 11, height: 1)),
          ],
        ),
      ),
    );
  }
}

class _TranscriptList extends StatefulWidget {
  const _TranscriptList({required this.controller});

  final TranscriptController controller;

  @override
  State<_TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends State<_TranscriptList> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _segmentKeys = {};
  Timer? _resumeFollowingTimer;
  int? _lastActiveSegmentIndex;
  int? _lastEpisodeId;
  bool _lastCanFollow = false;
  bool _followingPaused = false;

  TranscriptController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _lastActiveSegmentIndex = controller.activeSegment?.index;
    _lastEpisodeId = controller.document?.episodeId;
    _lastCanFollow = controller.canFollowPlayback;
    _scheduleActiveSegmentScroll();
  }

  @override
  void didUpdateWidget(covariant _TranscriptList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeIndex = controller.activeSegment?.index;
    final episodeId = controller.document?.episodeId;
    final canFollow = controller.canFollowPlayback;
    if (activeIndex == _lastActiveSegmentIndex &&
        episodeId == _lastEpisodeId &&
        canFollow == _lastCanFollow) {
      return;
    }
    if (episodeId != _lastEpisodeId) _segmentKeys.clear();
    _lastActiveSegmentIndex = activeIndex;
    _lastEpisodeId = episodeId;
    _lastCanFollow = canFollow;
    if (!canFollow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !controller.canFollowPlayback &&
            _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.offset);
        }
      });
    } else if (!_followingPaused) {
      _scheduleActiveSegmentScroll();
    }
  }

  @override
  void dispose() {
    _resumeFollowingTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleActiveSegmentScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_followingPaused) unawaited(_scrollToActiveSegment());
    });
  }

  Future<void> _scrollToActiveSegment() async {
    if (!controller.canFollowPlayback) return;
    final episodeId = controller.document?.episodeId;
    final active = controller.activeSegment;
    if (active == null || !_scrollController.hasClients) return;
    final activeContext = _segmentKeys[active.index]?.currentContext;
    if (activeContext != null) {
      await Scrollable.ensureVisible(
        activeContext,
        alignment: 0.42,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final segments = controller.document?.segments ?? const [];
    final position = segments.indexWhere((item) => item.index == active.index);
    if (position < 0 || segments.length < 2) return;
    final estimatedOffset =
        _scrollController.position.maxScrollExtent *
        position /
        (segments.length - 1);
    await _scrollController.animateTo(
      estimatedOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
    if (!mounted ||
        _followingPaused ||
        !controller.canFollowPlayback ||
        controller.activeSegment?.index != active.index ||
        controller.document?.episodeId != episodeId) {
      return;
    }
    final correctedContext = _segmentKeys[active.index]?.currentContext;
    if (correctedContext != null && correctedContext.mounted) {
      await Scrollable.ensureVisible(
        correctedContext,
        alignment: 0.42,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    _resumeFollowingTimer?.cancel();
    if (notification.direction != ScrollDirection.idle) {
      _followingPaused = true;
      return false;
    }
    _resumeFollowingTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _followingPaused = false;
      _scheduleActiveSegmentScroll();
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final segments = controller.document!.segments;
    final colors = Theme.of(context).colorScheme;
    return NotificationListener<UserScrollNotification>(
      onNotification: _handleUserScroll,
      child: ListView.builder(
        key: const ValueKey('transcript_list'),
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          hazeScreenInset,
          12,
          hazeScreenInset,
          24,
        ),
        itemCount: segments.length,
        itemBuilder: (context, index) {
          final segment = segments[index];
          final isActive = segment.index == controller.activeSegment?.index;
          final startsParagraph =
              index == 0 ||
              segments[index - 1].paragraphIndex != segment.paragraphIndex;
          final tile = ListTile(
            selected: isActive,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Text(
              _formatTimestamp(segment.startMs),
              style: TextStyle(
                color: isActive ? hazeGlassInk : colors.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            title: Text(
              segment.text,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                height: 1.35,
              ),
            ),
            subtitle:
                segment.speaker == null &&
                    (!controller.showTranslation || segment.translation == null)
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (segment.speaker != null)
                        Text(
                          segment.speaker!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: isActive
                                    ? hazeGlassInk.withValues(alpha: 0.76)
                                    : colors.onSurfaceVariant,
                              ),
                        ),
                      if (controller.showTranslation &&
                          segment.translation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          segment.translation!,
                          style: TextStyle(
                            color: isActive ? hazeGlassInk : colors.secondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
            onTap: controller.hasSynchronizedTranscript
                ? () => controller.select(segment)
                : null,
          );
          return KeyedSubtree(
            key: _segmentKeys.putIfAbsent(segment.index, GlobalKey.new),
            child: Padding(
              key: ValueKey('transcript_segment_${segment.index}'),
              padding: EdgeInsets.only(
                top: startsParagraph && index > 0 ? 12 : 0,
                bottom: 4,
              ),
              child: isActive
                  ? GlassSurface(
                      blur: hazeControlGlassBlur,
                      tint: hazeControlGlassTint,
                      borderRadius: BorderRadius.circular(12),
                      child: tile,
                    )
                  : Material(color: Colors.transparent, child: tile),
            ),
          );
        },
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

Duration _displayDuration(
  PlaybackController controller,
  TranscriptDocument? transcript,
) {
  if (controller.duration > Duration.zero) return controller.duration;
  final episodeSeconds = controller.episode?.durationSeconds ?? 0;
  if (episodeSeconds > 0) return Duration(seconds: episodeSeconds);
  final segments = transcript?.segments;
  return segments == null || segments.isEmpty
      ? Duration.zero
      : Duration(milliseconds: segments.last.endMs);
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

String _episodeMetadata(Episode episode) {
  final values = <String>[];
  final date = episode.publishedAt?.toLocal();
  if (date != null) values.add('${date.year}-${date.month}-${date.day}');
  final seconds = episode.durationSeconds;
  if (seconds != null) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    values.add(hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟');
  }
  return values.isEmpty ? '已同步' : values.join(' · ');
}
