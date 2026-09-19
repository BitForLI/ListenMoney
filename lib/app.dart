import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/glass_surface.dart';
import 'features/library/data/local_podcast_repository.dart';
import 'features/library/data/podcast_repository.dart';
import 'features/library/domain/podcast.dart';
import 'features/library/presentation/library_screen.dart';
import 'features/player/application/playback_controller.dart';
import 'features/player/application/playback_engine.dart';
import 'features/player/application/automatic_transcription_runner.dart';
import 'features/player/application/on_device_transcriber.dart';
import 'features/player/application/transcript_controller.dart';
import 'features/player/data/mobile_on_device_transcriber.dart';
import 'features/player/data/transcript_audio_store.dart';
import 'features/player/data/mobile_transcript_translator.dart';
import 'features/player/presentation/player_screen.dart';
import 'features/progress/presentation/progress_screen.dart';
import 'features/progress/application/listening_controller.dart';
import 'features/progress/domain/review_sentence.dart';

class ListenApp extends StatelessWidget {
  const ListenApp({super.key, this.podcastRepository, this.playbackController});

  final PodcastRepository? podcastRepository;
  final PlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PodRepeat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: AppShell(
        podcastRepository: podcastRepository,
        playbackController: playbackController,
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.podcastRepository, this.playbackController});

  final PodcastRepository? podcastRepository;
  final PlaybackController? playbackController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _progressIndex = 0;
  static const _libraryIndex = 1;
  static const _transcriptIndex = 2;

  late final List<Widget> _screens;
  late final PlaybackController _playbackController;
  late final TranscriptController _transcriptController;
  late final PodcastRepository _podcastRepository;
  late final ListeningController _listeningController;
  late final AutomaticTranscriptionRunner _automaticTranscriptionRunner;
  late final bool _ownsPlaybackController;
  final PageController _mainPageController = PageController();
  final GlobalKey _miniPlayerKey = GlobalKey();
  Timer? _playbackSaveTimer;

  int _selectedIndex = _progressIndex;
  Offset? _playerSwipeStart;
  bool _playerRouteOpening = false;
  bool _restoringPlaybackSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsPlaybackController = widget.playbackController == null;
    _podcastRepository =
        widget.podcastRepository ??
        LocalPodcastRepository(translator: MobileTranscriptTranslator());
    final audioStore = TranscriptAudioStore();
    _playbackController =
        widget.playbackController ??
        PlaybackController(
          JustAudioPlaybackEngine(),
          onSentenceRepeat: (episodeId, startMs) {
            unawaited(
              _listeningController.recordSentenceRepeat(episodeId, startMs),
            );
          },
          audioSourceForEpisode: (episode) async {
            final repository = _podcastRepository;
            if (repository is! LocalPodcastRepository) return null;
            final document = await repository.readCachedTranscript(episode.id);
            final key = document?.audioKey;
            if (key == null) return null;
            return (await audioStore.resolve(key))?.uri.toString();
          },
        );
    final onDeviceTranscriber = QueuedOnDeviceTranscriber(
      MobileOnDeviceTranscriber(audioStore: audioStore),
    );
    _transcriptController = TranscriptController(
      _podcastRepository,
      _playbackController,
      onDeviceTranscriber: onDeviceTranscriber,
      audioStore: audioStore,
    );
    _automaticTranscriptionRunner = AutomaticTranscriptionRunner(
      _podcastRepository,
      onDeviceTranscriber,
      audioStore: audioStore,
    );
    _listeningController = ListeningController(
      _podcastRepository,
      _playbackController,
    );
    _playbackController.addListener(_schedulePlaybackSessionSave);
    _screens = [
      ProgressScreen(
        controller: _listeningController,
        onReviewSentence: (sentence) =>
            unawaited(_openReviewSentence(sentence)),
      ),
      LibraryScreen(
        repository: _podcastRepository,
        onPodcastsChanged: (podcasts) {
          unawaited(_automaticTranscriptionRunner.run(podcasts));
          unawaited(_listeningController.load());
        },
        onPlayEpisode: (podcast, episode) {
          unawaited(_playEpisode(podcast, episode));
        },
      ),
      PlayerScreen(
        controller: _playbackController,
        transcriptController: _transcriptController,
        podcastRepository: _podcastRepository,
        transcriptOnly: true,
        onShowProgress: () => _selectMainPage(_progressIndex),
        onClose: () => _selectMainPage(_libraryIndex),
      ),
    ];
    unawaited(_restorePlaybackSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_listeningController.flush());
      unawaited(_savePlaybackSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackSaveTimer?.cancel();
    _playbackController.removeListener(_schedulePlaybackSessionSave);
    unawaited(_savePlaybackSession());
    unawaited(_listeningController.flush());
    _listeningController.dispose();
    _transcriptController.dispose();
    _mainPageController.dispose();
    if (_ownsPlaybackController) _playbackController.dispose();
    super.dispose();
  }

  Future<void> _restorePlaybackSession() async {
    final repository = _podcastRepository;
    if (repository is! LocalPodcastRepository ||
        _playbackController.episode != null) {
      return;
    }
    final session = await repository.loadPlaybackSession();
    if (session == null || !mounted) return;
    _restoringPlaybackSession = true;
    try {
      await _playbackController.restoreEpisode(
        session.episode,
        savedPosition: Duration(milliseconds: session.positionMs),
        savedSpeed: session.speed,
        fromPodcast: session.podcastTitle,
        fromArtworkUrl: session.artworkUrl,
      );
    } finally {
      _restoringPlaybackSession = false;
    }
  }

  void _schedulePlaybackSessionSave() {
    if (_restoringPlaybackSession || _playbackController.episode == null) {
      return;
    }
    if (_playbackSaveTimer?.isActive == true) return;
    _playbackSaveTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_savePlaybackSession()),
    );
  }

  Future<void> _savePlaybackSession() async {
    final repository = _podcastRepository;
    final episode = _playbackController.episode;
    if (repository is! LocalPodcastRepository || episode == null) return;
    await repository.savePlaybackSession(
      PlaybackSession(
        episode: episode,
        positionMs: _playbackController.position.inMilliseconds,
        speed: _playbackController.speed,
        podcastTitle: _playbackController.podcastTitle,
        artworkUrl: _playbackController.artworkUrl,
      ),
    );
  }

  void _selectMainPage(int index) {
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
    if (!_mainPageController.hasClients ||
        _mainPageController.page?.round() == index) {
      return;
    }
    _mainPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onMainPageChanged(int index) {
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  Future<void> _playEpisode(Podcast podcast, Episode episode) async {
    final loading = _playbackController.loadEpisode(
      episode,
      fromPodcast: podcast.title,
      fromArtworkUrl: podcast.artworkUrl,
    );
    if (mounted) unawaited(_openPlayerOverlay());
    await loading;
    if (_playbackController.episode?.id == episode.id &&
        _playbackController.errorMessage == null &&
        !_playbackController.playing) {
      await _playbackController.togglePlayPause();
    }
  }

  Future<void> _openReviewSentence(ReviewSentence sentence) async {
    try {
      final episodes = await _podcastRepository.listEpisodes(
        sentence.podcastId,
      );
      final episode = episodes
          .where((item) => item.id == sentence.episodeId)
          .firstOrNull;
      if (episode == null) throw StateError('这段音频已经不在本地播客库中');
      final podcasts = await _podcastRepository.listSubscriptions();
      final podcast = podcasts
          .where((item) => item.id == sentence.podcastId)
          .firstOrNull;
      if (_playbackController.episode?.id != episode.id) {
        await _playbackController.loadEpisode(
          episode,
          fromPodcast: podcast?.title,
          fromArtworkUrl: podcast?.artworkUrl,
        );
      }
      final playbackError = _playbackController.errorMessage;
      if (playbackError != null) {
        throw StateError(playbackError);
      }
      await _playbackController.seek(Duration(milliseconds: sentence.startMs));
      if (!_playbackController.playing) {
        await _playbackController.togglePlayPause();
      }
      if (mounted) unawaited(_openPlayerOverlay());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法播放复习句子：$error')));
      }
    }
  }

  void _startPlayerSwipe(PointerDownEvent event) {
    if (_selectedIndex == _transcriptIndex) {
      _playerSwipeStart = null;
      return;
    }
    final renderObject = _miniPlayerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !(renderObject.localToGlobal(Offset.zero) & renderObject.size).contains(
          event.position,
        )) {
      _playerSwipeStart = null;
      return;
    }
    _playerSwipeStart = event.localPosition;
  }

  void _updatePlayerSwipe(PointerMoveEvent event) {
    if (_selectedIndex == _transcriptIndex) {
      _playerSwipeStart = null;
      return;
    }
    final start = _playerSwipeStart;
    if (start == null || _playerRouteOpening) return;
    final movement = event.localPosition - start;
    if (movement.dy > -64 || movement.dy.abs() < movement.dx.abs() * 1.2) {
      return;
    }
    _playerSwipeStart = null;
    unawaited(_openPlayerOverlay());
  }

  void _clearPlayerSwipe(PointerEvent event) {
    _playerSwipeStart = null;
  }

  Future<void> _openPlayerOverlay() async {
    if (!mounted || _playerRouteOpening) return;
    if (_playbackController.episode == null) {
      return;
    }
    _playerRouteOpening = true;
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (routeContext, animation, secondaryAnimation) {
            return KeyedSubtree(
              key: const ValueKey('player_overlay'),
              child: PlayerScreen(
                controller: _playbackController,
                transcriptController: _transcriptController,
                podcastRepository: _podcastRepository,
                onShowProgress: () {
                  Navigator.of(routeContext).pop();
                  _selectMainPage(_progressIndex);
                },
                onShowTranscript: () {
                  Navigator.of(routeContext).pop();
                  _selectMainPage(_transcriptIndex);
                },
                onClose: () => Navigator.of(routeContext).maybePop(),
              ),
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
        ),
      );
    } finally {
      _playerRouteOpening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const ValueKey('player_swipe_launcher'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: _startPlayerSwipe,
      onPointerMove: _updatePlayerSwipe,
      onPointerUp: _clearPlayerSwipe,
      onPointerCancel: _clearPlayerSwipe,
      child: Scaffold(
        extendBody: true,
        body: DecoratedBox(
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
          child: PageView(
            key: const ValueKey('main_horizontal_pages'),
            controller: _mainPageController,
            onPageChanged: _onMainPageChanged,
            children: _screens,
          ),
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: _playbackController,
          builder: (context, child) {
            final showMiniPlayer = _playbackController.episode != null;
            return SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                hazeScreenInset,
                0,
                hazeScreenInset,
                hazeScreenInset,
              ),
              child: SizedBox(
                height: showMiniPlayer ? hazeBottomPanelHeight : 66,
                child: GlassSurface(
                  key: const ValueKey('home_bottom_glass'),
                  blur: hazeControlGlassBlur,
                  tint: hazeControlGlassTint,
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showMiniPlayer)
                        _MiniPlayer(
                          key: _miniPlayerKey,
                          controller: _playbackController,
                        ),
                      if (showMiniPlayer)
                        Divider(
                          height: 1,
                          indent: 14,
                          endIndent: 14,
                          color: hazeGlassInk.withValues(alpha: 0.12),
                        ),
                      MainNavigationRow(
                        key: const ValueKey('glass_bottom_navigation'),
                        selectedIndex: _selectedIndex,
                        onProgress: () => _selectMainPage(_progressIndex),
                        onLibrary: () => _selectMainPage(_libraryIndex),
                        onTranscript: () => _selectMainPage(_transcriptIndex),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFF202124);
    const secondary = Color(0xFF55575C);
    return Material(
      key: const ValueKey('mini_player'),
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            minHeight: 2,
            color: foreground,
            value: controller.duration == Duration.zero
                ? 0
                : (controller.position.inMilliseconds /
                          controller.duration.inMilliseconds)
                      .clamp(0, 1),
            backgroundColor: Colors.transparent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                _MiniArtwork(url: controller.artworkUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.episode!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                      if (controller.podcastTitle != null)
                        Text(
                          controller.podcastTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: secondary),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  color: foreground,
                  tooltip: controller.playing ? '暂停' : '播放',
                  onPressed: controller.togglePlayPause,
                  icon: Icon(
                    controller.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  color: foreground,
                  tooltip: '前进 30 秒',
                  onPressed: () => controller.skip(const Duration(seconds: 30)),
                  icon: const Icon(Icons.forward_30_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const SizedBox.square(
        dimension: 46,
        child: Icon(Icons.podcasts_rounded),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null || url!.isEmpty
          ? fallback
          : Image.network(
              url!,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }
}
