import '../../library/domain/podcast.dart';

enum DeviceTranscriptionModel { fast, accurate }

extension DeviceTranscriptionModelLabel on DeviceTranscriptionModel {
  String get label => switch (this) {
    DeviceTranscriptionModel.fast => '快速（Tiny 英语）',
    DeviceTranscriptionModel.accurate => '准确（Base 英语）',
  };
}

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
    required DeviceTranscriptionModel model,
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  });
}
