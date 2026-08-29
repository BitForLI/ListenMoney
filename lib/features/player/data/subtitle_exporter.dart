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
    final contents = '\uFEFF${buildSrt(document)}';
    final fileName = '${safeFileName(episodeTitle)}.srt';
    return SharePlus.instance.share(
      ShareParams(
        title: '导出字幕',
        subject: episodeTitle,
        files: [
          XFile.fromData(
            utf8.encode(contents),
            mimeType: 'application/x-subrip',
          ),
        ],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static String buildSrt(TranscriptDocument document) {
    final buffer = StringBuffer();
    for (var index = 0; index < document.segments.length; index += 1) {
      final segment = document.segments[index];
      buffer
        ..writeln(index + 1)
        ..writeln(
          '${_timestamp(segment.startMs)} --> ${_timestamp(segment.endMs)}',
        )
        ..writeln(segment.text);
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
    final fallback = sanitized.isEmpty ? 'Listen 字幕' : sanitized;
    return fallback.length <= 80 ? fallback : fallback.substring(0, 80).trim();
  }

  static String _timestamp(int milliseconds) {
    final value = milliseconds < 0 ? 0 : milliseconds;
    final hours = value ~/ 3600000;
    final minutes = (value ~/ 60000) % 60;
    final seconds = (value ~/ 1000) % 60;
    final millis = value % 1000;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')},'
        '${millis.toString().padLeft(3, '0')}';
  }
}
