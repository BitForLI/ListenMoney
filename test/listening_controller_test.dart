import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/progress/application/listening_controller.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

void main() {
  test('counts only ready playback and flushes accumulated seconds', () async {
    const episode = Episode(
      id: 1,
      podcastId: 1,
      guid: 'episode-1',
      title: 'Episode One',
      audioUrl: 'https://example.com/episode.mp3',
    );
    final repository = FakePodcastRepository();
    final engine = FakePlaybackEngine();
    final playback = PlaybackController(engine);
    final listening = ListeningController(
      repository,
      playback,
      startTimer: false,
    );
    await listening.load();

    listening.countTick();
    expect(listening.pendingSeconds, 0);

    await playback.loadEpisode(episode);
    await engine.play();
    listening
      ..countTick()
      ..countTick()
      ..countTick();

    expect(listening.pendingSeconds, 3);
    expect(listening.stats.todaySeconds, 3);

    await listening.flush();
    expect(repository.recordedSeconds, 3);
    expect(listening.pendingSeconds, 0);
  });
}
