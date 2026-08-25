import asyncio
from pathlib import Path

from httpx import ASGITransport, AsyncClient

from app.feeds import (
    FeedFetchResult,
    ParsedEpisode,
    ParsedFeed,
    TranscriptReference,
)
from app.main import create_app
from app.transcripts import TranscriptCue


class FlowFeedClient:
    async def fetch(
        self,
        feed_url: str,
        *,
        etag: str | None = None,
        last_modified: str | None = None,
    ) -> FeedFetchResult:
        return FeedFetchResult(
            feed=ParsedFeed(
                title="Flow Podcast",
                author="Test Author",
                description=None,
                artwork_url=None,
                website_url=None,
                episodes=(
                    ParsedEpisode(
                        guid="episode-1",
                        title="Flow Episode",
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
            etag="test-etag",
            last_modified=None,
        )


class FlowTranscriptGateway:
    supported_types = {"text/vtt"}

    async def fetch(
        self,
        reference: TranscriptReference,
    ) -> tuple[list[TranscriptCue], str]:
        return [TranscriptCue(start_ms=0, end_ms=3000, text="Good morning")], "en"


class FlowTranslator:
    async def translate(
        self,
        texts: list[str],
        *,
        source_language: str,
        target_language: str,
    ) -> list[str]:
        return ["早上好"]


def test_api_flow_from_subscription_to_bilingual_stats(tmp_path: Path) -> None:
    async def scenario() -> None:
        application = create_app(
            tmp_path / "listen.sqlite3",
            refresh_interval_seconds=3600,
        )
        async with application.router.lifespan_context(application):
            service = application.state.service
            service._feed_client = FlowFeedClient()
            service._transcript_gateway = FlowTranscriptGateway()
            service._translator = FlowTranslator()
            transport = ASGITransport(app=application)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                subscription = await client.post(
                    "/subscriptions",
                    json={"feed_url": "https://example.com/feed.xml"},
                )
                assert subscription.status_code == 201
                podcast_id = subscription.json()["id"]

                episodes = await client.get(f"/subscriptions/{podcast_id}/episodes")
                assert episodes.status_code == 200
                episode_id = episodes.json()[0]["id"]
                assert episodes.json()[0]["has_transcript_source"] is True

                transcript = await client.post(
                    f"/episodes/{episode_id}/transcript/import"
                )
                assert transcript.status_code == 200
                assert transcript.json()["segments"][0]["text"] == "Good morning"

                uploaded = await client.post(
                    f"/episodes/{episode_id}/transcript/upload",
                    json={
                        "language": "en",
                        "source": "android-tiny.en",
                        "segments": [
                            {
                                "index": 0,
                                "start_ms": 250,
                                "end_ms": 2750,
                                "text": "Good morning",
                                "speaker": None,
                                "paragraph_index": 0,
                            }
                        ],
                    },
                )
                assert uploaded.status_code == 200
                assert uploaded.json()["source"] == "android-tiny.en"
                assert uploaded.json()["segments"][0]["start_ms"] == 250

                bilingual = await client.post(
                    f"/episodes/{episode_id}/transcript/translate",
                    json={"target_language": "zh-Hans"},
                )
                assert bilingual.status_code == 200
                assert bilingual.json()["segments"][0]["translation"] == "早上好"

                recorded = await client.post(
                    "/listening/record",
                    json={"seconds": 90, "listened_at": "2026-08-25T18:00:00+10:00"},
                )
                assert recorded.status_code == 200
                assert recorded.json()["today_seconds"] == 90
                assert recorded.json()["streak_days"] == 1

    asyncio.run(scenario())
