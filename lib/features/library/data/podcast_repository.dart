import 'dart:convert';
import 'dart:io';

import '../domain/podcast.dart';
import '../../progress/domain/listening_stats.dart';

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

  Future<ListeningStats> listeningStats(DateTime today);

  Future<ListeningStats> recordListening({
    required int seconds,
    required DateTime listenedAt,
  });
}

class PodcastRepositoryException implements Exception {
  const PodcastRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HttpPodcastRepository implements PodcastRepository {
  HttpPodcastRepository({
    String baseUrl = const String.fromEnvironment(
      'LISTEN_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  final String _baseUrl;

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('$_baseUrl$path'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = responseBody.isEmpty ? null : jsonDecode(responseBody);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map<String, dynamic>
            ? decoded['detail']?.toString()
            : null;
        throw PodcastRepositoryException(
          detail ?? '请求失败（${response.statusCode}）',
        );
      }
      return decoded;
    } on PodcastRepositoryException {
      rethrow;
    } on SocketException {
      throw const PodcastRepositoryException('无法连接本地服务，请先启动后端');
    } on FormatException {
      throw const PodcastRepositoryException('服务返回了无法识别的数据');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<Podcast>> listSubscriptions() async {
    final data = await _request('GET', '/subscriptions') as List<dynamic>;
    return data
        .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Podcast> addSubscription(String feedUrl) async {
    final data = await _request(
      'POST',
      '/subscriptions',
      body: {'feed_url': feedUrl},
    );
    return Podcast.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteSubscription(int podcastId) async {
    await _request('DELETE', '/subscriptions/$podcastId');
  }

  @override
  Future<List<Episode>> listEpisodes(int podcastId) async {
    final data = await _request(
      'GET',
      '/subscriptions/$podcastId/episodes',
    ) as List<dynamic>;
    return data
        .map((item) => Episode.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<RefreshResult> refreshSubscriptions() async {
    final data = await _request('POST', '/subscriptions/refresh');
    return RefreshResult.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<List<PodcastSearchResult>> search(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final data = await _request('GET', '/search?q=$encoded') as List<dynamic>;
    return data
        .map(
          (item) => PodcastSearchResult.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<TranscriptDocument> importTranscript(int episodeId) async {
    final data = await _request(
      'POST',
      '/episodes/$episodeId/transcript/import',
    );
    return TranscriptDocument.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<TranscriptDocument> transcribeEpisode(
    int episodeId, {
    String? language,
  }) async {
    final data = await _request(
      'POST',
      '/episodes/$episodeId/transcript/transcribe',
      body: {'language': language},
    );
    return TranscriptDocument.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<TranscriptDocument> saveTranscript(TranscriptDocument document) async {
    final data = await _request(
      'POST',
      '/episodes/${document.episodeId}/transcript/upload',
      body: {
        'language': document.language,
        'source': document.source,
        'segments': document.segments
            .map(
              (segment) => {
                'index': segment.index,
                'start_ms': segment.startMs,
                'end_ms': segment.endMs,
                'text': segment.text,
                'speaker': segment.speaker,
                'paragraph_index': segment.paragraphIndex,
              },
            )
            .toList(),
      },
    );
    return TranscriptDocument.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<TranscriptDocument> translateTranscript(
    int episodeId, {
    String targetLanguage = 'zh-Hans',
  }) async {
    final data = await _request(
      'POST',
      '/episodes/$episodeId/transcript/translate',
      body: {'target_language': targetLanguage},
    );
    return TranscriptDocument.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<ListeningStats> listeningStats(DateTime today) async {
    final date = _dateOnly(today);
    final data = await _request('GET', '/listening/stats?today=$date');
    return ListeningStats.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<ListeningStats> recordListening({
    required int seconds,
    required DateTime listenedAt,
  }) async {
    final data = await _request(
      'POST',
      '/listening/record',
      body: {'seconds': seconds, 'listened_at': listenedAt.toIso8601String()},
    );
    return ListeningStats.fromJson(data as Map<String, dynamic>);
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
