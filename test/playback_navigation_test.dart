import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/player/application/transcript_controller.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

const _episode = Episode(
  id: 1,
  podcastId: 1,
  guid: 'one',
  title: 'One',
  audioUrl: 'https://example.com/one.mp3',
);
const _document = TranscriptDocument(
  episodeId: 1,
  language: 'en',
  source: 'rss',
  segments: [
    TranscriptSegment(
      index: 0,
      startMs: 100000,
      endMs: 105000,
      text: 'First sentence.',
      paragraphIndex: 0,
    ),
    TranscriptSegment(
      index: 1,
      startMs: 105000,
      endMs: 110000,
      text: 'Second sentence.',
      paragraphIndex: 0,
    ),
    TranscriptSegment(
      index: 2,
      startMs: 130000,
      endMs: 135000,
      text: 'Third sentence.',
      paragraphIndex: 1,
    ),
    TranscriptSegment(
      index: 3,
      startMs: 135000,
      endMs: 140000,
      text: 'Fourth sentence.',
      paragraphIndex: 1,
    ),
  ],
);

void main() {
  test(
    'cached transcript audio is loaded without requesting the remote URL',
    () async {
      final engine = FakePlaybackEngine();
      final playback = PlaybackController(
        engine,
        audioSourceForEpisode: (_) async => 'file:///private/bound-episode.mp3',
      );
      addTearDown(playback.dispose);
      await playback.loadEpisode(_episode);
      expect(engine.loadedUrl, 'file:///private/bound-episode.mp3');
      await playback.useTranscriptAudio(1, 'file:///private/bound-episode.mp3');
      expect(engine.loadCount, 1);
    },
  );

  for (final mode in PlaybackRepeatMode.values) {
    test('tap, previous and skip retain the full timeline in $mode', () async {
      final engine = FakePlaybackEngine();
      final playback = PlaybackController(engine);
      await playback.loadEpisode(_episode);
      final transcript = TranscriptController(
        FakePodcastRepository(transcript: _document),
        playback,
      );
      addTearDown(() {
        transcript.dispose();
        playback.dispose();
      });
      await transcript.load(1);
      expect(transcript.activeSegment, isNull);
      await transcript.select(_document.segments[0]);
      await playback.setRepeatMode(mode);
      await transcript.select(_document.segments[1]);
      // Paragraph mode must play the tapped sentence, not the paragraph start.
      expect(engine.position.inMilliseconds, 105000);
      expect(transcript.activeSegment?.index, 1);
      expect(playback.duration, const Duration(minutes: 10));
      await transcript.selectPrevious();
      expect(engine.position.inMilliseconds, 100000);
      expect(transcript.activeSegment?.index, 0);
      await playback.skip(const Duration(seconds: 30));
      expect(engine.position.inMilliseconds, 130000);
      expect(transcript.activeSegment?.index, 2);
      await engine.play();
      if (mode == PlaybackRepeatMode.sentence) {
        engine.emitPosition(const Duration(milliseconds: 135000));
        await pumpEventQueue();
        expect(engine.position.inMilliseconds, 130000);
        expect(transcript.activeSegment?.index, 2);
      } else if (mode == PlaybackRepeatMode.paragraph) {
        engine.emitPosition(const Duration(milliseconds: 136000));
        expect(transcript.activeSegment?.index, 3);
        engine.emitPosition(const Duration(milliseconds: 140000));
        await pumpEventQueue();
        expect(engine.position.inMilliseconds, 130000);
        expect(transcript.activeSegment?.index, 2);
      }
      expect(engine.loadCount, 1);
      expect(engine.pauseCount, 0);
      expect(engine.playing, isTrue);
    });
  }

  test(
    'silence and seeks before the first sentence do not highlight old text',
    () async {
      final engine = FakePlaybackEngine();
      final playback = PlaybackController(engine);
      await playback.loadEpisode(_episode);
      final transcript = TranscriptController(
        FakePodcastRepository(transcript: _document),
        playback,
      );
      addTearDown(() {
        transcript.dispose();
        playback.dispose();
      });
      await transcript.load(1);
      await transcript.select(_document.segments[1]);
      await playback.seek(const Duration(seconds: 120));
      expect(transcript.activeSegment, isNull);
      await transcript.selectNext();
      expect(transcript.activeSegment?.index, 2);
      await playback.seek(Duration.zero);
      expect(transcript.activeSegment, isNull);
      await transcript.selectNext();
      expect(transcript.activeSegment?.index, 0);
    },
  );

  test(
    'rapid requests serialize, ignore stale positions and keep the last skip',
    () async {
      final engine = _SlowSeekEngine();
      final playback = PlaybackController(engine);
      addTearDown(playback.dispose);
      await playback.loadEpisode(_episode);
      final first = playback.seek(const Duration(seconds: 10));
      await pumpEventQueue();
      final second = playback.seek(const Duration(seconds: 20));
      final last = playback.skip(const Duration(seconds: 30));
      expect(playback.position, const Duration(seconds: 50));
      engine.emitPosition(const Duration(seconds: 1));
      expect(playback.position, const Duration(seconds: 50));
      engine.gate.complete();
      await Future.wait([first, second, last]);
      expect(engine.seeks, [
        const Duration(seconds: 10),
        const Duration(seconds: 50),
      ]);
      expect(engine.maxConcurrent, 1);
      expect(playback.position, const Duration(seconds: 50));
    },
  );

  test('mode switches preserve paused state, duration and position', () async {
    final engine = FakePlaybackEngine();
    final playback = PlaybackController(engine);
    addTearDown(playback.dispose);
    await playback.loadEpisode(_episode);
    playback.updateTranscriptRanges(
      sentence: PlaybackRange(
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 14),
      ),
    );
    await playback.setRepeatMode(PlaybackRepeatMode.sentence);
    expect(playback.playing, isFalse);
    await playback.setRepeatMode(PlaybackRepeatMode.episode);
    expect(engine.looping, isTrue);
    expect(playback.position, const Duration(seconds: 10));
    expect(playback.duration, const Duration(minutes: 10));
    await playback.setRepeatMode(PlaybackRepeatMode.off);
    expect(engine.looping, isFalse);
    expect(engine.loadCount, 1);
  });

  test(
    'binding matching audio once preserves position, speed and play state',
    () async {
      final engine = FakePlaybackEngine();
      final playback = PlaybackController(engine);
      addTearDown(playback.dispose);
      await playback.loadEpisode(_episode);
      await playback.seek(const Duration(seconds: 123));
      await playback.setSpeed(1.5);
      await engine.play();
      await playback.useTranscriptAudio(1, 'file:///private/audio.mp3');
      expect(engine.loadedUrl, 'file:///private/audio.mp3');
      expect(playback.position, const Duration(seconds: 123));
      expect(playback.playing, isTrue);
      expect(playback.speed, 1.5);
      await playback.useTranscriptAudio(1, 'file:///private/audio.mp3');
      await playback.useTranscriptAudio(2, 'file:///private/wrong.mp3');
      expect(engine.loadCount, 2);
    },
  );

  test('seek failure is visible and does not block the next jump', () async {
    final engine = _FailOnceSeekEngine();
    final playback = PlaybackController(engine);
    addTearDown(playback.dispose);
    await playback.loadEpisode(_episode);
    await playback.seek(const Duration(seconds: 50));
    expect(playback.errorMessage, contains('跳转失败'));
    expect(playback.isSeeking, isFalse);
    await playback.seek(const Duration(seconds: 20));
    expect(playback.position, const Duration(seconds: 20));
  });
}

class _SlowSeekEngine extends FakePlaybackEngine {
  final gate = Completer<void>();
  int concurrent = 0;
  int maxConcurrent = 0;
  @override
  Future<void> seek(Duration value) async {
    concurrent += 1;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    await gate.future;
    await super.seek(value);
    concurrent -= 1;
  }
}

class _FailOnceSeekEngine extends FakePlaybackEngine {
  bool fail = true;
  @override
  Future<void> seek(Duration value) async {
    if (fail) {
      fail = false;
      throw StateError('seek failed');
    }
    await super.seek(value);
  }
}
