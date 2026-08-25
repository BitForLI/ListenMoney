from __future__ import annotations

import html
import json
import re
from dataclasses import dataclass, replace

import httpx

from app.feeds import FeedError, TranscriptReference, validate_feed_url


class TranscriptError(ValueError):
    pass


@dataclass(frozen=True)
class TranscriptCue:
    start_ms: int
    end_ms: int
    text: str
    speaker: str | None = None
    paragraph_index: int = 0


_TIMING = re.compile(
    r"(?P<start>(?:\d{1,2}:)?\d{2}:\d{2}[.,]\d{3})\s+-->\s+"
    r"(?P<end>(?:\d{1,2}:)?\d{2}:\d{2}[.,]\d{3})"
)
_TAGS = re.compile(r"<[^>]+>")
_SPEAKER = re.compile(r"^<v(?:\.\w+)?\s+([^>]+)>", re.IGNORECASE)


def _timestamp_ms(value: str) -> int:
    normalized = value.replace(",", ".")
    parts = normalized.split(":")
    if len(parts) == 2:
        hours = 0
        minutes, seconds = parts
    elif len(parts) == 3:
        hours, minutes, seconds = parts
    else:
        raise TranscriptError(f"无效时间戳：{value}")
    return int(hours) * 3_600_000 + int(minutes) * 60_000 + round(float(seconds) * 1000)


def _clean_text(value: str) -> str:
    without_tags = _TAGS.sub("", value)
    return " ".join(html.unescape(without_tags).split())


def _assign_paragraphs(cues: list[TranscriptCue]) -> list[TranscriptCue]:
    paragraph = 0
    count_in_paragraph = 0
    previous: TranscriptCue | None = None
    results: list[TranscriptCue] = []
    for cue in sorted(cues, key=lambda value: (value.start_ms, value.end_ms)):
        starts_new = previous is not None and (
            cue.start_ms - previous.end_ms >= 1500
            or (cue.speaker and previous.speaker and cue.speaker != previous.speaker)
            or count_in_paragraph >= 4
        )
        if starts_new:
            paragraph += 1
            count_in_paragraph = 0
        results.append(replace(cue, paragraph_index=paragraph))
        count_in_paragraph += 1
        previous = cue
    return results


def parse_caption_text(content: str) -> list[TranscriptCue]:
    normalized = content.replace("\r\n", "\n").replace("\r", "\n").lstrip("\ufeff")
    cues: list[TranscriptCue] = []
    for block in re.split(r"\n\s*\n", normalized):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        timing_index = next(
            (index for index, line in enumerate(lines) if _TIMING.search(line)),
            None,
        )
        if timing_index is None:
            continue
        match = _TIMING.search(lines[timing_index])
        assert match is not None
        raw_text = " ".join(lines[timing_index + 1 :]).strip()
        speaker_match = _SPEAKER.match(raw_text)
        speaker = speaker_match.group(1).strip() if speaker_match else None
        text = _clean_text(raw_text)
        if not text:
            continue
        start_ms = _timestamp_ms(match.group("start"))
        end_ms = _timestamp_ms(match.group("end"))
        if end_ms <= start_ms:
            continue
        cues.append(
            TranscriptCue(
                start_ms=start_ms,
                end_ms=end_ms,
                text=text,
                speaker=speaker,
            )
        )
    if not cues:
        raise TranscriptError("字幕文件中没有可用的时间轴")
    return _assign_paragraphs(cues)


def parse_json_transcript(content: str) -> tuple[list[TranscriptCue], str | None]:
    try:
        payload = json.loads(content)
    except json.JSONDecodeError as error:
        raise TranscriptError("JSON 字幕格式错误") from error
    if not isinstance(payload, dict):
        raise TranscriptError("JSON 字幕必须是对象")
    raw_segments = payload.get("segments")
    if not isinstance(raw_segments, list):
        raise TranscriptError("JSON 字幕缺少 segments")

    cues: list[TranscriptCue] = []
    for item in raw_segments:
        if not isinstance(item, dict):
            continue
        body = item.get("body") or item.get("text")
        start = item.get("startTime", item.get("start"))
        end = item.get("endTime", item.get("end"))
        if body is None or start is None or end is None:
            continue
        try:
            start_ms = round(float(start) * 1000)
            end_ms = round(float(end) * 1000)
        except (TypeError, ValueError):
            continue
        text = _clean_text(str(body))
        if not text or end_ms <= start_ms:
            continue
        cues.append(
            TranscriptCue(
                start_ms=start_ms,
                end_ms=end_ms,
                text=text,
                speaker=str(item["speaker"]) if item.get("speaker") else None,
            )
        )
    if not cues:
        raise TranscriptError("JSON 字幕中没有可用的时间轴")
    language = payload.get("language")
    return _assign_paragraphs(cues), str(language) if language else None


def parse_transcript(
    content: str,
    mime_type: str,
) -> tuple[list[TranscriptCue], str | None]:
    normalized_type = mime_type.lower().split(";", 1)[0].strip()
    if normalized_type in {"text/vtt", "application/srt", "text/srt"}:
        return parse_caption_text(content), None
    if normalized_type in {"application/json", "application/ld+json"}:
        return parse_json_transcript(content)
    raise TranscriptError(f"暂不支持这种字幕格式：{mime_type}")


class TranscriptGateway:
    supported_types = {
        "text/vtt",
        "application/srt",
        "text/srt",
        "application/json",
        "application/ld+json",
    }

    async def fetch(
        self,
        reference: TranscriptReference,
    ) -> tuple[list[TranscriptCue], str]:
        try:
            validate_feed_url(reference.url)
            async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
                response = await client.get(reference.url)
            response.raise_for_status()
        except (FeedError, httpx.HTTPError) as error:
            raise TranscriptError(f"无法获取字幕：{error}") from error
        cues, embedded_language = parse_transcript(response.text, reference.mime_type)
        return cues, reference.language or embedded_language or "und"
