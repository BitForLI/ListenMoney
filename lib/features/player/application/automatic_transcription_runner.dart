import '../../library/data/podcast_repository.dart';
import '../../library/domain/podcast.dart';
import 'on_device_transcriber.dart';

class AutomaticTranscriptionRunner {
  AutomaticTranscriptionRunner(this._repository, this._transcriber);

  static const latestEpisodeLimit = 5;

  final PodcastRepository _repository;
  final OnDeviceTranscriber _transcriber;
  final Set<int> _attemptedEpisodeIds = <int>{};
  List<Podcast>? _pendingPodcasts;
  bool _running = false;

  Future<void> run(List<Podcast> podcasts) async {
    if (!_transcriber.isSupported || podcasts.isEmpty) return;
    _pendingPodcasts = List<Podcast>.of(podcasts);
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final pending = _pendingPodcasts;
        if (pending == null) break;
        _pendingPodcasts = null;
        await _runOnce(pending);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runOnce(List<Podcast> podcasts) async {
    final episodeGroups = await Future.wait(
      podcasts.map((podcast) async {
        try {
          return await _repository.listEpisodes(podcast.id);
        } catch (_) {
          return <Episode>[];
        }
      }),
    );
    final latest = episodeGroups.expand((episodes) => episodes).toList()
      ..sort(_newestFirst);
    for (final episode in latest.take(latestEpisodeLimit)) {
      if (!_attemptedEpisodeIds.add(episode.id)) continue;
      try {
        final cached = await _transcriber.readCached(episode.id);
        if (cached != null && cached.segments.isNotEmpty) continue;
        if (await _hasUsableImportedTranscript(episode.id)) continue;
        final document = await _transcriber.transcribe(episode);
        try {
          await _repository.saveTranscript(document);
        } catch (_) {
          // The phone cache remains usable when the local backend disconnects.
        }
      } catch (_) {
        // Continue with the remaining recent episodes after one failure.
      }
    }
  }

  Future<bool> _hasUsableImportedTranscript(int episodeId) async {
    try {
      final document = await _repository.importTranscript(episodeId);
      if (document.segments.isEmpty) return false;
      if (!document.source.startsWith('android-')) return true;
      return document.source == 'android-v5-parakeet-tdt-0.6b-v2-int8';
    } catch (_) {
      return false;
    }
  }

  static int _newestFirst(Episode left, Episode right) {
    final leftDate = left.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate =
        right.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final dateOrder = rightDate.compareTo(leftDate);
    return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
  }
}
