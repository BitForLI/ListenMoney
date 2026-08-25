import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/app.dart';
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

    expect(find.text('我的播客'), findsOneWidget);
    expect(find.text('0 / 10'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.graphic_eq_outlined));
    await tester.pumpAndSettle();
    expect(find.text('尚未播放'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('今日听力'), findsOneWidget);
    expect(find.text('连续收听'), findsOneWidget);
  });

  testWidgets('adds a podcast from an RSS URL', (tester) async {
    await tester.pumpWidget(
      ListenApp(
        podcastRepository: FakePodcastRepository(),
        playbackController: PlaybackController(FakePlaybackEngine()),
      ),
    );
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
    expect(find.text('1 / 10'), findsOneWidget);
  });
}
