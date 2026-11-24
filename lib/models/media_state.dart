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
  /// True only while audio is actually moving. Buffering, seeking-in-place
  /// and paused all report false so the lyric clock can freeze without
  /// waiting for a stale position sample.
  final bool isAdvancing;
  /// Source playback speed. 1.0 is normal. Applied by [PlaybackClock].
  final double playbackRate;
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
    this.isAdvancing = false,
    this.playbackRate = 1.0,
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
      isAdvancing: false,
      playbackRate: 1.0,
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

    final isPlaying = map['isPlaying'] as bool? ?? false;
    final playbackRate = (map['playbackRate'] as num?)?.toDouble() ?? 1.0;
    final isAdvancing = map['isAdvancing'] as bool? ?? isPlaying;

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
      isPlaying: isPlaying,
      isAdvancing: isAdvancing,
      playbackRate: playbackRate,
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
    bool? isAdvancing,
    double? playbackRate,
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
      isAdvancing: isAdvancing ?? this.isAdvancing,
      playbackRate: playbackRate ?? this.playbackRate,
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
      isAdvancing: isAdvancing,
      playbackRate: playbackRate,
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
