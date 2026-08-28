import 'dart:async';

import '../../library/domain/podcast.dart';

class DeviceTranscriptionProgress {
  const DeviceTranscriptionProgress({
    required this.message,
    required this.fraction,
  });

  final String message;
  final double fraction;
}

abstract class OnDeviceTranscriber {
  bool get isSupported;

  Future<TranscriptDocument?> readCached(int episodeId);

  Future<TranscriptDocument> transcribe(
    Episode episode, {
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  });
}

class QueuedOnDeviceTranscriber implements OnDeviceTranscriber {
  QueuedOnDeviceTranscriber(this._delegate);

  final OnDeviceTranscriber _delegate;
  Future<void> _tail = Future<void>.value();
  final Map<int, _QueuedTranscriptionJob> _jobs = {};

  @override
  bool get isSupported => _delegate.isSupported;

  @override
  Future<TranscriptDocument?> readCached(int episodeId) {
    return _delegate.readCached(episodeId);
  }

  @override
  Future<TranscriptDocument> transcribe(
    Episode episode, {
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) {
    final existing = _jobs[episode.id];
    if (existing != null) {
      existing.addListeners(onProgress: onProgress, onPartial: onPartial);
      return existing.future;
    }
    final job = _QueuedTranscriptionJob()
      ..addListeners(onProgress: onProgress, onPartial: onPartial)
      ..emitProgress(
        const DeviceTranscriptionProgress(message: '正在等待转写队列…', fraction: 0),
      );
    _jobs[episode.id] = job;
    final previous = _tail;
    _tail = () async {
      try {
        await previous;
      } catch (_) {
        // A failed episode must not block later queued transcriptions.
      }
      try {
        final document = await _delegate.transcribe(
          episode,
          onProgress: job.emitProgress,
          onPartial: job.emitPartial,
        );
        job.complete(document);
      } catch (error, stackTrace) {
        job.completeError(error, stackTrace);
      } finally {
        _jobs.remove(episode.id);
      }
    }();
    return job.future;
  }
}

class _QueuedTranscriptionJob {
  final Completer<TranscriptDocument> _completer = Completer();
  final List<void Function(DeviceTranscriptionProgress)> _progressListeners =
      [];
  final List<void Function(TranscriptDocument)> _partialListeners = [];
  DeviceTranscriptionProgress? _lastProgress;
  TranscriptDocument? _lastPartial;

  Future<TranscriptDocument> get future => _completer.future;

  void addListeners({
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) {
    if (onProgress != null) {
      _progressListeners.add(onProgress);
      final progress = _lastProgress;
      if (progress != null) {
        try {
          onProgress(progress);
        } catch (_) {}
      }
    }
    if (onPartial != null) {
      _partialListeners.add(onPartial);
      final partial = _lastPartial;
      if (partial != null) {
        try {
          onPartial(partial);
        } catch (_) {}
      }
    }
  }

  void emitProgress(DeviceTranscriptionProgress progress) {
    _lastProgress = progress;
    for (final listener in List.of(_progressListeners)) {
      try {
        listener(progress);
      } catch (_) {}
    }
  }

  void emitPartial(TranscriptDocument document) {
    _lastPartial = document;
    for (final listener in List.of(_partialListeners)) {
      try {
        listener(document);
      } catch (_) {}
    }
  }

  void complete(TranscriptDocument document) => _completer.complete(document);

  void completeError(Object error, StackTrace stackTrace) {
    _completer.completeError(error, stackTrace);
  }
}
