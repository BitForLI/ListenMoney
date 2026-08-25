import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../library/domain/podcast.dart';
import '../application/on_device_transcriber.dart';

class MobileOnDeviceTranscriber implements OnDeviceTranscriber {
  MobileOnDeviceTranscriber({MethodChannel? audioDecoder})
    : _audioDecoder =
          audioDecoder ?? const MethodChannel('listen/audio_decoder');

  static const int _maximumAudioBytes = 500 * 1024 * 1024;
  final MethodChannel _audioDecoder;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<TranscriptDocument?> readCached(int episodeId) async {
    final file = await _cacheFile(episodeId);
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      return TranscriptDocument.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TranscriptDocument> transcribe(
    Episode episode, {
    required DeviceTranscriptionModel model,
    void Function(DeviceTranscriptionProgress progress)? onProgress,
    void Function(TranscriptDocument document)? onPartial,
  }) async {
    if (!isSupported) {
      throw const OnDeviceTranscriptionException('手机离线转写目前仅支持 Android');
    }
    final spec = _ModelSpec.forQuality(model);
    File? audioFile;
    var wavePaths = <String>[];
    try {
      final modelPaths = await _ensureModel(spec, onProgress);
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

      final cues = <Map<String, dynamic>>[];
      await _recognize(
        modelPaths: modelPaths,
        wavePaths: wavePaths,
        onChunk: (chunkCues, chunkIndex, chunkCount) async {
          cues.addAll(chunkCues);
          final document = _document(episode.id, spec.id, cues);
          await _writeCache(document);
          onPartial?.call(document);
          onProgress?.call(
            DeviceTranscriptionProgress(
              message: chunkIndex == 0
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
      final document = _document(episode.id, spec.id, cues);
      await _writeCache(document);
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
    final directory = Directory('${support.path}/asr/${spec.id}');
    await directory.create(recursive: true);
    final files = <String, Uri>{
      spec.encoderName: spec.uriFor(spec.encoderName),
      spec.decoderName: spec.uriFor(spec.decoderName),
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
      tokens: '${directory.path}/${spec.tokensName}',
    );
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
        'tokens': modelPaths.tokens,
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
  ) {
    return TranscriptDocument.fromJson({
      'episode_id': episodeId,
      'language': 'en',
      'source': 'android-$modelId',
      'segments': cues,
    });
  }

  Future<File> _cacheFile(int episodeId) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/transcripts');
    await directory.create(recursive: true);
    return File('${directory.path}/episode-$episodeId.json');
  }

  Future<void> _writeCache(TranscriptDocument document) async {
    final file = await _cacheFile(document.episodeId);
    await file.writeAsString(
      jsonEncode(_documentToJson(document)),
      flush: true,
    );
  }

  Map<String, dynamic> _documentToJson(TranscriptDocument document) => {
    'episode_id': document.episodeId,
    'language': document.language,
    'source': document.source,
    'target_language': document.targetLanguage,
    'translation_source': document.translationSource,
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
  const _ModelSpec({required this.id, required this.label});

  factory _ModelSpec.forQuality(DeviceTranscriptionModel quality) {
    return switch (quality) {
      DeviceTranscriptionModel.fast => const _ModelSpec(
        id: 'tiny.en',
        label: '快速',
      ),
      DeviceTranscriptionModel.accurate => const _ModelSpec(
        id: 'base.en',
        label: '准确',
      ),
    };
  }

  final String id;
  final String label;

  String get encoderName => '$id-encoder.int8.onnx';
  String get decoderName => '$id-decoder.int8.onnx';
  String get tokensName => '$id-tokens.txt';

  Uri uriFor(String filename) => Uri.parse(
    'https://huggingface.co/csukuangfj/'
    'sherpa-onnx-whisper-$id/resolve/main/$filename',
  );
}

class _ModelPaths {
  const _ModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String tokens;
}

void _recognitionEntry(Map<String, dynamic> request) {
  final sendPort = request['sendPort'] as SendPort;
  sherpa.OfflineRecognizer? recognizer;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: request['encoder'] as String,
            decoder: request['decoder'] as String,
            language: 'en',
            task: 'transcribe',
            enableTokenTimestamps: true,
            enableSegmentTimestamps: true,
          ),
          tokens: request['tokens'] as String,
          numThreads: 4,
          debug: false,
          provider: 'cpu',
          modelType: 'whisper',
        ),
      ),
    );
    final paths = (request['wavePaths'] as List<dynamic>).cast<String>();
    var offsetMs = 0;
    var cueIndex = 0;
    for (var chunkIndex = 0; chunkIndex < paths.length; chunkIndex += 1) {
      final wave = sherpa.readWave(paths[chunkIndex]);
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        final durationMs = (wave.samples.length * 1000 / wave.sampleRate)
            .round();
        final cues = _cuesFromResult(
          result,
          offsetMs: offsetMs,
          durationMs: durationMs,
          startIndex: cueIndex,
        );
        cueIndex += cues.length;
        sendPort.send({
          'type': 'chunk',
          'index': chunkIndex,
          'count': paths.length,
          'cues': cues,
        });
        offsetMs += durationMs;
      } finally {
        stream.free();
      }
    }
    sendPort.send({'type': 'done'});
  } catch (error, stackTrace) {
    sendPort.send({'type': 'error', 'message': '$error\n$stackTrace'});
  } finally {
    recognizer?.free();
  }
}

