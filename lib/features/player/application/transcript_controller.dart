import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/data/podcast_repository.dart';
import '../../library/domain/podcast.dart';
import '../data/transcript_audio_store.dart';
import 'on_device_transcriber.dart';
import 'playback_controller.dart';
import 'playback_engine.dart';

class TranscriptController extends ChangeNotifier {
  TranscriptController(
    this._repository,
    this._playback, {
    this.onDeviceTranscriber,
    this.audioStore,
  }) {
    _playback.addListener(_playbackChanged);
  }

  final PodcastRepository _repository;
  final PlaybackController _playback;
  final OnDeviceTranscriber? onDeviceTranscriber;
  final TranscriptAudioStore? audioStore;
  TranscriptDocument? document;
  TranscriptSegment? activeSegment;
  double? transcriptionProgress;
  String? transcriptionStatus;
  bool isLoading = false;
  bool isTranscribing = false;
  bool isTranslating = false;
  bool showTranslation = true;
  String? errorMessage;
  int? _episodeId;
  int _loadGeneration = 0;
  int _documentGeneration = 0;
  bool _disposed = false;
  bool _documentNeedsSync = false;
  String? _synchronizedAudioUri;

  bool get hasSynchronizedTranscript {
    final value = document;
    if (value == null || value.segments.isEmpty) return false;
    if (audioStore == null) return true;
    return value.source == currentPhoneTranscriptSource &&
        _synchronizedAudioUri != null &&
        _playback.loadedAudioUrl == _synchronizedAudioUri &&
        _playback.episode?.id == value.episodeId;
  }

  bool get needsAlignment => document != null && !hasSynchronizedTranscript;
  bool get canFollowPlayback =>
      hasSynchronizedTranscript &&
      !_playback.isLoading &&
      !_playback.isSeeking &&
      _playback.processingState == EngineProcessingState.ready;

  bool get supportsOnDeviceTranscription =>
      onDeviceTranscriber?.isSupported ?? false;

  int get _activePosition {
    final transcript = document;
    final active = _playback.isSeeking
        ? _segmentAt(_playback.position.inMilliseconds)
        : activeSegment;
    if (transcript == null || active == null) return -1;
    return transcript.segments.indexWhere((item) => item.index == active.index);
  }

  bool get canSelectPrevious {
    if (!hasSynchronizedTranscript) return false;
    final transcript = document;
    if (transcript == null) return false;
    final position = _activePosition;
    if (position >= 0) return position > 0;
    final playbackMs = _playback.position.inMilliseconds;
    return transcript.segments.any((segment) => segment.startMs < playbackMs);
  }

  bool get canSelectNext {
    if (!hasSynchronizedTranscript) return false;
    final transcript = document;
    final position = _activePosition;
    if (transcript == null) return false;
    if (position >= 0) return position < transcript.segments.length - 1;
    final playbackMs = _playback.position.inMilliseconds;
    return transcript.segments.any((segment) => segment.startMs > playbackMs);
  }

  List<TranscriptSegment> get _paragraphStarts {
    final transcript = document;
    if (transcript == null) return const [];
    final starts = <TranscriptSegment>[];
    int? previousParagraph;
    for (final segment in transcript.segments) {
      if (segment.paragraphIndex == previousParagraph) continue;
      starts.add(segment);
      previousParagraph = segment.paragraphIndex;
    }
    return starts;
  }

  int get _activeParagraphPosition {
    final active = activeSegment;
    if (active == null) return -1;
    return _paragraphStarts.indexWhere(
      (segment) => segment.paragraphIndex == active.paragraphIndex,
    );
  }

  bool get canSelectPreviousParagraph =>
      hasSynchronizedTranscript && _activeParagraphPosition > 0;

  bool get canSelectNextParagraph {
    if (!hasSynchronizedTranscript) return false;
    final position = _activeParagraphPosition;
    return position >= 0 && position < _paragraphStarts.length - 1;
  }

