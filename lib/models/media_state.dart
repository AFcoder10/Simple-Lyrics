import 'dart:typed_data';

/// Represents the current state of media playback.
class MediaState {
  final String title;
  final String artist;
  final Uint8List? albumArtBytes;
  final Uint8List? thumbnailArtBytes;
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
    this.albumArtBytes,
    this.thumbnailArtBytes,
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
  }) {
    final title = map['title'] as String? ?? 'Unknown Title';
    final artist = map['artist'] as String? ?? 'Unknown Artist';
    final isSameSong = title == previousTitle && artist == previousArtist;

    // Ignore incoming art completely to enforce iTunes-only artwork.
    // The high-quality artwork will be fetched by ArtworkService.

    return MediaState(
      title: title,
      artist: artist,
      albumArtBytes: isSameSong ? previousArtwork : null,
      thumbnailArtBytes: isSameSong ? previousThumbnail : null,
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
    Uint8List? albumArtBytes,
    Uint8List? thumbnailArtBytes,
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
      albumArtBytes: albumArtBytes ?? this.albumArtBytes,
      thumbnailArtBytes: thumbnailArtBytes ?? this.thumbnailArtBytes,
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
  }) {
    return MediaState(
      title: title,
      artist: artist,
      albumArtBytes: artworkBytes,
      thumbnailArtBytes: thumbnailBytes ?? artworkBytes,
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
  String toString() => 'MediaState(title: $title, artist: $artist, '
      'position: $position, duration: $duration, isPlaying: $isPlaying, '
      'shuffleMode: $shuffleMode, repeatMode: $repeatMode)';
}
