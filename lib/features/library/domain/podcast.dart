class Podcast {
  const Podcast({
    required this.id,
    required this.title,
    required this.feedUrl,
    required this.episodeCount,
    this.author,
    this.description,
    this.artworkUrl,
    this.websiteUrl,
    this.lastCheckedAt,
  });

  factory Podcast.fromJson(Map<String, dynamic> json) {
    return Podcast(
      id: json['id'] as int,
      title: json['title'] as String,
      feedUrl: json['feed_url'] as String,
      episodeCount: json['episode_count'] as int? ?? 0,
      author: json['author'] as String?,
      description: json['description'] as String?,
      artworkUrl: json['artwork_url'] as String?,
      websiteUrl: json['website_url'] as String?,
      lastCheckedAt: json['last_checked_at'] == null
          ? null
          : DateTime.tryParse(json['last_checked_at'] as String),
    );
  }

  final int id;
  final String title;
  final String feedUrl;
  final int episodeCount;
  final String? author;
  final String? description;
  final String? artworkUrl;
  final String? websiteUrl;
  final DateTime? lastCheckedAt;
}

class Episode {
  const Episode({
    required this.id,
    required this.podcastId,
    required this.guid,
    required this.title,
    required this.audioUrl,
    this.description,
    this.publishedAt,
    this.durationSeconds,
    this.hasTranscriptSource = false,
    this.transcriptReady = false,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'] as int,
      podcastId: json['podcast_id'] as int,
      guid: json['guid'] as String,
      title: json['title'] as String,
      audioUrl: json['audio_url'] as String,
      description: json['description'] as String?,
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.tryParse(json['published_at'] as String),
      durationSeconds: json['duration_seconds'] as int?,
      hasTranscriptSource: json['has_transcript_source'] as bool? ?? false,
      transcriptReady: json['transcript_ready'] as bool? ?? false,
    );
  }

  final int id;
  final int podcastId;
  final String guid;
  final String title;
  final String audioUrl;
  final String? description;
  final DateTime? publishedAt;
  final int? durationSeconds;
  final bool hasTranscriptSource;
  final bool transcriptReady;
}

class PodcastSearchResult {
  const PodcastSearchResult({
    required this.title,
    required this.feedUrl,
    this.author,
    this.artworkUrl,
  });

  factory PodcastSearchResult.fromJson(Map<String, dynamic> json) {
    return PodcastSearchResult(
      title: json['title'] as String,
      feedUrl: json['feed_url'] as String,
      author: json['author'] as String?,
      artworkUrl: json['artwork_url'] as String?,
    );
  }

  final String title;
  final String feedUrl;
  final String? author;
  final String? artworkUrl;
}

class RefreshResult {
  const RefreshResult({required this.newEpisodes, required this.failures});

  factory RefreshResult.fromJson(Map<String, dynamic> json) {
    return RefreshResult(
      newEpisodes: json['new_episodes'] as int? ?? 0,
      failures: (json['failures'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(),
    );
  }

  final int newEpisodes;
  final List<String> failures;
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.paragraphIndex,
    this.speaker,
    this.translation,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      index: json['index'] as int,
      startMs: json['start_ms'] as int,
      endMs: json['end_ms'] as int,
      text: json['text'] as String,
      speaker: json['speaker'] as String?,
      paragraphIndex: json['paragraph_index'] as int,
      translation: json['translation'] as String?,
    );
  }

  final int index;
  final int startMs;
  final int endMs;
  final String text;
  final String? speaker;
  final int paragraphIndex;
  final String? translation;
}

class TranscriptDocument {
  const TranscriptDocument({
    required this.episodeId,
    required this.language,
    required this.source,
    required this.segments,
    this.targetLanguage,
    this.translationSource,
  });

  factory TranscriptDocument.fromJson(Map<String, dynamic> json) {
    return TranscriptDocument(
      episodeId: json['episode_id'] as int,
      language: json['language'] as String,
      source: json['source'] as String,
      segments: (json['segments'] as List<dynamic>)
          .map(
            (item) => TranscriptSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      targetLanguage: json['target_language'] as String?,
      translationSource: json['translation_source'] as String?,
    );
  }

  final int episodeId;
  final String language;
  final String source;
  final List<TranscriptSegment> segments;
  final String? targetLanguage;
  final String? translationSource;
}
