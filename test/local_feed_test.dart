import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/data/local_feed.dart';

void main() {
  test('parses RSS podcast metadata, audio and transcript sources', () {
    final feed = parseLocalFeed('''
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"
        xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
        xmlns:podcast="https://podcastindex.org/namespace/1.0">
        <channel>
          <title>Example Podcast</title>
          <description>Long conversations</description>
          <itunes:author>Example Host</itunes:author>
          <itunes:image href="https://example.com/show.jpg" />
          <link>https://example.com</link>
          <language>en</language>
          <item>
            <guid>episode-1</guid>
            <title>First Episode</title>
            <pubDate>Fri, 28 Aug 2026 10:30:00 +1000</pubDate>
            <itunes:duration>01:02:03</itunes:duration>
            <enclosure url="https://example.com/one.mp3" type="audio/mpeg" />
            <podcast:transcript url="https://example.com/one.vtt" type="text/vtt" language="en" />
          </item>
        </channel>
      </rss>
    ''');

    expect(feed.title, 'Example Podcast');
    expect(feed.author, 'Example Host');
    expect(feed.artworkUrl, 'https://example.com/show.jpg');
    expect(feed.episodes, hasLength(1));
    expect(feed.episodes.single.durationSeconds, 3723);
    expect(feed.episodes.single.publishedAt, DateTime.utc(2026, 8, 28, 0, 30));
    expect(feed.episodes.single.transcriptSources.single.mimeType, 'text/vtt');
  });

  test('parses Atom enclosure links', () {
    final feed = parseLocalFeed('''
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Podcast</title>
        <author><name>Atom Host</name></author>
        <entry>
          <id>atom-1</id>
          <title>Atom Episode</title>
          <updated>2026-08-28T10:00:00Z</updated>
          <link rel="enclosure" type="audio/mpeg" href="https://example.com/atom.mp3" />
        </entry>
      </feed>
    ''');

    expect(feed.author, 'Atom Host');
    expect(feed.episodes.single.audioUrl, 'https://example.com/atom.mp3');
  });
}
