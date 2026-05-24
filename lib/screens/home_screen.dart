import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';
import '../services/lyrics_service.dart';
import '../services/lyrics_models.dart';
import '../services/artwork_service.dart';
import '../widgets/now_playing_header.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/playback_controls.dart';
import '../services/settings_service.dart';
import '../widgets/backgrounds/background_controller.dart';

const bool _lyricsHeaderFadeEnabled = true;

/// Main screen that composes all UI widgets.
class HomeScreen extends StatefulWidget {
  final MediaSessionService service;

  const HomeScreen({super.key, required this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
  with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey<LyricsViewState> _lyricsKey = GlobalKey<LyricsViewState>();
  MediaState _mediaState = MediaState.empty();
  StreamSubscription<MediaState>? _subscription;
  late final Ticker _positionTicker;
  final ValueNotifier<Duration> _visualPositionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _lyricsPositionNotifier = ValueNotifier<Duration>(Duration.zero);
  Duration get _visualPosition => _visualPositionNotifier.value;
  DateTime _lastPositionTick = DateTime.now();
  bool _hasVisualTrack = false;
  bool _isPreviewingPosition = false;
  bool _useLyricsOffset = true;
  bool _controlsVisible = true;
  bool _trackTransitioning = false;
  Timer? _hideTimer;

  // Lyrics state
  final LyricsService _lyricsService = LyricsService();
  final ArtworkService _artworkService = ArtworkService();
  
  LyricsData? _lyricsData;
  bool _lyricsLoading = false;
  String? _lyricsError;
  String _lastFetchedKey = ''; // "title|artist" to avoid duplicate fetches
  String _lastLyricsAttemptKey = '';
  DateTime _lastLyricsAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lyricsFetchInFlightKey;
  String _lastArtworkFetchKey = '';
  String? _artworkFetchInFlightKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _positionTicker = createTicker((_) => _tickVisualPosition())..start();
    widget.service.init();
    _subscription = widget.service.mediaStateStream.listen(_onMediaStateUpdate);
    _startHideTimer();

  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    widget.service.refreshState();

    if (_mediaState.isEmpty) return;

    final songKey = '${_mediaState.title}|${_mediaState.artist}';

    if (_mediaState.albumArtBytes == null && _artworkFetchInFlightKey == null) {
      _fetchArtwork(_mediaState.title, _mediaState.artist, _mediaState.album, songKey);
    }

    final lyricsMissing = _lyricsData == null || _lyricsData!.isEmpty;
    if (!_lyricsLoading && lyricsMissing && _lyricsFetchInFlightKey != songKey) {
      setState(() {
        _lyricsLoading = true;
        _lyricsError = null;
        _lyricsData = null;
        _lyricsFetchInFlightKey = songKey;
        _lastLyricsAttemptKey = songKey;
        _lastLyricsAttemptAt = DateTime.now();
      });
      _fetchLyrics(_mediaState.title, _mediaState.artist, songKey);
    }
  }


  void _tickVisualPosition() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastPositionTick);
    _lastPositionTick = now;

    if (_isPreviewingPosition || !_mediaState.isPlaying || _mediaState.isEmpty || _trackTransitioning) {
      return;
    }

    final duration = _mediaState.duration;
    final nextPosition = duration > Duration.zero &&
            _visualPositionNotifier.value + elapsed > duration
        ? duration
        : _visualPositionNotifier.value + elapsed;

    if (nextPosition == _visualPositionNotifier.value) return;

