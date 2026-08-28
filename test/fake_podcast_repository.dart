import 'package:listen/features/library/data/podcast_repository.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/progress/domain/listening_stats.dart';

class FakePodcastRepository implements PodcastRepository {
  FakePodcastRepository({
    List<Podcast> podcasts = const [],
    Map<int, List<Episode>> episodes = const {},
    this.transcript,
  }) : _podcasts = [...podcasts],
       _episodes = episodes.map(
         (podcastId, items) => MapEntry(podcastId, [...items]),
       );

  final List<Podcast> _podcasts;
  final Map<int, List<Episode>> _episodes;
  final TranscriptDocument? transcript;
  TranscriptDocument? savedTranscript;
  final List<TranscriptDocument> savedTranscripts = [];
  int addCallCount = 0;
  int recordedSeconds = 0;

  @override
  Future<Podcast> addSubscription(String feedUrl) async {
    addCallCount += 1;
    final podcast = Podcast(
      id: _podcasts.length + 1,
      title: '测试播客',
      feedUrl: feedUrl,
      episodeCount: 1,
    );
    _podcasts.add(podcast);
    return podcast;
  }

  @override
  Future<void> deleteSubscription(int podcastId) async {
    _podcasts.removeWhere((podcast) => podcast.id == podcastId);
  }

  @override
  Future<List<Episode>> listEpisodes(int podcastId) async => [
    ...?_episodes[podcastId],
  ];

  @override
  Future<List<Podcast>> listSubscriptions() async => [..._podcasts];

  @override
  Future<RefreshResult> refreshSubscriptions() async {
    return const RefreshResult(newEpisodes: 0, failures: []);
  }

  @override
  Future<List<PodcastSearchResult>> search(String query) async => const [];

  @override
  Future<TranscriptDocument> importTranscript(int episodeId) async {
    if (transcript != null) return transcript!;
    throw const PodcastRepositoryException('这个单集没有提供带时间轴的字幕');
  }

  @override
  Future<TranscriptDocument> transcribeEpisode(
    int episodeId, {
    String? language,
  }) async {
    return TranscriptDocument(
      episodeId: episodeId,
      language: language ?? 'en',
      source: 'fake',
      segments: const [
        TranscriptSegment(
          index: 0,
          startMs: 1000,
          endMs: 2500,
          text: 'Hello',
          paragraphIndex: 0,
        ),
      ],
    );
  }

  @override
  Future<TranscriptDocument> saveTranscript(TranscriptDocument document) async {
    savedTranscript = document;
    savedTranscripts.add(document);
    return document;
  }

  @override
  Future<TranscriptDocument> translateTranscript(
    int episodeId, {
    String targetLanguage = 'zh-Hans',
  }) async {
    final original = transcript ?? await transcribeEpisode(episodeId);
    return TranscriptDocument(
      episodeId: original.episodeId,
      language: original.language,
      source: original.source,
      targetLanguage: targetLanguage,
      translationSource: 'fake',
      segments: original.segments
          .map(
            (segment) => TranscriptSegment(
              index: segment.index,
              startMs: segment.startMs,
              endMs: segment.endMs,
              text: segment.text,
              speaker: segment.speaker,
              paragraphIndex: segment.paragraphIndex,
              translation: '中文：${segment.text}',
            ),
          )
          .toList(),
    );
  }

  @override
  Future<ListeningStats> listeningStats(DateTime today, {int days = 7}) async {
    return ListeningStats(
      todaySeconds: recordedSeconds,
      totalSeconds: recordedSeconds,
      streakDays: recordedSeconds > 0 ? 1 : 0,
      daily: List.generate(
        days,
        (index) => DailyListening(
          date: DateTime(today.year, today.month, today.day - days + 1 + index),
          seconds: index == days - 1 ? recordedSeconds : 0,
        ),
      ),
    );
  }

  @override
  Future<ListeningStats> recordListening({
    required int seconds,
    required DateTime listenedAt,
    int days = 7,
  }) async {
    recordedSeconds += seconds;
    return listeningStats(listenedAt, days: days);
  }
}
