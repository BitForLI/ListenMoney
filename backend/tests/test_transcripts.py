import json

from app.transcripts import parse_caption_text, parse_json_transcript


def test_parses_vtt_timestamps_speaker_and_paragraphs() -> None:
    content = """WEBVTT

00:00:01.000 --> 00:00:03.500
<v Alice>Hello there.</v>

00:00:03.600 --> 00:00:05.000
How are you?

00:00:07.000 --> 00:00:09.000
<v Bob>I am well.</v>
"""

    cues = parse_caption_text(content)

    assert cues[0].start_ms == 1000
    assert cues[0].end_ms == 3500
    assert cues[0].speaker == "Alice"
    assert cues[0].text == "Hello there."
    assert cues[0].paragraph_index == 0
    assert cues[2].paragraph_index == 1


def test_parses_podcasting_json_transcript() -> None:
    content = json.dumps(
        {
            "version": "1.0.0",
            "language": "en",
            "segments": [
                {
                    "speaker": "Alice",
                    "startTime": 1.25,
                    "endTime": 2.5,
                    "body": "Hello",
                }
            ],
        }
    )

    cues, language = parse_json_transcript(content)

    assert language == "en"
    assert cues[0].start_ms == 1250
    assert cues[0].end_ms == 2500
    assert cues[0].text == "Hello"
