import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/automatic_transcription_runner.dart';
import 'package:listen/features/player/application/on_device_transcriber.dart';

import 'fake_podcast_repository.dart';

void main() {
  test(
    'transcribes only the newest five episodes in descending order',
    () async {
      const podcasts = [
        Podcast(
          id: 1,
          title: 'One',
          feedUrl: 'https://example.com/one.xml',
          episodeCount: 4,
        ),
        Podcast(
          id: 2,
          title: 'Two',
          feedUrl: 'https://example.com/two.xml',
          episodeCount: 3,
        ),
      ];
      final episodes = {
        1: [_episode(1, 1), _episode(3, 3), _episode(5, 5), _episode(7, 7)],
        2: [_episode(2, 2), _episode(4, 4), _episode(6, 6)],
      };
      final repository = FakePodcastRepository(
        podcasts: podcasts,
        episodes: episodes,
      );
      final transcriber = _RecordingTranscriber();
      final runner = AutomaticTranscriptionRunner(repository, transcriber);

      await runner.run(podcasts);

      expect(transcriber.episodeIds, [7, 6, 5, 4, 3]);
      expect(repository.savedTranscripts.map((item) => item.episodeId), [
        7,
        6,
        5,
        4,
        3,
      ]);
    },
  );

  test('skips a recent episode that already has a phone cache', () async {
    const podcast = Podcast(
      id: 1,
      title: 'One',
      feedUrl: 'https://example.com/one.xml',
      episodeCount: 2,
    );
    final repository = FakePodcastRepository(
      podcasts: const [podcast],
      episodes: {
        1: [_episode(1, 1), _episode(2, 2)],
      },
    );
    final transcriber = _RecordingTranscriber(cachedEpisodeIds: {2});

    await AutomaticTranscriptionRunner(
      repository,
      transcriber,
    ).run(const [podcast]);

    expect(transcriber.episodeIds, [1]);
  });

  test('queues foreground and background model work serially', () async {
    final delegate = _BlockingTranscriber();
    final queued = QueuedOnDeviceTranscriber(delegate);

    final first = queued.transcribe(_episode(1, 1));
    final second = queued.transcribe(_episode(2, 2));
    await Future<void>.delayed(Duration.zero);
    expect(delegate.episodeIds, [1]);

    delegate.completeNext();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(delegate.episodeIds, [1, 2]);

    delegate.completeNext();
    await second;
  });

  test('coalesces duplicate work for the same episode', () async {
    final delegate = _BlockingTranscriber();
    final queued = QueuedOnDeviceTranscriber(delegate);
    final replayedProgress = <DeviceTranscriptionProgress>[];

    final first = queued.transcribe(_episode(1, 1));
    await Future<void>.delayed(Duration.zero);
    delegate.emitProgress(
      const DeviceTranscriptionProgress(message: '正在下载模型…', fraction: 0.42),
    );
    final duplicate = queued.transcribe(
      _episode(1, 1),
      onProgress: replayedProgress.add,
    );

    expect(delegate.episodeIds, [1]);
    expect(replayedProgress.single.fraction, 0.42);
    expect(replayedProgress.single.message, '正在下载模型…');
    delegate.completeNext();
    await Future.wait([first, duplicate]);
    expect(delegate.episodeIds, [1]);
  });
}

Episode _episode(int id, int day) => Episode(
  id: id,
  podcastId: id.isEven ? 2 : 1,
  guid: 'episode-$id',
  title: 'Episode $id',
  audioUrl: 'https://example.com/$id.mp3',
  publishedAt: DateTime(2026, 8, day),
);

class _RecordingTranscriber implements OnDeviceTranscriber {
  _RecordingTranscriber({this.cachedEpisodeIds = const {}});

  final Set<int> cachedEpisodeIds;
  final List<int> episodeIds = [];

  @override
  bool get isSupported => true;

  @override
  Future<TranscriptDocument?> readCached(int episodeId) async {
    if (!cachedEpisodeIds.contains(episodeId)) return null;
    return _transcript(episodeId);
  }

  @override
  Future<TranscriptDocument> transcribe(
    Episode episode, {
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) async {
    episodeIds.add(episode.id);
    return _transcript(episode.id);
  }
}

class _BlockingTranscriber implements OnDeviceTranscriber {
  final List<int> episodeIds = [];
  final List<
    (
      int,
      Completer<TranscriptDocument>,
      void Function(DeviceTranscriptionProgress)?,
    )
  >
  _pending = [];

  @override
  bool get isSupported => true;

  @override
  Future<TranscriptDocument?> readCached(int episodeId) async => null;

  @override
  Future<TranscriptDocument> transcribe(
    Episode episode, {
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) {
    episodeIds.add(episode.id);
    final completer = Completer<TranscriptDocument>();
    _pending.add((episode.id, completer, onProgress));
    return completer.future;
  }

  void emitProgress(DeviceTranscriptionProgress progress) {
    _pending.first.$3?.call(progress);
  }

  void completeNext() {
    final item = _pending.removeAt(0);
    item.$2.complete(_transcript(item.$1));
  }
}

TranscriptDocument _transcript(int episodeId) => TranscriptDocument(
  episodeId: episodeId,
  language: 'en',
  source: 'android-v5-parakeet-tdt-0.6b-v2-int8',
  segments: const [
    TranscriptSegment(
      index: 0,
      startMs: 0,
      endMs: 1000,
      text: 'Hello.',
      paragraphIndex: 0,
    ),
  ],
);
