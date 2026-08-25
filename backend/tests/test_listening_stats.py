from datetime import date, timedelta
from pathlib import Path

from app.database import Database


def test_daily_duration_and_streak_include_yesterday_before_today_starts(
    tmp_path: Path,
) -> None:
    database = Database(tmp_path / "listen.sqlite3")
    database.initialize()
    today = date(2026, 8, 25)
    database.record_listening(today - timedelta(days=3), 120)
    database.record_listening(today - timedelta(days=2), 60)
    database.record_listening(today - timedelta(days=1), 30)

    before_today = database.listening_stats(today)

    assert before_today.today_seconds == 0
    assert before_today.total_seconds == 210
    assert before_today.streak_days == 3
    assert len(before_today.daily) == 7

    database.record_listening(today, 40)
    database.record_listening(today, 50)
    after_today = database.listening_stats(today)

    assert after_today.today_seconds == 90
    assert after_today.total_seconds == 300
    assert after_today.streak_days == 4
    assert after_today.daily[-1].seconds == 90
