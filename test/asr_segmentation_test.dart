import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/player/data/asr_segmentation.dart';

void main() {
  test('timed cues split at punctuation and do not span long silence', () {
    final cues = buildTimedTranscriptCues(
      tokens: const [' Hello', ' world.', ' Next', ' sentence.'],
      timestamps: const [0.2, 0.8, 2.6, 3.2],
      fallbackText: 'Hello world. Next sentence.',
      offsetMs: 10000,
      durationMs: 5000,
      paragraphOffset: 0,
    );

    expect(cues, hasLength(2));
    expect(cues.first.text, 'Hello world.');
    expect(cues.first.startMs, 10200);
    expect(cues.first.endMs, lessThan(12000));
    expect(cues.last.startMs, 12600);
  });

  test('fallback timing is weighted by sentence length', () {
    final cues = buildTimedTranscriptCues(
      tokens: const [],
      timestamps: const [],
      fallbackText: 'Short. This sentence contains several more words.',
      offsetMs: 0,
      durationMs: 8000,
      paragraphOffset: 0,
    );

    expect(cues, hasLength(2));
    expect(cues.first.endMs, lessThan(3000));
    expect(cues.last.endMs, 8000);
  });

  test('sentencepiece subwords are joined without artificial spaces', () {
    final cues = buildTimedTranscriptCues(
      tokens: const ['▁Art', 'ifi', 'cial', '▁intelligence', '.'],
      timestamps: const [0.1, 0.2, 0.3, 0.6, 0.9],
      fallbackText: 'Artificial intelligence.',
      offsetMs: 0,
      durationMs: 1200,
      paragraphOffset: 0,
    );

    expect(cues, hasLength(1));
    expect(cues.single.text, 'Artificial intelligence.');
  });

  test('quality score penalizes repeated hallucinations', () {
    final healthy = recognitionQuality(
      'This is a clear sentence about artificial intelligence.',
      const [0.1, 0.3, 0.5],
      4000,
    );
    final repeated = recognitionQuality(
      'the the the the the the',
      const [],
      8000,
    );

    expect(healthy, greaterThan(repeated));
  });
}
