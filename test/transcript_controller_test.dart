import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/player/application/on_device_transcriber.dart';
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
      await playback.loadEpisode(
        const Episode(
          id: 1,
          podcastId: 1,
          guid: 'episode-1',
          title: 'Episode One',
          audioUrl: 'https://example.com/episode.mp3',
        ),
      );
      final transcript = TranscriptController(
        FakePodcastRepository(transcript: document),
        playback,
      );
      await transcript.load(1);

      await transcript.select(document.segments[1]);
      await playback.setRepeatMode(PlaybackRepeatMode.sentence);

      expect(playback.sentenceRange?.start, const Duration(milliseconds: 2500));
      expect(playback.sentenceRange?.end, const Duration(milliseconds: 4000));

      expect(transcript.canSelectPrevious, isTrue);
      expect(transcript.canSelectNext, isFalse);
      await transcript.selectPrevious();
      expect(transcript.activeSegment?.index, 0);
      expect(engine.position, const Duration(milliseconds: 1000));
      expect(playback.sentenceRange?.start, const Duration(milliseconds: 1000));
      expect(playback.sentenceRange?.end, const Duration(milliseconds: 2500));

      await transcript.selectNext();
      expect(transcript.activeSegment?.index, 1);
      expect(engine.position, const Duration(milliseconds: 2500));
      expect(playback.sentenceRange?.start, const Duration(milliseconds: 2500));
      expect(playback.sentenceRange?.end, const Duration(milliseconds: 4000));

      await playback.setRepeatMode(PlaybackRepeatMode.paragraph);
      expect(
        playback.paragraphRange?.start,
        const Duration(milliseconds: 1000),
      );
      expect(playback.paragraphRange?.end, const Duration(milliseconds: 4000));
      expect(engine.loadCount, 1);
      expect(engine.pauseCount, 0);

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

  test('stale position event cannot undo next sentence selection', () async {
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
    final engine = _DeferredSeekPlaybackEngine();
    final playback = PlaybackController(engine);
    await playback.loadEpisode(
      const Episode(
        id: 1,
        podcastId: 1,
        guid: 'episode-1',
        title: 'Episode One',
        audioUrl: 'https://example.com/episode.mp3',
      ),
    );
    final transcript = TranscriptController(
      FakePodcastRepository(transcript: document),
      playback,
    );
    await transcript.load(1);
    await transcript.select(document.segments.first);
    await playback.setRepeatMode(PlaybackRepeatMode.sentence);

    engine.deferSeek = true;
    final selection = transcript.selectNext();
    await pumpEventQueue();
    engine.emitPosition(const Duration(milliseconds: 1000));

    // A requested position is not evidence that the audio has reached it.
    expect(transcript.activeSegment?.index, 0);
    expect(playback.position, const Duration(milliseconds: 2500));
    expect(playback.actualPosition, const Duration(milliseconds: 1000));

    engine.completeSeek();
    await selection;
    expect(transcript.activeSegment?.index, 1);
    expect(playback.sentenceRange?.start, const Duration(milliseconds: 2500));
    expect(playback.sentenceRange?.end, const Duration(milliseconds: 4000));
  });

  test('Android local transcript is shown progressively and synced', () async {
    final engine = FakePlaybackEngine();
    final playback = PlaybackController(engine);
    const episode = Episode(
      id: 7,
      podcastId: 1,
      guid: 'episode-7',
      title: 'Phone transcript',
      audioUrl: 'https://example.com/episode.mp3',
    );
    await playback.loadEpisode(episode);
    final repository = FakePodcastRepository();
    final transcriber = _FakeOnDeviceTranscriber();
    final transcript = TranscriptController(
      repository,
      playback,
      onDeviceTranscriber: transcriber,
    );
    await transcript.load(episode.id);

    await transcript.transcribe();

    expect(transcript.document?.segments.single.text, 'Local sentence.');
    expect(
      repository.savedTranscript?.source,
      'android-v5-parakeet-tdt-0.6b-v2-int8',
    );
    expect(transcript.transcriptionProgress, 1);
    expect(transcript.errorMessage, isNull);
  });
}

class _DeferredSeekPlaybackEngine extends FakePlaybackEngine {
  bool deferSeek = false;
  Duration? _requestedPosition;
  final _seekCompleted = Completer<void>();

  @override
  Future<void> seek(Duration value) async {
    if (!deferSeek) return super.seek(value);
    _requestedPosition = value;
    await _seekCompleted.future;
  }

  void completeSeek() {
    final value = _requestedPosition;
    if (value == null) return;
    _requestedPosition = null;
    emitPosition(value);
    _seekCompleted.complete();
  }
}

class _FakeOnDeviceTranscriber implements OnDeviceTranscriber {
  @override
  bool get isSupported => true;

  @override
  Future<TranscriptDocument?> readCached(int episodeId) async => null;

  @override
  Future<TranscriptDocument> transcribe(
    Episode episode, {
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) async {
    const document = TranscriptDocument(
      episodeId: 7,
      language: 'en',
      source: 'android-v5-parakeet-tdt-0.6b-v2-int8',
      segments: [
        TranscriptSegment(
          index: 0,
          startMs: 0,
          endMs: 1500,
          text: 'Local sentence.',
          paragraphIndex: 0,
        ),
      ],
    );
    onProgress?.call(
      const DeviceTranscriptionProgress(message: '识别完成', fraction: 1),
    );
    onPartial?.call(document);
    return document;
  }
}
