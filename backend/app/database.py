from __future__ import annotations

import sqlite3
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from app.feeds import ParsedFeed, TranscriptReference
from app.schemas import (
    DailyListening,
    Episode,
    ListeningStats,
    Podcast,
    TranscriptDocument,
    TranscriptSegment,
)
from app.transcripts import TranscriptCue


class SubscriptionLimitError(ValueError):
    pass


class DuplicateSubscriptionError(ValueError):
    pass


class Database:
    max_subscriptions = 10

    def __init__(self, path: Path | str) -> None:
        self._path = str(path)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS podcasts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    author TEXT,
                    description TEXT,
                    artwork_url TEXT,
                    feed_url TEXT NOT NULL UNIQUE,
                    website_url TEXT,
                    etag TEXT,
                    last_modified TEXT,
                    last_checked_at TEXT
                );

                CREATE TABLE IF NOT EXISTS episodes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    podcast_id INTEGER NOT NULL REFERENCES podcasts(id) ON DELETE CASCADE,
                    guid TEXT NOT NULL,
                    title TEXT NOT NULL,
                    description TEXT,
                    audio_url TEXT NOT NULL,
                    published_at TEXT,
                    duration_seconds INTEGER,
                    website_url TEXT,
                    UNIQUE(podcast_id, guid)
                );

                CREATE INDEX IF NOT EXISTS episodes_podcast_published
                ON episodes(podcast_id, published_at DESC, id DESC);

                CREATE TABLE IF NOT EXISTS transcript_sources (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    episode_id INTEGER NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
                    url TEXT NOT NULL,
                    mime_type TEXT NOT NULL,
                    language TEXT,
                    UNIQUE(episode_id, url)
                );

                CREATE TABLE IF NOT EXISTS transcripts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    episode_id INTEGER NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
                    language TEXT NOT NULL,
                    source TEXT NOT NULL,
                    source_url TEXT,
                    created_at TEXT NOT NULL,
                    UNIQUE(episode_id, language)
                );

                CREATE TABLE IF NOT EXISTS transcript_segments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    transcript_id INTEGER NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    start_ms INTEGER NOT NULL,
                    end_ms INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    speaker TEXT,
                    paragraph_index INTEGER NOT NULL,
                    UNIQUE(transcript_id, position)
                );

                CREATE TABLE IF NOT EXISTS transcript_translations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    transcript_id INTEGER NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
                    target_language TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    source TEXT NOT NULL,
                    UNIQUE(transcript_id, target_language, position)
                );

                CREATE TABLE IF NOT EXISTS listening_days (
                    local_date TEXT PRIMARY KEY,
                    seconds INTEGER NOT NULL CHECK(seconds >= 0)
                );
                """
            )
            episode_columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(episodes)").fetchall()
            }
            if "website_url" not in episode_columns:
                connection.execute("ALTER TABLE episodes ADD COLUMN website_url TEXT")

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _to_podcast(row: sqlite3.Row) -> Podcast:
        return Podcast(
            id=row["id"],
            title=row["title"],
            author=row["author"],
            description=row["description"],
            artwork_url=row["artwork_url"],
            feed_url=row["feed_url"],
            website_url=row["website_url"],
            episode_count=row["episode_count"],
            last_checked_at=row["last_checked_at"],
        )

    def list_podcasts(self) -> list[Podcast]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT p.*, COUNT(e.id) AS episode_count
                FROM podcasts AS p
                LEFT JOIN episodes AS e ON e.podcast_id = p.id
                GROUP BY p.id
                ORDER BY p.title COLLATE NOCASE
                """
            ).fetchall()
        return [self._to_podcast(row) for row in rows]

    def get_podcast(self, podcast_id: int) -> Podcast | None:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT p.*, COUNT(e.id) AS episode_count
                FROM podcasts AS p
                LEFT JOIN episodes AS e ON e.podcast_id = p.id
                WHERE p.id = ?
                GROUP BY p.id
                """,
                (podcast_id,),
            ).fetchone()
        return self._to_podcast(row) if row else None

    def add_podcast(
        self,
        feed_url: str,
        parsed_feed: ParsedFeed,
        *,
        etag: str | None = None,
        last_modified: str | None = None,
    ) -> Podcast:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            count = connection.execute("SELECT COUNT(*) FROM podcasts").fetchone()[0]
            if count >= self.max_subscriptions:
                raise SubscriptionLimitError("最多只能收藏 10 个播客")
            try:
                cursor = connection.execute(
                    """
                    INSERT INTO podcasts(
                        title, author, description, artwork_url, feed_url,
                        website_url, etag, last_modified, last_checked_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        parsed_feed.title,
                        parsed_feed.author,
                        parsed_feed.description,
                        parsed_feed.artwork_url,
                        feed_url,
                        parsed_feed.website_url,
                        etag,
                        last_modified,
                        self._now(),
                    ),
                )
            except sqlite3.IntegrityError as error:
                raise DuplicateSubscriptionError("这个播客已经收藏") from error
            podcast_id = int(cursor.lastrowid)
            self._insert_episodes(connection, podcast_id, parsed_feed)
        podcast = self.get_podcast(podcast_id)
        assert podcast is not None
        return podcast

    @staticmethod
    def _sync_transcript_sources(
        connection: sqlite3.Connection,
        episode_id: int,
        references: tuple[TranscriptReference, ...],
    ) -> None:
        connection.executemany(
            """
            INSERT INTO transcript_sources(episode_id, url, mime_type, language)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(episode_id, url) DO UPDATE SET
                mime_type = excluded.mime_type,
                language = excluded.language
            """,
            [
                (episode_id, reference.url, reference.mime_type, reference.language)
                for reference in references
            ],
        )

    @classmethod
    def _insert_episodes(
        cls,
        connection: sqlite3.Connection,
        podcast_id: int,
        parsed_feed: ParsedFeed,
    ) -> int:
        before = connection.total_changes
        connection.executemany(
            """
            INSERT OR IGNORE INTO episodes(
                podcast_id, guid, title, description, audio_url,
                published_at, duration_seconds, website_url
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    podcast_id,
                    episode.guid,
                    episode.title,
                    episode.description,
                    episode.audio_url,
                    episode.published_at.isoformat() if episode.published_at else None,
                    episode.duration_seconds,
                    episode.website_url,
                )
                for episode in parsed_feed.episodes
            ],
        )
        inserted = connection.total_changes - before
        for episode in parsed_feed.episodes:
            row = connection.execute(
                "SELECT id FROM episodes WHERE podcast_id = ? AND guid = ?",
                (podcast_id, episode.guid),
            ).fetchone()
            if row:
                connection.execute(
                    """
                    UPDATE episodes
                    SET title = ?, description = ?, audio_url = ?, published_at = ?,
                        duration_seconds = ?, website_url = COALESCE(?, website_url)
                    WHERE id = ?
                    """,
                    (
                        episode.title,
                        episode.description,
                        episode.audio_url,
                        episode.published_at.isoformat()
                        if episode.published_at
                        else None,
                        episode.duration_seconds,
                        episode.website_url,
                        row["id"],
                    ),
                )
                cls._sync_transcript_sources(connection, row["id"], episode.transcripts)
        return inserted

    def sync_podcast(
        self,
        podcast_id: int,
        parsed_feed: ParsedFeed,
        *,
        etag: str | None = None,
        last_modified: str | None = None,
    ) -> int:
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE podcasts
                SET title = ?, author = ?, description = ?, artwork_url = ?,
                    website_url = ?, etag = ?, last_modified = ?, last_checked_at = ?
                WHERE id = ?
                """,
                (
                    parsed_feed.title,
                    parsed_feed.author,
                    parsed_feed.description,
                    parsed_feed.artwork_url,
                    parsed_feed.website_url,
                    etag,
                    last_modified,
                    self._now(),
                    podcast_id,
                ),
            )
            return self._insert_episodes(connection, podcast_id, parsed_feed)

    def mark_checked(
        self,
        podcast_id: int,
        *,
        etag: str | None,
        last_modified: str | None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE podcasts
                SET etag = ?, last_modified = ?, last_checked_at = ?
                WHERE id = ?
                """,
                (etag, last_modified, self._now(), podcast_id),
            )

    def feed_cache_headers(self, podcast_id: int) -> tuple[str | None, str | None]:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT etag, last_modified FROM podcasts WHERE id = ?",
                (podcast_id,),
            ).fetchone()
        if not row:
            return None, None
        return row["etag"], row["last_modified"]

    def list_episodes(self, podcast_id: int) -> list[Episode]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT e.*,
                    EXISTS(
                        SELECT 1 FROM transcript_sources AS ts
                        WHERE ts.episode_id = e.id
                    ) AS has_transcript_source,
                    EXISTS(
                        SELECT 1 FROM transcripts AS t
                        WHERE t.episode_id = e.id
                    ) AS transcript_ready
                FROM episodes AS e
                WHERE e.podcast_id = ?
                ORDER BY e.published_at DESC, e.id DESC
                """,
                (podcast_id,),
            ).fetchall()
        return [Episode(**dict(row)) for row in rows]

    def get_episode(self, episode_id: int) -> Episode | None:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT e.*,
                    EXISTS(
                        SELECT 1 FROM transcript_sources AS ts
                        WHERE ts.episode_id = e.id
                    ) AS has_transcript_source,
                    EXISTS(
                        SELECT 1 FROM transcripts AS t
                        WHERE t.episode_id = e.id
                    ) AS transcript_ready
                FROM episodes AS e
                WHERE e.id = ?
                """,
                (episode_id,),
            ).fetchone()
        return Episode(**dict(row)) if row else None

    def transcript_sources(self, episode_id: int) -> list[TranscriptReference]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT url, mime_type, language FROM transcript_sources
                WHERE episode_id = ?
                ORDER BY CASE mime_type
                    WHEN 'application/json' THEN 0
                    WHEN 'text/vtt' THEN 1
                    ELSE 2
                END, id
                """,
                (episode_id,),
            ).fetchall()
        return [
            TranscriptReference(
                url=row["url"],
                mime_type=row["mime_type"],
                language=row["language"],
            )
            for row in rows
        ]

    def save_transcript(
        self,
        episode_id: int,
        *,
        language: str,
        source: str,
        source_url: str | None,
        cues: list[TranscriptCue],
    ) -> TranscriptDocument:
        with self._connect() as connection:
            previous = connection.execute(
                "SELECT id FROM transcripts WHERE episode_id = ? AND language = ?",
                (episode_id, language),
            ).fetchone()
            if previous:
                connection.execute("DELETE FROM transcripts WHERE id = ?", (previous["id"],))
            cursor = connection.execute(
                """
                INSERT INTO transcripts(episode_id, language, source, source_url, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (episode_id, language, source, source_url, self._now()),
            )
            transcript_id = int(cursor.lastrowid)
            connection.executemany(
                """
                INSERT INTO transcript_segments(
                    transcript_id, position, start_ms, end_ms,
                    text, speaker, paragraph_index
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        transcript_id,
                        index,
                        cue.start_ms,
                        cue.end_ms,
                        cue.text,
                        cue.speaker,
                        cue.paragraph_index,
                    )
                    for index, cue in enumerate(cues)
                ],
            )
        transcript = self.get_transcript(episode_id, language=language)
        assert transcript is not None
        return transcript

    def get_transcript(
        self,
        episode_id: int,
        *,
        language: str | None = None,
        target_language: str | None = None,
    ) -> TranscriptDocument | None:
        query = "SELECT * FROM transcripts WHERE episode_id = ?"
        parameters: list[object] = [episode_id]
        if language:
            query += " AND language = ?"
            parameters.append(language)
        query += " ORDER BY id LIMIT 1"
        with self._connect() as connection:
            transcript = connection.execute(query, parameters).fetchone()
            if not transcript:
                return None
            rows = connection.execute(
                """
                SELECT position, start_ms, end_ms, text, speaker, paragraph_index
                FROM transcript_segments
                WHERE transcript_id = ?
                ORDER BY position
                """,
                (transcript["id"],),
            ).fetchall()
            translations: dict[int, str] = {}
            translation_source: str | None = None
            if target_language:
                translation_rows = connection.execute(
                    """
                    SELECT position, text, source FROM transcript_translations
                    WHERE transcript_id = ? AND target_language = ?
                    ORDER BY position
                    """,
                    (transcript["id"], target_language),
                ).fetchall()
                translations = {row["position"]: row["text"] for row in translation_rows}
                if translation_rows:
                    translation_source = translation_rows[0]["source"]
        return TranscriptDocument(
            episode_id=episode_id,
            language=transcript["language"],
            source=transcript["source"],
            segments=[
                TranscriptSegment(
                    index=row["position"],
                    start_ms=row["start_ms"],
                    end_ms=row["end_ms"],
                    text=row["text"],
                    speaker=row["speaker"],
                    paragraph_index=row["paragraph_index"],
                    translation=translations.get(row["position"]),
                )
                for row in rows
            ],
            target_language=target_language if translations else None,
            translation_source=translation_source,
        )

    def save_translations(
        self,
        episode_id: int,
        *,
        source_language: str,
        target_language: str,
        source: str,
        translations: list[str],
    ) -> TranscriptDocument:
        with self._connect() as connection:
            transcript = connection.execute(
                """
                SELECT id FROM transcripts
                WHERE episode_id = ? AND language = ?
                """,
                (episode_id, source_language),
            ).fetchone()
            if not transcript:
                raise ValueError("原文字幕不存在")
            transcript_id = transcript["id"]
            connection.execute(
                """
                DELETE FROM transcript_translations
                WHERE transcript_id = ? AND target_language = ?
                """,
                (transcript_id, target_language),
            )
            connection.executemany(
                """
                INSERT INTO transcript_translations(
                    transcript_id, target_language, position, text, source
                ) VALUES (?, ?, ?, ?, ?)
                """,
                [
                    (transcript_id, target_language, index, text, source)
                    for index, text in enumerate(translations)
                    if text.strip()
                ],
            )
        document = self.get_transcript(
            episode_id,
            language=source_language,
            target_language=target_language,
        )
        assert document is not None
        return document

    def record_listening(self, local_date: date, seconds: int) -> None:
        if seconds <= 0:
            return
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO listening_days(local_date, seconds)
                VALUES (?, ?)
                ON CONFLICT(local_date) DO UPDATE SET
                    seconds = listening_days.seconds + excluded.seconds
                """,
                (local_date.isoformat(), seconds),
            )

    def listening_stats(self, today: date, *, days: int = 7) -> ListeningStats:
        first_day = today - timedelta(days=days - 1)
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT local_date, seconds FROM listening_days
                WHERE local_date >= ? AND local_date <= ?
                ORDER BY local_date
                """,
                (first_day.isoformat(), today.isoformat()),
            ).fetchall()
            all_rows = connection.execute(
                "SELECT local_date, seconds FROM listening_days WHERE seconds > 0"
            ).fetchall()
            total_seconds = connection.execute(
                "SELECT COALESCE(SUM(seconds), 0) FROM listening_days"
            ).fetchone()[0]

        by_date = {date.fromisoformat(row["local_date"]): row["seconds"] for row in rows}
        active_dates = {date.fromisoformat(row["local_date"]) for row in all_rows}
        streak_cursor = today if today in active_dates else today - timedelta(days=1)
        streak_days = 0
        while streak_cursor in active_dates:
            streak_days += 1
            streak_cursor -= timedelta(days=1)

        return ListeningStats(
            today_seconds=by_date.get(today, 0),
            total_seconds=total_seconds,
            streak_days=streak_days,
            daily=[
                DailyListening(
                    date=day,
                    seconds=by_date.get(day, 0),
                )
                for day in (first_day + timedelta(days=index) for index in range(days))
            ],
        )

    def delete_podcast(self, podcast_id: int) -> bool:
        with self._connect() as connection:
            cursor = connection.execute("DELETE FROM podcasts WHERE id = ?", (podcast_id,))
        return cursor.rowcount > 0
