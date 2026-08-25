from __future__ import annotations

import json
import os

import httpx


class TranslationError(ValueError):
    pass


class OpenAICompatibleTranslator:
    def __init__(self) -> None:
        self._base_url = os.environ.get(
            "LISTEN_TRANSLATION_BASE_URL",
            "http://127.0.0.1:11434/v1",
        ).rstrip("/")
        self._model = os.environ.get("LISTEN_TRANSLATION_MODEL", "qwen3:4b")
        self._api_key = os.environ.get("LISTEN_TRANSLATION_API_KEY", "ollama")

    async def translate(
        self,
        texts: list[str],
        *,
        source_language: str,
        target_language: str,
    ) -> list[str]:
        translated: list[str] = []
        for start in range(0, len(texts), 20):
            translated.extend(
                await self._translate_batch(
                    texts[start : start + 20],
                    source_language=source_language,
                    target_language=target_language,
                )
            )
        return translated

    async def _translate_batch(
        self,
        texts: list[str],
        *,
        source_language: str,
        target_language: str,
    ) -> list[str]:
        indexed = [{"index": index, "text": text} for index, text in enumerate(texts)]
        prompt = (
            f"Translate every item from {source_language} to {target_language}. "
            "Keep names, tone and meaning. Return JSON only in this exact shape: "
            '{"translations":[{"index":0,"text":"..."}]}. '
            "Do not merge, omit, explain, or renumber items. Input: "
            + json.dumps(indexed, ensure_ascii=False)
        )
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                response = await client.post(
                    f"{self._base_url}/chat/completions",
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    json={
                        "model": self._model,
                        "messages": [
                            {
                                "role": "system",
                                "content": "You are a precise podcast subtitle translator.",
                            },
                            {"role": "user", "content": prompt},
                        ],
                        "temperature": 0,
                        "response_format": {"type": "json_object"},
                    },
                )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            payload = self._decode_content(content)
        except (httpx.HTTPError, KeyError, IndexError, TypeError, json.JSONDecodeError) as error:
            raise TranslationError(f"翻译服务返回异常：{error}") from error

        items = payload.get("translations")
        if not isinstance(items, list):
            raise TranslationError("翻译服务没有返回 translations 数组")
        by_index: dict[int, str] = {}
        for item in items:
            if not isinstance(item, dict):
                continue
            try:
                index = int(item["index"])
                text = str(item["text"]).strip()
            except (KeyError, TypeError, ValueError):
                continue
            if text:
                by_index[index] = text
        if set(by_index) != set(range(len(texts))):
            raise TranslationError("翻译服务返回的句子数量不完整")
        return [by_index[index] for index in range(len(texts))]

    @staticmethod
    def _decode_content(content: object) -> dict[str, object]:
        text = str(content).strip()
        if text.startswith("```"):
            lines = text.splitlines()
            text = "\n".join(lines[1:-1]).strip()
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end < start:
            raise json.JSONDecodeError("missing JSON object", text, 0)
        payload = json.loads(text[start : end + 1])
        if not isinstance(payload, dict):
            raise json.JSONDecodeError("expected JSON object", text, start)
        return payload
