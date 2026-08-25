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
  PlaybackController(this._engine) {
    _engine.addListener(_engineChanged);
  }

  final PlaybackEngine _engine;
  Episode? episode;
  String? podcastTitle;
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off;
  PlaybackRange? sentenceRange;
  PlaybackRange? paragraphRange;
  bool isLoading = false;
  String? errorMessage;

  Duration get position => _engine.position;
  Duration get bufferedPosition => _engine.bufferedPosition;
  Duration get duration => _engine.duration ?? Duration.zero;
  bool get playing => _engine.playing;
  double get speed => _engine.speed;
  EngineProcessingState get processingState => _engine.processingState;

  void _engineChanged() => notifyListeners();

  Future<void> loadEpisode(Episode value, {String? fromPodcast}) async {
    episode = value;
    podcastTitle = fromPodcast;
    repeatMode = PlaybackRepeatMode.off;
    sentenceRange = null;
    paragraphRange = null;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _engine.setLooping(false);
      await _engine.setClip();
      await _engine.load(value.audioUrl);
    } catch (error) {
      errorMessage = '无法加载音频：$error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void updateTranscriptRanges({
    PlaybackRange? sentence,
    PlaybackRange? paragraph,
  }) {
    sentenceRange = sentence;
    paragraphRange = paragraph;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (episode == null || isLoading) return;
    if (_engine.playing) {
      await _engine.pause();
    } else {
      if (_engine.processingState == EngineProcessingState.completed) {
        await _engine.seek(_rangeFor(repeatMode)?.start ?? Duration.zero);
      }
      unawaited(
        _engine.play().catchError((Object error) {
          errorMessage = '播放失败：$error';
          notifyListeners();
        }),
      );
    }
  }

  Future<void> seek(Duration target) async {
    final maximum = duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : maximum > Duration.zero && target > maximum
        ? maximum
        : target;
    await _engine.seek(clamped);
  }

  Future<void> skip(Duration offset) => seek(position + offset);

  Future<void> setSpeed(double value) => _engine.setSpeed(value);

  PlaybackRange? _rangeFor(PlaybackRepeatMode mode) => switch (mode) {
    PlaybackRepeatMode.sentence => sentenceRange,
    PlaybackRepeatMode.paragraph => paragraphRange,
    PlaybackRepeatMode.off || PlaybackRepeatMode.episode => null,
  };

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    final range = _rangeFor(mode);
    if ((mode == PlaybackRepeatMode.sentence ||
            mode == PlaybackRepeatMode.paragraph) &&
        range == null) {
      throw const PlaybackUnavailableException('需要先生成该单集的时间轴字幕');
    }

    await _engine.pause();
    if (mode == PlaybackRepeatMode.episode || mode == PlaybackRepeatMode.off) {
      await _engine.setClip();
    } else {
      await _engine.setClip(start: range!.start, end: range.end);
      await _engine.seek(range.start);
    }
    await _engine.setLooping(mode != PlaybackRepeatMode.off);
    repeatMode = mode;
    notifyListeners();
    unawaited(_engine.play());
  }

  @override
  void dispose() {
    _engine
      ..removeListener(_engineChanged)
      ..dispose();
    super.dispose();
  }
}
