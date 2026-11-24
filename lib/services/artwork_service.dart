import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cache_service.dart';
import 'settings_service.dart';

/// Service that fetches static and animated covers using decoupled API endpoints.
class ArtworkService {
  static const int _largeArtworkSize = 600;
  static const int _smallArtworkSize = 600;
  final HttpClient _client = HttpClient();
  final Map<String, ArtworkResult?> _cache = {};

  /// Fetches artwork and resolves motion playlists.
  ///
  /// If static artwork is cached but animated URLs are not, displays static image
  /// instantly and triggers a background fetch to resolve the motion URLs.
  Future<ArtworkResult?> fetchArtwork({
    required String songName,
    required String artistName,
    String? albumName,
    int? durationMs,
    void Function(String tallUrl, String squareUrl)? onAnimatedArtworkResolved,
  }) async {
    if (songName.isEmpty || songName == 'No media playing') return null;

    final cacheKey = '${_normalize(songName)}|${_normalize(artistName)}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    final diskKey = CacheService.makeKey(songName, artistName);
    final cachedDisk = await CacheService.readArtwork(diskKey);

    // 1. Static bytes are already cached: return static cover instantly!
    if (cachedDisk != null && (cachedDisk.largeBytes != null || cachedDisk.smallBytes != null)) {
      final cachedResult = ArtworkResult(
        largeBytes: cachedDisk.largeBytes,
        smallBytes: cachedDisk.smallBytes,
        tallMasterUrl: cachedDisk.tallMasterUrl,
        squareMasterUrl: cachedDisk.squareMasterUrl,
      );
      _cache[cacheKey] = cachedResult;

      // Check if animated artwork is enabled and HLS stream URLs are not yet cached
      final animatedEnabled = SettingsService().animatedArtworkEnabled.value;
      final needsAnimatedResolution = cachedDisk.tallMasterUrl == null || 
                                     cachedDisk.tallMasterUrl!.isEmpty || 
                                     cachedDisk.squareMasterUrl == null || 
                                     cachedDisk.squareMasterUrl!.isEmpty;

      if (animatedEnabled && needsAnimatedResolution) {
        _resolveAnimatedArtworkInBackground(
          songName: songName,
          artistName: artistName,
          albumName: albumName,
          diskKey: diskKey,
          onResolved: onAnimatedArtworkResolved,
        );
      }

      return cachedResult;
    }

    // 2. Static bytes are NOT cached: fetch from network
    String? staticArtworkUrl;
    String? tallMasterUrl;
    String? squareMasterUrl;

    if (cachedDisk != null) {
      staticArtworkUrl = cachedDisk.staticArtworkUrl;
      tallMasterUrl = cachedDisk.tallMasterUrl;
      squareMasterUrl = cachedDisk.squareMasterUrl;
    }

    if (staticArtworkUrl == null || staticArtworkUrl.isEmpty) {
      try {
        // ALWAYS fetch static artwork first and do NOT wait for animated artwork!
        final staticJson =
            await _fetchStaticArtworkPayload(songName, artistName, albumName);
        if (staticJson != null) {
          staticArtworkUrl = staticJson['static_artwork_url'] as String? ?? 
                             staticJson['artwork_url'] as String?;
        }

        if (staticArtworkUrl == null || staticArtworkUrl.isEmpty) return null;
      } catch (_) {
        return null;
      }
    }

    try {
      final largeArtwork = await _getArtworkAtSize(
        staticArtworkUrl,
        _largeArtworkSize,
      );
      final smallArtwork = await _getArtworkAtSize(
        staticArtworkUrl,
        _smallArtworkSize,
      );

      if (largeArtwork == null && smallArtwork == null) {
        return null;
      }

      final result = ArtworkResult(
        largeBytes: largeArtwork ?? smallArtwork,
        smallBytes: smallArtwork ?? largeArtwork,
        tallMasterUrl: tallMasterUrl,
        squareMasterUrl: squareMasterUrl,
      );
      _cache[cacheKey] = result;
      await CacheService.writeArtwork(
        diskKey,
        largeBytes: result.largeBytes,
        smallBytes: result.smallBytes,
        tallMasterUrl: result.tallMasterUrl,
        squareMasterUrl: result.squareMasterUrl,
        staticArtworkUrl: staticArtworkUrl,
        title: songName,
        artist: artistName,
      );

      // Trigger animated artwork background fetch if not already resolved and animated is enabled
      final animatedEnabled = SettingsService().animatedArtworkEnabled.value;
      final needsAnimatedResolution = result.tallMasterUrl == null || 
                                     result.tallMasterUrl!.isEmpty || 
                                     result.squareMasterUrl == null || 
                                     result.squareMasterUrl!.isEmpty;
      if (animatedEnabled && needsAnimatedResolution) {
        _resolveAnimatedArtworkInBackground(
          songName: songName,
          artistName: artistName,
          albumName: albumName,
          diskKey: diskKey,
          onResolved: onAnimatedArtworkResolved,
        );
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  /// Internal helper to POST to the static /api/v1/artwork endpoint
  Future<Map<String, dynamic>?> _fetchStaticArtworkPayload(
      String songName, String artistName, String? albumName) async {
    try {
      final bodyBytes = utf8.encode(jsonEncode({
        'song_name': songName,
        'artist_name': artistName,
        // Album is a strong disambiguator when the title and artist are not
        // unique on their own. Omitted rather than faked when unknown.
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
        'storefront': 'us',
        'width': 600,
        'height': 600,
      }));

      final request = await _client.postUrl(Uri.parse('https://bareminimum-lyrics.vercel.app/api/v1/artwork'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Internal helper to POST to the animated /api/v1/animated-artwork endpoint
  Future<Map<String, dynamic>?> _fetchAnimatedArtworkPayload(
      String songName, String artistName, String? albumName) async {
    try {
      final bodyBytes = utf8.encode(jsonEncode({
        'song_name': songName,
        'artist_name': artistName,
        // Never substitute the song title for a missing album — that hands the
        // API an actively wrong album and it will confidently pick the wrong
        // cover. Omit the field instead so it can match on what it does have.
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
        'storefront': 'us',
        'artwork_type': 'tall',
        'quality': 720,
        'width': 720,
        'height': 960,
      }));

      final request = await _client.postUrl(Uri.parse('https://bareminimum-lyrics.vercel.app/api/v1/animated-artwork'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Resolves animated artwork HLS playlists in the background and saves links to disk cache.
  void _resolveAnimatedArtworkInBackground({
    required String songName,
    required String artistName,
    String? albumName,
    required String diskKey,
    void Function(String tallUrl, String squareUrl)? onResolved,
  }) async {
    try {
      final animatedJson = await _fetchAnimatedArtworkPayload(songName, artistName, albumName);
      if (animatedJson == null) return;

      final animArtworks = animatedJson['animated_artworks'] as Map<String, dynamic>?;
      
      // Look for the custom_size_url first (since we requested exact dimensions), fallback to masters
      final tallUrl = (animatedJson['custom_size_url'] as String?) ??
                      (animatedJson['tall_master_url'] as String?) ??
                      (animArtworks?['tall']?['master_url'] as String?) ?? '';
                      
      // We also need the custom square one for the floating card. The API returns it if we ask.
      // But we sent 'artwork_type': 'tall' in the body, so the custom_size_url is the tall one.
      // We will just use the master URLs. The player handles ABR.
      final squareUrl = (animatedJson['square_master_url'] as String?) ??
                        (animArtworks?['square']?['master_url'] as String?) ?? '';

      if (tallUrl.isNotEmpty || squareUrl.isNotEmpty) {
        await CacheService.writeArtworkLinks(
          diskKey,
          tallMasterUrl: tallUrl,
          squareMasterUrl: squareUrl,
        );

        // Also dynamically update the in-memory cache to preserve these URLs for instant access
        final cacheKey = '${_normalize(songName)}|${_normalize(artistName)}';
        final current = _cache[cacheKey];
        if (current != null) {
          _cache[cacheKey] = ArtworkResult(
            largeBytes: current.largeBytes,
            smallBytes: current.smallBytes,
            tallMasterUrl: tallUrl,
            squareMasterUrl: squareUrl,
          );
        }

        if (onResolved != null) {
          onResolved(tallUrl, squareUrl);
        }
      }
    } catch (_) {
      // Fail silently in background
    }
  }

  Future<Uint8List?> _getArtworkAtSize(String artworkUrl, int size) {
    var sizedUrl = artworkUrl
        .replaceAll('{w}', '$size')
        .replaceAll('{h}', '$size');
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
  final String? tallMasterUrl;
  final String? squareMasterUrl;

  const ArtworkResult({
    required this.largeBytes,
    required this.smallBytes,
    this.tallMasterUrl,
    this.squareMasterUrl,
  });
}
