import '../../progress/domain/listening_stats.dart';
import '../../progress/domain/review_sentence.dart';
import '../domain/podcast.dart';

abstract class PodcastRepository {
  Future<List<Podcast>> listSubscriptions();

  Future<Podcast> addSubscription(String feedUrl);

  Future<void> deleteSubscription(int podcastId);

  Future<List<Episode>> listEpisodes(int podcastId);

  Future<RefreshResult> refreshSubscriptions();

  Future<List<PodcastSearchResult>> search(String query);

  Future<TranscriptDocument> importTranscript(int episodeId);

  Future<TranscriptDocument> transcribeEpisode(
    int episodeId, {
    String? language,
  });

  Future<TranscriptDocument> saveTranscript(TranscriptDocument document);

  Future<TranscriptDocument> translateTranscript(
    int episodeId, {
    String targetLanguage,
  });

  Future<ListeningStats> listeningStats(DateTime today, {int days = 7});

  Future<ListeningStats> recordListening({
    required int seconds,
    required DateTime listenedAt,
    int days = 7,
  });

  Future<List<ReviewSentence>> listReviewSentences();

  Future<ReviewSentence?> recordSentenceRepeat(int episodeId, int startMs);

  Future<void> removeReviewSentence(int episodeId, int startMs);
}

class PodcastRepositoryException implements Exception {
  const PodcastRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
