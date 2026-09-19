class ReviewSentence {
  const ReviewSentence({
    required this.episodeId,
    required this.podcastId,
    required this.episodeTitle,
    required this.startMs,
    required this.text,
    required this.repeatCount,
    required this.lastRepeatedAt,
  });

  factory ReviewSentence.fromJson(Map<String, dynamic> json) => ReviewSentence(
    episodeId: json['episode_id'] as int,
    podcastId: json['podcast_id'] as int,
    episodeTitle: json['episode_title'] as String,
    startMs: json['start_ms'] as int,
    text: json['text'] as String,
    repeatCount: json['repeat_count'] as int,
    lastRepeatedAt: DateTime.parse(json['last_repeated_at'] as String),
  );

  final int episodeId;
  final int podcastId;
  final String episodeTitle;
  final int startMs;
  final String text;
  final int repeatCount;
  final DateTime lastRepeatedAt;

  Map<String, dynamic> toJson() => {
    'episode_id': episodeId,
    'podcast_id': podcastId,
    'episode_title': episodeTitle,
    'start_ms': startMs,
    'text': text,
    'repeat_count': repeatCount,
    'last_repeated_at': lastRepeatedAt.toIso8601String(),
  };
}
