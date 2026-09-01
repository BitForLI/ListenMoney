import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/player/application/on_device_transcriber.dart';
import 'package:listen/features/player/application/playback_engine.dart';
import 'package:listen/features/player/application/transcript_controller.dart';
import 'package:listen/features/player/data/transcript_audio_store.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

void main() {
  late Directory temporary;
  late TranscriptAudioStore store;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('listen-audio-test-');
    store = TranscriptAudioStore(
      directory: Directory('${temporary.path}/saved'),
    );
  });
  tearDown(() => temporary.delete(recursive: true));

  test(
    'retains the original bytes and rejects missing or unsafe keys',
    () async {
      final download = File('${temporary.path}/download.mp3');
      await download.writeAsBytes([1, 2, 3, 4, 5]);
      final key = await store.retain(download, episodeId: 7);
      await download.writeAsBytes([6, 7, 8]);
      final original = await store.resolve(key);
      expect(await original!.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(await store.resolve('../download.mp3'), isNull);
      expect(await store.resolve('episode-7-999.mp3'), isNull);
    },
  );

  test(
    'persisted subtitles bind playback to their recording before selection',
    () async {
      final file = File('${temporary.path}/download.mp3');
      await file.writeAsBytes([1, 2, 3]);
      final key = await store.retain(file, episodeId: 1);
      final document = TranscriptDocument(
        episodeId: 1,
        language: 'en',
        source: currentPhoneTranscriptSource,
        audioKey: key,
        segments: const [
          TranscriptSegment(
            index: 0,
            startMs: 100000,
            endMs: 104000,
            text: 'Bound sentence.',
            paragraphIndex: 0,
          ),
        ],
      );
      final restored = TranscriptDocument.fromJson(document.toJson());
      expect(restored.audioKey, key);
      final engine = FakePlaybackEngine();
      final playback = PlaybackController(engine);
      await playback.loadEpisode(
        const Episode(
          id: 1,
          podcastId: 1,
          guid: 'one',
          title: 'Episode',
          audioUrl: 'https://example.com/changed-ad-version.mp3',
        ),
      );
      final transcript = TranscriptController(
        FakePodcastRepository(transcript: restored),
        playback,
        audioStore: store,
      );
      addTearDown(() {
        transcript.dispose();
        playback.dispose();
      });
      await transcript.load(1);
      expect(engine.loadedUrl, (await store.resolve(key))!.uri.toString());
      await transcript.select(restored.segments.first);
      expect(playback.position, const Duration(seconds: 100));
      expect(transcript.activeSegment?.text, 'Bound sentence.');
      await transcript.load(1);
      expect(engine.loadCount, 2);
    },
  );

  test(
    'a missing bound recording is not silently replaced with remote audio',
    () async {
      final document = TranscriptDocument(
        episodeId: 1,
        language: 'en',
        source: currentPhoneTranscriptSource,
        audioKey: 'episode-1-999.mp3',
        segments: const [
          TranscriptSegment(
            index: 0,
            startMs: 0,
            endMs: 1000,
            text: 'Sentence.',
            paragraphIndex: 0,
          ),
        ],
      );
      final playback = PlaybackController(FakePlaybackEngine());
      final transcript = TranscriptController(
        FakePodcastRepository(transcript: document),
        playback,
        audioStore: store,
      );
      addTearDown(() {
        transcript.dispose();
        playback.dispose();
      });
      await transcript.load(1);
      expect(transcript.document, isNull);
      expect(transcript.errorMessage, contains('音频已丢失'));
    },
  );

  test('legacy subtitles remain readable without an audio key', () async {
    final doc = TranscriptDocument.fromJson({
      'episode_id': 1,
      'language': 'en',
      'source': 'rss',
      'segments': [],
    });
    expect(doc.audioKey, isNull);
  });

  test(
    'legacy or imported timeline never highlights the body during ads',
    () async {
      for (final source in [
        'android-v5-parakeet-tdt-0.6b-v2-int8',
        'rss',
        currentPhoneTranscriptSource,
      ]) {
        final doc = TranscriptDocument(
          episodeId: 1,
          language: 'en',
          source: source,
          segments: const [
            TranscriptSegment(
              index: 0,
              startMs: 0,
              endMs: 60000,
              text: 'Main content without the current ad.',
              paragraphIndex: 0,
            ),
          ],
        );
        final engine = FakePlaybackEngine();
        final playback = PlaybackController(engine);
        await playback.loadEpisode(_episode);
        final controller = TranscriptController(
          FakePodcastRepository(transcript: doc),
          playback,
          audioStore: store,
        );
        await controller.load(1);
        engine.emitPosition(const Duration(seconds: 20));
        expect(controller.document, same(doc));
        expect(controller.needsAlignment, isTrue);
        expect(controller.activeSegment, isNull);
        expect(controller.canSelectNext, isFalse);
        expect(playback.sentenceRange, isNull);
        await controller.select(doc.segments.first);
        expect(engine.position, const Duration(seconds: 20));
        controller.dispose();
        playback.dispose();
      }
    },
  );

  test(
    'bound captions follow actual media time, leaving the intro gap intact',
    () async {
      final file = File('${temporary.path}/intro.mp3');
      await file.writeAsBytes([1, 2, 3]);
      final key = await store.retain(file, episodeId: 1);
      final doc = TranscriptDocument(
        episodeId: 1,
        language: 'en',
        source: currentPhoneTranscriptSource,
        audioKey: key,
        segments: const [
          TranscriptSegment(
            index: 0,
            startMs: 65000,
            endMs: 70000,
            text: 'The main content begins.',
            paragraphIndex: 0,
          ),
          TranscriptSegment(
            index: 1,
            startMs: 70000,
            endMs: 75000,
            text: 'The next sentence.',
            paragraphIndex: 0,
          ),
        ],
      );
      final engine = FakePlaybackEngine();
      final playback = PlaybackController(engine);
      await playback.loadEpisode(_episode);
      final controller = TranscriptController(
        FakePodcastRepository(transcript: doc),
        playback,
        audioStore: store,
      );
      addTearDown(() {
        controller.dispose();
        playback.dispose();
      });
      await controller.load(1);
      expect(controller.hasSynchronizedTranscript, isTrue);
      engine.emitPosition(const Duration(seconds: 30));
      expect(controller.activeSegment, isNull);
      engine.bufferedPosition = const Duration(seconds: 200);
      await playback.setSpeed(2);
      expect(controller.activeSegment, isNull);
      await playback.skip(const Duration(seconds: 30));
      expect(controller.activeSegment, isNull);
      engine.emitPosition(const Duration(seconds: 65));
      expect(controller.activeSegment?.index, 0);
      engine.processingState = EngineProcessingState.loading;
      engine.emitPosition(const Duration(seconds: 71));
      expect(controller.activeSegment?.index, 0);
      engine.processingState = EngineProcessingState.ready;
      engine.emitPosition(const Duration(seconds: 71));
      expect(controller.activeSegment?.index, 1);
      await playback.seek(const Duration(seconds: 30));
      expect(controller.activeSegment, isNull);
    },
  );
}

const _episode = Episode(
  id: 1,
  podcastId: 1,
  guid: 'intro-episode',
  title: 'With intro',
  audioUrl: 'https://example.com/with-ads.mp3',
);
