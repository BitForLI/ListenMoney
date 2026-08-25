from __future__ import annotations

import asyncio
import os
import tempfile
from pathlib import Path

import httpx

from app.transcripts import TranscriptCue, TranscriptError


class LocalWhisperTranscriber:
    max_audio_bytes = 500 * 1024 * 1024

    def __init__(self) -> None:
        self._model: object | None = None

    async def transcribe(
        self,
        audio_url: str,
        *,
        language: str | None = None,
    ) -> tuple[list[TranscriptCue], str]:
        audio_path = await self._download(audio_url)
        try:
            return await asyncio.to_thread(self._run, audio_path, language)
        finally:
            audio_path.unlink(missing_ok=True)

    async def _download(self, audio_url: str) -> Path:
        temporary = tempfile.NamedTemporaryFile(suffix=".audio", delete=False)
        path = Path(temporary.name)
        total = 0
        try:
            async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
                async with client.stream("GET", audio_url) as response:
                    response.raise_for_status()
                    async for chunk in response.aiter_bytes():
                        total += len(chunk)
                        if total > self.max_audio_bytes:
                            raise TranscriptError("音频超过 500 MB，无法本地转写")
                        temporary.write(chunk)
            temporary.close()
            return path
        except (httpx.HTTPError, OSError) as error:
            temporary.close()
            path.unlink(missing_ok=True)
            raise TranscriptError(f"无法下载音频：{error}") from error
        except Exception:
            temporary.close()
            path.unlink(missing_ok=True)
            raise

    def _run(
        self,
        audio_path: Path,
        language: str | None,
    ) -> tuple[list[TranscriptCue], str]:
        try:
            from faster_whisper import WhisperModel
        except ImportError as error:
            raise TranscriptError(
                "本地转写组件未安装，请安装 backend 的 transcription 可选依赖"
            ) from error

        if self._model is None:
            model_name = os.environ.get("LISTEN_WHISPER_MODEL", "small")
            self._model = WhisperModel(model_name, device="cpu", compute_type="int8")
        segments, information = self._model.transcribe(
            str(audio_path),
            language=language,
            vad_filter=True,
        )
        cues: list[TranscriptCue] = []
        paragraph_index = 0
        for index, segment in enumerate(segments):
            text = segment.text.strip()
            if not text or segment.end <= segment.start:
                continue
            if index > 0 and index % 4 == 0:
                paragraph_index += 1
            cues.append(
                TranscriptCue(
                    start_ms=round(segment.start * 1000),
                    end_ms=round(segment.end * 1000),
                    text=text,
                    paragraph_index=paragraph_index,
                )
            )
        if not cues:
            raise TranscriptError("本地转写没有识别到语音")
        return cues, information.language or language or "und"
