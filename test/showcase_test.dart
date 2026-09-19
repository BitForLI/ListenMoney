import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/core/theme/app_theme.dart';
import 'package:listen/features/library/domain/podcast.dart';
import 'package:listen/features/library/presentation/library_screen.dart';
import 'package:listen/features/player/application/playback_controller.dart';
import 'package:listen/features/player/application/transcript_controller.dart';
import 'package:listen/features/player/presentation/player_screen.dart';
import 'package:listen/features/progress/application/listening_controller.dart';
import 'package:listen/features/progress/domain/review_sentence.dart';
import 'package:listen/features/progress/presentation/progress_screen.dart';

import 'fake_playback_engine.dart';
import 'fake_podcast_repository.dart';

const _generateShowcase = bool.fromEnvironment('GENERATE_SHOWCASE');

void main() {
  setUpAll(() async {
    if (!_generateShowcase) return;
    final bytes = await File('test/assets/NotoSansCJKsc-Showcase.otf')
        .readAsBytes();
    final loader = FontLoader('NotoSansShowcase')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null) {
      throw StateError('FLUTTER_ROOT is required to render showcase icons.');
    }
    final materialFontDirectory = Directory(
      '$flutterRoot/bin/cache/artifacts/material_fonts',
    );
    final materialIconFile = materialFontDirectory
        .listSync()
        .whereType<File>()
        .firstWhere(
          (file) => file.uri.pathSegments.last.toLowerCase().contains(
            'materialicons',
          ),
        );
    final materialIconBytes = await materialIconFile.readAsBytes();
    final materialIconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(materialIconBytes)));
    await materialIconLoader.load();
  });

  testWidgets('renders the podcast library showcase', (tester) async {
    _usePhoneViewport(tester);
    final repository = FakePodcastRepository(
      podcasts: const [
        Podcast(
          id: 1,
          title: 'Everyday English',
          feedUrl: 'https://example.com/everyday.xml',
          episodeCount: 24,
          author: 'PodRepeat Studio',
        ),
        Podcast(
          id: 2,
          title: 'Technology in Plain English',
          feedUrl: 'https://example.com/technology.xml',
          episodeCount: 18,
          author: 'Open Conversations',
        ),
        Podcast(
          id: 3,
          title: 'Short Stories',
          feedUrl: 'https://example.com/stories.xml',
          episodeCount: 31,
          author: 'Daily Listening',
        ),
        Podcast(
          id: 4,
          title: 'Workplace English',
          feedUrl: 'https://example.com/work.xml',
          episodeCount: 12,
          author: 'Clear Speech',
        ),
      ],
    );

    await tester.pumpWidget(
      _ShowcaseShell(child: LibraryScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/library.png'),
    );
  }, skip: !_generateShowcase);

  testWidgets('renders the repeated-sentence review showcase', (tester) async {
    _usePhoneViewport(tester);
    final playback = PlaybackController(FakePlaybackEngine());
    addTearDown(playback.dispose);
    final repository = FakePodcastRepository();
    repository.reviewSentences.addAll([
      ReviewSentence(
        episodeId: 11,
        podcastId: 1,
        episodeTitle: 'How habits shape the way we learn',
        startMs: 42000,
        text: 'Small improvements become meaningful when they are repeated.',
        repeatCount: 7,
        lastRepeatedAt: DateTime(2026, 9, 18),
      ),
      ReviewSentence(
        episodeId: 12,
        podcastId: 1,
        episodeTitle: 'Speaking with more confidence',
        startMs: 81000,
        text: 'Confidence often comes after practice, not before it.',
        repeatCount: 4,
        lastRepeatedAt: DateTime(2026, 9, 17),
      ),
    ]);
    final controller = ListeningController(
      repository,
      playback,
      startTimer: false,
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      _ShowcaseShell(child: ProgressScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/review.png'),
    );
  }, skip: !_generateShowcase);

  testWidgets('renders the synchronized transcript showcase', (tester) async {
    _usePhoneViewport(tester);
    const document = TranscriptDocument(
      episodeId: 21,
      language: 'en',
      source: 'showcase',
      targetLanguage: 'zh-Hans',
      translationSource: 'showcase',
      segments: [
        TranscriptSegment(
          index: 0,
          startMs: 0,
          endMs: 4200,
          text: 'Learning a language takes time, but every sentence helps.',
          translation: '学习一门语言需要时间，但每一句话都会带来帮助。',
          paragraphIndex: 0,
        ),
        TranscriptSegment(
          index: 1,
          startMs: 4200,
          endMs: 8100,
          text: 'Listen again, notice the details, and repeat what you hear.',
          translation: '再听一遍，留意细节，然后复述你听到的内容。',
          paragraphIndex: 1,
        ),
        TranscriptSegment(
          index: 2,
          startMs: 8100,
          endMs: 12600,
          text: 'The goal is not speed. The goal is clear understanding.',
          translation: '目标不是速度，而是真正听懂。',
          paragraphIndex: 2,
        ),
      ],
    );
    final engine = FakePlaybackEngine()
      ..duration = const Duration(minutes: 18, seconds: 32)
      ..position = const Duration(seconds: 5);
    final playback = PlaybackController(engine);
    final repository = FakePodcastRepository(transcript: document);
    final transcript = TranscriptController(repository, playback);
    addTearDown(transcript.dispose);
    addTearDown(playback.dispose);
    await playback.loadEpisode(
      const Episode(
        id: 21,
        podcastId: 1,
        guid: 'showcase-episode',
        title: 'How to learn from one good podcast',
        audioUrl: 'https://example.com/showcase.mp3',
        durationSeconds: 1112,
      ),
      fromPodcast: 'Everyday English',
    );
    await transcript.load(21);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _showcaseTheme(),
        home: PlayerScreen(
          controller: playback,
          transcriptController: transcript,
          podcastRepository: repository,
          transcriptOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/transcript.png'),
    );
  }, skip: !_generateShowcase);
}

class _ShowcaseShell extends StatelessWidget {
  const _ShowcaseShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _showcaseTheme(),
      home: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE7E8E9),
              Color(0xFFDDE1E5),
              Color(0xFFCBD4DC),
              Color(0xFFBECAD5),
            ],
            stops: [0, 0.30, 0.68, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}

ThemeData _showcaseTheme() {
  final base = AppTheme.light;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'NotoSansShowcase'),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'NotoSansShowcase',
    ),
  );
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