List<Map<String, dynamic>> _cuesFromResult(
  sherpa.OfflineRecognizerResult result, {
  required int offsetMs,
  required int durationMs,
  required int startIndex,
}) {
  final entries = <({String text, int startMs})>[];
  final count = result.tokens.length < result.timestamps.length
      ? result.tokens.length
      : result.timestamps.length;
  for (var index = 0; index < count; index += 1) {
    final token = _cleanToken(result.tokens[index]);
    if (token.isEmpty) continue;
    final start = (result.timestamps[index] * 1000).round().clamp(
      0,
      durationMs,
    );
    entries.add((text: token, startMs: start));
  }
  if (entries.isEmpty) {
    return _fallbackCues(
      result.text,
      offsetMs: offsetMs,
      durationMs: durationMs,
      startIndex: startIndex,
    );
  }

  final cues = <Map<String, dynamic>>[];
  var buffer = '';
  var cueStart = entries.first.startMs;
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    if (buffer.isEmpty) cueStart = entry.startMs;
    buffer = _appendToken(buffer, entry.text);
    final nextStart = index + 1 < entries.length
        ? entries[index + 1].startMs
        : durationMs;
    final sentenceEnd = RegExp(r'[.!?][\"”’]?\s*$').hasMatch(buffer);
    final longCue = nextStart - cueStart >= 12000 || buffer.length >= 180;
    if (!sentenceEnd && !longCue && index + 1 < entries.length) continue;
    final text = buffer.trim();
    if (text.isNotEmpty) {
      final absoluteIndex = startIndex + cues.length;
      cues.add({
        'index': absoluteIndex,
        'start_ms': offsetMs + cueStart,
        'end_ms': offsetMs + (nextStart > cueStart ? nextStart : cueStart + 1),
        'text': text,
        'speaker': null,
        'paragraph_index': absoluteIndex ~/ 4,
        'translation': null,
      });
    }
    buffer = '';
  }
  return cues;
}

List<Map<String, dynamic>> _fallbackCues(
  String text, {
  required int offsetMs,
  required int durationMs,
  required int startIndex,
}) {
  final sentences = RegExp(r'[^.!?]+[.!?]?')
      .allMatches(text)
      .map((match) => match.group(0)!.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (sentences.isEmpty) return const [];
  final cueDuration = durationMs / sentences.length;
  return List.generate(sentences.length, (index) {
    final absoluteIndex = startIndex + index;
    final start = (cueDuration * index).round();
    final end = (cueDuration * (index + 1)).round();
    return {
      'index': absoluteIndex,
      'start_ms': offsetMs + start,
      'end_ms': offsetMs + (end > start ? end : start + 1),
      'text': sentences[index],
      'speaker': null,
      'paragraph_index': absoluteIndex ~/ 4,
      'translation': null,
    };
  });
}

String _cleanToken(String token) {
  if (token.startsWith('<|') && token.endsWith('|>')) return '';
  return token.replaceAll('▁', ' ').replaceAll('Ġ', ' ');
}

String _appendToken(String current, String token) {
  if (current.isEmpty) return token.trimLeft();
  if (token.startsWith(' ') || RegExp(r'^[,.;:!?\)\]”’]').hasMatch(token)) {
    return '$current$token';
  }
  if (RegExp(r'[\(\[“‘]$').hasMatch(current)) return '$current$token';
  return '$current $token';
}
