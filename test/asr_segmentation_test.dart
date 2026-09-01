import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/player/data/asr_segmentation.dart';

void main() {
  test('timed cues split at punctuation and do not span long silence', () {
    final cues = buildTimedTranscriptCues(
      tokens: const [' Hello', ' world.', ' Next', ' sentence.'],
      timestamps: const [0.2, 0.8, 2.6, 3.2],
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

  test('missing model timestamps cannot produce estimated subtitle cues', () {
    final cues = buildTimedTranscriptCues(
      tokens: const [],
      timestamps: const [],
      offsetMs: 0,
      durationMs: 8000,
      paragraphOffset: 0,
    );

    expect(cues, isEmpty);
  });

  test('sentencepiece subwords are joined without artificial spaces', () {
    final cues = buildTimedTranscriptCues(
      tokens: const ['▁Art', 'ifi', 'cial', '▁intelligence', '.'],
      timestamps: const [0.1, 0.2, 0.3, 0.6, 0.9],
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

  test('malformed token times cannot be clamped into a plausible sentence', () {
    for (final timestamps in <List<double>>[
      [0.5],
      [0.8, 0.2],
      [-0.1, 0.4],
      [0.2, 2.0],
      [double.nan, 0.4],
    ]) {
      expect(
        buildTimedTranscriptCues(
          tokens: [' Hello', ' world.'],
          timestamps: timestamps,
          offsetMs: 0,
          durationMs: 2000,
          paragraphOffset: 0,
        ),
        isEmpty,
      );
    }
  });

  test(
    'intro and unrecognized gaps are preserved on the full audio timeline',
    () {
      final cues = buildTimedTranscriptCues(
        tokens: [' Main', ' content.'],
        timestamps: [0.4, 1.0],
        offsetMs: 65000,
        durationMs: 2500,
        paragraphOffset: 0,
      );
      expect(cues.single.startMs, 65400);
      expect(cues.single.endMs, lessThanOrEqualTo(67500));
    },
  );
}
