import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cache_service.dart';
/// Fetches fallback artwork from the public iTunes Search API.
class ArtworkService {
  static const int _largeArtworkSize = 600;
  static const int _smallArtworkSize = 120;
  final HttpClient _client = HttpClient();
  final Map<String, ArtworkResult?> _cache = {};

  Future<ArtworkResult?> fetchArtwork({
    required String songName,
    required String artistName,
    int? durationMs,
  }) async {
    if (songName.isEmpty || songName == 'No media playing') return null;

    final cacheKey = '${_normalize(songName)}|${_normalize(artistName)}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    final diskKey = CacheService.makeKey(songName, artistName);
    final cachedDisk = await CacheService.readArtwork(diskKey);
    if (cachedDisk != null) {
      final cachedResult = ArtworkResult(
        largeBytes: cachedDisk.largeBytes,
        smallBytes: cachedDisk.smallBytes,
      );
      _cache[cacheKey] = cachedResult;
      return cachedResult;
    }

    try {
      // We send the EXACT raw string received from the music player.
      // The backend API handles the search algorithm and fuzziness internally.
      // Pre-mangling the string here often breaks perfect matches.
      final bodyBytes = utf8.encode(jsonEncode({
        'song_name': songName,
        'artist_name': artistName,
      }));

      final request = await _client.postUrl(Uri.parse('https://bareminimum-lyrics.vercel.app/api/v1/artwork'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      final artworkUrl = json['artwork_url'] as String?;
      if (artworkUrl == null || artworkUrl.isEmpty) return null;

      final largeArtwork = await _getArtworkAtSize(
        artworkUrl,
        _largeArtworkSize,
      );
      final smallArtwork = await _getArtworkAtSize(
        artworkUrl,
        _smallArtworkSize,
      );

      if (largeArtwork == null && smallArtwork == null) {
        return null;
      }

      final result = ArtworkResult(
        largeBytes: largeArtwork ?? smallArtwork,
        smallBytes: smallArtwork ?? largeArtwork,
      );
      _cache[cacheKey] = result;
      await CacheService.writeArtwork(
        diskKey,
        largeBytes: result.largeBytes,
        smallBytes: result.smallBytes,
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _getArtworkAtSize(String artworkUrl, int size) {
    // The API returns URLs with {w}x{h}bb.jpg template placeholders.
    // Replace both the template format AND any existing digit-based sizes.
    var sizedUrl = artworkUrl
        .replaceAll('{w}', '$size')
        .replaceAll('{h}', '$size');
    // Fallback: also handle pre-sized URLs like 100x100bb.jpg
    sizedUrl = sizedUrl.replaceFirst(
      RegExp(r'\d+x\d+bb\.jpg$'),
      '${size}x${size}bb.jpg',
    );
    return _get(Uri.parse(sizedUrl));
  }



  String _normalize(String value) {
    return _asciiFold(value)
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String _asciiFold(String value) {
    const replacements = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
      'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A', 'Ā': 'A',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
      'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E', 'Ē': 'E',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
      'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I', 'Ī': 'I',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ō': 'o',
      'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O', 'Ō': 'O',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
      'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ū': 'U',
      'ñ': 'n', 'Ñ': 'N', 'ç': 'c', 'Ç': 'C', 'ß': 'ss',
    };

    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString();
  }



  Future<Uint8List?> _get(Uri uri) async {
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) return null;

    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  void dispose() {
    _client.close(force: true);
  }

  void clearCache() {
    _cache.clear();
  }
}

class ArtworkResult {
  final Uint8List? largeBytes;
  final Uint8List? smallBytes;

  const ArtworkResult({
    required this.largeBytes,
    required this.smallBytes,
  });
}
