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
  required int offsetMs,
  required int durationMs,
  required int paragraphOffset,
}) {
  // Never invent a timeline from word count. Unaligned recognition must be
  // retried (or left as a gap), not displayed as timed subtitles.
  if (durationMs <= 0 || tokens.isEmpty || tokens.length != timestamps.length) {
    return const [];
  }
  var previousTimestamp = 0.0;
  for (final timestamp in timestamps) {
    if (!timestamp.isFinite ||
        timestamp < previousTimestamp ||
        timestamp * 1000 >= durationMs) {
      return const [];
    }
    previousTimestamp = timestamp;
  }
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
  if (entries.isEmpty) return const [];

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
      final end = math.min(durationMs, math.max(cueStart + 1, spokenEnd));
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
