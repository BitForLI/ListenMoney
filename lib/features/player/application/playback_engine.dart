import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

enum EngineProcessingState { idle, loading, ready, completed }

abstract class PlaybackEngine implements Listenable {
  Duration get position;
  Duration get bufferedPosition;
  Duration? get duration;
  bool get playing;
  double get speed;
  EngineProcessingState get processingState;

  Future<void> load(String audioUrl);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setLooping(bool enabled);
  Future<void> setClip({Duration? start, Duration? end});
  void dispose();
}

class JustAudioPlaybackEngine extends ChangeNotifier implements PlaybackEngine {
  JustAudioPlaybackEngine() {
    _subscriptions = [
      _player.positionStream.listen((value) {
        _position = value;
        notifyListeners();
      }),
      _player.bufferedPositionStream.listen((value) {
        _bufferedPosition = value;
        notifyListeners();
      }),
      _player.durationStream.listen((value) {
        _duration = value;
        notifyListeners();
      }),
      _player.playerStateStream.listen((value) {
        _playing = value.playing;
        _processingState = switch (value.processingState) {
          just_audio.ProcessingState.idle => EngineProcessingState.idle,
          just_audio.ProcessingState.loading ||
          just_audio.ProcessingState.buffering => EngineProcessingState.loading,
          just_audio.ProcessingState.ready => EngineProcessingState.ready,
          just_audio.ProcessingState.completed =>
            EngineProcessingState.completed,
        };
        notifyListeners();
      }),
      _player.speedStream.listen((value) {
        _speed = value;
        notifyListeners();
      }),
    ];
  }

  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();
  late final List<StreamSubscription<Object?>> _subscriptions;

  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  double _speed = 1;
  EngineProcessingState _processingState = EngineProcessingState.idle;

  @override
  Duration get position => _position;

  @override
  Duration get bufferedPosition => _bufferedPosition;

  @override
  Duration? get duration => _duration;

  @override
  bool get playing => _playing;

  @override
  double get speed => _speed;

  @override
  EngineProcessingState get processingState => _processingState;

  @override
  Future<void> load(String audioUrl) async {
    await _player.setUrl(audioUrl);
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setClip({Duration? start, Duration? end}) {
    return _player.setClip(start: start, end: end);
  }

  @override
  Future<void> setLooping(bool enabled) {
    return _player.setLoopMode(
      enabled ? just_audio.LoopMode.one : just_audio.LoopMode.off,
    );
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
