import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';
import '../services/lyrics_service.dart';
import '../services/lyrics_models.dart';
import '../services/artwork_service.dart';
import '../services/cache_service.dart';
import '../widgets/now_playing_header.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/playback_controls.dart';
import '../widgets/playback_controls.dart';
import '../widgets/backgrounds/background_controller.dart';

/// Main screen that composes all UI widgets.
class HomeScreen extends StatefulWidget {
  final MediaSessionService service;

  const HomeScreen({super.key, required this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<LyricsViewState> _lyricsKey = GlobalKey<LyricsViewState>();
  MediaState _mediaState = MediaState.empty();
  StreamSubscription<MediaState>? _subscription;
  late final Ticker _positionTicker;
  Duration _visualPosition = Duration.zero;
  static const Duration _newSongLyricsOffset = Duration(milliseconds: 1);
  DateTime _lastPositionTick = DateTime.now();
  bool _hasVisualTrack = false;
  bool _isPreviewingPosition = false;
  bool _useNewSongLyricsOffset = true;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  // Lyrics state
  final LyricsService _lyricsService = LyricsService();
  final ArtworkService _artworkService = ArtworkService();
  
  LyricsData? _lyricsData;
  bool _lyricsLoading = false;
  String? _lyricsError;
  String _lastFetchedKey = ''; // "title|artist" to avoid duplicate fetches
  String _lastArtworkFetchKey = '';
  String? _artworkFetchInFlightKey;

  @override
  void initState() {
    super.initState();
    _positionTicker = createTicker((_) => _tickVisualPosition())..start();
    widget.service.init();
    _subscription = widget.service.mediaStateStream.listen(_onMediaStateUpdate);
    _startHideTimer();
  }

  void _tickVisualPosition() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastPositionTick);
    _lastPositionTick = now;

    if (_isPreviewingPosition || !_mediaState.isPlaying || _mediaState.isEmpty) {
      return;
    }

    final duration = _mediaState.duration;
    final nextPosition = duration > Duration.zero &&
            _visualPosition + elapsed > duration
        ? duration
        : _visualPosition + elapsed;

    if (nextPosition == _visualPosition) return;

    setState(() {
      _visualPosition = nextPosition;
    });
  }

  void _syncVisualPosition(MediaState state, {required bool songChanged}) {
    _lastPositionTick = DateTime.now();

    if (_isPreviewingPosition) return;

    if (state.isEmpty) {
      _visualPosition = Duration.zero;
      _hasVisualTrack = false;
      return;
    }

    if (songChanged && _hasVisualTrack) {
      _visualPosition = Duration.zero;
      _hasVisualTrack = true;
      return;
    }

    final realPosition = state.position;
    final deltaMs =
        (realPosition.inMilliseconds - _visualPosition.inMilliseconds).abs();
    final movedBackward = realPosition < _visualPosition &&
        _visualPosition.inMilliseconds - realPosition.inMilliseconds > 250;

    if (!_hasVisualTrack || !state.isPlaying || movedBackward || deltaMs > 120) {
      _visualPosition = realPosition;
    } else if (deltaMs > 16) {
      final correctionUs =
          ((realPosition - _visualPosition).inMicroseconds * 0.85).round();
      _visualPosition += Duration(microseconds: correctionUs);
    }

    final duration = state.duration;
    if (duration > Duration.zero && _visualPosition > duration) {
      _visualPosition = duration;
    }

    _hasVisualTrack = true;
  }

  void _previewVisualPosition(Duration position) {
    final duration = _mediaState.duration;
    final clampedPosition = duration > Duration.zero && position > duration
        ? duration
        : position;

    setState(() {
      _visualPosition = clampedPosition;
      _lastPositionTick = DateTime.now();
    });
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
            
    final shouldFetchLyrics =
        songKey != _lastFetchedKey && !displayState.isEmpty;
    final shouldFetchArtwork = !displayState.isEmpty &&
        displayState.albumArtBytes == null &&
        songKey != _lastArtworkFetchKey &&
        songKey != _artworkFetchInFlightKey;

    setState(() {
      if (songChanged) {
        _isPreviewingPosition = false;
        _useNewSongLyricsOffset = true;
      }
      if (shouldFetchLyrics) {
        _lastFetchedKey = songKey;
        _lyricsLoading = true;
        _lyricsError = null;
        _lyricsData = null;
      }
      _syncVisualPosition(displayState, songChanged: songChanged);
      _mediaState = displayState;
    });

    if (shouldFetchLyrics) {
      _fetchLyrics(displayState.title, displayState.artist, songKey);
    }
    if (shouldFetchArtwork) {
      _fetchArtwork(displayState.title, displayState.artist, songKey);
    }
  }

  Duration get _lyricsPosition {
    if (!_useNewSongLyricsOffset) return _visualPosition;

    final shiftedPosition = _visualPosition + _newSongLyricsOffset;
    final duration = _mediaState.duration;
    if (duration > Duration.zero && shiftedPosition > duration) {
      return duration;
    }
    return shiftedPosition;
  }

  void _clearNewSongLyricsOffset() {
    if (!_useNewSongLyricsOffset) return;
    setState(() {
      _useNewSongLyricsOffset = false;
    });
  }

  Future<void> _fetchLyrics(
      String title, String artist, String songKey) async {
    try {
      final data = await _lyricsService.fetchLyrics(
        songName: title,
        artistName: artist,
      );

      if (_lastFetchedKey == songKey && mounted) {
        setState(() {
          _lyricsData = data;
          _lyricsLoading = false;
          if (data.isEmpty) {
            _lyricsError = 'Lyrics not found';
          }
        });
      }
    } catch (e) {
      if (_lastFetchedKey == songKey && mounted) {
        setState(() {
          _lyricsLoading = false;
          _lyricsError = 'Could not load lyrics';
        });
      }
    }
  }

  Future<void> _fetchArtwork(
      String title, String artist, String songKey) async {
    _artworkFetchInFlightKey = songKey;

    final artwork = await _artworkService.fetchArtwork(
      songName: title,
      artistName: artist,
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
      );
      _lastArtworkFetchKey = songKey;
      _artworkFetchInFlightKey = null;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionTicker.dispose();
    _subscription?.cancel();
    _lyricsService.dispose();
    _artworkService.dispose();
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
    final visualMediaState = _mediaState.copyWith(position: _visualPosition);

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
                child: BackgroundController(
                  albumArtBytes: _mediaState.albumArtBytes,
                ),
              ),

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
                      child: LyricsView(
                        key: _lyricsKey,
                        trackKey: '${_mediaState.title}|${_mediaState.artist}',
                        lyricsData: _lyricsData,
                        position: _lyricsPosition,
                        duration: _mediaState.duration,
                        service: widget.service,
                        onLyricsInteraction: _clearNewSongLyricsOffset,
                        isLoading: _lyricsLoading,
                        errorMessage: _lyricsError,
                      ),
                    ),
                  ),
                ],
              ),

              PlaybackControls(
                mediaState: visualMediaState,
                service: widget.service,
                visible: _controlsVisible,
                onInteraction: _onInteraction,
                onPositionPreview: _previewVisualPosition,
                onPositionPreviewing: _setPositionPreviewing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
