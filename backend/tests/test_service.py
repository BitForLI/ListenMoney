import asyncio
from pathlib import Path

from app.database import Database
from app.feeds import FeedFetchResult, ParsedEpisode, ParsedFeed, TranscriptReference
from app.service import PodcastService
from app.transcripts import TranscriptCue


def episode(guid: str) -> ParsedEpisode:
    return ParsedEpisode(
        guid=guid,
        title=guid,
        description=None,
        audio_url=f"https://example.com/{guid}.mp3",
        published_at=None,
        duration_seconds=60,
    )


class FakeFeedClient:
    def __init__(self) -> None:
        self.fetch_count = 0

    async def fetch(
        self,
        feed_url: str,
        *,
        etag: str | None = None,
        last_modified: str | None = None,
    ) -> FeedFetchResult:
        self.fetch_count += 1
        episodes = (episode("episode-1"),)
        if self.fetch_count > 1:
            episodes = (episode("episode-2"), *episodes)
        return FeedFetchResult(
            feed=ParsedFeed(
                title="Test Podcast",
                author=None,
                description=None,
                artwork_url=None,
                website_url=None,
                episodes=episodes,
            ),
            etag=f"etag-{self.fetch_count}",
            last_modified=None,
        )


class FakeTranscriptGateway:
    supported_types = {"text/vtt"}

    def __init__(self) -> None:
        self.fetch_count = 0

    async def fetch(
        self,
        reference: TranscriptReference,
    ) -> tuple[list[TranscriptCue], str]:
        self.fetch_count += 1
        return [TranscriptCue(start_ms=1000, end_ms=2500, text="Hello")], "en"


class FakeTranslator:
    def __init__(self) -> None:
        self.call_count = 0

    async def translate(
        self,
        texts: list[str],
        *,
        source_language: str,
        target_language: str,
    ) -> list[str]:
        self.call_count += 1
        return [f"中文：{text}" for text in texts]


class BilingualTranscriptGateway(FakeTranscriptGateway):
    async def fetch(
        self,
        reference: TranscriptReference,
    ) -> tuple[list[TranscriptCue], str]:
        self.fetch_count += 1
        if reference.language == "zh-Hans":
            return [TranscriptCue(start_ms=1000, end_ms=2500, text="你好")], "zh-Hans"
        return [TranscriptCue(start_ms=1000, end_ms=2500, text="Hello")], "en"


def test_refresh_adds_only_new_episodes(tmp_path: Path) -> None:
    async def scenario() -> None:
        database = Database(tmp_path / "listen.sqlite3")
        database.initialize()
        service = PodcastService(database, feed_client=FakeFeedClient())

        podcast = await service.add_subscription("https://example.com/feed.xml")
        first_refresh = await service.refresh_all()
        second_refresh = await service.refresh_all()

        assert podcast.episode_count == 1
        assert first_refresh.new_episodes == 1
        assert second_refresh.new_episodes == 0
        assert len(database.list_episodes(podcast.id)) == 2

    asyncio.run(scenario())

def test_imports_rss_transcript_once_and_reuses_cache(tmp_path: Path) -> None:
    async def scenario() -> None:
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
        episode_id = database.list_episodes(podcast.id)[0].id
        gateway = FakeTranscriptGateway()
        service = PodcastService(database, transcript_gateway=gateway)

        first = await service.import_transcript(episode_id)
        second = await service.import_transcript(episode_id)

        assert first.segments[0].text == "Hello"
        assert second.segments[0].start_ms == 1000
        assert gateway.fetch_count == 1

    asyncio.run(scenario())


def test_translates_and_caches_bilingual_segments(tmp_path: Path) -> None:
    async def scenario() -> None:
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
                episodes=(episode("episode-1"),),
            ),
        )
        episode_id = database.list_episodes(podcast.id)[0].id
        database.save_transcript(
            episode_id,
            language="en",
            source="test",
            source_url=None,
            cues=[TranscriptCue(start_ms=0, end_ms=1000, text="Hello")],
        )
        translator = FakeTranslator()
        service = PodcastService(database, translator=translator)

        first = await service.translate_transcript(
            episode_id,
            target_language="zh-Hans",
        )
        second = await service.translate_transcript(
            episode_id,
            target_language="zh-Hans",
        )

        assert first.segments[0].translation == "中文：Hello"
        assert second.target_language == "zh-Hans"
        assert translator.call_count == 1

    asyncio.run(scenario())


def test_prefers_publisher_chinese_transcript_over_machine_translation(
    tmp_path: Path,
) -> None:
    async def scenario() -> None:
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
                                url="https://example.com/en.vtt",
                                mime_type="text/vtt",
                                language="en",
                            ),
                            TranscriptReference(
                                url="https://example.com/zh.vtt",
                                mime_type="text/vtt",
                                language="zh-Hans",
                            ),
                        ),
                    ),
                ),
            ),
        )
        episode_id = database.list_episodes(podcast.id)[0].id
        gateway = BilingualTranscriptGateway()
        translator = FakeTranslator()
        service = PodcastService(
            database,
            transcript_gateway=gateway,
            translator=translator,
        )
        await service.import_transcript(episode_id, language="en")

        document = await service.translate_transcript(
            episode_id,
            target_language="zh-Hans",
        )

        assert document.segments[0].translation == "你好"
        assert document.translation_source == "rss"
        assert translator.call_count == 0

    asyncio.run(scenario())
