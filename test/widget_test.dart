import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/app.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

void main() {
  testWidgets('shows the three MVP sections', (tester) async {
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: PlaybackController(FakePlaybackEngine()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('听力日历'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('glass_bottom_navigation')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Transcript'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('节目'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();
    expect(find.text('BANK'), findsOneWidget);

    final pages = find.byKey(const ValueKey('main_horizontal_pages'));
    await tester.drag(pages, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('尚未播放'), findsOneWidget);
    expect(find.byKey(const ValueKey('player_action_glass')), findsNothing);

    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.text('今日'), findsNothing);
    expect(find.text('连续'), findsNothing);
    expect(find.text('累计'), findsNothing);
    expect(find.text('进度'), findsNothing);
    expect(find.text('活动记录'), findsNothing);
    expect(find.text('听力日历'), findsOneWidget);
  });

  testWidgets('swipes horizontally between the three main sections', (
    tester,
  ) async {
    final playback = PlaybackController(FakePlaybackEngine());
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 3,
        podcastId: 1,
        guid: 'horizontal-caption-episode',
        title: 'Horizontal caption episode',
        audioUrl: 'https://example.com/horizontal-caption.mp3',
      ),
      fromPodcast: 'Caption podcast',
    );
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: playback,
      ),
    );
    await tester.pumpAndSettle();

    final pages = find.byKey(const ValueKey('main_horizontal_pages'));
    await tester.drag(pages, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('BANK'), findsOneWidget);

    await tester.drag(pages, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transcript_only_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('player_action_glass')), findsNothing);

    await tester.drag(pages, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('BANK'), findsOneWidget);
  });

  testWidgets('home and player bottom glass panels share the same top edge', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final playback = PlaybackController(FakePlaybackEngine());
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 1,
        podcastId: 1,
        guid: 'aligned-episode',
        title: 'Aligned episode',
        audioUrl: 'https://example.com/aligned.mp3',
      ),
      fromPodcast: 'Aligned podcast',
    );

    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: playback,
      ),
    );
    await tester.pumpAndSettle();

    final homeTop = tester
        .getTopLeft(find.byKey(const ValueKey('home_bottom_glass')))
        .dy;
    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('mini_player')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    final playerTop = tester
        .getTopLeft(find.byKey(const ValueKey('player_action_glass')))
        .dy;

    expect(playerTop, closeTo(homeTop, 1));
  });

  testWidgets('BANK swipes up into player and player slides down to BANK', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final playback = PlaybackController(FakePlaybackEngine());
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 1,
        podcastId: 1,
        guid: 'gesture-episode',
        title: 'Gesture episode',
        audioUrl: 'https://example.com/gesture.mp3',
      ),
      fromPodcast: 'Gesture podcast',
    );

    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: playback,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();
    expect(find.text('BANK'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('player_swipe_launcher')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_overlay')), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('mini_player')),
      const Offset(0, -180),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final enteringPlayer = find.byKey(const ValueKey('player_overlay'));
    expect(enteringPlayer, findsOneWidget);
    expect(tester.getTopLeft(enteringPlayer).dy, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_action_glass')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('player_pull_down_handle')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_action_glass')), findsOneWidget);
    expect(find.byKey(const ValueKey('transcript_only_page')), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('player_pull_down_handle')),
      const Offset(0, 220),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(enteringPlayer).dy, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('BANK'), findsOneWidget);
    final returnedGlass = find.byKey(const ValueKey('home_bottom_glass'));
    expect(
      find.descendant(
        of: returnedGlass,
        matching: find.byKey(const ValueKey('mini_player')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: returnedGlass,
        matching: find.byKey(const ValueKey('glass_bottom_navigation')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('progress opens player but captions reserve vertical scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final playback = PlaybackController(FakePlaybackEngine());
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 4,
        podcastId: 1,
        guid: 'return-origin-episode',
        title: 'Return origin episode',
        audioUrl: 'https://example.com/return-origin.mp3',
      ),
      fromPodcast: 'Return origin podcast',
    );
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: playback,
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openAndReturnTo(Finder origin) async {
      expect(origin, findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('mini_player')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player_action_glass')), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('player_pull_down_handle')),
        const Offset(0, 220),
      );
      await tester.pumpAndSettle();
      expect(origin, findsOneWidget);
      expect(find.byKey(const ValueKey('player_overlay')), findsNothing);
    }

    await openAndReturnTo(find.text('听力日历'));

    await tester.tap(find.bySemanticsLabel('Transcript'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transcript_only_page')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('mini_player')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transcript_only_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('player_overlay')), findsNothing);

    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('mini_player')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('player_overlay')),
        matching: find.bySemanticsLabel('Transcript'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_overlay')), findsNothing);
    expect(find.byKey(const ValueKey('transcript_only_page')), findsOneWidget);
  });

  testWidgets('the third main button opens captions instead of the player', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final playback = PlaybackController(FakePlaybackEngine());
    addTearDown(playback.dispose);
    const transcript = TranscriptDocument(
      episodeId: 1,
      language: 'en',
      source: 'test',
      segments: [
        TranscriptSegment(
          index: 0,
          startMs: 0,
          endMs: 1200,
          text: 'Caption sentence.',
          paragraphIndex: 0,
        ),
      ],
    );
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(transcript: transcript),
        playbackController: playback,
      ),
    );
    await playback.loadEpisode(
      const Episode(
        id: 1,
        podcastId: 1,
        guid: 'caption-episode',
        title: 'Caption episode',
        audioUrl: 'https://example.com/caption.mp3',
      ),
      fromPodcast: 'Caption podcast',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Transcript'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('transcript_only_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('player_vertical_pages')), findsNothing);
    expect(find.byKey(const ValueKey('player_action_glass')), findsNothing);
    final transcriptControls = find.byKey(
      const ValueKey('transcript_control_glass'),
    );
    final homeControls = find.byKey(const ValueKey('home_bottom_glass'));
    final controlsBottom = tester.getBottomRight(transcriptControls).dy;
    final navigationTop = tester.getTopLeft(homeControls).dy;
    expect(navigationTop - controlsBottom, inInclusiveRange(0, 12));
    expect(tester.getSize(transcriptControls).height, closeTo(120, 1));
    expect(
      tester.getSize(transcriptControls).height,
      lessThan(tester.getSize(homeControls).height),
    );
  });

  testWidgets('adds a podcast from an RSS URL', (tester) async {
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: PlaybackController(FakePlaybackEngine()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.podcasts_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加播客'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'https://example.com/feed.xml',
    );
    await tester.tap(find.widgetWithText(FilledButton, '收藏这个播客'));
    await tester.pumpAndSettle();

    expect(find.text('测试播客'), findsOneWidget);
  });

  testWidgets('tapping an episode opens the player and starts playback', (
    tester,
  ) async {
    const podcast = Podcast(
      id: 7,
      title: 'Test Show',
      feedUrl: 'https://example.com/show.xml',
      episodeCount: 1,
    );
    const episode = Episode(
      id: 70,
      podcastId: 7,
      guid: 'direct-play',
      title: 'Direct Play Episode',
      audioUrl: 'https://example.com/direct.mp3',
      durationSeconds: 1200,
    );
    final engine = FakePlaybackEngine();
    final playback = PlaybackController(engine);
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(
          podcasts: const [podcast],
          episodes: const {
            7: [episode],
          },
        ),
        playbackController: playback,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Show'));
    await tester.pumpAndSettle();
    expect(find.textContaining('▶'), findsNothing);

    await tester.tap(find.text('Direct Play Episode'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('player_overlay')), findsOneWidget);
    expect(playback.episode?.id, episode.id);
    expect(playback.playing, isTrue);
  });

  testWidgets('shows the three publisher-transcript recommendations', (
    tester,
  ) async {
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: PlaybackController(FakePlaybackEngine()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.podcasts_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加播客'));
    await tester.pumpAndSettle();

    expect(find.text('推荐播客'), findsOneWidget);
    expect(find.text('Practical AI'), findsOneWidget);
    expect(find.text('The TED AI Show'), findsOneWidget);
    expect(find.text('Latent Space'), findsOneWidget);
  });
}
