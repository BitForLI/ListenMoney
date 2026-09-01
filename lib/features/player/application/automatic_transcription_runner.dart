import '../../library/data/podcast_repository.dart';
import '../../library/domain/podcast.dart';
import '../data/transcript_audio_store.dart';
import 'on_device_transcriber.dart';

class AutomaticTranscriptionRunner {
  AutomaticTranscriptionRunner(
    this._repository,
    this._transcriber, {
    this.audioStore,
  });
  final TranscriptAudioStore? audioStore;

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
        if (cached != null && await _isUsable(cached)) continue;
        if (await _hasUsableImportedTranscript(episode.id)) continue;
        final document = await _transcriber.transcribe(episode);
        try {
          await _repository.saveTranscript(document);
        } catch (_) {
          // The transcriber cache remains usable if app data persistence fails.
        }
      } catch (_) {
        // Continue with the remaining recent episodes after one failure.
      }
    }
  }

  Future<bool> _hasUsableImportedTranscript(int episodeId) async {
    try {
      final document = await _repository.importTranscript(episodeId);
      return await _isUsable(document);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isUsable(TranscriptDocument document) async {
    if (document.segments.isEmpty) return false;
    final store = audioStore;
    if (store == null) return true;
    final key = document.audioKey;
    return document.source == currentPhoneTranscriptSource &&
        key != null &&
        await store.resolve(key) != null;
  }

  static int _newestFirst(Episode left, Episode right) {
    final leftDate = left.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate =
        right.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final dateOrder = rightDate.compareTo(leftDate);
    return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
  }
}
