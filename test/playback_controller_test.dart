import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';

import 'fake_playback_engine.dart';

void main() {
  const episode = Episode(
    id: 1,
    podcastId: 1,
    guid: 'episode-1',
    title: 'Episode One',
    audioUrl: 'https://example.com/episode.mp3',
  );

  test('loads a full episode and clears looping', () async {
    final engine = FakePlaybackEngine()..looping = true;
    final controller = PlaybackController(engine);

    await controller.loadEpisode(episode, fromPodcast: 'Test Podcast');

    expect(engine.loadedUrl, episode.audioUrl);
    expect(engine.hasAudioSource, isTrue);
    expect(engine.looping, isFalse);
    expect(controller.podcastTitle, 'Test Podcast');
  });

  test('restores position and speed without autoplaying', () async {
    final engine = FakePlaybackEngine();
    final controller = PlaybackController(engine);
    addTearDown(controller.dispose);

    await controller.restoreEpisode(
      episode,
      savedPosition: const Duration(seconds: 123),
      savedSpeed: 1.25,
      fromPodcast: 'Test Podcast',
    );

    expect(engine.position, const Duration(seconds: 123));
    expect(engine.speed, 1.25);
    expect(engine.playing, isFalse);
    expect(controller.podcastTitle, 'Test Podcast');
  });

  test('loops an exact sentence range', () async {
    final engine = FakePlaybackEngine();
    final repeats = <(int, int)>[];
    final controller = PlaybackController(
      engine,
      onSentenceRepeat: (episodeId, startMs) => repeats.add((episodeId, startMs)),
    );
    addTearDown(controller.dispose);
    await controller.loadEpisode(episode);
    controller.updateTranscriptRanges(
      sentence: PlaybackRange(
        start: Duration(seconds: 10),
        end: Duration(seconds: 14),
      ),
    );

    await controller.setRepeatMode(PlaybackRepeatMode.sentence);

    expect(engine.position, const Duration(seconds: 10));
    expect(controller.duration, const Duration(minutes: 10));
    expect(engine.looping, isFalse);
    expect(engine.playing, isFalse);
    await engine.play();
    engine.emitPosition(const Duration(seconds: 14));
    await pumpEventQueue();
    expect(engine.position, const Duration(seconds: 10));
    expect(engine.loadCount, 1);
    expect(engine.pauseCount, 0);
    expect(engine.playing, isTrue);
    expect(repeats, [(episode.id, 10000)]);
  });

  test('requires a timed range before sentence repetition', () async {
    final controller = PlaybackController(FakePlaybackEngine());
    await controller.loadEpisode(episode);

    await expectLater(
      controller.setRepeatMode(PlaybackRepeatMode.sentence),
      throwsA(isA<PlaybackUnavailableException>()),
    );
  });
}
