import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/library/data/podcast_repository.dart';
import 'features/library/presentation/library_screen.dart';
import 'features/player/application/playback_controller.dart';
import 'features/player/application/playback_engine.dart';
import 'features/player/application/transcript_controller.dart';
import 'features/player/data/mobile_on_device_transcriber.dart';
import 'features/player/presentation/player_screen.dart';
import 'features/progress/presentation/progress_screen.dart';
import 'features/progress/application/listening_controller.dart';

class ListenApp extends StatelessWidget {
  const ListenApp({super.key, this.podcastRepository, this.playbackController});

  final PodcastRepository? podcastRepository;
  final PlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Listen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
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
  late final List<Widget> _screens;
  late final PlaybackController _playbackController;
  late final TranscriptController _transcriptController;
  late final PodcastRepository _podcastRepository;
  late final ListeningController _listeningController;
  late final bool _ownsPlaybackController;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsPlaybackController = widget.playbackController == null;
    _playbackController =
        widget.playbackController ??
        PlaybackController(JustAudioPlaybackEngine());
    _podcastRepository = widget.podcastRepository ?? HttpPodcastRepository();
    _transcriptController = TranscriptController(
      _podcastRepository,
      _playbackController,
      onDeviceTranscriber: MobileOnDeviceTranscriber(),
    );
    _listeningController = ListeningController(
      _podcastRepository,
      _playbackController,
    );
    _screens = [
      LibraryScreen(
        repository: _podcastRepository,
        onPlayEpisode: (podcast, episode) {
          setState(() => _selectedIndex = 1);
          _playbackController.loadEpisode(episode, fromPodcast: podcast.title);
        },
      ),
      PlayerScreen(
        controller: _playbackController,
        transcriptController: _transcriptController,
      ),
      ProgressScreen(controller: _listeningController),
    ];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_listeningController.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_listeningController.flush());
    _listeningController.dispose();
    _transcriptController.dispose();
    if (_ownsPlaybackController) _playbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _screens[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: '播客',
          ),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq),
            label: '播放',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '进度',
          ),
        ],
      ),
    );
  }
}
