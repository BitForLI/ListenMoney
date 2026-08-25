from __future__ import annotations

from typing import Protocol
from urllib.parse import urlsplit, urlunsplit

import httpx

from app.database import Database
from app.feeds import FeedFetchResult, FeedGateway, validate_feed_url
from app.schemas import Podcast, PodcastSearchResult, RefreshSummary, TranscriptDocument
from app.transcriber import LocalWhisperTranscriber
from app.transcripts import TranscriptCue, TranscriptError, TranscriptGateway
from app.translator import OpenAICompatibleTranslator, TranslationError


class FeedClient(Protocol):
    async def fetch(
        self,
        feed_url: str,
        *,
        etag: str | None = None,
        last_modified: str | None = None,
    ) -> FeedFetchResult: ...


class Translator(Protocol):
    async def translate(
        self,
        texts: list[str],
        *,
        source_language: str,
        target_language: str,
    ) -> list[str]: ...


def normalize_feed_url(feed_url: str) -> str:
    value = feed_url.strip()
    validate_feed_url(value)
    parts = urlsplit(value)
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), parts.path, parts.query, ""))


class ApplePodcastSearch:
    async def search(self, query: str, limit: int = 20) -> list[PodcastSearchResult]:
        if not query.strip():
            return []
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(
                    "https://itunes.apple.com/search",
                    params={
                        "term": query.strip(),
                        "media": "podcast",
                        "entity": "podcast",
                        "limit": min(max(limit, 1), 50),
                    },
                )
            response.raise_for_status()
        except httpx.HTTPError as error:
            raise ValueError(f"Apple Podcasts 搜索失败：{error}") from error

        results: list[PodcastSearchResult] = []
        for item in response.json().get("results", []):
            feed_url = item.get("feedUrl")
            title = item.get("collectionName")
            if not feed_url or not title:
                continue
            results.append(
                PodcastSearchResult(
                    title=title,
                    author=item.get("artistName"),
                    artwork_url=item.get("artworkUrl600") or item.get("artworkUrl100"),
                    feed_url=feed_url,
                )
            )
        return results


class PodcastService:
    def __init__(
        self,
        database: Database,
        feed_client: FeedClient | None = None,
        search_client: ApplePodcastSearch | None = None,
        transcript_gateway: TranscriptGateway | None = None,
        transcriber: LocalWhisperTranscriber | None = None,
        translator: Translator | None = None,
    ) -> None:
        self.database = database
        self._feed_client = feed_client or FeedGateway()
        self._search_client = search_client or ApplePodcastSearch()
        self._transcript_gateway = transcript_gateway or TranscriptGateway()
        self._transcriber = transcriber or LocalWhisperTranscriber()
        self._translator = translator or OpenAICompatibleTranslator()

    async def add_subscription(self, feed_url: str) -> Podcast:
        normalized_url = normalize_feed_url(feed_url)
        result = await self._feed_client.fetch(normalized_url)
        if not result.feed:
            raise ValueError("RSS 没有返回播客内容")
        return self.database.add_podcast(
            normalized_url,
            result.feed,
            etag=result.etag,
            last_modified=result.last_modified,
        )

    async def refresh_all(self) -> RefreshSummary:
        summary = RefreshSummary()
        for podcast in self.database.list_podcasts():
            etag, last_modified = self.database.feed_cache_headers(podcast.id)
            try:
                result = await self._feed_client.fetch(
                    podcast.feed_url,
                    etag=etag,
                    last_modified=last_modified,
                )
                if result.not_modified:
                    self.database.mark_checked(
                        podcast.id,
                        etag=result.etag,
                        last_modified=result.last_modified,
                    )
                elif result.feed:
                    summary.new_episodes += self.database.sync_podcast(
                        podcast.id,
                        result.feed,
                        etag=result.etag,
                        last_modified=result.last_modified,
                    )
                summary.refreshed += 1
            except (ValueError, httpx.HTTPError) as error:
                summary.failures.append(f"{podcast.title}: {error}")
        return summary

    async def search(self, query: str) -> list[PodcastSearchResult]:
        return await self._search_client.search(query)

    async def import_transcript(
        self,
        episode_id: int,
        *,
        language: str | None = None,
    ) -> TranscriptDocument:
        episode = self.database.get_episode(episode_id)
        if not episode:
            raise TranscriptError("单集不存在")
        cached = self.database.get_transcript(episode_id, language=language)
        if cached:
            return cached

        errors: list[str] = []
        references = self.database.transcript_sources(episode_id)
        for reference in references:
            if language and not (reference.language or "").lower().startswith(
                language.lower()
            ):
                continue
            if reference.mime_type not in self._transcript_gateway.supported_types:
                continue
            try:
                cues, language = await self._transcript_gateway.fetch(reference)
                return self.database.save_transcript(
                    episode_id,
                    language=language,
                    source="rss",
                    source_url=reference.url,
                    cues=cues,
                )
            except TranscriptError as error:
                errors.append(str(error))
        if errors:
            raise TranscriptError(errors[0])
        raise TranscriptError("这个单集没有提供带时间轴的字幕")

    async def transcribe_episode(
        self,
        episode_id: int,
        *,
        language: str | None = None,
    ) -> TranscriptDocument:
        episode = self.database.get_episode(episode_id)
        if not episode:
            raise TranscriptError("单集不存在")
        cues, detected_language = await self._transcriber.transcribe(
            episode.audio_url,
            language=language,
        )
        return self.database.save_transcript(
            episode_id,
            language=detected_language,
            source="local-whisper",
            source_url=None,
            cues=cues,
        )

    async def translate_transcript(
        self,
        episode_id: int,
        *,
        target_language: str,
    ) -> TranscriptDocument:
        original = self.database.get_transcript(episode_id)
        if not original:
            original = await self.import_transcript(episode_id)
        cached = self.database.get_transcript(
            episode_id,
            language=original.language,
            target_language=target_language,
        )
        if cached and cached.target_language:
            return cached

        target_prefix = target_language.split("-", 1)[0].lower()
        for reference in self.database.transcript_sources(episode_id):
            reference_language = (reference.language or "").lower()
            if not reference_language.startswith(target_prefix):
                continue
            if reference.mime_type not in self._transcript_gateway.supported_types:
                continue
            try:
                target_cues, _ = await self._transcript_gateway.fetch(reference)
                aligned = self._align_translation(original, target_cues)
                if any(aligned):
                    return self.database.save_translations(
                        episode_id,
                        source_language=original.language,
                        target_language=target_language,
                        source="rss",
                        translations=aligned,
                    )
            except TranscriptError:
                continue

        try:
            translations = await self._translator.translate(
                [segment.text for segment in original.segments],
                source_language=original.language,
                target_language=target_language,
            )
        except TranslationError:
            raise
        return self.database.save_translations(
            episode_id,
            source_language=original.language,
            target_language=target_language,
            source="translation-service",
            translations=translations,
        )

    @staticmethod
    def _align_translation(
        original: TranscriptDocument,
        target_cues: list[TranscriptCue],
    ) -> list[str]:
        aligned: list[str] = []
        for segment in original.segments:
            matches = [
                cue.text
                for cue in target_cues
                if cue.end_ms > segment.start_ms and cue.start_ms < segment.end_ms
            ]
            aligned.append(" ".join(dict.fromkeys(matches)))
        return aligned
