import 'dart:io';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../library/data/podcast_repository.dart';

abstract interface class TranscriptTranslator {
  Future<List<String>> translate(
    List<String> texts, {
    required String sourceLanguage,
    required String targetLanguage,
  });
}

class MobileTranscriptTranslator implements TranscriptTranslator {
  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const PodcastRepositoryException('离线翻译仅支持 Android 和 iOS');
    }
    final source = _language(
      sourceLanguage,
      fallback: TranslateLanguage.english,
    );
    final target = _language(
      targetLanguage,
      fallback: TranslateLanguage.chinese,
    );
    final manager = OnDeviceTranslatorModelManager();
    await _ensureModel(manager, source);
    await _ensureModel(manager, target);
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      final results = <String>[];
      for (final text in texts) {
        results.add(await translator.translateText(text));
      }
      return results;
    } catch (error) {
      throw PodcastRepositoryException('手机离线翻译失败：$error');
    } finally {
      await translator.close();
    }
  }

  Future<void> _ensureModel(
    OnDeviceTranslatorModelManager manager,
    TranslateLanguage language,
  ) async {
    final code = language.bcpCode;
    if (await manager.isModelDownloaded(code)) return;
    final downloaded = await manager.downloadModel(code);
    if (!downloaded) {
      throw const PodcastRepositoryException('无法下载手机离线翻译模型');
    }
  }

  TranslateLanguage _language(
    String value, {
    required TranslateLanguage fallback,
  }) {
    final prefix = value.toLowerCase().split('-').first;
    if (prefix == 'en') return TranslateLanguage.english;
    if (prefix == 'zh') return TranslateLanguage.chinese;
    return fallback;
  }
}
