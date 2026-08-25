from app.feeds import parse_feed_bytes


RSS = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:podcast="https://podcastindex.org/namespace/1.0">
  <channel>
    <title>Test Podcast</title>
    <link>https://example.com/podcast</link>
    <description>A podcast for tests</description>
    <itunes:author>Test Author</itunes:author>
    <itunes:image href="https://example.com/cover.jpg" />
    <item>
      <guid>episode-1</guid>
      <title>Episode One</title>
      <description>Hello</description>
      <pubDate>Mon, 24 Aug 2026 10:00:00 GMT</pubDate>
      <itunes:duration>01:02:03</itunes:duration>
      <enclosure url="https://example.com/episode-1.mp3" type="audio/mpeg" />
      <podcast:transcript url="https://example.com/episode-1.vtt" type="text/vtt" language="en" />
      <podcast:transcript url="https://example.com/episode-1.json" type="application/json" language="en" />
    </item>
  </channel>
</rss>
"""


def test_parse_feed_and_episode() -> None:
    podcast = parse_feed_bytes(RSS)

    assert podcast.title == "Test Podcast"
    assert podcast.author == "Test Author"
    assert podcast.artwork_url == "https://example.com/cover.jpg"
    assert len(podcast.episodes) == 1
    assert podcast.episodes[0].audio_url == "https://example.com/episode-1.mp3"
    assert podcast.episodes[0].duration_seconds == 3723
    assert podcast.episodes[0].published_at is not None
    assert len(podcast.episodes[0].transcripts) == 2
    assert podcast.episodes[0].transcripts[0].mime_type == "text/vtt"
