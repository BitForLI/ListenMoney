import 'dart:math' as math;

class TimedTranscriptCue {
  const TimedTranscriptCue({
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.paragraphIndex,
  });

  final int startMs;
  final int endMs;
  final String text;
  final int paragraphIndex;
}

List<TimedTranscriptCue> buildTimedTranscriptCues({
  required List<String> tokens,
  required List<double> timestamps,
  required String fallbackText,
  required int offsetMs,
  required int durationMs,
  required int paragraphOffset,
}) {
  final entries = <({String text, int startMs})>[];
  final count = math.min(tokens.length, timestamps.length);
  for (var index = 0; index < count; index += 1) {
    final token = cleanAsrToken(tokens[index]);
    if (token.isEmpty) continue;
    entries.add((
      text: token,
      startMs: (timestamps[index] * 1000).round().clamp(0, durationMs),
    ));
  }
  if (entries.isEmpty) {
    return _fallbackTimedCues(
      fallbackText,
      offsetMs: offsetMs,
      durationMs: durationMs,
      paragraphOffset: paragraphOffset,
    );
  }

  final cues = <TimedTranscriptCue>[];
  var buffer = '';
  var cueStart = entries.first.startMs;
  var lastTokenStart = cueStart;
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    if (buffer.isEmpty) cueStart = entry.startMs;
    buffer = appendAsrToken(buffer, entry.text);
    lastTokenStart = entry.startMs;
    final nextStart = index + 1 < entries.length
        ? entries[index + 1].startMs
        : math.min(durationMs, entry.startMs + 650);
    final pauseMs = nextStart - entry.startMs;
    final sentenceEnd = RegExp(r'[.!?][\"”’]?\s*$').hasMatch(buffer);
    final naturalPause =
        pauseMs >= 650 && buffer.trim().split(RegExp(r'\s+')).length >= 3;
    final longCue = nextStart - cueStart >= 10500 || buffer.length >= 155;
    if (!sentenceEnd &&
        !naturalPause &&
        !longCue &&
        index + 1 < entries.length) {
      continue;
    }
    final text = buffer.trim();
    if (text.isNotEmpty) {
      // Do not stretch a sentence across a long silence. The final word gets
      // a small readable tail, capped by the next token/window boundary.
      final spokenEnd = math.min(
        durationMs,
        math.min(nextStart, lastTokenStart + 520),
      );
      final end = math.max(cueStart + 80, spokenEnd);
      cues.add(
        TimedTranscriptCue(
          startMs: offsetMs + cueStart,
          endMs: offsetMs + end,
          text: text,
          paragraphIndex: paragraphOffset + cues.length ~/ 4,
        ),
      );
    }
    buffer = '';
  }
  return cues;
}

List<TimedTranscriptCue> _fallbackTimedCues(
  String text, {
  required int offsetMs,
  required int durationMs,
  required int paragraphOffset,
}) {
  final sentences = RegExp(r'[^.!?]+[.!?]?')
      .allMatches(text)
      .map((match) => match.group(0)!.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (sentences.isEmpty) return const [];
  final weights = sentences
      .map((sentence) => math.max(1, sentence.split(RegExp(r'\s+')).length))
      .toList();
  final totalWeight = weights.fold<int>(0, (sum, value) => sum + value);
  var elapsedWeight = 0;
  return List.generate(sentences.length, (index) {
    final start = (durationMs * elapsedWeight / totalWeight).round();
    elapsedWeight += weights[index];
    final end = (durationMs * elapsedWeight / totalWeight).round();
    return TimedTranscriptCue(
      startMs: offsetMs + start,
      endMs: offsetMs + math.max(start + 1, end),
      text: sentences[index],
      paragraphIndex: paragraphOffset + index ~/ 4,
    );
  });
}

String cleanAsrToken(String token) {
  if (token.startsWith('<') && token.endsWith('>')) return '';
  return token.replaceAll('▁', ' ').replaceAll('Ġ', ' ');
}

String appendAsrToken(String current, String token) {
  if (current.isEmpty) return token.trimLeft();
  // Whisper BPE and Parakeet SentencePiece tokens carry their own word
  // boundary marker. Once Ġ/▁ becomes a space, verbatim concatenation keeps
  // word boundaries and also joins subword pieces such as Art+ifi+cial.
  return '$current$token';
}

double recognitionQuality(
  String text,
  List<double> timestamps,
  int durationMs,
) {
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 0;
  final normalized = words.map((word) => word.toLowerCase()).toList();
  final uniqueRatio = normalized.toSet().length / normalized.length;
  var repeatedRuns = 0;
  for (var index = 1; index < normalized.length; index += 1) {
    if (normalized[index] == normalized[index - 1]) repeatedRuns += 1;
  }
  final seconds = math.max(1.0, durationMs / 1000);
  final density = math.min(1.0, words.length / (seconds * 1.2));
  final timing = timestamps.isEmpty ? 0.55 : 1.0;
  return (uniqueRatio * 0.45 + density * 0.35 + timing * 0.20) -
      math.min(0.35, repeatedRuns / math.max(1, words.length));
}
