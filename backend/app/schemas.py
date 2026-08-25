from datetime import date, datetime

from pydantic import BaseModel, Field, HttpUrl


class SubscriptionCreate(BaseModel):
    feed_url: HttpUrl


class Podcast(BaseModel):
    id: int
    title: str
    author: str | None = None
    description: str | None = None
    artwork_url: str | None = None
    feed_url: str
    website_url: str | None = None
    episode_count: int = 0
    last_checked_at: datetime | None = None


class Episode(BaseModel):
    id: int
    podcast_id: int
    guid: str
    title: str
    description: str | None = None
    audio_url: str
    published_at: datetime | None = None
    duration_seconds: int | None = None
    has_transcript_source: bool = False
    transcript_ready: bool = False


class PodcastSearchResult(BaseModel):
    title: str
    author: str | None = None
    artwork_url: str | None = None
    feed_url: str


class RefreshSummary(BaseModel):
    refreshed: int = 0
    new_episodes: int = 0
    failures: list[str] = Field(default_factory=list)


class TranscriptSegment(BaseModel):
    index: int
    start_ms: int
    end_ms: int
    text: str
    speaker: str | None = None
    paragraph_index: int
    translation: str | None = None


class TranscriptDocument(BaseModel):
    episode_id: int
    language: str
    source: str
    segments: list[TranscriptSegment]
    target_language: str | None = None
    translation_source: str | None = None


class TranscriptionRequest(BaseModel):
    language: str | None = Field(default=None, min_length=2, max_length=12)


class TranslationRequest(BaseModel):
    target_language: str = Field(default="zh-Hans", min_length=2, max_length=12)


class ListeningRecord(BaseModel):
    seconds: int = Field(ge=1, le=3600)
    listened_at: datetime


class DailyListening(BaseModel):
    date: date
    seconds: int


class ListeningStats(BaseModel):
    today_seconds: int
    total_seconds: int
    streak_days: int
    daily: list[DailyListening]
