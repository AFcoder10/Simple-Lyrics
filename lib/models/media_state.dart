import 'dart:typed_data';

/// Represents the current state of media playback.
class MediaState {
  final String title;
  final String artist;
  final String? album;
  final Uint8List? albumArtBytes;
  final Uint8List? thumbnailArtBytes;
  final String? tallMasterUrl;
  final String? squareMasterUrl;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final DateTime lastUpdated;
  final int shuffleMode;
  final int repeatMode;
  final bool supportsShuffleMode;
  final bool supportsRepeatMode;

  const MediaState({
    required this.title,
    required this.artist,
    this.album,
    this.albumArtBytes,
    this.thumbnailArtBytes,
    this.tallMasterUrl,
    this.squareMasterUrl,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.lastUpdated,
    required this.shuffleMode,
    required this.repeatMode,
    required this.supportsShuffleMode,
    required this.supportsRepeatMode,
  });

  factory MediaState.empty() {
    return MediaState(
      title: 'No media playing',
      artist: '',
      album: null,
      tallMasterUrl: null,
      squareMasterUrl: null,
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      lastUpdated: DateTime.now(),
      shuffleMode: 0,
      repeatMode: 0,
      supportsShuffleMode: false,
      supportsRepeatMode: false,
    );
  }

  factory MediaState.fromMap(
    Map<dynamic, dynamic> map, {
    Uint8List? previousArtwork,
    Uint8List? previousThumbnail,
    String? previousTitle,
    String? previousArtist,
    String? previousTallMasterUrl,
    String? previousSquareMasterUrl,
  }) {
    final title = map['title'] as String? ?? 'Unknown Title';
    final artist = map['artist'] as String? ?? 'Unknown Artist';
    final album = map['album'] as String?;
    final isSameSong = title == previousTitle && artist == previousArtist;

    // Ignore incoming art completely to enforce iTunes-only artwork.
    // The high-quality artwork will be fetched by ArtworkService.

    return MediaState(
      title: title,
      artist: artist,
      album: album,
      albumArtBytes: isSameSong ? previousArtwork : null,
      thumbnailArtBytes: isSameSong ? previousThumbnail : null,
      tallMasterUrl: isSameSong ? previousTallMasterUrl : null,
      squareMasterUrl: isSameSong ? previousSquareMasterUrl : null,
      position: Duration(milliseconds: (map['position'] as int?) ?? 0),
      duration: Duration(milliseconds: (map['duration'] as int?) ?? 0),
      isPlaying: map['isPlaying'] as bool? ?? false,
      lastUpdated: DateTime.now(),
      shuffleMode: map['shuffleMode'] as int? ?? 0,
      repeatMode: map['repeatMode'] as int? ?? 0,
      supportsShuffleMode: map['supportsShuffleMode'] as bool? ?? false,
      supportsRepeatMode: map['supportsRepeatMode'] as bool? ?? false,
    );
  }

  MediaState copyWith({
    String? title,
    String? artist,
    String? album,
    Uint8List? albumArtBytes,
    Uint8List? thumbnailArtBytes,
    String? tallMasterUrl,
    String? squareMasterUrl,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    DateTime? lastUpdated,
    int? shuffleMode,
    int? repeatMode,
    bool? supportsShuffleMode,
    bool? supportsRepeatMode,
  }) {
    return MediaState(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtBytes: albumArtBytes ?? this.albumArtBytes,
      thumbnailArtBytes: thumbnailArtBytes ?? this.thumbnailArtBytes,
      tallMasterUrl: tallMasterUrl ?? this.tallMasterUrl,
      squareMasterUrl: squareMasterUrl ?? this.squareMasterUrl,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      repeatMode: repeatMode ?? this.repeatMode,
      supportsShuffleMode: supportsShuffleMode ?? this.supportsShuffleMode,
      supportsRepeatMode: supportsRepeatMode ?? this.supportsRepeatMode,
    );
  }

  MediaState copyWithArtwork(
    Uint8List? artworkBytes, {
    Uint8List? thumbnailBytes,
    String? tallMasterUrl,
    String? squareMasterUrl,
  }) {
    return MediaState(
      title: title,
      artist: artist,
      album: album,
      albumArtBytes: artworkBytes,
      thumbnailArtBytes: thumbnailBytes ?? artworkBytes,
      tallMasterUrl: tallMasterUrl ?? this.tallMasterUrl,
      squareMasterUrl: squareMasterUrl ?? this.squareMasterUrl,
      position: position,
      duration: duration,
      isPlaying: isPlaying,
      lastUpdated: lastUpdated,
      shuffleMode: shuffleMode,
      repeatMode: repeatMode,
      supportsShuffleMode: supportsShuffleMode,
      supportsRepeatMode: supportsRepeatMode,
    );
  }

  bool get isEmpty => title == 'No media playing' && artist.isEmpty;

  @override
  String toString() => 'MediaState(title: $title, artist: $artist, album: $album, '
      'position: $position, duration: $duration, isPlaying: $isPlaying, '
      'shuffleMode: $shuffleMode, repeatMode: $repeatMode)';
}
