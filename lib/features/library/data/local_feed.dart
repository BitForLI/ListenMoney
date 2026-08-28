import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../domain/podcast.dart';
import 'podcast_repository.dart';

class LocalFeedResult {
  const LocalFeedResult({
    required this.title,
    required this.episodes,
    this.author,
    this.description,
    this.artworkUrl,
    this.websiteUrl,
    this.etag,
    this.lastModified,
    this.notModified = false,
  });

  final String title;
  final String? author;
  final String? description;
  final String? artworkUrl;
  final String? websiteUrl;
  final List<LocalFeedEpisode> episodes;
  final String? etag;
  final String? lastModified;
  final bool notModified;
}

class LocalFeedEpisode {
  const LocalFeedEpisode({
    required this.guid,
    required this.title,
    required this.audioUrl,
    this.description,
    this.publishedAt,
    this.durationSeconds,
    this.websiteUrl,
    this.transcriptSources = const [],
  });

  final String guid;
  final String title;
  final String audioUrl;
  final String? description;
  final DateTime? publishedAt;
  final int? durationSeconds;
  final String? websiteUrl;
  final List<TranscriptSource> transcriptSources;
}

class LocalFeedGateway {
  const LocalFeedGateway();

  Future<LocalFeedResult> fetch(
    String feedUrl, {
    String? etag,
    String? lastModified,
  }) async {
    final uri = Uri.tryParse(feedUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const PodcastRepositoryException('RSS 地址必须是有效的网址');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'ListenPodcast/1.0');
      if (etag?.isNotEmpty == true) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag!);
      }
      if (lastModified?.isNotEmpty == true) {
        request.headers.set(HttpHeaders.ifModifiedSinceHeader, lastModified!);
      }
      final response = await request.close();
      if (response.statusCode == HttpStatus.notModified) {
        await response.drain<void>();
        return LocalFeedResult(
          title: '',
          episodes: const [],
          etag: response.headers.value(HttpHeaders.etagHeader) ?? etag,
          lastModified:
              response.headers.value(HttpHeaders.lastModifiedHeader) ??
              lastModified,
          notModified: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw PodcastRepositoryException('无法获取 RSS（${response.statusCode}）');
      }
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final content = utf8.decode(bytes, allowMalformed: true);
      final parsed = parseLocalFeed(content);
      return LocalFeedResult(
        title: parsed.title,
        author: parsed.author,
        description: parsed.description,
        artworkUrl: parsed.artworkUrl,
        websiteUrl: parsed.websiteUrl,
        episodes: parsed.episodes,
        etag: response.headers.value(HttpHeaders.etagHeader),
        lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
      );
    } on PodcastRepositoryException {
      rethrow;
    } on SocketException catch (error) {
      throw PodcastRepositoryException('无法连接播客服务器：${error.message}');
    } on HandshakeException {
      throw const PodcastRepositoryException('播客服务器的安全连接失败');
    } on XmlParserException {
      throw const PodcastRepositoryException('RSS 格式无法解析');
    } finally {
      client.close(force: true);
    }
  }
}

