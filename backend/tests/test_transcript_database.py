from pathlib import Path

from app.database import Database
from app.feeds import ParsedEpisode, ParsedFeed, TranscriptReference
from app.transcripts import TranscriptCue


def test_saves_and_reads_timed_transcript(tmp_path: Path) -> None:
    database = Database(tmp_path / "listen.sqlite3")
    database.initialize()
    podcast = database.add_podcast(
        "https://example.com/feed.xml",
        ParsedFeed(
            title="Test Podcast",
            author=None,
            description=None,
            artwork_url=None,
            website_url=None,
            episodes=(
                ParsedEpisode(
                    guid="episode-1",
                    title="Episode One",
                    description=None,
                    audio_url="https://example.com/episode.mp3",
                    published_at=None,
                    duration_seconds=60,
                    transcripts=(
                        TranscriptReference(
                            url="https://example.com/transcript.vtt",
                            mime_type="text/vtt",
                            language="en",
                        ),
                    ),
                ),
            ),
        ),
    )
    episode = database.list_episodes(podcast.id)[0]

    assert episode.has_transcript_source is True
    assert episode.transcript_ready is False

    document = database.save_transcript(
        episode.id,
        language="en",
        source="rss",
        source_url="https://example.com/transcript.vtt",
        cues=[
            TranscriptCue(
                start_ms=1000,
                end_ms=2500,
                text="Hello",
                paragraph_index=0,
            )
        ],
    )

    assert document.language == "en"
    assert document.segments[0].text == "Hello"
    assert database.get_episode(episode.id).transcript_ready is True
