from __future__ import annotations

import asyncio
import contextlib
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import date
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, Request, Response, status

from app.database import Database, DuplicateSubscriptionError, SubscriptionLimitError
from app.feeds import FeedError
from app.schemas import (
    Episode,
    ListeningRecord,
    ListeningStats,
    Podcast,
    PodcastSearchResult,
    RefreshSummary,
    SubscriptionCreate,
    TranscriptDocument,
    TranscriptUpload,
    TranscriptionRequest,
    TranslationRequest,
)
from app.service import PodcastService
from app.transcripts import TranscriptError
from app.translator import TranslationError


async def _refresh_loop(service: PodcastService, interval_seconds: float) -> None:
    while True:
        await asyncio.sleep(interval_seconds)
        await service.refresh_all()


def create_app(
    database_path: Path | str | None = None,
    *,
    refresh_interval_seconds: float = 900.0,
) -> FastAPI:
    resolved_path = Path(
        database_path or os.environ.get("LISTEN_DATABASE_PATH", "listen.sqlite3")
    )

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        database = Database(resolved_path)
        database.initialize()
        service = PodcastService(database)
        application.state.service = service
        refresh_task = asyncio.create_task(
            _refresh_loop(service, refresh_interval_seconds)
        )
        try:
            yield
        finally:
            refresh_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await refresh_task

    application = FastAPI(title="Listen API", version="0.2.0", lifespan=lifespan)

    def service(request: Request) -> PodcastService:
        return request.app.state.service

    @application.get("/health")
    async def health_route() -> dict[str, str]:
        return await health()

    @application.get("/subscriptions", response_model=list[Podcast])
    async def subscriptions(request: Request) -> list[Podcast]:
        return service(request).database.list_podcasts()

    @application.post(
        "/subscriptions",
        response_model=Podcast,
        status_code=status.HTTP_201_CREATED,
    )
    async def add_subscription(
        payload: SubscriptionCreate,
        request: Request,
    ) -> Podcast:
        try:
            return await service(request).add_subscription(str(payload.feed_url))
        except (SubscriptionLimitError, DuplicateSubscriptionError) as error:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error)) from error
        except (FeedError, ValueError) as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(error),
            ) from error

    @application.delete("/subscriptions/{podcast_id}", status_code=status.HTTP_204_NO_CONTENT)
    async def delete_subscription(podcast_id: int, request: Request) -> Response:
        deleted = service(request).database.delete_podcast(podcast_id)
        if not deleted:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="播客不存在")
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @application.get(
        "/subscriptions/{podcast_id}/episodes",
        response_model=list[Episode],
    )
    async def episodes(podcast_id: int, request: Request) -> list[Episode]:
        database = service(request).database
        if not database.get_podcast(podcast_id):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="播客不存在")
        return database.list_episodes(podcast_id)

    @application.post("/subscriptions/refresh", response_model=RefreshSummary)
    async def refresh_subscriptions(request: Request) -> RefreshSummary:
        return await service(request).refresh_all()

    @application.get("/search", response_model=list[PodcastSearchResult])
    async def search(
        request: Request,
        q: str = Query(min_length=1, max_length=120),
    ) -> list[PodcastSearchResult]:
        try:
            return await service(request).search(q)
        except ValueError as error:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(error)) from error

    @application.get(
        "/episodes/{episode_id}/transcript",
        response_model=TranscriptDocument,
    )
    async def transcript(
        episode_id: int,
        request: Request,
        language: str | None = Query(default=None, min_length=2, max_length=12),
        target_language: str | None = Query(default=None, min_length=2, max_length=12),
    ) -> TranscriptDocument:
        document = service(request).database.get_transcript(
            episode_id,
            language=language,
            target_language=target_language,
        )
        if not document:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="该单集还没有已生成的时间轴字幕",
            )
        return document

    @application.post(
        "/episodes/{episode_id}/transcript/import",
        response_model=TranscriptDocument,
    )
    async def import_transcript(
        episode_id: int,
        request: Request,
        language: str | None = Query(default=None, min_length=2, max_length=12),
    ) -> TranscriptDocument:
        try:
            return await service(request).import_transcript(
                episode_id,
                language=language,
            )
        except TranscriptError as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(error),
            ) from error

    @application.post(
        "/episodes/{episode_id}/transcript/translate",
        response_model=TranscriptDocument,
    )
    async def translate_transcript(
        episode_id: int,
        payload: TranslationRequest,
        request: Request,
    ) -> TranscriptDocument:
        try:
            return await service(request).translate_transcript(
                episode_id,
                target_language=payload.target_language,
            )
        except (TranscriptError, TranslationError) as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(error),
            ) from error

    @application.post(
        "/episodes/{episode_id}/transcript/transcribe",
        response_model=TranscriptDocument,
    )
    async def transcribe_episode(
        episode_id: int,
        payload: TranscriptionRequest,
        request: Request,
    ) -> TranscriptDocument:
        try:
            return await service(request).transcribe_episode(
                episode_id,
                language=payload.language,
            )
        except TranscriptError as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(error),
            ) from error

    @application.post(
        "/episodes/{episode_id}/transcript/upload",
        response_model=TranscriptDocument,
    )
    async def upload_transcript(
        episode_id: int,
        payload: TranscriptUpload,
        request: Request,
    ) -> TranscriptDocument:
        try:
            return service(request).save_uploaded_transcript(episode_id, payload)
        except TranscriptError as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(error),
            ) from error

    @application.post("/listening/record", response_model=ListeningStats)
    async def record_listening(
        payload: ListeningRecord,
        request: Request,
    ) -> ListeningStats:
        database = service(request).database
        local_date = payload.listened_at.date()
        database.record_listening(local_date, payload.seconds)
        return database.listening_stats(local_date)

    @application.get("/listening/stats", response_model=ListeningStats)
    async def listening_stats(
        request: Request,
        today: date = Query(),
        days: int = Query(default=7, ge=1, le=31),
    ) -> ListeningStats:
        return service(request).database.listening_stats(today, days=days)

    return application


app = create_app()


async def health() -> dict[str, str]:
    return {"status": "ok"}