LocalFeedResult parseLocalFeed(String content) {
  final document = XmlDocument.parse(content);
  final root = document.rootElement;
  final isAtom = root.name.local.toLowerCase() == 'feed';
  final container = isAtom
      ? root
      : _descendants(root, 'channel').firstOrNull ?? root;
  final entryName = isAtom ? 'entry' : 'item';
  final entries = _children(container, entryName).toList();
  final title = _text(container, 'title');
  if (title == null || title.isEmpty) {
    throw const PodcastRepositoryException('RSS 缺少播客标题');
  }

  final imageElements = _children(container, 'image').toList();
  String? artworkUrl;
  for (final image in imageElements) {
    artworkUrl = image.getAttribute('href') ?? _text(image, 'url');
    if (artworkUrl?.isNotEmpty == true) break;
  }
  final authorElement = _children(container, 'author').firstOrNull;
  final author = authorElement == null
      ? _text(container, 'creator')
      : _text(authorElement, 'name') ?? _clean(authorElement.innerText);
  final language = _text(container, 'language');
  final episodes = <LocalFeedEpisode>[];
  for (final entry in entries) {
    final audio = _audioUrl(entry);
    if (audio == null || audio.isEmpty) continue;
    final sources = _children(entry, 'transcript')
        .map(
          (element) => TranscriptSource(
            url: element.getAttribute('url') ?? '',
            mimeType: (element.getAttribute('type') ?? '').toLowerCase(),
            language: element.getAttribute('language') ?? language,
          ),
        )
        .where((source) => source.url.isNotEmpty && source.mimeType.isNotEmpty)
        .toList();
    final episodeTitle = _text(entry, 'title') ?? '未命名单集';
    episodes.add(
      LocalFeedEpisode(
        guid:
            _text(entry, 'guid') ??
            _text(entry, 'id') ??
            _entryLink(entry) ??
            audio,
        title: episodeTitle,
        description:
            _text(entry, 'summary') ??
            _text(entry, 'description') ??
            _text(entry, 'encoded'),
        audioUrl: audio,
        publishedAt: _parsePublished(
          _text(entry, 'pubDate') ??
              _text(entry, 'published') ??
              _text(entry, 'updated'),
        ),
        durationSeconds: _parseDuration(_text(entry, 'duration')),
        websiteUrl: _entryLink(entry),
        transcriptSources: sources,
      ),
    );
  }

  return LocalFeedResult(
    title: title,
    author: author,
    description:
        _text(container, 'subtitle') ?? _text(container, 'description'),
    artworkUrl: artworkUrl,
    websiteUrl: _entryLink(container),
    episodes: episodes,
  );
}

Iterable<XmlElement> _children(XmlElement element, String localName) {
  return element.childElements.where(
    (child) => child.name.local.toLowerCase() == localName.toLowerCase(),
  );
}

Iterable<XmlElement> _descendants(XmlNode node, String localName) {
  return node.descendants.whereType<XmlElement>().where(
    (child) => child.name.local.toLowerCase() == localName.toLowerCase(),
  );
}

String? _text(XmlElement element, String localName) {
  final child = _children(element, localName).firstOrNull;
  if (child == null) return null;
  final value = _clean(child.innerText);
  return value.isEmpty ? null : value;
}

String _clean(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String? _audioUrl(XmlElement entry) {
  for (final child in entry.childElements) {
    final local = child.name.local.toLowerCase();
    final type = (child.getAttribute('type') ?? '').toLowerCase();
    if (local == 'enclosure') {
      final url = child.getAttribute('url') ?? child.getAttribute('href');
      if (url != null && (type.isEmpty || type.startsWith('audio/'))) {
        return url;
      }
    }
    if (local == 'link' && child.getAttribute('rel') == 'enclosure') {
      final url = child.getAttribute('href');
      if (url != null) return url;
    }
    if (local == 'content' && type.startsWith('audio/')) {
      final url = child.getAttribute('url');
      if (url != null) return url;
    }
  }
  return null;
}

String? _entryLink(XmlElement element) {
  for (final link in _children(element, 'link')) {
    final relation = link.getAttribute('rel');
    if (relation == null || relation.isEmpty || relation == 'alternate') {
      final value = link.getAttribute('href') ?? _clean(link.innerText);
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}

int? _parseDuration(String? value) {
  if (value == null || value.isEmpty) return null;
  final direct = int.tryParse(value);
  if (direct != null) return direct;
  final parts = value.split(':').map(int.tryParse).toList();
  if (parts.any((part) => part == null) ||
      parts.length < 2 ||
      parts.length > 3) {
    return null;
  }
  if (parts.length == 2) return parts[0]! * 60 + parts[1]!;
  return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
}

DateTime? _parsePublished(String? value) {
  if (value == null || value.isEmpty) return null;
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso.toUtc();
  final match = RegExp(
    r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s+([+-]\d{4}|GMT|UTC)$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  const months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final month = months[match.group(2)!.toLowerCase()];
  if (month == null) return null;
  var result = DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.tryParse(match.group(6) ?? '') ?? 0,
  );
  final zone = match.group(7)!;
  if (zone.startsWith('+') || zone.startsWith('-')) {
    final sign = zone.startsWith('+') ? 1 : -1;
    final offset = Duration(
      hours: int.parse(zone.substring(1, 3)),
      minutes: int.parse(zone.substring(3, 5)),
    );
    result = result.subtract(offset * sign);
  }
  return result;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
