from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import urlparse
from xml.etree import ElementTree

import feedparser
import httpx


class FeedError(ValueError):
    pass


@dataclass(frozen=True)
class TranscriptReference:
    url: str
    mime_type: str
    language: str | None


@dataclass(frozen=True)
class ParsedEpisode:
    guid: str
    title: str
    description: str | None
    audio_url: str
    published_at: datetime | None
    duration_seconds: int | None
    website_url: str | None = None
    transcripts: tuple[TranscriptReference, ...] = ()


@dataclass(frozen=True)
class ParsedFeed:
    title: str
    author: str | None
    description: str | None
    artwork_url: str | None
    website_url: str | None
    episodes: tuple[ParsedEpisode, ...]


@dataclass(frozen=True)
class FeedFetchResult:
    feed: ParsedFeed | None
    etag: str | None
    last_modified: str | None
    not_modified: bool = False


def validate_feed_url(feed_url: str) -> None:
    parsed = urlparse(feed_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise FeedError("RSS 地址必须是有效的 HTTP 或 HTTPS URL")


def _entry_audio_url(entry: feedparser.FeedParserDict) -> str | None:
    for enclosure in entry.get("enclosures", []):
        href = enclosure.get("href")
        media_type = str(enclosure.get("type", ""))
        if href and (not media_type or media_type.startswith("audio/")):
            return str(href)
    for link in entry.get("links", []):
        href = link.get("href")
        if href and str(link.get("rel", "")) == "enclosure":
            return str(href)
    return None


def _duration_seconds(value: object) -> int | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if text.isdigit():
        return int(text)
    parts = text.split(":")
    if not all(part.isdigit() for part in parts) or len(parts) not in {2, 3}:
        return None
    values = [int(part) for part in parts]
    if len(values) == 2:
        minutes, seconds = values
        return minutes * 60 + seconds
    hours, minutes, seconds = values
    return hours * 3600 + minutes * 60 + seconds


def _published_at(entry: feedparser.FeedParserDict) -> datetime | None:
    time_value = entry.get("published_parsed") or entry.get("updated_parsed")
    if not time_value:
        return None
    return datetime.fromtimestamp(calendar.timegm(time_value), tz=timezone.utc)


def _entry_transcripts(content: bytes) -> list[tuple[TranscriptReference, ...]]:
    try:
        root = ElementTree.fromstring(content)
    except ElementTree.ParseError:
        return []

    results: list[tuple[TranscriptReference, ...]] = []
    for element in root.iter():
        local_name = element.tag.rsplit("}", 1)[-1]
        if local_name not in {"item", "entry"}:
            continue
        references: list[TranscriptReference] = []
        for child in element:
            if child.tag.rsplit("}", 1)[-1] != "transcript":
                continue
            url = child.attrib.get("url")
            mime_type = child.attrib.get("type")
            if url and mime_type:
                references.append(
                    TranscriptReference(
                        url=url,
                        mime_type=mime_type.lower(),
                        language=child.attrib.get("language"),
                    )
                )
        results.append(tuple(references))
    return results


def parse_feed_bytes(content: bytes) -> ParsedFeed:
    parsed = feedparser.parse(content)
    if parsed.bozo and not parsed.entries:
        raise FeedError(f"无法解析 RSS：{parsed.get('bozo_exception', '格式错误')}")

    feed = parsed.feed
    title = str(feed.get("title", "")).strip()
    if not title:
        raise FeedError("RSS 缺少播客标题")

    image = feed.get("image") or {}
    artwork_url = image.get("href") or feed.get("itunes_image")
    feed_language = str(feed.get("language") or "").strip() or None
    transcript_references = _entry_transcripts(content)
    episodes: list[ParsedEpisode] = []
    for index, entry in enumerate(parsed.entries):
        audio_url = _entry_audio_url(entry)
        if not audio_url:
            continue
        guid = str(entry.get("id") or entry.get("guid") or audio_url).strip()
        episode_title = str(entry.get("title") or "未命名单集").strip()
        episodes.append(
            ParsedEpisode(
                guid=guid,
                title=episode_title,
                description=entry.get("summary") or entry.get("description"),
                audio_url=audio_url,
                published_at=_published_at(entry),
                duration_seconds=_duration_seconds(entry.get("itunes_duration")),
                website_url=str(entry.get("link")) if entry.get("link") else None,
                transcripts=tuple(
                    TranscriptReference(
                        url=reference.url,
                        mime_type=reference.mime_type,
                        language=reference.language or feed_language,
                    )
                    for reference in (
                        transcript_references[index]
                        if index < len(transcript_references)
                        else ()
                    )
                ),
            )
        )

    return ParsedFeed(
        title=title,
        author=feed.get("author") or feed.get("itunes_author"),
        description=feed.get("subtitle") or feed.get("description"),
        artwork_url=str(artwork_url) if artwork_url else None,
        website_url=feed.get("link"),
        episodes=tuple(episodes),
    )


class FeedGateway:
    def __init__(self, timeout_seconds: float = 15.0) -> None:
        self._timeout_seconds = timeout_seconds

    async def fetch(
        self,
        feed_url: str,
        *,
        etag: str | None = None,
        last_modified: str | None = None,
    ) -> FeedFetchResult:
        validate_feed_url(feed_url)
        headers = {
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
            "User-Agent": "ListenPodcast/0.1",
        }
        if etag:
            headers["If-None-Match"] = etag
        if last_modified:
            headers["If-Modified-Since"] = last_modified

        try:
            async with httpx.AsyncClient(
                timeout=self._timeout_seconds,
                follow_redirects=True,
            ) as client:
                response = await client.get(feed_url, headers=headers)
            if response.status_code == 304:
                return FeedFetchResult(
                    feed=None,
                    etag=response.headers.get("etag") or etag,
                    last_modified=response.headers.get("last-modified") or last_modified,
                    not_modified=True,
                )
            response.raise_for_status()
        except httpx.HTTPError as error:
            raise FeedError(f"无法获取 RSS：{error}") from error

        return FeedFetchResult(
            feed=parse_feed_bytes(response.content),
            etag=response.headers.get("etag"),
            last_modified=response.headers.get("last-modified"),
        )
