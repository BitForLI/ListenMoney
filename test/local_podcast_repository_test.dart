import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/data/local_feed.dart';
import 'package:listen/features/library/data/local_podcast_repository.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/data/mobile_transcript_translator.dart';

void main() {
  late Directory directory;
  late File storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('listen-local-test-');
    storage = File('${directory.path}/listen.json');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('persists subscriptions, transcripts and listening history', () async {
    final repository = LocalPodcastRepository(
      storageFile: storage,
      feedGateway: _FakeFeedGateway(),
      translator: _FakeTranslator(),
      initialFeedUrls: const [],
    );
    final podcast = await repository.addSubscription(
      'https://example.com/feed',
    );
    final episode = (await repository.listEpisodes(podcast.id)).single;
    await repository.saveTranscript(
      TranscriptDocument(
        episodeId: episode.id,
        language: 'en',
        source: 'test',
        audioKey: 'episode-1-123.mp3',
        segments: const [
          TranscriptSegment(
            index: 0,
            startMs: 0,
            endMs: 1000,
            text: 'Hello',
            paragraphIndex: 0,
          ),
        ],
      ),
    );
    expect((await repository.recordSentenceRepeat(episode.id, 0))?.repeatCount, 1);
    expect((await repository.recordSentenceRepeat(episode.id, 0))?.repeatCount, 2);
    await repository.recordListening(
      seconds: 30,
      listenedAt: DateTime(2026, 8, 28),
    );
    await repository.savePlaybackSession(
      PlaybackSession(
        episode: episode,
        positionMs: 123456,
        speed: 1.25,
        podcastTitle: podcast.title,
        artworkUrl: podcast.artworkUrl,
      ),
    );

    final restored = LocalPodcastRepository(
      storageFile: storage,
      feedGateway: _FakeFeedGateway(),
      translator: _FakeTranslator(),
      initialFeedUrls: const [],
    );
    expect(await restored.listSubscriptions(), hasLength(1));
    expect(
      (await restored.listEpisodes(podcast.id)).single.transcriptReady,
      isTrue,
    );
    expect(
      (await restored.importTranscript(episode.id)).segments.single.text,
      'Hello',
    );
    final review = (await restored.listReviewSentences()).single;
    expect(review.text, 'Hello');
    expect(review.repeatCount, 2);
    expect(review.episodeTitle, episode.title);
    expect(
      (await restored.listeningStats(DateTime(2026, 8, 28))).todaySeconds,
      30,
    );
    final session = await restored.loadPlaybackSession();
    expect(session?.episode.id, episode.id);
    expect(session?.positionMs, 123456);
    expect(session?.speed, 1.25);
    expect(session?.podcastTitle, podcast.title);
    final translated = await restored.translateTranscript(episode.id);
    expect(translated.segments.single.translation, '中文：Hello');
    expect(translated.audioKey, 'episode-1-123.mp3');
    expect(
      (await restored.importTranscript(episode.id)).audioKey,
      'episode-1-123.mp3',
    );
    await restored.removeReviewSentence(episode.id, 0);
    expect(await restored.listReviewSentences(), isEmpty);
  });
}

class _FakeFeedGateway extends LocalFeedGateway {
  @override
  Future<LocalFeedResult> fetch(
    String feedUrl, {
    String? etag,
    String? lastModified,
  }) async {
    return LocalFeedResult(
      title: 'Example',
      episodes: [
        LocalFeedEpisode(
          guid: 'one',
          title: 'Episode One',
          audioUrl: 'https://example.com/one.mp3',
          publishedAt: DateTime.utc(2026, 8, 28),
        ),
      ],
    );
  }
}

class _FakeTranslator implements TranscriptTranslator {
  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    return texts.map((text) => '中文：$text').toList();
  }
}
