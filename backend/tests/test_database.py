from pathlib import Path

import pytest

from app.database import Database, SubscriptionLimitError
from app.feeds import ParsedFeed


def feed(number: int) -> ParsedFeed:
    return ParsedFeed(
        title=f"Podcast {number}",
        author=None,
        description=None,
        artwork_url=None,
        website_url=None,
        episodes=(),
    )


def test_subscription_limit_is_ten(tmp_path: Path) -> None:
    database = Database(tmp_path / "listen.sqlite3")
    database.initialize()
    for number in range(10):
        database.add_podcast(f"https://example.com/{number}.xml", feed(number))

    with pytest.raises(SubscriptionLimitError, match="10"):
        database.add_podcast("https://example.com/10.xml", feed(10))

    assert len(database.list_podcasts()) == 10
