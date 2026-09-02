import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/domain/podcast.dart';
import 'playback_engine.dart';

enum PlaybackRepeatMode { off, sentence, paragraph, episode }

class PlaybackRange {
  PlaybackRange({required this.start, required this.end}) : assert(end > start);

  final Duration start;
  final Duration end;
}

class PlaybackUnavailableException implements Exception {
  const PlaybackUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlaybackController extends ChangeNotifier {
  PlaybackController(this._engine, {this.audioSourceForEpisode}) {
    _engine.addListener(_engineChanged);
  }

  final PlaybackEngine _engine;
  final Future<String?> Function(Episode episode)? audioSourceForEpisode;
  Episode? episode;
  String? podcastTitle;
  String? artworkUrl;
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off;
  PlaybackRange? sentenceRange;
  PlaybackRange? paragraphRange;
  bool isLoading = false;
  String? errorMessage;

  PlaybackRange? _repeatRange;
  Timer? _repeatTimer;
  Duration? _pendingPosition;
  Future<void> _operations = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  String? _loadedAudioUrl;

  bool get isSeeking => _pendingPosition != null;
  String? get loadedAudioUrl => _loadedAudioUrl;
  Duration get actualPosition => _engine.position;

  Duration get position => _pendingPosition ?? _engine.position;
  Duration get bufferedPosition => _engine.bufferedPosition;
  Duration get duration => _engine.duration ?? Duration.zero;
  bool get playing => _engine.playing;
  double get speed => _engine.speed;
  EngineProcessingState get processingState => _engine.processingState;

  void _engineChanged() {
    if (_disposed) return;
    if (_repeatIfAtEnd()) return;
    notifyListeners();
    _scheduleRepeat();
  }

  // A sentence is a range on the original episode, never a new audio source.
  // In particular, just_audio clips have their own zero-based timeline.
  bool _repeatIfAtEnd() {
    final range = _repeatRange;
    if (isLoading || isSeeking || !playing || range == null) return false;
    if (position < range.end) return false;
    unawaited(_seek(range.start, reanchor: false));
    return true;
  }

  void _scheduleRepeat() {
    _repeatTimer?.cancel();
    final range = _repeatRange;
    if (_disposed ||
        isLoading ||
        isSeeking ||
        !playing ||
        range == null ||
        processingState != EngineProcessingState.ready) {
      return;
    }
    final remaining = range.end - position;
    final delayUs = (remaining.inMicroseconds / speed).ceil();
    _repeatTimer = Timer(
      Duration(microseconds: delayUs.clamp(1000, 60000000)),
      () {
        if (!_repeatIfAtEnd()) _scheduleRepeat();
      },
    );
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _operations.then((_) async {
      if (!_disposed) await action();
    });
    _operations = result.catchError((Object _) {});
    return result;
  }

  Future<void> loadEpisode(
    Episode value, {
    String? fromPodcast,
    String? fromArtworkUrl,
  }) async {
    final generation = ++_generation;
    _repeatTimer?.cancel();
    _repeatRange = null;
    _pendingPosition = Duration.zero;
    episode = value;
    podcastTitle = fromPodcast;
    artworkUrl = fromArtworkUrl;
    repeatMode = PlaybackRepeatMode.off;
    sentenceRange = null;
    paragraphRange = null;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _enqueue(() async {
        if (generation != _generation) return;
        final source =
            await audioSourceForEpisode?.call(value) ?? value.audioUrl;
        if (generation != _generation) return;
        await _engine.setLooping(false);
        await _engine.load(source);
        _loadedAudioUrl = source;
      });
    } catch (error) {
      if (generation == _generation) errorMessage = '无法加载音频：$error';
    } finally {
      if (!_disposed && generation == _generation) {
        _pendingPosition = null;
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> restoreEpisode(
    Episode value, {
    required Duration savedPosition,
    double savedSpeed = 1,
    String? fromPodcast,
    String? fromArtworkUrl,
  }) async {
    await loadEpisode(
      value,
      fromPodcast: fromPodcast,
      fromArtworkUrl: fromArtworkUrl,
    );
    if (errorMessage != null) return;
    final maximum = duration;
    final resumeAt =
        maximum > Duration.zero &&
            savedPosition >= maximum - const Duration(seconds: 2)
        ? Duration.zero
        : savedPosition;
    if (resumeAt > Duration.zero) await seek(resumeAt);
    if (savedSpeed != 1) await setSpeed(savedSpeed);
  }

  Future<void> useTranscriptAudio(int episodeId, String uri) =>
      _enqueue(() async {
        if (episode?.id != episodeId || _loadedAudioUrl == uri) return;
        final generation = ++_generation;
        final resumeAt = position;
        final resumePlayback = playing;
        _pendingPosition = resumeAt;
        isLoading = true;
        _repeatTimer?.cancel();
        notifyListeners();
        try {
          await _engine.load(uri);
          if (generation != _generation) return;
          final maximum = duration;
          await _engine.seek(
            maximum > Duration.zero && resumeAt > maximum ? maximum : resumeAt,
          );
          await _engine.setLooping(repeatMode == PlaybackRepeatMode.episode);
          _loadedAudioUrl = uri;
          errorMessage = null;
          if (resumePlayback) unawaited(_engine.play());
        } finally {
          if (!_disposed && generation == _generation) {
            _pendingPosition = null;
            isLoading = false;
            notifyListeners();
            _scheduleRepeat();
          }
        }
      });

  void updateTranscriptRanges({
    PlaybackRange? sentence,
    PlaybackRange? paragraph,
  }) {
    sentenceRange = sentence;
    paragraphRange = paragraph;
    if (_repeatRange == null && !isSeeking) {
      final candidate = _rangeFor(repeatMode);
      if (_contains(candidate, position)) _repeatRange = candidate;
    }
    notifyListeners();
    _scheduleRepeat();
  }

  Future<void> togglePlayPause() async {
    if (episode == null || isLoading) return;
    if (_engine.playing) {
      await _engine.pause();
    } else {
      if (_engine.processingState == EngineProcessingState.completed) {
        await _seek(_repeatRange?.start ?? Duration.zero, reanchor: false);
      }
      unawaited(
        _engine.play().catchError((Object error) {
          errorMessage = '播放失败：$error';
          notifyListeners();
        }),
      );
    }
  }

  Future<void> seek(Duration target) => _seek(target, reanchor: true);

  Future<void> _seek(Duration target, {required bool reanchor}) async {
    if (_disposed || isLoading) return;
    final maximum = duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : maximum > Duration.zero && target > maximum
        ? maximum
        : target;
    final generation = ++_generation;
    _repeatTimer?.cancel();
    _pendingPosition = clamped;
    errorMessage = null;
    if (reanchor) _repeatRange = null;
    // Controls can preview the requested position; subtitle following waits
    // for the native seek to complete before using actualPosition.
    notifyListeners();
    try {
      await _enqueue(() async {
        if (generation != _generation) return;
        await _engine.seek(clamped);
      });
    } catch (error) {
      if (generation == _generation) {
        errorMessage = '跳转失败：$error';
        // Do not repeatedly retry a failed boundary seek from the loop timer.
        _repeatRange = null;
        repeatMode = PlaybackRepeatMode.off;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _pendingPosition = null;
        notifyListeners();
        if (reanchor) {
          final candidate = _rangeFor(repeatMode);
          if (_contains(candidate, actualPosition)) _repeatRange = candidate;
        }
        _scheduleRepeat();
      }
    }
  }

  Future<void> skip(Duration offset) => seek(position + offset);

  Future<void> setSpeed(double value) => _engine.setSpeed(value);

  PlaybackRange? _rangeFor(PlaybackRepeatMode mode) => switch (mode) {
    PlaybackRepeatMode.sentence => sentenceRange,
    PlaybackRepeatMode.paragraph => paragraphRange,
    PlaybackRepeatMode.off || PlaybackRepeatMode.episode => null,
  };

  bool _contains(PlaybackRange? range, Duration value) =>
      range != null && value >= range.start && value < range.end;

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    if (_disposed || isLoading) return;
    final generation = _generation;
    final range = _rangeFor(mode);
    if ((mode == PlaybackRepeatMode.sentence ||
            mode == PlaybackRepeatMode.paragraph) &&
        range == null) {
      throw const PlaybackUnavailableException('需要先生成该单集的时间轴字幕');
    }

    _repeatTimer?.cancel();
    repeatMode = mode;
    _repeatRange = range;
    await _enqueue(
      () => _engine.setLooping(repeatMode == PlaybackRepeatMode.episode),
    );
    if (_disposed || generation != _generation || repeatMode != mode) return;
    if (range != null) await _seek(range.start, reanchor: false);
    notifyListeners();
    // Switching modes does not implicitly resume a paused episode.
    _scheduleRepeat();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _repeatTimer?.cancel();
    _engine
      ..removeListener(_engineChanged)
      ..dispose();
    super.dispose();
  }
}
