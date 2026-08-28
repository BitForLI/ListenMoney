import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/player/data/local_transcript.dart';

void main() {
  test('parses VTT cues and assigns paragraphs', () {
    final document = parseLocalTranscript(
      episodeId: 7,
      mimeType: 'text/vtt',
      language: 'en',
      content: '''
WEBVTT

00:00:01.000 --> 00:00:03.000
<v Host>Hello &amp; welcome.</v>

00:00:05.000 --> 00:00:07.000
This starts a new paragraph.
''',
    );

    expect(document.episodeId, 7);
    expect(document.segments, hasLength(2));
    expect(document.segments.first.text, 'Hello & welcome.');
    expect(document.segments.first.speaker, 'Host');
    expect(document.segments.last.paragraphIndex, 1);
  });

  test('parses Podcasting 2.0 JSON transcript', () {
    final document = parseLocalTranscript(
      episodeId: 8,
      mimeType: 'application/json',
      content: '''
        {"language":"en","segments":[
          {"startTime":0.5,"endTime":2.0,"body":"Hello"}
        ]}
      ''',
    );

    expect(document.language, 'en');
    expect(document.segments.single.startMs, 500);
  });
}