    _visualPositionNotifier.value = nextPosition;
    _lyricsPositionNotifier.value = _lyricsPosition;
  }

  void _syncVisualPosition(MediaState state, {required bool songChanged}) {
    _lastPositionTick = DateTime.now();

    if (_isPreviewingPosition) return;

    if (state.isEmpty) {
      _visualPositionNotifier.value = Duration.zero;
      _lyricsPositionNotifier.value = Duration.zero;
      _hasVisualTrack = false;
      return;
    }

    if (songChanged) {
      _visualPositionNotifier.value = Duration.zero;
      _lyricsPositionNotifier.value = Duration.zero;
      _trackTransitioning = true;
      _hasVisualTrack = true;
      return;
    }

    if (_trackTransitioning) {
      _trackTransitioning = false;
    }

    final realPosition = state.position;
    final deltaMs =
        (realPosition.inMilliseconds - _visualPositionNotifier.value.inMilliseconds).abs();
    final movedBackward = realPosition < _visualPositionNotifier.value &&
        _visualPositionNotifier.value.inMilliseconds - realPosition.inMilliseconds > 250;

    Duration nextPosition = _visualPositionNotifier.value;
    if (!_hasVisualTrack || !state.isPlaying || movedBackward || deltaMs > 120) {
      nextPosition = realPosition;
    } else if (deltaMs > 16) {
      final correctionUs =
          ((realPosition - _visualPositionNotifier.value).inMicroseconds * 0.85).round();
      nextPosition += Duration(microseconds: correctionUs);
    }

    final duration = state.duration;
    if (duration > Duration.zero && nextPosition > duration) {
      nextPosition = duration;
    }

    _visualPositionNotifier.value = nextPosition;
    _lyricsPositionNotifier.value = _lyricsPosition;
    _hasVisualTrack = true;
  }

  void _previewVisualPosition(Duration position) {
    final duration = _mediaState.duration;
    final clampedPosition = duration > Duration.zero && position > duration
        ? duration
        : position;

    _visualPositionNotifier.value = clampedPosition;
    _lyricsPositionNotifier.value = _lyricsPosition;
    _lastPositionTick = DateTime.now();
  }

  void _setPositionPreviewing(bool isPreviewing) {
    _isPreviewingPosition = isPreviewing;
    _lastPositionTick = DateTime.now();
  }

  void _onMediaStateUpdate(MediaState state) {
    if (!mounted) return;

    final songKey = '${state.title}|${state.artist}';
    final previousSongKey = '${_mediaState.title}|${_mediaState.artist}';
    final songChanged = songKey != previousSongKey;
    
    final displayState =
        !songChanged && state.albumArtBytes == null
            ? state.copyWithArtwork(
                _mediaState.albumArtBytes,
                thumbnailBytes: _mediaState.thumbnailArtBytes,
              )
            : state;

    final now = DateTime.now();
    final recentlyAttempted = songKey == _lastLyricsAttemptKey &&
      now.difference(_lastLyricsAttemptAt) < const Duration(seconds: 8);
    final shouldFetchLyrics =
      songKey != _lastFetchedKey &&
      !displayState.isEmpty &&
      !recentlyAttempted &&
      _lyricsFetchInFlightKey != songKey;
    final shouldFetchArtwork = !displayState.isEmpty &&
        displayState.albumArtBytes == null &&
        songKey != _lastArtworkFetchKey &&
        songKey != _artworkFetchInFlightKey;

    setState(() {
      if (songChanged) {
        _isPreviewingPosition = false;
        _useLyricsOffset = true;
      }
      if (shouldFetchLyrics) {
        _lyricsLoading = true;
        _lyricsError = null;
        _lyricsData = null;
        _lyricsFetchInFlightKey = songKey;
        _lastLyricsAttemptKey = songKey;
        _lastLyricsAttemptAt = now;
      }
      _syncVisualPosition(displayState, songChanged: songChanged);
      _mediaState = displayState;
    });

    if (shouldFetchLyrics) {
      _fetchLyrics(displayState.title, displayState.artist, songKey);
    }
    if (shouldFetchArtwork) {
      _fetchArtwork(displayState.title, displayState.artist, displayState.album, songKey);
    }
  }

  Duration get _lyricsPosition {
    if (!_useLyricsOffset) return _visualPosition;
    final offsetMs = SettingsService().lyricsOffsetMs.value;
    final offsetPos = _visualPosition + Duration(milliseconds: offsetMs);
    return offsetPos < Duration.zero ? Duration.zero : offsetPos;
  }

  void _clearLyricsOffset() {
    if (!_useLyricsOffset) return;
    setState(() => _useLyricsOffset = false);
  }


  Future<void> _fetchLyrics(
      String title, String artist, String songKey) async {
    try {
      final data = await _lyricsService.fetchLyrics(
        songName: title,
        artistName: artist,
      );

      final isCurrentSong = '${_mediaState.title}|${_mediaState.artist}' == songKey;
      if (mounted && (_lyricsFetchInFlightKey == songKey || isCurrentSong)) {
        setState(() {
          _lyricsData = data;
          _lyricsLoading = false;
          if (data.isEmpty) {
            _lyricsError = 'Lyrics not found';
          }
        });
      }
      if (mounted && _lyricsFetchInFlightKey == songKey) {
        _lyricsFetchInFlightKey = null;
      }
      if (mounted && !data.isEmpty) {
        _lastFetchedKey = songKey;
      }
    } catch (e) {
      final isCurrentSong = '${_mediaState.title}|${_mediaState.artist}' == songKey;
      if (mounted && (_lyricsFetchInFlightKey == songKey || isCurrentSong)) {
        setState(() {
          _lyricsLoading = false;
          _lyricsError = 'Could not load lyrics';
        });
      }
      if (mounted && _lyricsFetchInFlightKey == songKey) {
        _lyricsFetchInFlightKey = null;
      }
    }
  }

  Future<void> _fetchArtwork(
      String title, String artist, String? album, String songKey) async {
    _artworkFetchInFlightKey = songKey;

    final artwork = await _artworkService.fetchArtwork(
      songName: title,
      artistName: artist,
      albumName: album,
      onAnimatedArtworkResolved: (tallUrl, squareUrl) {
        final currentSongKey = '${_mediaState.title}|${_mediaState.artist}';
        if (mounted && currentSongKey == songKey) {
          setState(() {
            _mediaState = _mediaState.copyWithArtwork(
              _mediaState.albumArtBytes,
              thumbnailBytes: _mediaState.thumbnailArtBytes,
              tallMasterUrl: tallUrl,
              squareMasterUrl: squareUrl,
            );
          });
          widget.service.updateArtworkForSong(
            title: title,
            artist: artist,
            artworkBytes: _mediaState.albumArtBytes,
            thumbnailBytes: _mediaState.thumbnailArtBytes,
            tallMasterUrl: tallUrl,
            squareMasterUrl: squareUrl,
          );
        }
      },
    );

    if (!mounted || _artworkFetchInFlightKey != songKey) {
      if (_artworkFetchInFlightKey == songKey) {
        _artworkFetchInFlightKey = null;
      }
      return;
    }

    if (artwork == null) {
      _artworkFetchInFlightKey = null;
      return;
    }

    final currentSongKey = '${_mediaState.title}|${_mediaState.artist}';
    if (currentSongKey != songKey || _mediaState.albumArtBytes != null) {
      _artworkFetchInFlightKey = null;
      return;
    }

    setState(() {
      _mediaState = _mediaState.copyWithArtwork(
        artwork.largeBytes,
        thumbnailBytes: artwork.smallBytes,
        tallMasterUrl: artwork.tallMasterUrl,
        squareMasterUrl: artwork.squareMasterUrl,
      );
      _lastArtworkFetchKey = songKey;
      _artworkFetchInFlightKey = null;
    });

    widget.service.updateArtworkForSong(
      title: _mediaState.title,
      artist: _mediaState.artist,
      artworkBytes: _mediaState.albumArtBytes,
      thumbnailBytes: _mediaState.thumbnailArtBytes,
      tallMasterUrl: artwork.tallMasterUrl,
      squareMasterUrl: artwork.squareMasterUrl,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _positionTicker.dispose();
    _subscription?.cancel();
    _lyricsService.dispose();
    _artworkService.dispose();
    _visualPositionNotifier.dispose();
    _lyricsPositionNotifier.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _onInteraction() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isEmptyState = _mediaState.isEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: GestureDetector(
          onTap: _onInteraction,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: SettingsService().performanceModeEnabled,
                  builder: (context, performanceMode, _) {
                    return BackgroundController(
                      albumArtBytes: _mediaState.albumArtBytes,
                      forceStatic: performanceMode,
                    );
                  },
                ),
              ),
              // 20% black tint specifically for the home screen (covers lyrics and metadata)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: Colors.black.withValues(alpha: 0.18)),
                ),
              ),
              if (isEmptyState)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.music_note_rounded,
                            size: 72,
                            color: Colors.white24,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Waiting for music…',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Play a song or grant notification access.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Stack(
                children: [
                  Column(
                    children: [
                      NowPlayingHeader(
                        mediaState: _mediaState,
                        service: widget.service,
                        onSettingsClosed: () {
                          _lyricsKey.currentState?.resetAutoScroll();
                        },
                      ),
                      Expanded(
                        child: RepaintBoundary(
                          child: isEmptyState
                              ? const SizedBox.shrink()
                              : ValueListenableBuilder<bool>(
                                  valueListenable: SettingsService().performanceModeEnabled,
                                  builder: (context, performanceMode, _) {
                                    return _LyricsHeaderFade(
                                      enabled: _lyricsHeaderFadeEnabled && !performanceMode,
                                      child: LyricsView(
                                        key: _lyricsKey,
                                        trackKey: '${_mediaState.title}|${_mediaState.artist}',
                                        lyricsData: _lyricsData,
                                        positionNotifier: _lyricsPositionNotifier,
                                        duration: _mediaState.duration,
                                        service: widget.service,
                                        onLyricsInteraction: _clearLyricsOffset,
                                        isLoading: _lyricsLoading,
                                        errorMessage: _lyricsError,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                  PlaybackControls(
                    mediaState: _mediaState,
                    positionNotifier: _visualPositionNotifier,
                    service: widget.service,
                    visible: _controlsVisible,
                    onInteraction: _onInteraction,
                    onPositionPreview: _previewVisualPosition,
                    onPositionPreviewing: _setPositionPreviewing,
                  ),
                  if (!_controlsVisible)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 160,
                      child: GestureDetector(
                        onTap: _onInteraction,
                        behavior: HitTestBehavior.translucent,
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsHeaderFade extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _LyricsHeaderFade({
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
          ],
          stops: [0.0, 0.10, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
