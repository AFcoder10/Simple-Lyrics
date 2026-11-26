import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../core/platform_capabilities.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';
import '../services/lyrics_service.dart';
import '../services/lyrics_models.dart';
import '../services/artwork_service.dart';
import '../services/playback_clock.dart';
import '../services/update_service.dart';
import '../widgets/now_playing_header.dart';
import '../widgets/lyrics_fade_mask.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/playback_controls.dart';
import '../services/settings_service.dart';
import '../services/window_service.dart';
import '../widgets/backgrounds/background_controller.dart';
import '../widgets/compact_player.dart';
import '../widgets/now_playing_split_view.dart';
import 'windows_settings.dart';

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

  /// Single source of truth for playback position. See [PlaybackClock].
  final PlaybackClock _clock = PlaybackClock(nativeLag: defaultNativeLag);
  VoidCallback? _seekRequestedListener;
  VoidCallback? _advancingRequestedListener;

  bool _useLyricsOffset = true;
  bool _controlsVisible = true;
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

  /// How long a `title|artist` pair must hold still before it is treated as
  /// the real identity of the current track.
  ///
  /// GSMTC apps report title, artist and album in separate stages, and
  /// sometimes briefly publish an empty field, so committing on the first
  /// differing sample means asking the lyrics/artwork APIs about half-old
  /// metadata — and getting a confidently wrong answer back.
  static const _metadataSettle = Duration(milliseconds: 600);

  String _observedSongKey = '';
  String _lastStableSongKey = '';
  DateTime _observedSince = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _metadataSettleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _positionTicker = createTicker((_) => _tickVisualPosition())..start();
    widget.service.init();
    _subscription = widget.service.mediaStateStream.listen(_onMediaStateUpdate);

    // Every seek path (scrub, keyboard shortcuts, transport buttons) funnels
    // through MediaSessionService.seekTo, so listening here is enough for the
    // clock to protect the target on all of them.
    _seekRequestedListener = () {
      final target = widget.service.seekRequested.value;
      if (target != null && mounted) {
        _clock.beginSeek(target);
        _visualPositionNotifier.value = _clock.position;
        _lyricsPositionNotifier.value = _lyricsPosition;
      }
    };
    widget.service.seekRequested.addListener(_seekRequestedListener!);

    _advancingRequestedListener = () {
      final advancing = widget.service.advancingRequested.value;
      if (advancing != null && mounted) {
        _clock.setAdvancing(advancing);
        _visualPositionNotifier.value = _clock.position;
        _lyricsPositionNotifier.value = _lyricsPosition;
      }
    };
    widget.service.advancingRequested.addListener(_advancingRequestedListener!);
    _startHideTimer();
    // Silently check for updates on launch after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.checkAndShowUpdate(context, silent: true);
      }
    });
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


  /// Repaints both position notifiers from the clock. Runs every frame, so the
  /// scrubber and the lyric highlight move continuously between native events
  /// and respond on the very next frame to pause, resume and seeks.
  void _tickVisualPosition() {
    final position = _clock.position;
    _visualPositionNotifier.value = position;
    _lyricsPositionNotifier.value = _lyricsPosition;
    widget.service.displayPosition = position;
  }

  /// Hands a native sample to the clock, which reconciles it with where the
  /// UI currently believes playback is.
  void _syncVisualPosition(MediaState state, {required bool songChanged}) {
    if (state.isEmpty) {
      _clock.reset();
      _visualPositionNotifier.value = Duration.zero;
      _lyricsPositionNotifier.value = Duration.zero;
      return;
    }

    _clock.sync(
      position: state.position,
      isPlaying: state.isAdvancing,
      duration: state.duration,
      playbackRate: state.playbackRate,
      songChanged: songChanged,
    );

    _visualPositionNotifier.value = _clock.position;
    _lyricsPositionNotifier.value = _lyricsPosition;
  }

  void _previewVisualPosition(Duration position) {
    final duration = _mediaState.duration;
    final clamped = duration > Duration.zero && position > duration
        ? duration
        : position;

    if (!_clock.previewing) _clock.beginPreview();
    _clock.updatePreview(clamped);

    _visualPositionNotifier.value = _clock.position;
    _lyricsPositionNotifier.value = _lyricsPosition;
  }

  void _setPositionPreviewing(bool isPreviewing) {
    if (isPreviewing) {
      _clock.beginPreview();
    } else {
      // Releasing the drag commits the previewed position as a pending seek,
      // so the UI holds where the user dropped it until the source app answers.
      _clock.endPreview();
    }
    _visualPositionNotifier.value = _clock.position;
    _lyricsPositionNotifier.value = _lyricsPosition;
  }

  void _onMediaStateUpdate(MediaState state) {
    if (!mounted) return;

    final now = DateTime.now();
    final incomingKey = '${state.title}|${state.artist}';

    if (incomingKey != _observedSongKey) {
      _observedSongKey = incomingKey;
      _observedSince = now;
      // A paused session publishes nothing, so waiting for the next tick to
      // re-check whether the pair has settled can mean waiting forever. Arm a
      // timer instead — that is what actually completes the settle.
      _metadataSettleTimer?.cancel();
      _metadataSettleTimer = Timer(_metadataSettle, () {
        if (mounted) _updateFetches();
      });
    }

    // GSMTC / MediaSession sometimes briefly publishes empty or partial
    // metadata between tracks. Compare against the last stable track identity
    // so track changes are never missed across brief unstable frames.
    final isStable = _hasStableIdentity(state);
    final songChanged = isStable && incomingKey != _lastStableSongKey;
    if (isStable) {
      _lastStableSongKey = incomingKey;
    }

    final displayState =
        !songChanged && state.albumArtBytes == null
            ? state.copyWithArtwork(
                _mediaState.albumArtBytes,
                thumbnailBytes: _mediaState.thumbnailArtBytes,
              )
            : state;

    setState(() {
      if (songChanged) {
        _useLyricsOffset = true;
      }
      _syncVisualPosition(displayState, songChanged: songChanged);
      _mediaState = displayState;
    });

    _updateFetches();
  }

  /// The single place lyrics and artwork requests are decided, so the same
  /// gate can run on every state tick and once more when metadata settles.
  void _updateFetches() {
    final state = _mediaState;
    final songKey = '${state.title}|${state.artist}';
    final now = DateTime.now();

    // Nothing is asked about until the pair has held still — and only for the
    // sample that actually armed the settle.
    if (songKey != _observedSongKey) return;
    if (now.difference(_observedSince) < _metadataSettle) return;

    final recentlyAttempted = songKey == _lastLyricsAttemptKey &&
        now.difference(_lastLyricsAttemptAt) < const Duration(seconds: 8);
    final shouldFetchLyrics = songKey != _lastFetchedKey &&
        !state.isEmpty &&
        !recentlyAttempted &&
        _lyricsFetchInFlightKey != songKey;
    final shouldFetchArtwork = !state.isEmpty &&
        state.albumArtBytes == null &&
        songKey != _lastArtworkFetchKey &&
        songKey != _artworkFetchInFlightKey;

    if (!shouldFetchLyrics && !shouldFetchArtwork) return;

    if (shouldFetchLyrics) {
      setState(() {
        _lyricsLoading = true;
        _lyricsError = null;
        _lyricsData = null;
        _lyricsFetchInFlightKey = songKey;
        _lastLyricsAttemptKey = songKey;
        _lastLyricsAttemptAt = now;
      });
      _fetchLyrics(state.title, state.artist, songKey);
    }
    if (shouldFetchArtwork) {
      _fetchArtwork(state.title, state.artist, state.album, songKey);
    }
  }

  static bool _hasStableIdentity(MediaState state) {
    if (state.isEmpty) return false;
    final title = state.title.trim();
    final artist = state.artist.trim();
    if (title.isEmpty ||
        title == 'Unknown Title' ||
        title == 'No media playing') {
      return false;
    }
    if (artist.isEmpty || artist == 'Unknown Artist') return false;
    return true;
  }

  Duration get _lyricsPosition {
    if (!_useLyricsOffset) return _clock.position;
    final offsetMs = SettingsService().lyricsOffsetMs.value;
    final offsetPos = _clock.position + Duration(milliseconds: offsetMs);
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
      if (mounted) {
        if (!data.isEmpty) {
          // Only an actual match locks the key.
          _lastFetchedKey = songKey;
        } else {
          // A confirmed miss leaves the key open so corrected metadata can
          // retry immediately, but backs off for a minute so a song the API
          // genuinely does not have is not re-asked on every tick.
          _lastLyricsAttemptKey = songKey;
          _lastLyricsAttemptAt = DateTime.now().add(const Duration(minutes: 1));
        }
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
      // Network failures are worth retrying, but not on every state tick.
      if (mounted) {
        _lastLyricsAttemptKey = songKey;
        _lastLyricsAttemptAt = DateTime.now().add(const Duration(minutes: 1));
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
    _metadataSettleTimer?.cancel();
    _positionTicker.dispose();
    _subscription?.cancel();
    if (_seekRequestedListener != null) {
      widget.service.seekRequested.removeListener(_seekRequestedListener!);
      _seekRequestedListener = null;
    }
    if (_advancingRequestedListener != null) {
      widget.service.advancingRequested
          .removeListener(_advancingRequestedListener!);
      _advancingRequestedListener = null;
    }
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
    if (!WindowService.isSupported) return _buildStandard(context);

    // Windows is its own app: the windowed, fullscreen and compact modes each
    // get their own layout rather than the phone layout being stretched.
    return ValueListenableBuilder<WindowMode>(
      valueListenable: WindowService.mode,
      builder: (context, mode, _) {
        switch (mode) {
          case WindowMode.compact:
            return _buildCompact();
          case WindowMode.windowed:
            return _buildSplit(fullscreen: false);
          case WindowMode.fullscreen:
            return _buildSplit(fullscreen: true);
        }
      },
    );
  }

  /// The lyrics widget shared by every desktop layout. One instance lives
  /// behind [_lyricsKey] so scrolling state survives a mode change.
  ///
  /// Wrapped in a [LyricsFadeMask] because the scroll viewport hard-clips its
  /// content: without it the pane reads as a box with a sharp rule drawn across
  /// its top and bottom edges rather than lyrics dissolving into the artwork.
  Widget _buildDesktopLyrics() {
    return LyricsFadeMask(
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
  }

  void _openDesktopSettings() {
    showWindowsSettings(context, widget.service);
  }

  Widget _buildSplit({required bool fullscreen}) {
    return NowPlayingSplitView(
      mediaState: _mediaState,
      service: widget.service,
      lyrics: _buildDesktopLyrics(),
      positionNotifier: _visualPositionNotifier,
      fullscreen: fullscreen,
      onSettings: _openDesktopSettings,
      onPositionPreview: _previewVisualPosition,
      onPositionPreviewing: _setPositionPreviewing,
    );
  }

  Widget _buildCompact() {
    return CompactPlayer(
      mediaState: _mediaState,
      service: widget.service,
      lyrics: _buildDesktopLyrics(),
      positionNotifier: _visualPositionNotifier,
      onSettings: _openDesktopSettings,
      onPositionPreview: _previewVisualPosition,
      onPositionPreviewing: _setPositionPreviewing,
    );
  }

  Widget _buildStandard(BuildContext context) {
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
                      isPlaying: _mediaState.isPlaying,
                    );
                  },
                ),
              ),
              // Fading UI layer
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: SettingsService().isFullScreenArtworkOpen,
                  builder: (context, isFullScreenOpen, child) {
                    final hideForTransparentFullscreen = isFullScreenOpen &&
                        SettingsService()
                            .showBackgroundInFullScreenArtwork
                            .value;
                    return AnimatedOpacity(
                      opacity: hideForTransparentFullscreen ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      child: child,
                    );
                  },
                  child: Stack(
                    children: [
                      // 20% black tint specifically for the home screen (covers lyrics and metadata)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(color: Colors.black.withValues(alpha: 0.18)),
                        ),
                      ),
                      if (isEmptyState)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
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
                                      : TweenAnimationBuilder<double>(
                                          tween: Tween<double>(
                                              begin: 0.0,
                                              end: _controlsVisible ? 1.0 : 0.0),
                                          duration: const Duration(milliseconds: 250),
                                          curve: Curves.easeInOut,
                                          builder: (context, value, child) {
                                            return ShaderMask(
                                              shaderCallback: (rect) {
                                                // Start fading out 240px from bottom
                                                final fadeStart =
                                                    (rect.height - 240) / rect.height;
                                                // Fully transparent by 190px from bottom (just above the progress bar)
                                                final fadeEnd = 
                                                    (rect.height - 190) / rect.height;
                                                
                                                final maskColor = Color.lerp(Colors.white,
                                                        Colors.transparent, value)!;
                                                        
                                                return LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.white,
                                                    Colors.white,
                                                    maskColor,
                                                    maskColor,
                                                  ],
                                                  stops: [
                                                    0.0,
                                                    fadeStart.clamp(0.0, 1.0),
                                                    fadeEnd.clamp(0.0, 1.0),
                                                    1.0,
                                                  ],
                                                ).createShader(rect);
                                              },
                                              blendMode: BlendMode.dstIn,
                                              child: child,
                                            );
                                          },
                                          child: ValueListenableBuilder<bool>(
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
                              ), // Closes TweenAnimationBuilder
                            ), // Closes RepaintBoundary
                          ), // Closes Expanded
                        ],
                      ), // Closes Column
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
        ), // End of ValueListenableBuilder
      ), // End of Positioned.fill
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
