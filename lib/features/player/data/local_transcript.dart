import 'dart:convert';

import '../../library/data/podcast_repository.dart';
import '../../library/domain/podcast.dart';

TranscriptDocument parseLocalTranscript({
  required int episodeId,
  required String content,
  required String mimeType,
  String? language,
}) {
  final normalizedType = mimeType.toLowerCase().split(';').first.trim();
  if (normalizedType == 'application/json' ||
      normalizedType == 'application/ld+json') {
    return _parseJson(
      episodeId: episodeId,
      content: content,
      language: language,
    );
  }
  if (normalizedType == 'text/vtt' ||
      normalizedType == 'application/srt' ||
      normalizedType == 'text/srt') {
    return _parseTimedText(
      episodeId: episodeId,
      content: content,
      language: language,
    );
  }
  throw PodcastRepositoryException('暂不支持这种字幕格式：$mimeType');
}

TranscriptDocument _parseTimedText({
  required int episodeId,
  required String content,
  String? language,
}) {
  final normalized = content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceFirst('\ufeff', '');
  final timing = RegExp(
    r'((?:\d{1,2}:)?\d{2}:\d{2}[.,]\d{3})\s+-->\s+((?:\d{1,2}:)?\d{2}:\d{2}[.,]\d{3})',
  );
  final speakerPattern = RegExp(
    r'^<v(?:\.\w+)?\s+([^>]+)>',
    caseSensitive: false,
  );
  final raw = <_Cue>[];
  for (final block in normalized.split(RegExp(r'\n\s*\n'))) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final timingIndex = lines.indexWhere((line) => timing.hasMatch(line));
    if (timingIndex < 0) continue;
    final match = timing.firstMatch(lines[timingIndex])!;
    final body = lines.skip(timingIndex + 1).join(' ').trim();
    final speaker = speakerPattern.firstMatch(body)?.group(1)?.trim();
    final text = _clean(body);
    if (text.isEmpty) continue;
    final start = _timestampMs(match.group(1)!);
    final end = _timestampMs(match.group(2)!);
    if (end <= start) continue;
    raw.add(_Cue(start: start, end: end, text: text, speaker: speaker));
  }
  return _document(episodeId, language ?? 'und', raw);
}

TranscriptDocument _parseJson({
  required int episodeId,
  required String content,
  String? language,
}) {
  dynamic payload;
  try {
    payload = jsonDecode(content);
  } on FormatException {
    throw const PodcastRepositoryException('JSON 字幕格式错误');
  }
  if (payload is! Map<String, dynamic>) {
    throw const PodcastRepositoryException('JSON 字幕必须是对象');
  }
  final rawSegments = payload['segments'];
  if (rawSegments is! List<dynamic>) {
    throw const PodcastRepositoryException('JSON 字幕缺少 segments');
  }
  final raw = <_Cue>[];
  for (final item in rawSegments.whereType<Map<String, dynamic>>()) {
    final body = item['body'] ?? item['text'];
    final start = item['startTime'] ?? item['start'];
    final end = item['endTime'] ?? item['end'];
    final startSeconds = _number(start);
    final endSeconds = _number(end);
    if (body == null || startSeconds == null || endSeconds == null) continue;
    final text = _clean(body.toString());
    if (text.isEmpty || endSeconds <= startSeconds) continue;
    raw.add(
      _Cue(
        start: (startSeconds * 1000).round(),
        end: (endSeconds * 1000).round(),
        text: text,
        speaker: item['speaker']?.toString(),
      ),
    );
  }
  return _document(
    episodeId,
    language ?? payload['language']?.toString() ?? 'und',
    raw,
  );
}

TranscriptDocument _document(int episodeId, String language, List<_Cue> cues) {
  if (cues.isEmpty) {
    throw const PodcastRepositoryException('字幕中没有可用的时间轴');
  }
  cues.sort((left, right) {
    final start = left.start.compareTo(right.start);
    return start != 0 ? start : left.end.compareTo(right.end);
  });
  var paragraph = 0;
  var countInParagraph = 0;
  _Cue? previous;
  final segments = <TranscriptSegment>[];
  for (final cue in cues) {
    final startsNew =
        previous != null &&
        (cue.start - previous.end >= 1500 ||
            (cue.speaker != null &&
                previous.speaker != null &&
                cue.speaker != previous.speaker) ||
            countInParagraph >= 4);
    if (startsNew) {
      paragraph += 1;
      countInParagraph = 0;
    }
    segments.add(
      TranscriptSegment(
        index: segments.length,
        startMs: cue.start,
        endMs: cue.end,
        text: cue.text,
        speaker: cue.speaker,
        paragraphIndex: paragraph,
      ),
    );
    countInParagraph += 1;
    previous = cue;
  }
  return TranscriptDocument(
    episodeId: episodeId,
    language: language,
    source: 'rss',
    segments: segments,
  );
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceFirst(RegExp(r's$'), ''));
  }
  return null;
}

int _timestampMs(String value) {
  final parts = value.replaceAll(',', '.').split(':');
  if (parts.length != 2 && parts.length != 3) {
    throw PodcastRepositoryException('无效字幕时间：$value');
  }
  final seconds = double.parse(parts.last);
  final minutes = int.parse(parts[parts.length - 2]);
  final hours = parts.length == 3 ? int.parse(parts.first) : 0;
  return (hours * 3600000 + minutes * 60000 + seconds * 1000).round();
}

String _clean(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _Cue {
  const _Cue({
    required this.start,
    required this.end,
    required this.text,
    this.speaker,
  });

  final int start;
  final int end;
  final String text;
  final String? speaker;
}
