import 'package:flutter/foundation.dart';
import 'package:listen/features/player/application/playback_engine.dart';

class FakePlaybackEngine extends ChangeNotifier implements PlaybackEngine {
  @override
  Duration position = Duration.zero;

  @override
  Duration bufferedPosition = Duration.zero;

  @override
  Duration? duration = const Duration(minutes: 10);

  @override
  bool playing = false;

  @override
  double speed = 1;

  @override
  EngineProcessingState processingState = EngineProcessingState.idle;

  String? loadedUrl;
  bool hasAudioSource = false;
  bool looping = false;
  int loadCount = 0;
  int pauseCount = 0;
  final List<Duration> seeks = [];

  @override
  Future<void> load(String audioUrl) async {
    loadedUrl = audioUrl;
    loadCount += 1;
    hasAudioSource = true;
    position = Duration.zero;
    processingState = EngineProcessingState.ready;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    position = value;
    if (processingState == EngineProcessingState.completed) {
      processingState = EngineProcessingState.ready;
    }
    notifyListeners();
  }

  void emitPosition(Duration value) {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> setLooping(bool enabled) async {
    looping = enabled;
  }

  @override
  Future<void> setSpeed(double value) async {
    speed = value;
    notifyListeners();
  }
}
