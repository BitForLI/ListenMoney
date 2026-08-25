import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/data/podcast_repository.dart';
import '../../library/domain/podcast.dart';
import 'playback_controller.dart';

class TranscriptController extends ChangeNotifier {
  TranscriptController(this._repository, this._playback) {
    _playback.addListener(_playbackChanged);
  }

  final PodcastRepository _repository;
  final PlaybackController _playback;
  TranscriptDocument? document;
  TranscriptSegment? activeSegment;
  bool isLoading = false;
  bool isTranscribing = false;
  bool isTranslating = false;
  bool showTranslation = true;
  String? errorMessage;
  int? _episodeId;
  int _loadGeneration = 0;

  void _playbackChanged() {
    final episode = _playback.episode;
    if (episode != null && episode.id != _episodeId) {
      _episodeId = episode.id;
      unawaited(load(episode.id));
      return;
    }
    final transcript = document;
    if (transcript == null || transcript.segments.isEmpty) return;
    final position = _playback.position.inMilliseconds;
    TranscriptSegment? next;
    for (final segment in transcript.segments) {
      if (position >= segment.startMs && position < segment.endMs) {
        next = segment;
        break;
      }
    }
    if (next == null || next.index == activeSegment?.index) return;
    _select(next, seek: false);
  }

  Future<void> load(int episodeId) async {
    _episodeId = episodeId;
    final generation = ++_loadGeneration;
    document = null;
    activeSegment = null;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      final loaded = await _repository.importTranscript(episodeId);
      if (generation != _loadGeneration) return;
      document = loaded;
      if (document!.segments.isNotEmpty) {
        _select(document!.segments.first, seek: false);
      }
    } catch (error) {
      if (generation != _loadGeneration) return;
      errorMessage = error.toString();
    } finally {
      if (generation == _loadGeneration) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> transcribe({String? language}) async {
    final episodeId = _episodeId;
    if (episodeId == null || isTranscribing) return;
    isTranscribing = true;
    errorMessage = null;
    notifyListeners();
    try {
      document = await _repository.transcribeEpisode(
        episodeId,
        language: language,
      );
      if (document!.segments.isNotEmpty) {
        _select(document!.segments.first, seek: false);
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isTranscribing = false;
      notifyListeners();
    }
  }

  Future<void> translate({String targetLanguage = 'zh-Hans'}) async {
    final episodeId = _episodeId;
    if (episodeId == null || document == null || isTranslating) return;
    isTranslating = true;
    errorMessage = null;
    notifyListeners();
    try {
      document = await _repository.translateTranscript(
        episodeId,
        targetLanguage: targetLanguage,
      );
      showTranslation = true;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isTranslating = false;
      notifyListeners();
    }
  }

  void toggleTranslation() {
    showTranslation = !showTranslation;
    notifyListeners();
  }

  Future<void> select(TranscriptSegment segment) async {
    _select(segment, seek: true);
  }

  void _select(TranscriptSegment segment, {required bool seek}) {
    activeSegment = segment;
    final segments = document!.segments
        .where((item) => item.paragraphIndex == segment.paragraphIndex)
        .toList();
    _playback.updateTranscriptRanges(
      sentence: PlaybackRange(
        start: Duration(milliseconds: segment.startMs),
        end: Duration(milliseconds: segment.endMs),
      ),
      paragraph: PlaybackRange(
        start: Duration(milliseconds: segments.first.startMs),
        end: Duration(milliseconds: segments.last.endMs),
      ),
    );
    if (seek) {
      unawaited(_playback.seek(Duration(milliseconds: segment.startMs)));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _playback.removeListener(_playbackChanged);
    super.dispose();
  }
}
