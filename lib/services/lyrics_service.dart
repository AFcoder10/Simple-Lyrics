import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cache_service.dart';
import 'lyrics_models.dart';
import 'ttml_parser.dart';

/// Service that fetches lyrics from the bareminimum-lyrics API.
///
/// Sends a POST request with song_name and artist_name,
/// receives TTML-formatted lyrics, and parses them into
/// structured [LyricsData].
class LyricsService {
  static const _apiUrl = 'https://bareminimum-lyrics.vercel.app/api/v1/lyrics';

  final HttpClient _client = HttpClient();
  final Map<String, String> _lyricsCache = {};

  /// Fetch and parse lyrics for the given song and artist.
  ///
  /// Returns [LyricsData] with parsed lines, or an empty result
  /// if lyrics are not found or an error occurs.
  Future<LyricsData> fetchLyrics({
    required String songName,
    required String artistName,
  }) async {
    if (songName.isEmpty || songName == 'No media playing') {
      return LyricsData.empty();
    }

    final cacheKey = CacheService.makeKey(songName, artistName);
    final cachedTtml = _lyricsCache[cacheKey] ??
        await CacheService.readLyrics(cacheKey);
    if (cachedTtml != null && cachedTtml.isNotEmpty) {
      _lyricsCache[cacheKey] = cachedTtml;
      final cachedData = await _parseTtml(cachedTtml);
      if (!cachedData.isEmpty) {
        return cachedData;
      }
    }

    // Build a short, focused list of queries.
    // The API handles fuzzy matching, scoring, and multi-storefront
    // search internally — so we just send a few well-cleaned variants.
    final cleanedSong = _cleanMetadata(songName);
    final cleanedArtist = _cleanMetadata(artistName);
    final strippedSong = _stripDecorations(cleanedSong);
    final primaryArt = _primaryArtist(_stripDecorations(cleanedArtist));
    final foldedSong = _asciiFold(strippedSong);
    final foldedArtist = _asciiFold(primaryArt);

    final queries = <_LyricsQuery>[];
    final seen = <String>{};

    void addQuery(String s, String a) {
      if (s.isEmpty) return;
      final key = '${s.toLowerCase()}|${a.toLowerCase()}';
      if (seen.add(key)) queries.add(_LyricsQuery(s, a));
    }

    // 0. Exact raw metadata (highest chance of perfect match if it's correct)
    addQuery(songName, artistName);
    // 1. Cleaned metadata (preserves unicode like Señorita)
    addQuery(cleanedSong, cleanedArtist);
    // 2. Stripped decorations + primary artist only
    addQuery(strippedSong, primaryArt);
    // 3. Stylized variants (Señorita, Where Are Ü Now)
    for (final stylized in _stylizedTitleVariants(strippedSong)) {
      addQuery(stylized, cleanedArtist);
      addQuery(stylized, primaryArt);
    }
    // 4. ASCII-folded (last resort for tricky unicode)
    addQuery(foldedSong, foldedArtist);

    var attempt = 0;
    for (final query in queries) {
      _logAttempt(++attempt, query, 'focused');
      final ttml = await _fetchTtmlForQuery(query);
      final data = ttml == null ? LyricsData.empty() : await _parseTtml(ttml);
      if (!data.isEmpty) {
        _logHit(query);
        _lyricsCache[cacheKey] = ttml!;
        await CacheService.writeLyrics(cacheKey, ttml, title: songName, artist: artistName);
        return data;
      }
    }

    if (kDebugMode) {
      debugPrint(
        'LyricsService: no lyrics after $attempt attempts for "$songName" by "$artistName"',
      );
    }
    return LyricsData.empty();
  }

  Future<String?> _fetchTtmlForQuery(_LyricsQuery query) async {
    try {
      final bodyBytes = utf8.encode(jsonEncode({
        'song_name': query.songName,
        'artist_name': query.artistName,
      }));

      final request = await _client.postUrl(Uri.parse(_apiUrl));
      request.headers.set('Content-Type', 'application/json');
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return null;

      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      final firstResult = data[0] as Map<String, dynamic>;
      final attributes = firstResult['attributes'] as Map<String, dynamic>?;
      final ttml = attributes?['ttmlLocalizations'] as String?;
      if (ttml == null || ttml.isEmpty) return null;

      return ttml;
    } catch (e) {
      // ignore: avoid_print
      print('LyricsService.fetchLyrics error: $e');
      return null;
    }
  }

  Future<LyricsData> _parseTtml(String ttml) {
    return compute(TtmlParser.parse, ttml);
  }

  void clearCache() {
    _lyricsCache.clear();
  }




  String _cleanMetadata(String value) {
    return value
        .replaceAll(RegExp(r'[’‘`´]'), "'")
        .replaceAll(RegExp(r'[“”]'), '"')
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[?¿!¡*]'), '') // Strip punctuation that breaks some APIs
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripDecorations(String value) {
    return value
        .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), '') // Strip (Official Video), [Remix], etc.
        .replaceAll(RegExp(r'\s+-\s+.*$'), '') // Strip - Remastered, etc.
        .replaceAll(RegExp(r'\b(feat|ft|featuring)\.?\b.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _primaryArtist(String value) {
    return value
        .split(RegExp(r'\s*(,|&|\band\b|/|x)\s*', caseSensitive: false))
        .first
        .trim();
  }

  List<String> _stylizedTitleVariants(String value) {
    final normalized = _asciiFold(value).toLowerCase();
    final variants = <String>[];

    if (normalized == 'where are u now' || normalized == 'where are you now') {
      variants.add('Where Are Ü Now');
    }
    if (normalized == 'senorita') {
      variants.add('Señorita');
    }

    return variants;
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

  void _logAttempt(int attempt, _LyricsQuery query, String source) {
    if (!kDebugMode) return;
    debugPrint(
      'LyricsService: attempt $attempt [$source] "${query.songName}" / "${query.artistName}"',
    );
  }

  void _logHit(_LyricsQuery query) {
    if (!kDebugMode) return;
    debugPrint(
      'LyricsService: found lyrics for "${query.songName}" / "${query.artistName}"',
    );
  }

  void dispose() {
    _client.close();
  }
}

class _LyricsQuery {
  final String songName;
  final String artistName;

  const _LyricsQuery(this.songName, this.artistName);
}
