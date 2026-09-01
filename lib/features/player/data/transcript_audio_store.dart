import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keeps the exact compressed audio used by ASR. A fresh request to the same
/// podcast URL is not necessarily the same recording (for example, ads).
class TranscriptAudioStore {
  TranscriptAudioStore({this.directory});

  final Directory? directory;
  Directory? _directory;

  Future<Directory> _root() async {
    final directory = _directory ??=
        this.directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/transcript-audio',
        );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> retain(File source, {required int episodeId}) async {
    final root = await _root();
    final extension =
        RegExp(r'\.[a-zA-Z0-9]{2,5}$')
            .firstMatch(source.path)
            ?.group(0)
            ?.toLowerCase() ??
        '.audio';
    final key =
        'episode-$episodeId-${DateTime.now().microsecondsSinceEpoch}$extension';
    final partial = File('${root.path}/$key.part');
    try {
      await source.copy(partial.path);
      await partial.rename('${root.path}/$key');
      return key;
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<File?> resolve(String key) async {
    // Stored documents contain a relative opaque key, never an arbitrary path.
    if (!RegExp(r'^episode-\d+-\d+\.[a-z0-9]{2,5}$').hasMatch(key)) return null;
    final file = File('${(await _root()).path}/$key');
    return await file.exists() && await file.length() > 0 ? file : null;
  }
}
