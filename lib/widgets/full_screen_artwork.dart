import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../models/media_state.dart';
import '../services/media_session_service.dart';
import '../services/settings_service.dart';
import 'animated_artwork_player.dart';
import 'playback_controls.dart';

class FullScreenArtwork extends StatefulWidget {
  final Uint8List? artBytes;
  final String title;
  final String artist;
  final MediaState mediaState;
  final MediaSessionService service;

  const FullScreenArtwork({
    super.key,
    required this.artBytes,
    required this.title,
    required this.artist,
    required this.mediaState,
    required this.service,
  });

  @override
  State<FullScreenArtwork> createState() => _FullScreenArtworkState();
}

class _FullScreenArtworkState extends State<FullScreenArtwork>
  with TickerProviderStateMixin {
  late MediaState _mediaState;
  final ValueNotifier<Duration> _visualPositionNotifier = ValueNotifier<Duration>(Duration.zero);
  DateTime _lastPositionTick = DateTime.now();
  late final Ticker _positionTicker;
  late final AnimationController _entryController;
  StreamSubscription<MediaState>? _subscription;
  bool _isPreviewingPosition = false;

  // State variables for delayed dark overlay when live artwork is active
  bool _showLiveOverlayDarkFade = false;
  Timer? _liveOverlayDelayTimer;
  bool _lastIsLiveActive = false;


  @override
  void initState() {
    super.initState();
    _mediaState = widget.mediaState;
    _visualPositionNotifier.value = widget.mediaState.position;
    _positionTicker = createTicker((_) => _tickVisualPosition())..start();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
    _subscription = widget.service.mediaStateStream.listen(_onMediaStateUpdate);
    
    // Listen to changes in settings for animated artwork
    SettingsService().animatedArtworkEnabled.addListener(_onSettingsChanged);
    
    // Initialize initial state for the delayed overlay
    final animatedEnabled = SettingsService().animatedArtworkEnabled.value;
    final hasTallUrl = _mediaState.tallMasterUrl != null &&
        _mediaState.tallMasterUrl!.isNotEmpty;
    _lastIsLiveActive = animatedEnabled && hasTallUrl;
    if (_lastIsLiveActive) {
      _startLiveOverlayDelayTimer();
    }

    // Hide status bar and navigation bar for fullscreen immersion
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  void _onMediaStateUpdate(MediaState state) {
    if (!mounted) return;
    final previousState = _mediaState;
    setState(() {
      _mediaState = state;
    });

    // Sync position if it drifts too much or if song changes
    final delta = (state.position.inMilliseconds - _visualPositionNotifier.value.inMilliseconds).abs();
    final songChanged = state.title != previousState.title ||
        state.artist != previousState.artist;
    if (delta > 1000 || songChanged) {
      _visualPositionNotifier.value = state.position;
    }

    _updateLiveOverlayTimer(forceReset: songChanged);
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
            _visualPositionNotifier.value + elapsed > duration
        ? duration
        : _visualPositionNotifier.value + elapsed;

    if (nextPosition == _visualPositionNotifier.value) return;

    _visualPositionNotifier.value = nextPosition;
  }

  void _previewVisualPosition(Duration position) {
    final duration = _mediaState.duration;
    final clampedPosition = duration > Duration.zero && position > duration
        ? duration
        : position;

    _visualPositionNotifier.value = clampedPosition;
    _lastPositionTick = DateTime.now();
  }

  @override
  void dispose() {
    SettingsService().animatedArtworkEnabled.removeListener(_onSettingsChanged);
    _liveOverlayDelayTimer?.cancel();
    _positionTicker.dispose();
    _entryController.dispose();
    _subscription?.cancel();
    _visualPositionNotifier.dispose();
    // Restore system UI when exiting fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    super.dispose();
  }

  void _onSettingsChanged() {
    _updateLiveOverlayTimer();
  }

  void _updateLiveOverlayTimer({bool forceReset = false}) {
    if (!mounted) return;
    final animatedEnabled = SettingsService().animatedArtworkEnabled.value;
    final hasTallUrl = _mediaState.tallMasterUrl != null &&
        _mediaState.tallMasterUrl!.isNotEmpty;
    final isLiveActive = animatedEnabled && hasTallUrl;

    if (isLiveActive != _lastIsLiveActive || forceReset) {
      _lastIsLiveActive = isLiveActive;
      if (isLiveActive) {
        _startLiveOverlayDelayTimer();
      } else {
        _cancelLiveOverlayDelayTimer();
      }
    }
  }

  void _startLiveOverlayDelayTimer() {
    _liveOverlayDelayTimer?.cancel();
    setState(() {
      _showLiveOverlayDarkFade = false;
    });
    _liveOverlayDelayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showLiveOverlayDarkFade = true;
        });
      }
    });
  }

  void _cancelLiveOverlayDelayTimer() {
    _liveOverlayDelayTimer?.cancel();
    if (_showLiveOverlayDarkFade) {
      setState(() {
        _showLiveOverlayDarkFade = false;
      });
    }
  }

  Widget _buildTallPlaceholder(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: SizedBox.expand(child: child),
      ),
    );
  }

  Widget _buildEdgeBlurOverlay({required double top, required double height}) {
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      height: height,
      child: IgnorePointer(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metadataFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.70, 1.0, curve: Curves.easeOutCubic),
    );
    final controlsFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.82, 1.0, curve: Curves.easeOutCubic),
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          SystemChrome.setSystemUIOverlayStyle(
            const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<bool>(
          valueListenable: SettingsService().animatedArtworkEnabled,
          builder: (context, animatedEnabled, _) {
            final hasTallUrl = _mediaState.tallMasterUrl != null &&
                _mediaState.tallMasterUrl!.isNotEmpty;
            final isLiveActive = animatedEnabled && hasTallUrl;

            final songChanged = _mediaState.title != widget.title ||
                _mediaState.artist != widget.artist;

            final art = _mediaState.albumArtBytes ??
                (songChanged ? null : widget.artBytes) ??
                _mediaState.thumbnailArtBytes;

            final staticPlaceholder = art != null && art.isNotEmpty
                ? Image.memory(
                    art,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.grey.shade800,
                          Colors.grey.shade900,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white38,
                      size: 80,
                    ),
                  );

            final livePlaceholder = art != null && art.isNotEmpty
                ? _buildTallPlaceholder(
                    Image.memory(
                      art,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      gaplessPlayback: true,
                    ),
                  )
                : _buildTallPlaceholder(staticPlaceholder);

            final minSpace = 160.0;
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final double size = (screenHeight - 2 * minSpace).clamp(screenWidth * 0.5, screenWidth * 0.92);
            final liveVideoHeight = screenWidth * (4 / 3);
            final liveFadeHeight = 120.0;
            final liveFadeTop =
              (liveVideoHeight - liveFadeHeight + 128).clamp(0.0, screenHeight - liveFadeHeight);

            return Stack(
              children: [
                // 1. Base Backgrounds
                Positioned.fill(
                  child: Stack(
                    children: [
                      // Normal static artwork background is pure black
                      Positioned.fill(
                        child: Container(color: Colors.black),
                      ),
                      // Dynamic color background from bottom 8 pixels of LIVE artwork
                      if (isLiveActive)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRect(
                                  child: Transform.scale(
                                    scaleY: 100.0, // Stretches the bottom ~8 pixels to fill the entire screen!
                                    alignment: Alignment.bottomCenter,
                                    child: AnimatedArtworkPlayer(
                                      url: _mediaState.tallMasterUrl!,
                                      placeholder: staticPlaceholder,
                                      fit: BoxFit.fitWidth,
                                      alignment: Alignment.bottomCenter,
                                      enableCrossFade: false,
                                    ),
                                  ),
                                ),
                                // Smooth out the stretched pixels into a perfect gradient
                                BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                                  child: Container(color: Colors.transparent),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 3. Immersive morphing Artwork Player (Static Centered Card <-> Live Full-Bleed)
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOutCubic,
                    alignment: isLiveActive ? Alignment.topCenter : const Alignment(0, -0.20),
                    child: AnimatedScale(
                      scale: 1.0,
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeInOutCubic,
                      child: Hero(
                        tag: 'album_art',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeInOutCubic,
                          width: isLiveActive ? screenWidth : size,
                          height: isLiveActive ? screenHeight : size,
                          decoration: BoxDecoration(
                            borderRadius: isLiveActive
                                ? BorderRadius.zero
                                : BorderRadius.circular(12),
                            boxShadow: isLiveActive
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 25,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 900),
                                switchInCurve: Curves.easeIn,
                                switchOutCurve: Curves.easeOut,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  );
                                },
                                child: isLiveActive
                                    ? RepaintBoundary(
                                        key: ValueKey('live_art_${_mediaState.tallMasterUrl}'),
                                        child: ShaderMask(
                                          shaderCallback: (rect) {
                                            // Live artwork is 3:4, so its physical height is screenWidth * (4 / 3).
                                            // Fade out over the last 120 pixels at the bottom edge.
                                            final videoBottom = liveVideoHeight;
                                            final fadeStart = (videoBottom - liveFadeHeight) / screenHeight;
                                            final fadeEnd = videoBottom / screenHeight;

                                            return LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: const [
                                                Colors.black,
                                                Colors.black,
                                                Colors.transparent,
                                                Colors.transparent, // Ensure it stays transparent below
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
                                          child: AnimatedArtworkPlayer(
                                            url: _mediaState.tallMasterUrl!,
                                            placeholder: livePlaceholder,
                                            fit: BoxFit.fitWidth,
                                            alignment: Alignment.topCenter,
                                          ),
                                        ),
                                      )
                                    : SizedBox.expand(
                                        key: const ValueKey('static_art'),
                                        child: staticPlaceholder,
                                      ),
                              ),
                              if (isLiveActive)
                                _buildEdgeBlurOverlay(
                                  top: liveFadeTop,
                                  height: liveFadeHeight,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. Subtle dark gradient overlays for legibility
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: isLiveActive ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeInOutCubic,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.40), // status bar contrast
                              Colors.transparent,                   // perfectly clean video view in the middle
                              Colors.black.withValues(alpha: 0.15), // subtle darkening for lyrics
                              Colors.black.withValues(alpha: 0.45), // controls contrast
                            ],
                            stops: const [0.0, 0.20, 0.70, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4.1. (Removed buggy BackdropFilter fade zone, now using native ImageFiltered in Super Stack above)

                // 5. Immersive Drag / Tap to Dismiss Gesture layer
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta! > 10) {
                      Navigator.of(context).pop();
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),

                // 6. Premium Top Drag indicator handle
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ),

                // 7. Dynamic Overlay Panel for Metadata and Playback Controls
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 900),
                    switchInCurve: Curves.easeInOutCubic,
                    switchOutCurve: Curves.easeInOutCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                    },
                    child: isLiveActive
                        ? SizedBox.expand(
                            key: const ValueKey('live_layout'),
                            child: Stack(
                              children: [
                                _buildLiveOverlays(metadataFade, controlsFade),
                              ],
                            ),
                          )
                        : SizedBox.expand(
                            key: const ValueKey('static_layout'),
                            child: Stack(
                              children: [
                                _buildStaticOverlays(size, metadataFade, controlsFade),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveOverlays(Animation<double> metadataFade, Animation<double> controlsFade) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Floating metadata
          FadeTransition(
            opacity: metadataFade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                       _mediaState.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Display',
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  type: MaterialType.transparency,
                  child: Text(
                     _mediaState.artist,
                    style: TextStyle(
                      fontFamily: 'Display',
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PlaybackControls(
            key: const ValueKey('live_controls'),
            mediaState: _mediaState,
            positionNotifier: _visualPositionNotifier,
            service: widget.service,
            visible: true,
            onInteraction: () {},
            onPositionPreview: _previewVisualPosition,
            onPositionPreviewing: (val) =>
                setState(() => _isPreviewingPosition = val),
            transparentBackground: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStaticOverlays(double size, Animation<double> metadataFade, Animation<double> controlsFade) {
    final screenHeight = MediaQuery.of(context).size.height;
    final centerY = (screenHeight / 2) - 0.20 * (screenHeight / 2 - size / 2);
    final bottomOfCard = centerY + (size / 2);

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: bottomOfCard + 20,
          child: FadeTransition(
            opacity: metadataFade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _mediaState.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Display',
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(0, 2),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  type: MaterialType.transparency,
                  child: Text(
                    _mediaState.artist,
                    style: TextStyle(
                      fontFamily: 'Display',
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(0, 2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: FadeTransition(
            opacity: controlsFade,
            child: PlaybackControls(
              key: const ValueKey('static_controls'),
              mediaState: _mediaState,
              positionNotifier: _visualPositionNotifier,
              service: widget.service,
              visible: true,
              onInteraction: () {},
              onPositionPreview: _previewVisualPosition,
              onPositionPreviewing: (val) =>
                  setState(() => _isPreviewingPosition = val),
              transparentBackground: false,
            ),
          ),
        ),
      ],
    );
  }
}
