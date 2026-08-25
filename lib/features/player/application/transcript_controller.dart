import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/data/podcast_repository.dart';
import '../../library/domain/podcast.dart';
import 'on_device_transcriber.dart';
import 'playback_controller.dart';

class TranscriptController extends ChangeNotifier {
  TranscriptController(
    this._repository,
    this._playback, {
    this.onDeviceTranscriber,
  }) {
    _playback.addListener(_playbackChanged);
  }

  final PodcastRepository _repository;
  final PlaybackController _playback;
  final OnDeviceTranscriber? onDeviceTranscriber;
  TranscriptDocument? document;
  TranscriptSegment? activeSegment;
  DeviceTranscriptionModel transcriptionModel = DeviceTranscriptionModel.fast;
  double? transcriptionProgress;
  String? transcriptionStatus;
  bool isLoading = false;
  bool isTranscribing = false;
  bool isTranslating = false;
  bool showTranslation = true;
  String? errorMessage;
  int? _episodeId;
  int _loadGeneration = 0;
  bool _isSelectingSegment = false;
  bool _documentNeedsSync = false;

  bool get supportsOnDeviceTranscription =>
      onDeviceTranscriber?.isSupported ?? false;

  int get _activePosition {
    final transcript = document;
    final active = activeSegment;
    if (transcript == null || active == null) return -1;
    return transcript.segments.indexWhere((item) => item.index == active.index);
  }

  bool get canSelectPrevious => _activePosition > 0;

  bool get canSelectNext {
    final transcript = document;
    final position = _activePosition;
    return transcript != null &&
        position >= 0 &&
        position < transcript.segments.length - 1;
  }

  void _playbackChanged() {
    final episode = _playback.episode;
    if (episode != null && episode.id != _episodeId) {
      _episodeId = episode.id;
      unawaited(load(episode.id));
      return;
    }
    if (_isSelectingSegment) return;
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
    unawaited(_select(next, seek: false));
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
        if (cached == null) rethrow;
        _documentNeedsSync = true;
        await _showDocument(cached);
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
    transcriptionProgress = 0;
    transcriptionStatus = supportsOnDeviceTranscription
        ? '准备手机离线转写…'
        : '准备 Mac 本地转写…';
    notifyListeners();
    try {
      final episode = _playback.episode;
      if (supportsOnDeviceTranscription &&
          episode != null &&
          episode.id == episodeId) {
        final generated = await onDeviceTranscriber!.transcribe(
          episode,
          model: transcriptionModel,
          onProgress: (progress) {
            if (_episodeId != episodeId) return;
            transcriptionProgress = progress.fraction.clamp(0, 1);
            transcriptionStatus = progress.message;
            notifyListeners();
          },
          onPartial: (partial) {
            if (_episodeId != episodeId) return;
            _documentNeedsSync = true;
            unawaited(_showDocument(partial));
          },
        );
        if (_episodeId != episodeId) return;
        _documentNeedsSync = true;
        await _showDocument(generated);
        transcriptionStatus = '字幕已生成，正在同步到本地后端…';
        notifyListeners();
        try {
          final saved = await _repository.saveTranscript(generated);
          if (_episodeId != episodeId) return;
          _documentNeedsSync = false;
          await _showDocument(saved);
          transcriptionStatus = '手机离线字幕已完成';
        } catch (error) {
          errorMessage = '字幕已保存在手机，但未同步到后端：$error';
          transcriptionStatus = '手机离线字幕已完成';
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
      notifyListeners();
    }
  }

  void toggleTranslation() {
    showTranslation = !showTranslation;
    notifyListeners();
  }

  void setTranscriptionModel(DeviceTranscriptionModel model) {
    if (isTranscribing || transcriptionModel == model) return;
    transcriptionModel = model;
    notifyListeners();
  }

  Future<void> select(TranscriptSegment segment) async {
    _isSelectingSegment = true;
    try {
      await _select(segment, seek: true);
    } finally {
      _isSelectingSegment = false;
    }
  }

  Future<void> selectPrevious() => _selectRelative(-1);

  Future<void> selectNext() => _selectRelative(1);

  Future<void> _selectRelative(int offset) async {
    final transcript = document;
    final position = _activePosition;
    if (transcript == null || position < 0) return;
    final target = position + offset;
    if (target < 0 || target >= transcript.segments.length) return;
    await select(transcript.segments[target]);
  }

  Future<void> _showDocument(TranscriptDocument value) async {
    document = value;
    if (value.segments.isEmpty) {
      activeSegment = null;
      notifyListeners();
      return;
    }
    final position = _playback.position.inMilliseconds;
    final current = value.segments.where(
      (segment) => position >= segment.startMs && position < segment.endMs,
    );
    await _select(
      current.isEmpty ? value.segments.first : current.first,
      seek: false,
    );
  }

  Future<void> _select(TranscriptSegment segment, {required bool seek}) async {
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
    notifyListeners();
    if (seek) {
      final mode = _playback.repeatMode;
      if (mode == PlaybackRepeatMode.sentence ||
          mode == PlaybackRepeatMode.paragraph) {
        await _playback.setRepeatMode(mode);
      } else {
        await _playback.seek(Duration(milliseconds: segment.startMs));
      }
    }
  }

  @override
  void dispose() {
    _playback.removeListener(_playbackChanged);
    super.dispose();
  }
}
