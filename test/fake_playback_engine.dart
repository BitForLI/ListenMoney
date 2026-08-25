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
  bool looping = false;
  Duration? clipStart;
  Duration? clipEnd;

  @override
  Future<void> load(String audioUrl) async {
    loadedUrl = audioUrl;
    processingState = EngineProcessingState.ready;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
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
    position = value;
    notifyListeners();
  }

  @override
  Future<void> setClip({Duration? start, Duration? end}) async {
    clipStart = start;
    clipEnd = end;
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
