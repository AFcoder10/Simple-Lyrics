import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class CacheService {
  static const String _lyricsDirName = 'lyrics_cache';
  static const String _artworkDirName = 'artwork_cache';

  static String makeKey(String songName, String artistName) {
    final song = _normalizeKey(songName);
    final artist = _normalizeKey(artistName);
    return _hashKey('$song|$artist');
  }

  static Future<String?> readLyrics(String key) async {
    try {
      final file = await _lyricsFile(key);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeLyrics(String key, String ttml, {String? title, String? artist}) async {
    try {
      final file = await _lyricsFile(key);
      await file.writeAsString(ttml, flush: true);
      
      if (title != null && artist != null) {
        await _updateIndex(key, title, artist);
      }
    } catch (_) {
      return;
    }
  }

  static Future<Map<String, dynamic>> getIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _updateIndex(String key, String title, String artist) async {
    final index = await getIndex();
    index[key] = {'title': title, 'artist': artist, 'timestamp': DateTime.now().millisecondsSinceEpoch};
    final file = await _indexFile();
    await file.writeAsString(jsonEncode(index), flush: true);
  }

  static Future<File> _indexFile() async {
    final base = await _baseDir();
    return File('${base.path}/cache_index.json');
  }

  static Future<CachedArtworkBytes?> readArtwork(String key) async {
    try {
      final dir = await _ensureDir(_artworkDirName);
      final largeFile = File('${dir.path}/${key}_l.jpg');
      final smallFile = File('${dir.path}/${key}_s.jpg');

      final hasLarge = await largeFile.exists();
      final hasSmall = await smallFile.exists();
      if (!hasLarge && !hasSmall) return null;

      final largeBytes = hasLarge ? await largeFile.readAsBytes() : null;
      final smallBytes = hasSmall ? await smallFile.readAsBytes() : null;

      return CachedArtworkBytes(
        largeBytes: largeBytes ?? smallBytes,
        smallBytes: smallBytes ?? largeBytes,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeArtwork(
    String key, {
    Uint8List? largeBytes,
    Uint8List? smallBytes,
  }) async {
    if (largeBytes == null && smallBytes == null) return;
    try {
      final dir = await _ensureDir(_artworkDirName);
      if (largeBytes != null) {
        final largeFile = File('${dir.path}/${key}_l.jpg');
        await largeFile.writeAsBytes(largeBytes, flush: true);
      }
      if (smallBytes != null) {
        final smallFile = File('${dir.path}/${key}_s.jpg');
        await smallFile.writeAsBytes(smallBytes, flush: true);
      }
    } catch (_) {
      return;
    }
  }

  static Future<void> clearAll() async {
    final base = await _baseDir();
    final lyricsDir = Directory('${base.path}/$_lyricsDirName');
    final artworkDir = Directory('${base.path}/$_artworkDirName');
    final iFile = await _indexFile();

    if (await lyricsDir.exists()) {
      await lyricsDir.delete(recursive: true);
    }
    if (await artworkDir.exists()) {
      await artworkDir.delete(recursive: true);
    }
    if (await iFile.exists()) {
      await iFile.delete();
    }
  }

  static Future<void> clearSong(String key) async {
    try {
      final lFile = await _lyricsFile(key);
      if (await lFile.exists()) await lFile.delete();

      final dir = await _ensureDir(_artworkDirName);
      final largeFile = File('${dir.path}/${key}_l.jpg');
      final smallFile = File('${dir.path}/${key}_s.jpg');
      if (await largeFile.exists()) await largeFile.delete();
      if (await smallFile.exists()) await smallFile.delete();

      // Update index
      final index = await getIndex();
      if (index.containsKey(key)) {
        index.remove(key);
        final iFile = await _indexFile();
        await iFile.writeAsString(jsonEncode(index), flush: true);
      }
    } catch (_) {}
  }

  static Future<File> _lyricsFile(String key) async {
    final dir = await _ensureDir(_lyricsDirName);
    return File('${dir.path}/$key.ttml');
  }

  static Future<Directory> _ensureDir(String name) async {
    final base = await _baseDir();
    final dir = Directory('${base.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _baseDir() async {
    return getTemporaryDirectory();
  }

  static String _normalizeKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static String _hashKey(String input) {
    const int fnvOffset = 0xcbf29ce484222325;
    const int fnvPrime = 0x100000001b3;

    var hash = fnvOffset;
    final bytes = utf8.encode(input);
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static Future<void> syncIndexWithFiles() async {
    try {
      final index = await getIndex();
      final base = await _baseDir();
      final lyricsDir = Directory('${base.path}/$_lyricsDirName');
      if (!await lyricsDir.exists()) return;

      final files = await lyricsDir.list().toList();
      bool changed = false;

      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.ttml')) {
          final fileName = entity.path.split('/').last.split('\\').last;
          final key = fileName.replaceAll('.ttml', '');
          
          if (!index.containsKey(key)) {
            // Try to recover metadata from file content
            final content = await entity.readAsString();
            final titleMatch = RegExp(r'<title>(.*?)<\/title>').firstMatch(content);
            final artistMatch = RegExp(r'<artist>(.*?)<\/artist>').firstMatch(content);
            
            if (titleMatch != null && artistMatch != null) {
              index[key] = {
                'title': titleMatch.group(1),
                'artist': artistMatch.group(1),
                'timestamp': entity.lastModifiedSync().millisecondsSinceEpoch,
              };
              changed = true;
            }
          }
        }
      }

      if (changed) {
        final iFile = await _indexFile();
        await iFile.writeAsString(jsonEncode(index), flush: true);
      }
    } catch (_) {}
  }
}

class CachedArtworkBytes {
  final Uint8List? largeBytes;
  final Uint8List? smallBytes;

  const CachedArtworkBytes({
    required this.largeBytes,
    required this.smallBytes,
  });
}
