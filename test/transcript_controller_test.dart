import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/player/application/transcript_controller.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

void main() {
  test(
    'selected transcript cue drives sentence and paragraph ranges',
    () async {
      const document = TranscriptDocument(
        episodeId: 1,
        language: 'en',
        source: 'rss',
        segments: [
          TranscriptSegment(
            index: 0,
            startMs: 1000,
            endMs: 2500,
            text: 'First sentence.',
            paragraphIndex: 0,
          ),
          TranscriptSegment(
            index: 1,
            startMs: 2500,
            endMs: 4000,
            text: 'Second sentence.',
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
      await transcript.load(1);

      await transcript.select(document.segments[1]);
      await playback.setRepeatMode(PlaybackRepeatMode.sentence);

      expect(engine.clipStart, const Duration(milliseconds: 2500));
      expect(engine.clipEnd, const Duration(milliseconds: 4000));

      await playback.setRepeatMode(PlaybackRepeatMode.paragraph);
      expect(engine.clipStart, const Duration(milliseconds: 1000));
      expect(engine.clipEnd, const Duration(milliseconds: 4000));

      await transcript.translate();
      expect(
        transcript.document!.segments[0].translation,
        '中文：First sentence.',
      );
      expect(transcript.showTranslation, isTrue);
      transcript.toggleTranslation();
      expect(transcript.showTranslation, isFalse);
    },
  );
}
