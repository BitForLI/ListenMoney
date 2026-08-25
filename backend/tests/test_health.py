import asyncio

from app.main import health


def test_health() -> None:
    assert asyncio.run(health()) == {"status": "ok"}
