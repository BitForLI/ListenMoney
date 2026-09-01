import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../library/domain/podcast.dart';
import '../application/on_device_transcriber.dart';
import 'asr_segmentation.dart';
import 'transcript_audio_store.dart';

class MobileOnDeviceTranscriber implements OnDeviceTranscriber {
  MobileOnDeviceTranscriber({
    MethodChannel? audioDecoder,
    TranscriptAudioStore? audioStore,
  }) : _audioDecoder =
           audioDecoder ?? const MethodChannel('listen/audio_decoder'),
       _audioStore = audioStore ?? TranscriptAudioStore();

  static const int _maximumAudioBytes = 500 * 1024 * 1024;
  static const int _cacheVersion = 6;
  static const String _vadFilename = 'silero_vad.onnx';
  static final Uri _vadUri = Uri.parse(
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    'asr-models/$_vadFilename',
  );
  final MethodChannel _audioDecoder;
  final TranscriptAudioStore _audioStore;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<TranscriptDocument?> readCached(int episodeId) async {
    final file = await _cacheFile(episodeId);
    if (!await file.exists()) return null;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['asr_cache_version'] != _cacheVersion) return null;
      if (data['asr_complete'] != true) return null;
      final document = TranscriptDocument.fromJson(data);
      final key = document.audioKey;
      if (key == null || await _audioStore.resolve(key) == null) return null;
      return document;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TranscriptDocument> transcribe(
    Episode episode, {
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) async {
    if (!isSupported) {
      throw const OnDeviceTranscriptionException('手机离线转写目前仅支持 Android');
    }
    const spec = _ModelSpec();
    File? audioFile;
    var wavePaths = <String>[];
    try {
      final modelPaths = await _ensureModel(spec, onProgress);
      final vadPath = await _ensureVadModel(onProgress);
      onProgress?.call(
        const DeviceTranscriptionProgress(message: '正在下载播客音频…', fraction: 0.25),
      );
      audioFile = await _downloadAudio(episode, onProgress);
      onProgress?.call(
        const DeviceTranscriptionProgress(
          message: '正在为离线识别准备音频…',
          fraction: 0.42,
        ),
      );
      wavePaths = await _decodeAudio(audioFile.path);
      if (wavePaths.isEmpty) {
        throw const OnDeviceTranscriptionException('没有从节目中解码出可识别的音频');
      }
      final audioKey = await _audioStore.retain(
        audioFile,
        episodeId: episode.id,
      );

      final cues = <Map<String, dynamic>>[];
      await _recognize(
        modelPaths: modelPaths,
        vadPath: vadPath,
        wavePaths: wavePaths,
        onChunk: (chunkCues, chunkIndex, chunkCount) async {
          cues.addAll(chunkCues);
          final document = _document(episode.id, spec.id, cues, audioKey);
          await _writeCache(document, complete: false);
          onPartial?.call(document);
          onProgress?.call(
            DeviceTranscriptionProgress(
              message: cues.isEmpty
                  ? '正在分析人声并生成字幕…'
                  : chunkIndex == 0
                  ? '第一段字幕已可用，继续处理剩余内容…'
                  : '正在转写第 ${chunkIndex + 1} / $chunkCount 段…',
              fraction: 0.45 + 0.55 * ((chunkIndex + 1) / chunkCount),
            ),
          );
        },
      );
      if (cues.isEmpty) {
        throw const OnDeviceTranscriptionException('手机没有识别到有效语音');
      }
      final document = _document(episode.id, spec.id, cues, audioKey);
      await _writeCache(document, complete: true);
      onProgress?.call(
        const DeviceTranscriptionProgress(message: '手机离线字幕已完成', fraction: 1),
      );
      return document;
    } on OnDeviceTranscriptionException {
      rethrow;
    } on PlatformException catch (error) {
      throw OnDeviceTranscriptionException(error.message ?? 'Android 音频解码失败');
    } on SocketException catch (error) {
      throw OnDeviceTranscriptionException('下载失败：${error.message}');
    } catch (error) {
      throw OnDeviceTranscriptionException('手机离线转写失败：$error');
    } finally {
      if (audioFile != null && await audioFile.exists()) {
        await audioFile.delete();
      }
      for (final path in wavePaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<_ModelPaths> _ensureModel(
    _ModelSpec spec,
    void Function(DeviceTranscriptionProgress progress)? onProgress,
  ) async {
    final support = await getApplicationSupportDirectory();
    await _removeLegacyWhisperModels(support);
    final directory = Directory('${support.path}/asr/${spec.id}');
    await directory.create(recursive: true);
    final files = <String, Uri>{
      spec.encoderName: spec.uriFor(spec.encoderName),
      spec.decoderName: spec.uriFor(spec.decoderName),
      spec.joinerName: spec.uriFor(spec.joinerName),
      spec.tokensName: spec.uriFor(spec.tokensName),
    };
    var completed = 0;
    for (final entry in files.entries) {
      final target = File('${directory.path}/${entry.key}');
      if (!await target.exists() || await target.length() == 0) {
        await _downloadFile(
          entry.value,
          target,
          onBytes: (received, total) {
            final current = total > 0 ? received / total : 0.0;
            onProgress?.call(
              DeviceTranscriptionProgress(
                message:
                    '首次使用：下载${spec.label}模型 '
                    '${completed + 1} / ${files.length}',
                fraction: 0.22 * ((completed + current) / files.length),
              ),
            );
          },
        );
      }
      completed += 1;
    }
    return _ModelPaths(
      encoder: '${directory.path}/${spec.encoderName}',
      decoder: '${directory.path}/${spec.decoderName}',
      joiner: '${directory.path}/${spec.joinerName}',
      tokens: '${directory.path}/${spec.tokensName}',
    );
  }

  Future<void> _removeLegacyWhisperModels(Directory support) async {
    for (final id in const ['tiny.en', 'base.en', 'small.en', 'medium.en']) {
      final directory = Directory('${support.path}/asr/$id');
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<String> _ensureVadModel(
    void Function(DeviceTranscriptionProgress progress)? onProgress,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/asr/vad');
    await directory.create(recursive: true);
    final target = File('${directory.path}/$_vadFilename');
    if (!await target.exists() || await target.length() == 0) {
      await _downloadFile(
        _vadUri,
        target,
        onBytes: (received, total) {
          final current = total > 0 ? received / total : 0.0;
          onProgress?.call(
            DeviceTranscriptionProgress(
              message: '首次使用：下载高精度人声检测模型',
              fraction: 0.22 + current * 0.02,
            ),
          );
        },
      );
    }
    return target.path;
  }

  Future<File> _downloadAudio(
    Episode episode,
    void Function(DeviceTranscriptionProgress progress)? onProgress,
  ) async {
    final temporary = await getTemporaryDirectory();
    final uri = Uri.parse(episode.audioUrl);
    final extension = _safeExtension(uri.path);
    final file = File(
      '${temporary.path}/listen-episode-${episode.id}'
      '-${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await _downloadFile(
      uri,
      file,
      maximumBytes: _maximumAudioBytes,
      onBytes: (received, total) {
        final current = total > 0 ? received / total : 0.0;
        onProgress?.call(
          DeviceTranscriptionProgress(
            message: total > 0
                ? '正在下载播客音频 ${(current * 100).round()}%'
                : '正在下载播客音频…',
            fraction: 0.25 + current * 0.15,
          ),
        );
      },
    );
    return file;
  }

  Future<void> _downloadFile(
    Uri uri,
    File target, {
    int? maximumBytes,
    required void Function(int received, int total) onBytes,
  }) async {
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();
    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OnDeviceTranscriptionException(
          '下载失败（HTTP ${response.statusCode}）',
        );
      }
      final total = response.contentLength;
      var received = 0;
      sink = partial.openWrite();
      await for (final bytes in response) {
        received += bytes.length;
        if (maximumBytes != null && received > maximumBytes) {
          throw const OnDeviceTranscriptionException('音频超过 500 MB，无法手机转写');
        }
        sink.add(bytes);
        onBytes(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await partial.rename(target.path);
    } finally {
      await sink?.close();
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<List<String>> _decodeAudio(String path) async {
    final result = await _audioDecoder.invokeMethod<List<dynamic>>(
      'decodeToWavChunks',
      {'path': path, 'chunkSeconds': 30},
    );
    return (result ?? const []).map((item) => item.toString()).toList();
  }

  Future<void> _recognize({
    required _ModelPaths modelPaths,
    required String vadPath,
    required List<String> wavePaths,
    required Future<void> Function(
      List<Map<String, dynamic>> cues,
      int chunkIndex,
      int chunkCount,
    )
    onChunk,
  }) async {
    final messages = ReceivePort();
    final completer = Completer<void>();
    var pending = Future<void>.value();
    late final StreamSubscription<dynamic> messageSubscription;
    messageSubscription = messages.listen((message) {
      if (message is! Map) return;
      final type = message['type'];
      if (type == 'chunk') {
        final cues = (message['cues'] as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        pending = pending.then(
          (_) =>
              onChunk(cues, message['index'] as int, message['count'] as int),
        );
      } else if (type == 'done' && !completer.isCompleted) {
        pending.then(
          (_) {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );
      } else if (type == 'error' && !completer.isCompleted) {
        pending.then(
          (_) {
            if (!completer.isCompleted) {
              completer.completeError(
                OnDeviceTranscriptionException(message['message'].toString()),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );
      }
    });
    final isolate = await Isolate.spawn<Map<String, dynamic>>(
      _recognitionEntry,
      {
        'sendPort': messages.sendPort,
        'encoder': modelPaths.encoder,
        'decoder': modelPaths.decoder,
        'joiner': modelPaths.joiner,
        'tokens': modelPaths.tokens,
        'vad': vadPath,
        'wavePaths': wavePaths,
      },
    );
    try {
      await completer.future;
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await messageSubscription.cancel();
      messages.close();
    }
  }

  TranscriptDocument _document(
    int episodeId,
    String modelId,
    List<Map<String, dynamic>> cues,
    String audioKey,
  ) {
    return TranscriptDocument.fromJson({
      'episode_id': episodeId,
      'language': 'en',
      'source': 'android-v$_cacheVersion-$modelId',
      'segments': cues,
      'audio_key': audioKey,
    });
  }

  Future<File> _cacheFile(int episodeId) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/transcripts');
    await directory.create(recursive: true);
    return File('${directory.path}/episode-$episodeId.json');
  }

  Future<void> _writeCache(
    TranscriptDocument document, {
    required bool complete,
  }) async {
    final file = await _cacheFile(document.episodeId);
    await file.writeAsString(
      jsonEncode(_documentToJson(document, complete: complete)),
      flush: true,
    );
  }

  Map<String, dynamic> _documentToJson(
    TranscriptDocument document, {
    required bool complete,
  }) => {
    'asr_cache_version': _cacheVersion,
    'asr_complete': complete,
    'episode_id': document.episodeId,
    'language': document.language,
    'source': document.source,
    'target_language': document.targetLanguage,
    'translation_source': document.translationSource,
    'audio_key': document.audioKey,
    'segments': document.segments
        .map(
          (segment) => {
            'index': segment.index,
            'start_ms': segment.startMs,
            'end_ms': segment.endMs,
            'text': segment.text,
            'speaker': segment.speaker,
            'paragraph_index': segment.paragraphIndex,
            'translation': segment.translation,
          },
        )
        .toList(),
  };

  String _safeExtension(String path) {
    final match = RegExp(r'\.[a-zA-Z0-9]{2,5}$').firstMatch(path);
    return match?.group(0)?.toLowerCase() ?? '.audio';
  }
}

class OnDeviceTranscriptionException implements Exception {
  const OnDeviceTranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ModelSpec {
  const _ModelSpec();

  String get id => 'parakeet-tdt-0.6b-v2-int8';
  String get label => 'Parakeet 最高精度';

  String get encoderName => 'encoder.int8.onnx';
  String get decoderName => 'decoder.int8.onnx';
  String get joinerName => 'joiner.int8.onnx';
  String get tokensName => 'tokens.txt';

  Uri uriFor(String filename) => Uri.parse(
    'https://huggingface.co/csukuangfj/'
    'sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/'
    'resolve/main/$filename',
  );
}

class _ModelPaths {
  const _ModelPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
}

void _recognitionEntry(Map<String, dynamic> request) {
  final sendPort = request['sendPort'] as SendPort;
  sherpa.OfflineRecognizer? recognizer;
  sherpa.VoiceActivityDetector? vad;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        model: sherpa.OfflineModelConfig(
          transducer: sherpa.OfflineTransducerModelConfig(
            encoder: request['encoder'] as String,
            decoder: request['decoder'] as String,
            joiner: request['joiner'] as String,
          ),
          tokens: request['tokens'] as String,
          numThreads: math.min(6, math.max(4, Platform.numberOfProcessors - 2)),
          debug: false,
          provider: 'cpu',
          modelType: 'nemo_transducer',
        ),
      ),
    );
    const sampleRate = 16000;
    const vadWindowSize = 512;
    vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: request['vad'] as String,
          threshold: 0.50,
          minSilenceDuration: 0.45,
          minSpeechDuration: 0.25,
          windowSize: vadWindowSize,
          maxSpeechDuration: 24.0,
        ),
        sampleRate: sampleRate,
        numThreads: 2,
        provider: 'cpu',
        debug: false,
      ),
      bufferSizeInSeconds: 120,
    );
    final paths = (request['wavePaths'] as List<dynamic>).cast<String>();
    final vadWindow = Float32List(vadWindowSize);
    var vadWindowLength = 0;
    var cueIndex = 0;
    for (var chunkIndex = 0; chunkIndex < paths.length; chunkIndex += 1) {
      final wave = sherpa.readWave(paths[chunkIndex]);
      if (wave.sampleRate != sampleRate) {
        throw StateError('人声检测只支持 16 kHz 音频');
      }
      final cues = <Map<String, dynamic>>[];
      var sampleIndex = 0;
      while (sampleIndex < wave.samples.length) {
        final copied = math.min(
          vadWindowSize - vadWindowLength,
          wave.samples.length - sampleIndex,
        );
        vadWindow.setRange(
          vadWindowLength,
          vadWindowLength + copied,
          wave.samples,
          sampleIndex,
        );
        vadWindowLength += copied;
        sampleIndex += copied;
        if (vadWindowLength == vadWindowSize) {
          vad.acceptWaveform(vadWindow);
          vadWindowLength = 0;
        }
      }
      if (chunkIndex == paths.length - 1) {
        if (vadWindowLength > 0) {
          vadWindow.fillRange(vadWindowLength, vadWindowSize, 0);
          vad.acceptWaveform(vadWindow);
          vadWindowLength = 0;
        }
        vad.flush();
      }
      cueIndex = _drainVadSegments(
        vad,
        recognizer,
        cues,
        cueIndex: cueIndex,
        sampleRate: sampleRate,
      );
      sendPort.send({
        'type': 'chunk',
        'index': chunkIndex,
        'count': paths.length,
        'cues': cues,
      });
    }
    sendPort.send({'type': 'done'});
  } catch (error, stackTrace) {
    sendPort.send({'type': 'error', 'message': '$error\n$stackTrace'});
  } finally {
    vad?.free();
    recognizer?.free();
  }
}

int _drainVadSegments(
  sherpa.VoiceActivityDetector vad,
  sherpa.OfflineRecognizer recognizer,
  List<Map<String, dynamic>> cues, {
  required int cueIndex,
  required int sampleRate,
}) {
  var nextCueIndex = cueIndex;
  while (!vad.isEmpty()) {
    final speech = vad.front();
    vad.pop();
    if (speech.samples.isEmpty) continue;
    final regionOffsetMs = (speech.start * 1000 / sampleRate).round();
    final pass = _recognizeWithRetry(
      recognizer,
      speech.samples,
      sampleRate: sampleRate,
      offsetMs: regionOffsetMs,
    );
    for (final cue in pass.cues) {
      cues.add({
        'index': nextCueIndex,
        'start_ms': cue.startMs,
        'end_ms': cue.endMs,
        'text': cue.text,
        'speaker': null,
        'paragraph_index': nextCueIndex ~/ 4,
        'translation': null,
      });
      nextCueIndex += 1;
    }
  }
  return nextCueIndex;
}

class _RecognitionPass {
  const _RecognitionPass({required this.cues, required this.quality});

  final List<TimedTranscriptCue> cues;
  final double quality;
}

_RecognitionPass _recognizeWithRetry(
  sherpa.OfflineRecognizer recognizer,
  Float32List samples, {
  required int sampleRate,
  required int offsetMs,
}) {
  final first = _recognizeOnce(
    recognizer,
    samples,
    sampleRate: sampleRate,
    offsetMs: offsetMs,
  );
  final durationMs = (samples.length * 1000 / sampleRate).round();
  if (durationMs < 8000 || first.quality >= 0.50) return first;

  // Difficult long windows can repeat or drop words. Retry only that
  // low-quality window as two shorter windows, cut near the quietest point,
  // and keep whichever pass has the stronger text/timing score.
  final split = _quietSplit(samples, sampleRate);
  if (split <= sampleRate * 2 || split >= samples.length - sampleRate * 2) {
    return first;
  }
  final left = _recognizeOnce(
    recognizer,
    Float32List.sublistView(samples, 0, split),
    sampleRate: sampleRate,
    offsetMs: offsetMs,
  );
  final right = _recognizeOnce(
    recognizer,
    Float32List.sublistView(samples, split),
    sampleRate: sampleRate,
    offsetMs: offsetMs + (split * 1000 / sampleRate).round(),
  );
  final retryQuality = (left.quality + right.quality) / 2;
  if (retryQuality <= first.quality + 0.03 && first.cues.isNotEmpty) {
    return first;
  }
  return _RecognitionPass(
    cues: [...left.cues, ...right.cues],
    quality: retryQuality,
  );
}

_RecognitionPass _recognizeOnce(
  sherpa.OfflineRecognizer recognizer,
  Float32List samples, {
  required int sampleRate,
  required int offsetMs,
}) {
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);
    final durationMs = (samples.length * 1000 / sampleRate).round();
    final cues = buildTimedTranscriptCues(
      tokens: result.tokens,
      timestamps: result.timestamps,
      offsetMs: offsetMs,
      durationMs: durationMs,
      paragraphOffset: 0,
    );
    return _RecognitionPass(
      cues: cues,
      quality: cues.isEmpty
          ? 0
          : recognitionQuality(result.text, result.timestamps, durationMs),
    );
  } finally {
    stream.free();
  }
}

int _quietSplit(Float32List samples, int sampleRate) {
  final midpoint = samples.length ~/ 2;
  final radius = math.min(sampleRate * 2, samples.length ~/ 4);
  final frame = math.max(1, (sampleRate * 0.04).round());
  var best = midpoint;
  var bestEnergy = double.infinity;
  for (
    var start = math.max(frame, midpoint - radius);
    start < math.min(samples.length - frame, midpoint + radius);
    start += frame
  ) {
    var energy = 0.0;
    for (var index = start; index < start + frame; index += 1) {
      energy += samples[index].abs();
    }
    if (energy < bestEnergy) {
      bestEnergy = energy;
      best = start + frame ~/ 2;
    }
  }
  return best;
}
