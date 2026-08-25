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

  test('loads an episode and clears the previous clip', () async {
    final engine = FakePlaybackEngine()
      ..clipStart = const Duration(seconds: 10)
      ..clipEnd = const Duration(seconds: 20)
      ..looping = true;
    final controller = PlaybackController(engine);

    await controller.loadEpisode(episode, fromPodcast: 'Test Podcast');

    expect(engine.loadedUrl, episode.audioUrl);
    expect(engine.clipStart, isNull);
    expect(engine.clipEnd, isNull);
    expect(engine.looping, isFalse);
    expect(controller.podcastTitle, 'Test Podcast');
  });

  test('loops an exact sentence range', () async {
    final engine = FakePlaybackEngine();
    final controller = PlaybackController(engine);
    await controller.loadEpisode(episode);
    controller.updateTranscriptRanges(
      sentence: PlaybackRange(
        start: Duration(seconds: 10),
        end: Duration(seconds: 14),
      ),
    );

    await controller.setRepeatMode(PlaybackRepeatMode.sentence);

    expect(engine.clipStart, const Duration(seconds: 10));
    expect(engine.clipEnd, const Duration(seconds: 14));
    expect(engine.position, const Duration(seconds: 10));
    expect(engine.looping, isTrue);
    expect(engine.playing, isTrue);
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