  void _playbackChanged() {
    final episode = _playback.episode;
    if (episode != null && episode.id != _episodeId) {
      _episodeId = episode.id;
      unawaited(load(episode.id));
      return;
    }
    final transcript = document;
    if (transcript == null || transcript.segments.isEmpty) return;
    if (!hasSynchronizedTranscript) {
      if (activeSegment != null || _playback.sentenceRange != null) {
        activeSegment = null;
        _playback.updateTranscriptRanges();
        notifyListeners();
      }
      return;
    }
    if (!canFollowPlayback) return;
    final position = _playback.actualPosition.inMilliseconds;
    final next = _segmentAt(position);
    if (next == null) {
      _clearActiveSegment(position);
      return;
    }
    if (next.index == activeSegment?.index) return;
    _setActiveSegment(next);
  }

  TranscriptSegment? _segmentAt(int positionMs) => document?.segments
      .where(
        (segment) =>
            positionMs >= segment.startMs && positionMs < segment.endMs,
      )
      .firstOrNull;

  Future<void> load(int episodeId) async {
    if (_disposed) return;
    _episodeId = episodeId;
    final generation = ++_loadGeneration;
    _documentGeneration += 1;
    document = null;
    activeSegment = null;
    _synchronizedAudioUri = null;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      try {
        final loaded = await _repository.importTranscript(episodeId);
        if (generation != _loadGeneration) return;
        _documentNeedsSync = false;
        await _showDocument(loaded);
      } catch (remoteError) {
        final cached = supportsOnDeviceTranscription
            ? await onDeviceTranscriber!.readCached(episodeId)
            : null;
        if (generation != _loadGeneration) return;
        if (cached != null) {
          _documentNeedsSync = true;
          await _showDocument(cached);
        }
        if (cached == null) rethrow;
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
    if (_disposed || episodeId == null || isTranscribing) return;
    isTranscribing = true;
    errorMessage = null;
    transcriptionProgress = 0;
    transcriptionStatus = supportsOnDeviceTranscription
        ? '准备手机离线转写…'
        : '当前设备不支持离线转写';
    notifyListeners();
    try {
      final episode = _playback.episode;
      if (supportsOnDeviceTranscription &&
          episode != null &&
          episode.id == episodeId) {
        final generated = await onDeviceTranscriber!.transcribe(
          episode,
          onProgress: (progress) {
            if (_episodeId != episodeId) return;
            transcriptionProgress = progress.fraction.clamp(0, 1);
            transcriptionStatus = progress.message;
            notifyListeners();
          },
          onPartial: (partial) {
            if (_episodeId != episodeId) return;
            _documentNeedsSync = true;
            unawaited(
              _showDocument(partial).catchError((Object error) {
                if (_episodeId != episodeId) return;
                errorMessage = error.toString();
                notifyListeners();
              }),
            );
          },
        );
        if (_episodeId != episodeId) return;
        _documentNeedsSync = true;
        await _showDocument(generated);
        transcriptionStatus = '字幕已生成，正在保存到手机…';
        notifyListeners();
        try {
          final saved = await _repository.saveTranscript(generated);
          if (_episodeId != episodeId) return;
          _documentNeedsSync = false;
          await _showDocument(saved);
          transcriptionStatus = '手机离线字幕已完成';
        } catch (error) {
          errorMessage = '字幕缓存已生成，但保存失败：$error';
          transcriptionStatus = '手机离线字幕缓存已完成';
        }
      } else {
        final generated = await _repository.transcribeEpisode(
          episodeId,
          language: language,
        );
        _documentNeedsSync = false;
        await _showDocument(generated);
        transcriptionStatus = '本地字幕已完成';
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isTranscribing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> translate({String targetLanguage = 'zh-Hans'}) async {
    final episodeId = _episodeId;
    if (episodeId == null || document == null || isTranslating) return;
    isTranslating = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (_documentNeedsSync) {
        document = await _repository.saveTranscript(document!);
        _documentNeedsSync = false;
      }
      document = await _repository.translateTranscript(
        episodeId,
        targetLanguage: targetLanguage,
      );
      showTranslation = true;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isTranslating = false;
      if (!_disposed) notifyListeners();
    }
  }

  void toggleTranslation() {
    showTranslation = !showTranslation;
    notifyListeners();
  }

  Future<void> select(TranscriptSegment segment) async {
    if (!hasSynchronizedTranscript) return;
    if (document?.segments.contains(segment) != true) return;
    await _playback.seek(Duration(milliseconds: segment.startMs));
  }

  Future<void> selectPrevious() => _selectRelative(-1);

  Future<void> selectNext() => _selectRelative(1);

  Future<void> selectPreviousParagraph() => _selectParagraphRelative(-1);

  Future<void> selectNextParagraph() => _selectParagraphRelative(1);

  Future<void> _selectParagraphRelative(int offset) async {
    final paragraphs = _paragraphStarts;
    final position = _activeParagraphPosition;
    if (position < 0) return;
    final target = position + offset;
    if (target < 0 || target >= paragraphs.length) return;
    await select(paragraphs[target]);
  }

  Future<void> _selectRelative(int offset) async {
    final transcript = document;
    final position = _activePosition;
    if (transcript == null) return;
    if (position < 0) {
      final playbackMs = _playback.position.inMilliseconds;
      final candidates = offset > 0
          ? transcript.segments.where((segment) => segment.startMs > playbackMs)
          : transcript.segments
                .where((segment) => segment.startMs < playbackMs)
                .toList()
                .reversed;
      if (candidates.isEmpty) return;
      await select(candidates.first);
      return;
    }
    final target = position + offset;
    if (target < 0 || target >= transcript.segments.length) return;
    await select(transcript.segments[target]);
  }

  Future<void> _showDocument(TranscriptDocument value) async {
    if (_disposed || _episodeId != value.episodeId) return;
    final generation = _loadGeneration;
    final revision = ++_documentGeneration;
    final key = value.audioKey;
    String? synchronizedUri;
    if (key != null &&
        audioStore != null &&
        value.source == currentPhoneTranscriptSource) {
      final file = await audioStore!.resolve(key);
      if (generation != _loadGeneration ||
          revision != _documentGeneration ||
          _episodeId != value.episodeId) {
        return;
      }
      if (file == null) {
        throw const PodcastRepositoryException('字幕对应的音频已丢失，请重新转写以校准时间轴');
      }
      await _playback.useTranscriptAudio(value.episodeId, file.uri.toString());
      if (generation != _loadGeneration ||
          revision != _documentGeneration ||
          _episodeId != value.episodeId) {
        return;
      }
      synchronizedUri = file.uri.toString();
    }
    document = value;
    _synchronizedAudioUri = synchronizedUri;
    if (!hasSynchronizedTranscript) {
      activeSegment = null;
      _playback.updateTranscriptRanges();
      notifyListeners();
      return;
    }
    if (value.segments.isEmpty) {
      activeSegment = null;
      _playback.updateTranscriptRanges();
      notifyListeners();
      return;
    }
    if (!canFollowPlayback) {
      notifyListeners();
      return;
    }
    final position = _playback.actualPosition.inMilliseconds;
    final current = value.segments.where(
      (segment) => position >= segment.startMs && position < segment.endMs,
    );
    if (current.isEmpty) {
      _clearActiveSegment(position);
    } else {
      _setActiveSegment(current.first);
    }
  }

  void _setActiveSegment(TranscriptSegment segment) {
    activeSegment = segment;
    _updateRanges(segment);
    notifyListeners();
  }

  void _clearActiveSegment(int positionMs) {
    final upcoming = document!.segments
        .where((s) => s.startMs > positionMs)
        .firstOrNull;
    final unchanged =
        activeSegment == null &&
        _playback.sentenceRange?.start.inMilliseconds == upcoming?.startMs &&
        _playback.sentenceRange?.end.inMilliseconds == upcoming?.endMs;
    activeSegment = null;
    if (unchanged) return;
    // Before speech (or in a gap), allow selecting the next loop without
    // pretending its words are already being spoken.
    if (upcoming == null) {
      _playback.updateTranscriptRanges();
    } else {
      _updateRanges(upcoming);
    }
    notifyListeners();
  }

  void _updateRanges(TranscriptSegment segment) {
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
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration += 1;
    _documentGeneration += 1;
    _episodeId = null;
    _playback.removeListener(_playbackChanged);
    super.dispose();
  }
}
