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
      // expire after 30 days
      final modified = await file.lastModified();
      if (DateTime.now().difference(modified) > const Duration(days: 30)) {
        try { await file.delete(); } catch (_) {}
        return null;
      }
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
        await _updateIndex(_lyricsDirName, key, title, artist);
      }
    } catch (_) {
      return;
    }
  }

  static Future<Map<String, dynamic>> getIndex() async {
    try {
      final base = await _baseDir();
      final lyricsIndex = File('${base.path}/$_lyricsDirName/index.json');
      final artworkIndex = File('${base.path}/$_artworkDirName/index.json');
      final Map<String, dynamic> merged = {};
      if (await lyricsIndex.exists()) {
        final content = await lyricsIndex.readAsString();
        merged.addAll(jsonDecode(content) as Map<String, dynamic>);
      }
      if (await artworkIndex.exists()) {
        final content = await artworkIndex.readAsString();
        final Map<String, dynamic> artIndex = jsonDecode(content) as Map<String, dynamic>;
        artIndex.forEach((k, v) {
          // prefer lyrics metadata if present
          merged.putIfAbsent(k, () => v);
        });
      }
      return merged;
    } catch (_) {
      return {};
    }
  }

  static Future<int> cacheSizeBytes() async {
    try {
      final base = await _baseDir();
      var total = 0;

      Future<void> addDirectory(String dirName) async {
        final dir = Directory('${base.path}/$dirName');
        if (!await dir.exists()) return;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              total += await entity.length();
            } catch (_) {}
          }
        }
      }

      await addDirectory(_lyricsDirName);
      await addDirectory(_artworkDirName);
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<CacheBreakdown> getCacheBreakdown() async {
    try {
      final base = await _baseDir();
      int lyricsBytes = 0;
      int artworkImagesBytes = 0;
      int artworkMetaBytes = 0;

      final lyricsDir = Directory('${base.path}/$_lyricsDirName');
      if (await lyricsDir.exists()) {
        await for (final entity in lyricsDir.list(recursive: true, followLinks: false)) {
          if (entity is File) lyricsBytes += await entity.length();
        }
      }

      final artworkDir = Directory('${base.path}/$_artworkDirName');
      if (await artworkDir.exists()) {
        await for (final entity in artworkDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            if (entity.path.endsWith('_meta.json')) {
              artworkMetaBytes += await entity.length();
            } else {
              artworkImagesBytes += await entity.length();
            }
          }
        }
      }

      return CacheBreakdown(
        lyricsBytes: lyricsBytes,
        artworkImagesBytes: artworkImagesBytes,
        liveArtworkLinkBytes: artworkMetaBytes,
      );
    } catch (_) {
      return const CacheBreakdown(lyricsBytes: 0, artworkImagesBytes: 0, liveArtworkLinkBytes: 0);
    }
  }

  static Future<void> _updateIndex(String dirName, String key, String title, String artist) async {
    final base = await _baseDir();
    final indexFile = File('${base.path}/$dirName/index.json');
    final Map<String, dynamic> index = await (indexFile.exists().then((exists) async {
      if (!exists) return <String, dynamic>{};
      final c = await indexFile.readAsString();
      return jsonDecode(c) as Map<String, dynamic>;
    }));
    index[key] = {'title': title, 'artist': artist, 'timestamp': DateTime.now().millisecondsSinceEpoch};
    await indexFile.writeAsString(jsonEncode(index), flush: true);
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
      final metaFile = File('${dir.path}/${key}_meta.json');

      final hasLarge = await largeFile.exists();
      final hasSmall = await smallFile.exists();
      
      final largeBytes = await (hasLarge && await largeFile.exists() ? largeFile.readAsBytes() : null);
      final smallBytes = await (hasSmall && await smallFile.exists() ? smallFile.readAsBytes() : null);

      // expire after 30 days if files exist
      if (hasLarge) {
        final m = await largeFile.lastModified();
        if (DateTime.now().difference(m) > const Duration(days: 30)) {
          try { await largeFile.delete(); } catch (_) {}
        }
      }
      if (hasSmall) {
        final m = await smallFile.lastModified();
        if (DateTime.now().difference(m) > const Duration(days: 30)) {
          try { await smallFile.delete(); } catch (_) {}
        }
      }

      String? tallMasterUrl;
      String? squareMasterUrl;
      String? staticArtworkUrl;
      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          final metaData = jsonDecode(content) as Map<String, dynamic>;
          tallMasterUrl = metaData['tall_master_url'] as String?;
          squareMasterUrl = metaData['square_master_url'] as String?;
          staticArtworkUrl = metaData['static_artwork_url'] as String?;
        } catch (_) {}
      }

      // If we have at least the meta file or image files, return the cached artwork container.
      if (!hasLarge && !hasSmall && tallMasterUrl == null && squareMasterUrl == null && staticArtworkUrl == null) {
        return null;
      }

      return CachedArtworkBytes(
        largeBytes: largeBytes ?? smallBytes,
        smallBytes: smallBytes ?? largeBytes,
        tallMasterUrl: tallMasterUrl,
        squareMasterUrl: squareMasterUrl,
        staticArtworkUrl: staticArtworkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeArtwork(
    String key, {
    Uint8List? largeBytes,
    Uint8List? smallBytes,
    String? tallMasterUrl,
    String? squareMasterUrl,
    String? staticArtworkUrl,
    String? title,
    String? artist,
  }) async {
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
      
      final metaFile = File('${dir.path}/${key}_meta.json');
      Map<String, dynamic> metaData = {};
      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          metaData = jsonDecode(content) as Map<String, dynamic>;
        } catch (_) {}
      }
      
      if (tallMasterUrl != null) metaData['tall_master_url'] = tallMasterUrl;
      if (squareMasterUrl != null) metaData['square_master_url'] = squareMasterUrl;
      if (staticArtworkUrl != null) metaData['static_artwork_url'] = staticArtworkUrl;
      
      if (metaData.isNotEmpty) {
        await metaFile.writeAsString(jsonEncode(metaData), flush: true);
      }
      if (title != null && artist != null) {
        await _updateIndex(_artworkDirName, key, title, artist);
      }
    } catch (_) {
      return;
    }
  }

  static Future<void> writeArtworkLinks(
    String key, {
    String? staticArtworkUrl,
    String? tallMasterUrl,
    String? squareMasterUrl,
  }) async {
    try {
      final dir = await _ensureDir(_artworkDirName);
      final metaFile = File('${dir.path}/${key}_meta.json');
      Map<String, dynamic> metaData = {};
      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          metaData = jsonDecode(content) as Map<String, dynamic>;
        } catch (_) {}
      }
      
      if (staticArtworkUrl != null) metaData['static_artwork_url'] = staticArtworkUrl;
      if (tallMasterUrl != null) metaData['tall_master_url'] = tallMasterUrl;
      if (squareMasterUrl != null) metaData['square_master_url'] = squareMasterUrl;
      
      await metaFile.writeAsString(jsonEncode(metaData), flush: true);
    } catch (_) {}
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
      final metaFile = File('${dir.path}/${key}_meta.json');
      if (await largeFile.exists()) await largeFile.delete();
      if (await smallFile.exists()) await smallFile.delete();
      if (await metaFile.exists()) await metaFile.delete();

      // Update index
      final base = await _baseDir();
      final lyricsIndex = File('${base.path}/$_lyricsDirName/index.json');
      if (await lyricsIndex.exists()) {
        final content = await lyricsIndex.readAsString();
        final Map<String, dynamic> idx = jsonDecode(content) as Map<String, dynamic>;
        if (idx.containsKey(key)) {
          idx.remove(key);
          await lyricsIndex.writeAsString(jsonEncode(idx), flush: true);
        }
      }
      final artworkIndex = File('${base.path}/$_artworkDirName/index.json');
      if (await artworkIndex.exists()) {
        final content = await artworkIndex.readAsString();
        final Map<String, dynamic> idx = jsonDecode(content) as Map<String, dynamic>;
        if (idx.containsKey(key)) {
          idx.remove(key);
          await artworkIndex.writeAsString(jsonEncode(idx), flush: true);
        }
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
    // Use application support directory so cache persists longer
    return getApplicationSupportDirectory();
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
      final base = await _baseDir();
      // Sync lyrics index
      final lyricsDir = Directory('${base.path}/$_lyricsDirName');
      final lyricsIndexFile = File('${lyricsDir.path}/index.json');
      if (await lyricsDir.exists()) {
        final files = await lyricsDir.list().toList();
        final Map<String, dynamic> idx = (await (lyricsIndexFile.exists().then((exists) async {
          if (!exists) return <String, dynamic>{};
          final c = await lyricsIndexFile.readAsString();
          return jsonDecode(c) as Map<String, dynamic>;
        })));
        bool changed = false;
        for (final entity in files) {
          if (entity is File && entity.path.endsWith('.ttml')) {
            final fileName = entity.path.split('/').last.split('\\').last;
            final key = fileName.replaceAll('.ttml', '');
            if (!idx.containsKey(key)) {
              final content = await entity.readAsString();
              final titleMatch = RegExp(r'<title>(.*?)<\/title>').firstMatch(content);
              final artistMatch = RegExp(r'<artist>(.*?)<\/artist>').firstMatch(content);
              if (titleMatch != null && artistMatch != null) {
                idx[key] = {
                  'title': titleMatch.group(1),
                  'artist': artistMatch.group(1),
                  'timestamp': entity.lastModifiedSync().millisecondsSinceEpoch,
                };
                changed = true;
              }
            }
          }
        }
        if (changed) await lyricsIndexFile.writeAsString(jsonEncode(idx), flush: true);
      }

      // Sync artwork index: ensure files referenced exist
      final artworkDir = Directory('${base.path}/$_artworkDirName');
      final artworkIndexFile = File('${artworkDir.path}/index.json');
      if (await artworkDir.exists()) {
        final Map<String, dynamic> idx = (await (artworkIndexFile.exists().then((exists) async {
          if (!exists) return <String, dynamic>{};
          final c = await artworkIndexFile.readAsString();
          return jsonDecode(c) as Map<String, dynamic>;
        })));
        bool changed = false;
        final files = await artworkDir.list().toList();
        final Set<String> presentKeys = {};
        for (final entity in files) {
          if (entity is File) {
            final name = entity.path.split('/').last.split('\\').last;
            final m = RegExp(r'^([0-9a-f]+)_[ls]\.jpg$').firstMatch(name);
            if (m != null) presentKeys.add(m.group(1)!);
          }
        }
        final remove = <String>[];
        idx.forEach((k, v) {
          if (!presentKeys.contains(k)) remove.add(k);
        });
        for (final k in remove) { idx.remove(k); changed = true; }
        if (changed) await artworkIndexFile.writeAsString(jsonEncode(idx), flush: true);
      }
    } catch (_) {}
  }
}

class CachedArtworkBytes {
  final Uint8List? largeBytes;
  final Uint8List? smallBytes;
  final String? tallMasterUrl;
  final String? squareMasterUrl;
  final String? staticArtworkUrl;

  const CachedArtworkBytes({
    required this.largeBytes,
    required this.smallBytes,
    this.tallMasterUrl,
    this.squareMasterUrl,
    this.staticArtworkUrl,
  });
}

class CacheBreakdown {
  final int lyricsBytes;
  final int artworkImagesBytes;
  final int liveArtworkLinkBytes;

  int get totalBytes => lyricsBytes + artworkImagesBytes + liveArtworkLinkBytes;

  const CacheBreakdown({
    required this.lyricsBytes,
    required this.artworkImagesBytes,
    required this.liveArtworkLinkBytes,
  });
}
