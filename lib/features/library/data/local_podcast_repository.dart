import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../player/data/local_transcript.dart';
import '../../player/data/mobile_transcript_translator.dart';
import '../../progress/domain/listening_stats.dart';
import '../domain/podcast.dart';
import 'local_feed.dart';
import 'podcast_repository.dart';

class LocalPodcastRepository implements PodcastRepository {
  factory LocalPodcastRepository({
    File? storageFile,
    LocalFeedGateway feedGateway = const LocalFeedGateway(),
    TranscriptTranslator? translator,
    List<String> initialFeedUrls = defaultInitialFeedUrls,
  }) {
    return LocalPodcastRepository._(
      storageFile,
      feedGateway,
      translator,
      initialFeedUrls,
    );
  }

  LocalPodcastRepository._(
    this._storageFile,
    this._feedGateway,
    this._translator,
    this._initialFeedUrls,
  );

  static const defaultInitialFeedUrls = [
    'https://feeds.megaphone.fm/allearsenglish',
    'https://feeds.transistor.fm/practical-ai-machine-learning-data-science-llm',
  ];

  File? _storageFile;
  final LocalFeedGateway _feedGateway;
  final TranscriptTranslator? _translator;
  final List<String> _initialFeedUrls;
  Future<void>? _loading;
  Future<void> _writeQueue = Future<void>.value();
  int _nextPodcastId = 1;
  int _nextEpisodeId = 1;
  bool _didSeedDefaults = false;
  final List<Podcast> _podcasts = [];
  final Map<int, List<Episode>> _episodes = {};
  final Map<int, TranscriptDocument> _transcripts = {};
  final Map<int, Map<String, String?>> _feedCache = {};
  final Map<String, int> _listeningDays = {};

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _storageFile ??= File(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}listen-local-v1.json',
    );
    if (!await _storageFile!.exists()) return;
    try {
      final value = jsonDecode(await _storageFile!.readAsString());
      if (value is! Map<String, dynamic>) throw const FormatException();
      _nextPodcastId = value['next_podcast_id'] as int? ?? 1;
      _nextEpisodeId = value['next_episode_id'] as int? ?? 1;
      _didSeedDefaults = value['did_seed_defaults'] as bool? ?? false;
      _podcasts
        ..clear()
        ..addAll(
          (value['podcasts'] as List<dynamic>? ?? const []).map(
            (item) => Podcast.fromJson(item as Map<String, dynamic>),
          ),
        );
      _episodes.clear();
      for (final item in value['episodes'] as List<dynamic>? ?? const []) {
        final episode = Episode.fromJson(item as Map<String, dynamic>);
        _episodes.putIfAbsent(episode.podcastId, () => []).add(episode);
      }
      _transcripts.clear();
      final transcripts =
          value['transcripts'] as Map<String, dynamic>? ?? const {};
      for (final entry in transcripts.entries) {
        _transcripts[int.parse(entry.key)] = TranscriptDocument.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
      _feedCache.clear();
      final cache = value['feed_cache'] as Map<String, dynamic>? ?? const {};
      for (final entry in cache.entries) {
        final item = entry.value as Map<String, dynamic>;
        _feedCache[int.parse(entry.key)] = {
          'etag': item['etag'] as String?,
          'last_modified': item['last_modified'] as String?,
        };
      }
      _listeningDays
        ..clear()
        ..addAll(
          (value['listening_days'] as Map<String, dynamic>? ?? const {}).map(
            (key, value) => MapEntry(key, value as int),
          ),
        );
      for (final episodes in _episodes.values) {
        episodes.sort(_newestFirst);
      }
    } on Object catch (error) {
      throw PodcastRepositoryException('手机本地数据无法读取：$error');
    }
  }

  Future<void> _seedDefaultsIfNeeded() async {
    if (_didSeedDefaults || _initialFeedUrls.isEmpty) return;
    var complete = true;
    for (final feedUrl in _initialFeedUrls) {
      if (_podcasts.any(
        (podcast) => podcast.feedUrl == _normalizeUrl(feedUrl),
      )) {
        continue;
      }
      try {
        await _addSubscription(feedUrl);
      } catch (_) {
        complete = false;
      }
    }
    if (complete) {
      _didSeedDefaults = true;
      await _save();
    }
  }

  @override
  Future<List<Podcast>> listSubscriptions() async {
    await _ensureLoaded();
    await _seedDefaultsIfNeeded();
    final results = _podcasts.map(_withEpisodeCount).toList()
      ..sort((left, right) => left.title.compareTo(right.title));
    return results;
  }

  @override
  Future<Podcast> addSubscription(String feedUrl) async {
    await _ensureLoaded();
    return _addSubscription(feedUrl);
  }

  Future<Podcast> _addSubscription(String feedUrl) async {
    if (_podcasts.length >= 10) {
      throw const PodcastRepositoryException('最多只能收藏 10 个播客');
    }
    final normalized = _normalizeUrl(feedUrl);
    if (_podcasts.any((podcast) => podcast.feedUrl == normalized)) {
      throw const PodcastRepositoryException('这个播客已经收藏');
    }
    final feed = await _feedGateway.fetch(normalized);
    if (feed.title.isEmpty) {
      throw const PodcastRepositoryException('RSS 没有返回播客内容');
    }
    final podcastId = _nextPodcastId++;
    final podcast = Podcast(
      id: podcastId,
      title: feed.title,
      feedUrl: normalized,
      episodeCount: feed.episodes.length,
      author: feed.author,
      description: feed.description,
      artworkUrl: feed.artworkUrl,
      websiteUrl: feed.websiteUrl,
      lastCheckedAt: DateTime.now(),
    );
    _podcasts.add(podcast);
    _episodes[podcastId] =
        feed.episodes
            .map((episode) => _createEpisode(podcastId, episode))
            .toList()
          ..sort(_newestFirst);
    _feedCache[podcastId] = {
      'etag': feed.etag,
      'last_modified': feed.lastModified,
    };
    await _save();
    return _withEpisodeCount(podcast);
  }

  @override
  Future<void> deleteSubscription(int podcastId) async {
    await _ensureLoaded();
    _podcasts.removeWhere((podcast) => podcast.id == podcastId);
    final removed = _episodes.remove(podcastId) ?? const [];
    for (final episode in removed) {
      _transcripts.remove(episode.id);
    }
    _feedCache.remove(podcastId);
    await _save();
  }

  @override
  Future<List<Episode>> listEpisodes(int podcastId) async {
    await _ensureLoaded();
    return (_episodes[podcastId] ?? const []).map(_withTranscriptReady).toList()
      ..sort(_newestFirst);
  }

  @override
  Future<RefreshResult> refreshSubscriptions() async {
    await _ensureLoaded();
    var newEpisodes = 0;
    final failures = <String>[];
    for (final podcast in List<Podcast>.of(_podcasts)) {
      final cache = _feedCache[podcast.id];
      try {
        final feed = await _feedGateway.fetch(
          podcast.feedUrl,
          etag: cache?['etag'],
          lastModified: cache?['last_modified'],
        );
        if (!feed.notModified) {
          newEpisodes += _syncFeed(podcast, feed);
        }
        _feedCache[podcast.id] = {
          'etag': feed.etag ?? cache?['etag'],
          'last_modified': feed.lastModified ?? cache?['last_modified'],
        };
      } catch (error) {
        failures.add('${podcast.title}: $error');
      }
    }
    await _save();
    return RefreshResult(newEpisodes: newEpisodes, failures: failures);
  }

  int _syncFeed(Podcast podcast, LocalFeedResult feed) {
    final current = _episodes.putIfAbsent(podcast.id, () => []);
    final byGuid = {for (final episode in current) episode.guid: episode};
    var inserted = 0;
    for (final incoming in feed.episodes) {
      final previous = byGuid[incoming.guid];
      if (previous == null) {
        current.add(_createEpisode(podcast.id, incoming));
        inserted += 1;
      } else {
        final updated = Episode(
          id: previous.id,
          podcastId: previous.podcastId,
          guid: previous.guid,
          title: incoming.title,
          audioUrl: incoming.audioUrl,
          description: incoming.description,
          publishedAt: incoming.publishedAt,
          durationSeconds: incoming.durationSeconds,
          websiteUrl: incoming.websiteUrl ?? previous.websiteUrl,
          hasTranscriptSource: incoming.transcriptSources.isNotEmpty,
          transcriptReady: _transcripts.containsKey(previous.id),
          transcriptSources: incoming.transcriptSources,
        );
        current[current.indexOf(previous)] = updated;
      }
    }
    current.sort(_newestFirst);
    final index = _podcasts.indexWhere((item) => item.id == podcast.id);
    _podcasts[index] = Podcast(
      id: podcast.id,
      title: feed.title,
      feedUrl: podcast.feedUrl,
      episodeCount: current.length,
      author: feed.author,
      description: feed.description,
      artworkUrl: feed.artworkUrl,
      websiteUrl: feed.websiteUrl,
      lastCheckedAt: DateTime.now(),
    );
    return inserted;
  }

  @override
  Future<List<PodcastSearchResult>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': text,
        'media': 'podcast',
        'entity': 'podcast',
        'limit': '20',
      });
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw PodcastRepositoryException(
          'Apple Podcasts 搜索失败（${response.statusCode}）',
        );
      }
      final payload = jsonDecode(await response.transform(utf8.decoder).join());
      final results = payload is Map<String, dynamic>
          ? payload['results'] as List<dynamic>? ?? const []
          : const <dynamic>[];
      return results
          .whereType<Map<String, dynamic>>()
          .where(
            (item) =>
                item['feedUrl'] is String && item['collectionName'] is String,
          )
          .map(
            (item) => PodcastSearchResult(
              title: item['collectionName'] as String,
              feedUrl: item['feedUrl'] as String,
              author: item['artistName'] as String?,
              artworkUrl:
                  item['artworkUrl600'] as String? ??
                  item['artworkUrl100'] as String?,
            ),
          )
          .toList();
    } on PodcastRepositoryException {
      rethrow;
    } on SocketException catch (error) {
      throw PodcastRepositoryException('无法搜索播客：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<TranscriptDocument> importTranscript(int episodeId) async {
    await _ensureLoaded();
    final cached = _transcripts[episodeId];
    if (cached != null) return cached;
    final episode = _episodeById(episodeId);
    if (episode == null) {
      throw const PodcastRepositoryException('单集不存在');
    }
    final supported = episode.transcriptSources.where(
      (source) => const {
        'text/vtt',
        'application/srt',
        'text/srt',
        'application/json',
        'application/ld+json',
      }.contains(source.mimeType.split(';').first.toLowerCase()),
    );
    Object? firstError;
    for (final source in supported) {
      try {
        final content = await _getText(source.url);
        final document = parseLocalTranscript(
          episodeId: episodeId,
          content: content,
          mimeType: source.mimeType,
          language: source.language,
        );
        _transcripts[episodeId] = document;
        await _save();
        return document;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
    throw const PodcastRepositoryException('这个单集没有提供带时间轴的字幕');
  }

  @override
  Future<TranscriptDocument> transcribeEpisode(
    int episodeId, {
    String? language,
  }) {
    throw const PodcastRepositoryException('请使用手机离线转写');
  }

  @override
  Future<TranscriptDocument> saveTranscript(TranscriptDocument document) async {
    await _ensureLoaded();
    if (_episodeById(document.episodeId) == null) {
      throw const PodcastRepositoryException('单集不存在');
    }
    _transcripts[document.episodeId] = document;
    await _save();
    return document;
  }

  @override
  Future<TranscriptDocument> translateTranscript(
    int episodeId, {
    String targetLanguage = 'zh-Hans',
  }) async {
    await _ensureLoaded();
    var original = _transcripts[episodeId];
    original ??= await importTranscript(episodeId);
    if (original.targetLanguage == targetLanguage &&
        original.segments.any((segment) => segment.translation != null)) {
      return original;
    }
    final translator = _translator;
    if (translator == null) {
      throw const PodcastRepositoryException('手机离线翻译尚不可用');
    }
    final translated = await translator.translate(
      original.segments.map((segment) => segment.text).toList(),
      sourceLanguage: original.language,
      targetLanguage: targetLanguage,
    );
    final document = TranscriptDocument(
      episodeId: original.episodeId,
      language: original.language,
      source: original.source,
      targetLanguage: targetLanguage,
      translationSource: 'google-mlkit-on-device',
      segments: [
        for (var index = 0; index < original.segments.length; index += 1)
          TranscriptSegment(
            index: original.segments[index].index,
            startMs: original.segments[index].startMs,
            endMs: original.segments[index].endMs,
            text: original.segments[index].text,
            speaker: original.segments[index].speaker,
            paragraphIndex: original.segments[index].paragraphIndex,
            translation: index < translated.length ? translated[index] : null,
          ),
      ],
    );
    _transcripts[episodeId] = document;
    await _save();
    return document;
  }

  @override
  Future<ListeningStats> listeningStats(DateTime today, {int days = 7}) async {
    await _ensureLoaded();
    final date = DateTime(today.year, today.month, today.day);
    final first = date.subtract(Duration(days: days - 1));
    final activeDates = _listeningDays.entries
        .where((entry) => entry.value > 0)
        .map((entry) => DateTime.tryParse(entry.key))
        .whereType<DateTime>()
        .map((value) => DateTime(value.year, value.month, value.day))
        .toSet();
    var cursor = activeDates.contains(date)
        ? date
        : date.subtract(const Duration(days: 1));
    var streak = 0;
    while (activeDates.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return ListeningStats(
      todaySeconds: _listeningDays[_dateKey(date)] ?? 0,
      totalSeconds: _listeningDays.values.fold(0, (sum, value) => sum + value),
      streakDays: streak,
      daily: List.generate(days, (index) {
        final day = first.add(Duration(days: index));
        return DailyListening(
          date: day,
          seconds: _listeningDays[_dateKey(day)] ?? 0,
        );
      }),
    );
  }

  @override
  Future<ListeningStats> recordListening({
    required int seconds,
    required DateTime listenedAt,
    int days = 7,
  }) async {
    await _ensureLoaded();
    if (seconds > 0) {
      final key = _dateKey(listenedAt);
      _listeningDays[key] = (_listeningDays[key] ?? 0) + seconds;
      await _save();
    }
    return listeningStats(listenedAt, days: days);
  }

  Future<String> _getText(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
      throw const PodcastRepositoryException('字幕地址无效');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw PodcastRepositoryException('无法获取字幕（${response.statusCode}）');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  Episode _createEpisode(int podcastId, LocalFeedEpisode value) {
    return Episode(
      id: _nextEpisodeId++,
      podcastId: podcastId,
      guid: value.guid,
      title: value.title,
      audioUrl: value.audioUrl,
      description: value.description,
      publishedAt: value.publishedAt,
      durationSeconds: value.durationSeconds,
      websiteUrl: value.websiteUrl,
      hasTranscriptSource: value.transcriptSources.isNotEmpty,
      transcriptSources: value.transcriptSources,
    );
  }

  Episode? _episodeById(int episodeId) {
    for (final episodes in _episodes.values) {
      for (final episode in episodes) {
        if (episode.id == episodeId) return episode;
      }
    }
    return null;
  }

  Episode _withTranscriptReady(Episode episode) {
    return Episode(
      id: episode.id,
      podcastId: episode.podcastId,
      guid: episode.guid,
      title: episode.title,
      audioUrl: episode.audioUrl,
      description: episode.description,
      publishedAt: episode.publishedAt,
      durationSeconds: episode.durationSeconds,
      websiteUrl: episode.websiteUrl,
      hasTranscriptSource: episode.transcriptSources.isNotEmpty,
      transcriptReady: _transcripts.containsKey(episode.id),
      transcriptSources: episode.transcriptSources,
    );
  }

  Podcast _withEpisodeCount(Podcast podcast) {
    return Podcast(
      id: podcast.id,
      title: podcast.title,
      feedUrl: podcast.feedUrl,
      episodeCount: _episodes[podcast.id]?.length ?? 0,
      author: podcast.author,
      description: podcast.description,
      artworkUrl: podcast.artworkUrl,
      websiteUrl: podcast.websiteUrl,
      lastCheckedAt: podcast.lastCheckedAt,
    );
  }

  String _normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw const PodcastRepositoryException('RSS 地址必须是有效的网址');
    }
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          fragment: '',
        )
        .toString();
  }

  Future<void> _save() {
    _writeQueue = _writeQueue
        .catchError((Object _) {})
        .then((_) => _writeNow());
    return _writeQueue;
  }

  Future<void> _writeNow() async {
    final file = _storageFile!;
    await file.parent.create(recursive: true);
    final payload = {
      'version': 1,
      'next_podcast_id': _nextPodcastId,
      'next_episode_id': _nextEpisodeId,
      'did_seed_defaults': _didSeedDefaults,
      'podcasts': _podcasts.map((podcast) => podcast.toJson()).toList(),
      'episodes': _episodes.values
          .expand((episodes) => episodes)
          .map((episode) => episode.toJson())
          .toList(),
      'transcripts': _transcripts.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      ),
      'feed_cache': _feedCache.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'listening_days': _listeningDays,
    };
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    await temporary.rename(file.path);
  }

  String _dateKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static int _newestFirst(Episode left, Episode right) {
    final leftDate = left.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate =
        right.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final dateOrder = rightDate.compareTo(leftDate);
    return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
  }
}
