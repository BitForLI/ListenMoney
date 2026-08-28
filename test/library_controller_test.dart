import 'package:flutter_test/flutter_test.dart';
import 'package:listen/features/library/application/library_controller.dart';
import 'package:listen/features/library/data/podcast_repository.dart';
import 'package:listen/features/library/domain/podcast.dart';

import 'fake_podcast_repository.dart';

void main() {
  test('blocks an eleventh subscription before writing local data', () async {
    final podcasts = List.generate(
      10,
      (index) => Podcast(
        id: index,
        title: 'Podcast $index',
        feedUrl: 'https://example.com/$index.xml',
        episodeCount: 0,
      ),
    );
    final repository = FakePodcastRepository(podcasts: podcasts);
    final controller = LibraryController(repository);
    await controller.load();

    expect(controller.canAdd, isFalse);
    await expectLater(
      controller.add('https://example.com/10.xml'),
      throwsA(isA<PodcastRepositoryException>()),
    );
    expect(repository.addCallCount, 0);
  });
}
