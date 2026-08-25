import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/player/application/transcript_controller.dart';
import 'package:listen/features/player/presentation/player_screen.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

void main() {
  testWidgets('swipes from the player to transcript reading controls', (
    tester,
  ) async {
    const document = TranscriptDocument(
      episodeId: 1,
      language: 'en',
      source: 'rss',
      targetLanguage: 'zh-Hans',
      segments: [
        TranscriptSegment(
          index: 0,
          startMs: 1000,
          endMs: 2500,
          text: 'First sentence.',
          translation: '第一句。',
          paragraphIndex: 0,
        ),
        TranscriptSegment(
          index: 1,
          startMs: 2500,
          endMs: 4000,
          text: 'Second sentence.',
          translation: '第二句。',
          paragraphIndex: 0,
        ),
      ],
    );
    final engine = FakePlaybackEngine();
    final playback = PlaybackController(engine);
    final transcript = TranscriptController(
      FakePodcastRepository(transcript: document),
      playback,
    );
    addTearDown(transcript.dispose);
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 1,
        podcastId: 1,
        guid: 'episode-1',
        title: 'Episode One',
        audioUrl: 'https://example.com/episode.mp3',
      ),
      fromPodcast: 'Test Podcast',
    );
    await transcript.load(1);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          controller: playback,
          transcriptController: transcript,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('上滑查看文本'), findsOneWidget);
    await tester.fling(
      find.byKey(const ValueKey('player_vertical_pages')),
      const Offset(0, -500),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('文本'), findsOneWidget);
    expect(find.text('第一句。'), findsOneWidget);
    expect(find.text('上一句'), findsOneWidget);
    expect(find.text('下一句'), findsOneWidget);
    expect(find.text('顺序播放'), findsOneWidget);

    await tester.tap(find.text('下一句'));
    await tester.pumpAndSettle();
    expect(transcript.activeSegment?.index, 1);
    expect(engine.position, const Duration(milliseconds: 2500));
  });
}
