import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/data/subtitle_exporter.dart';

void main() {
  test('exports bilingual subtitles as valid SRT', () {
    const document = TranscriptDocument(
      episodeId: 1,
      language: 'en',
      source: 'test',
      targetLanguage: 'zh-Hans',
      segments: [
        TranscriptSegment(
          index: 0,
          startMs: 1234,
          endMs: 4567,
          text: 'Hello there.',
          translation: '你好。',
          paragraphIndex: 0,
        ),
        TranscriptSegment(
          index: 1,
          startMs: 3661001,
          endMs: 3662500,
          text: 'The next sentence.',
          paragraphIndex: 0,
        ),
      ],
    );

    expect(
      SubtitleExporter.buildSrt(document),
      '1\n'
      '00:00:01,234 --> 00:00:04,567\n'
      'Hello there.\n'
      '你好。\n'
      '\n'
      '2\n'
      '01:01:01,001 --> 01:01:02,500\n'
      'The next sentence.\n',
    );
  });

  test('makes a safe SRT file name', () {
    expect(
      SubtitleExporter.safeFileName('AEE 1: Hello / Goodbye?'),
      'AEE 1 Hello Goodbye',
    );
    expect(SubtitleExporter.safeFileName('  '), 'Listen 字幕');
  });
}
