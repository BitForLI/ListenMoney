import 'dart:convert';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import '../../library/domain/podcast.dart';

class SubtitleExporter {
  const SubtitleExporter();

  Future<ShareResult> export(
    TranscriptDocument document, {
    required String episodeTitle,
    Rect? sharePositionOrigin,
  }) {
    final contents = '\uFEFF${buildReadableText(document)}';
    final fileName = '${safeFileName(episodeTitle)}.txt';
    return SharePlus.instance.share(
      ShareParams(
        title: '导出字幕',
        subject: episodeTitle,
        files: [XFile.fromData(utf8.encode(contents), mimeType: 'text/plain')],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static String buildReadableText(TranscriptDocument document) {
    final buffer = StringBuffer();
    for (var index = 0; index < document.segments.length; index += 1) {
      final segment = document.segments[index];
      buffer.writeln(segment.text.trim());
      final translation = segment.translation?.trim();
      if (translation?.isNotEmpty == true) buffer.writeln(translation);
      if (index < document.segments.length - 1) buffer.writeln();
    }
    return buffer.toString();
  }

  static String safeFileName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fallback = sanitized.isEmpty ? 'PodRepeat Transcript' : sanitized;
    return fallback.length <= 80 ? fallback : fallback.substring(0, 80).trim();
  }
}
