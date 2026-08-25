import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/data/podcast_repository.dart';
import '../../player/application/playback_controller.dart';
import '../../player/application/playback_engine.dart';
import '../domain/listening_stats.dart';

class ListeningController extends ChangeNotifier {
  ListeningController(
    this._repository,
    this._playback, {
    Duration tickInterval = const Duration(seconds: 1),
    this._flushEverySeconds = 15,
    bool startTimer = true,
  }) {
    _wasPlaying = _playback.playing;
    _playback.addListener(_playbackChanged);
    unawaited(load());
    if (startTimer) {
      _timer = Timer.periodic(tickInterval, (_) => countTick());
    }
  }

  final PodcastRepository _repository;
  final PlaybackController _playback;
  final int _flushEverySeconds;
  Timer? _timer;
  ListeningStats stats = ListeningStats.empty;
  bool isLoading = false;
  String? errorMessage;
  int _pendingSeconds = 0;
  bool _isFlushing = false;
  bool _disposed = false;
  bool _wasPlaying = false;

  int get pendingSeconds => _pendingSeconds;

  void _playbackChanged() {
    final isPlaying = _playback.playing;
    if (_wasPlaying && !isPlaying) unawaited(flush());
    _wasPlaying = isPlaying;
  }

  Future<void> load() async {
    isLoading = true;
    if (!_disposed) notifyListeners();
    try {
      stats = await _repository.listeningStats(DateTime.now());
      errorMessage = null;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @visibleForTesting
  void countTick() {
    if (!_playback.playing ||
        _playback.processingState != EngineProcessingState.ready) {
      return;
    }
    _pendingSeconds += 1;
    stats = stats.addLocalSecond(DateTime.now());
    if (!_disposed) notifyListeners();
    if (_pendingSeconds >= _flushEverySeconds) unawaited(flush());
  }

  Future<void> flush() async {
    if (_pendingSeconds == 0 || _isFlushing) return;
    _isFlushing = true;
    final seconds = _pendingSeconds;
    _pendingSeconds -= seconds;
    try {
      stats = await _repository.recordListening(
        seconds: seconds,
        listenedAt: DateTime.now(),
      );
      errorMessage = null;
    } catch (error) {
      _pendingSeconds += seconds;
      errorMessage = error.toString();
    } finally {
      _isFlushing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _playback.removeListener(_playbackChanged);
    super.dispose();
  }
}
