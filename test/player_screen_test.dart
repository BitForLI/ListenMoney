import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/core/widgets/glass_surface.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/player/application/on_device_transcriber.dart';
import 'package:listen/features/player/application/transcript_controller.dart';
import 'package:listen/features/player/presentation/player_screen.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

void main() {
  testWidgets('player mode and transcript controls drive semantic navigation', (
    tester,
  ) async {
    const document = TranscriptDocument(
      episodeId: 1,
      language: 'en',
      source: 'rss',
      targetLanguage: 'zh-Hans',
      segments: [
        TranscriptSegment(
          index: 0,
          startMs: 1000,
          endMs: 2500,
          text: 'First sentence.',
          translation: '第一句。',
          paragraphIndex: 0,
        ),
        TranscriptSegment(
          index: 1,
          startMs: 2500,
          endMs: 4000,
          text: 'Second sentence.',
          translation: '第二句。',
          paragraphIndex: 1,
        ),
      ],
    );
    final engine = FakePlaybackEngine();
    final playback = PlaybackController(engine);
    final repository = FakePodcastRepository(transcript: document);
    final transcript = TranscriptController(repository, playback);
    addTearDown(transcript.dispose);
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 1,
        podcastId: 1,
        guid: 'episode-1',
        title: 'Episode One',
        audioUrl: 'https://example.com/episode.mp3',
      ),
      fromPodcast: 'Test Podcast',
    );
    await transcript.load(1);
    var transcriptRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          controller: playback,
          transcriptController: transcript,
          podcastRepository: repository,
          onShowTranscript: () => transcriptRequested = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final artworkBottom = tester
        .getBottomRight(find.byKey(const ValueKey('player_artwork')))
        .dy;
    final tools = find.byKey(const ValueKey('player_secondary_tools'));
    final toolsTop = tester.getTopLeft(tools).dy;
    final toolsBottom = tester.getBottomRight(tools).dy;
    final titleTop = tester
        .getTopLeft(find.byKey(const ValueKey('player_episode_title')))
        .dy;
    expect(toolsTop - artworkBottom, lessThanOrEqualTo(12));
    expect(titleTop - toolsBottom, lessThanOrEqualTo(14));

    expect(find.byTooltip('切换播放方式'), findsOneWidget);
    expect(find.byTooltip('查看文本'), findsOneWidget);
    expect(find.byTooltip('下一句'), findsOneWidget);
    final actionGlass = find.byKey(const ValueKey('player_action_glass'));
    expect(
      find.descendant(
        of: actionGlass,
        matching: find.byType(MainNavigationRow),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player_main_navigation')),
      findsOneWidget,
    );
    for (final tooltip in const [
      '播放速度',
      '上一句',
      '播放',
      '下一句',
      '打开进度',
      '返回 BANK',
      '查看文本',
    ]) {
      expect(
        find.descendant(of: actionGlass, matching: find.byTooltip(tooltip)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: actionGlass, matching: find.byTooltip('切换播放方式')),
      findsNothing,
    );
    expect(
      find.descendant(of: actionGlass, matching: find.byTooltip('播放队列')),
      findsNothing,
    );

    expect(playback.repeatMode, PlaybackRepeatMode.off);
    await tester.tap(find.byTooltip('切换播放方式'));
    await tester.pumpAndSettle();
    expect(playback.repeatMode, PlaybackRepeatMode.sentence);
    await tester.tap(find.byTooltip('切换播放方式'));
    await tester.pumpAndSettle();

    expect(playback.repeatMode, PlaybackRepeatMode.paragraph);
    expect(find.byTooltip('下一段'), findsOneWidget);
    await tester.tap(find.byTooltip('下一段'));
    await tester.pumpAndSettle();
    expect(transcript.activeSegment?.index, 1);
    expect(engine.position, const Duration(milliseconds: 2500));

    await tester.tap(find.byTooltip('切换播放方式'));
    await tester.pumpAndSettle();
    expect(playback.repeatMode, PlaybackRepeatMode.episode);
    await tester.tap(find.byTooltip('切换播放方式'));
    await tester.pumpAndSettle();
    expect(playback.repeatMode, PlaybackRepeatMode.sentence);
    await tester.tap(find.byTooltip('切换播放方式'));
    await tester.pumpAndSettle();
    expect(playback.repeatMode, PlaybackRepeatMode.paragraph);

    await tester.drag(
      find.byKey(const ValueKey('player_pull_down_handle')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_action_glass')), findsOneWidget);
    expect(find.byKey(const ValueKey('transcript_only_page')), findsNothing);

    await tester.tap(find.byTooltip('查看文本'));
    await tester.pumpAndSettle();
    expect(transcriptRequested, isTrue);
  });

  testWidgets('queue lists and plays other episodes from the same podcast', (
    tester,
  ) async {
    const currentEpisode = Episode(
      id: 11,
      podcastId: 7,
      guid: 'current',
      title: 'Current Episode',
      audioUrl: 'https://example.com/current.mp3',
    );
    const nextEpisode = Episode(
      id: 12,
      podcastId: 7,
      guid: 'next',
      title: 'Another Episode',
      audioUrl: 'https://example.com/next.mp3',
      durationSeconds: 1200,
    );
    final repository = FakePodcastRepository(
      episodes: const {
        7: [currentEpisode, nextEpisode],
      },
    );
    final playback = PlaybackController(FakePlaybackEngine());
    final transcript = TranscriptController(repository, playback);
    addTearDown(transcript.dispose);
    addTearDown(playback.dispose);
    await playback.loadEpisode(currentEpisode, fromPodcast: 'Queue Podcast');

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          controller: playback,
          transcriptController: transcript,
          podcastRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('播放队列'), findsOneWidget);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    expect(find.text('播放队列'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Another Episode'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Current Episode'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'Another Episode'));
    await tester.pumpAndSettle();
    expect(playback.episode?.id, 12);
  });

  testWidgets('captions automatically follow the active sentence', (
    tester,
  ) async {
    final segments = List.generate(
      40,
      (index) => TranscriptSegment(
        index: index,
        startMs: index * 2000,
        endMs: (index + 1) * 2000,
        text: 'Automatically followed sentence number $index.',
        paragraphIndex: index,
      ),
    );
    final document = TranscriptDocument(
      episodeId: 21,
      language: 'en',
      source: 'test',
      segments: segments,
    );
    final repository = FakePodcastRepository(transcript: document);
    final playback = PlaybackController(FakePlaybackEngine());
    final transcript = TranscriptController(repository, playback);
    addTearDown(transcript.dispose);
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 21,
        podcastId: 2,
        guid: 'follow-captions',
        title: 'Follow captions',
        audioUrl: 'https://example.com/follow.mp3',
      ),
    );
    await transcript.load(21);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          controller: playback,
          transcriptController: transcript,
          podcastRepository: repository,
          transcriptOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('导出字幕'), findsOneWidget);
    final transcriptList = find.byKey(const ValueKey('transcript_list'));
    final scrollable = find.descendant(
      of: transcriptList,
      matching: find.byType(Scrollable),
    );
    final scrollableState = tester.state<ScrollableState>(scrollable);
    expect(scrollableState.position.pixels, 0);

    await transcript.select(segments[32]);
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, greaterThan(0));
    final activeSentence = find.byKey(const ValueKey('transcript_segment_32'));
    expect(activeSentence, findsOneWidget);
    final listRect = tester.getRect(transcriptList);
    expect(listRect.contains(tester.getCenter(activeSentence)), isTrue);
  });

  testWidgets(
    'opening captions starts the minimal English transcription flow',
    (tester) async {
      final engine = FakePlaybackEngine();
      final playback = PlaybackController(engine);
      final transcriber = _DelayedTranscriber();
      final repository = FakePodcastRepository();
      final transcript = TranscriptController(
        repository,
        playback,
        onDeviceTranscriber: transcriber,
      );
      addTearDown(transcript.dispose);
      addTearDown(playback.dispose);
      await playback.loadEpisode(
        const Episode(
          id: 2,
          podcastId: 1,
          guid: 'episode-2',
          title: 'Episode Two',
          audioUrl: 'https://example.com/episode-2.mp3',
        ),
      );
      await transcript.load(2);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            controller: playback,
            transcriptController: transcript,
            podcastRepository: repository,
            transcriptOnly: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(transcriber.callCount, 1);
      expect(find.text('转写英语'), findsOneWidget);
      expect(find.textContaining('Parakeet'), findsNothing);
      expect(find.textContaining('离线识别'), findsNothing);

      transcriber.complete();
      await tester.pumpAndSettle();
      expect(find.text('英语转写'), findsNothing);
      expect(find.text('Generated English.'), findsOneWidget);
    },
  );
}

class _DelayedTranscriber implements OnDeviceTranscriber {
  final Completer<TranscriptDocument> _completer = Completer();
  int callCount = 0;

  @override
  bool get isSupported => true;

  @override
  Future<TranscriptDocument?> readCached(int episodeId) async => null;

  @override
  Future<TranscriptDocument> transcribe(
    Episode episode, {
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) {
    callCount += 1;
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      const TranscriptDocument(
        episodeId: 2,
        language: 'en',
        source: 'android-v5-parakeet-tdt-0.6b-v2-int8',
        segments: [
          TranscriptSegment(
            index: 0,
            startMs: 0,
            endMs: 1000,
            text: 'Generated English.',
            paragraphIndex: 0,
          ),
        ],
      ),
    );
  }
}
