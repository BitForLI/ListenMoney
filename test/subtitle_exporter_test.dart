import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/data/subtitle_exporter.dart';

void main() {
  test('exports bilingual subtitles as readable text', () {
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
      SubtitleExporter.buildReadableText(document),
      'Hello there.\n'
      '你好。\n'
      '\n'
      'The next sentence.\n',
    );
  });

  test('makes a safe text file name', () {
    expect(
      SubtitleExporter.safeFileName('AEE 1: Hello / Goodbye?'),
      'AEE 1 Hello Goodbye',
    );
    expect(SubtitleExporter.safeFileName('  '), 'PodRepeat Transcript');
  });
}
