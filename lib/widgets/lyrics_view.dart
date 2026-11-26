import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'package:simple_lyrics/core/platform_capabilities.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:vibration/vibration.dart';
import '../services/cache_service.dart';
import '../services/lyrics_models.dart';
import '../services/media_session_service.dart';
import 'karaoke_text_fill.dart';
import '../services/settings_service.dart';

class LyricsView extends StatefulWidget {
  final String trackKey;
  final LyricsData? lyricsData;
  final ValueNotifier<Duration> positionNotifier;
  final Duration duration;
  final bool isLoading;
  final String? errorMessage;
  final MediaSessionService service;
  final VoidCallback onLyricsInteraction;

  const LyricsView({
    super.key,
    required this.trackKey,
    this.lyricsData,
    required this.positionNotifier,
    required this.duration,
    required this.service,
    required this.onLyricsInteraction,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  State<LyricsView> createState() => LyricsViewState();
}

class LyricsViewState extends State<LyricsView> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _autoScrollController;
  late final _LyricsWaveController _waveController;

  List<int> _activeIndices = [];
  int _focusIndex = -1;
  int _focusDisplayIndex = -1;
  
  static const double _focusViewportAlignment = 0.25;
  final ValueNotifier<double> _smoothSeconds = ValueNotifier<double>(0.0);
  bool _scrollQueued = false;
  bool _pendingScrollToTop = false;
  List<GlobalKey> _lineKeys = [];

  bool _isAutoLocked = true;
  bool _firstScroll = true;
  bool _startupSettling = false;
  bool _userIsTouching = false;
  bool _waitingForNewTrackLyrics = false;
  Timer? _trackWaitTimer;
  Timer? _autoRelockTimer;
  int _searchAttempts = 0; // NEW: Track search jumps
  
  // Seek indicator state
  bool _showSeekIndicator = false;
  int _seekDelta = 0;
  Timer? _seekIndicatorTimer;
  double? _dragStartX;

  List<int> _displayItems = [];
  List<double> _interludeStarts = []; 
  List<double> _interludeEnds = [];   
  List<int> _lineToDisplayIndex = [];

  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  final ValueNotifier<Matrix4> _parallaxTransform = ValueNotifier<Matrix4>(Matrix4.identity());
  double _roll = 0.0;
  double _pitch = 0.0;
  double _targetRoll = 0.0;
  double _targetPitch = 0.0;
  int _lastHoveredLine = -1;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    widget.positionNotifier.addListener(_onPositionChanged);
    _applyPosition(widget.positionNotifier.value, widget.duration);

    _autoScrollController = AnimationController.unbounded(vsync: this)
      ..addListener(_onAutoScrollTick);

    _waveController = _LyricsWaveController(
      scrollController: _scrollController,
      vsync: this,
    );
    _syncWaveEnabled();

    _initParallax();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculateFocus(_smoothSeconds.value);
    });
  }

  void _initParallax() {
    // Ticker runs only while parallax is enabled so disabled devices spend
    // zero per-frame callbacks on tilt interpolation.
    _ticker = createTicker((elapsed) {
      if (!SettingsService().parallaxEnabled.value) {
        if (_roll != 0 || _pitch != 0) {
          _roll = 0; _pitch = 0; _targetRoll = 0; _targetPitch = 0;
          _parallaxTransform.value = Matrix4.identity();
        }
        _ticker.stop();
        return;
      }

      // Smoothly interpolate towards target (Spring/Lerp logic)
      const lerpFactor = 0.12; // Lower = smoother/more "floaty"
      _roll += (_targetRoll - _roll) * lerpFactor;
      _pitch += (_targetPitch - _pitch) * lerpFactor;

      final offset = Offset(
        (_roll * 18.0).clamp(-22, 22),
        (_pitch * 18.0).clamp(-22, 22),
      );

      _parallaxTransform.value = Matrix4.identity()
        ..setEntry(3, 2, 0.0007) // Subtle perspective
        ..translate(offset.dx, offset.dy, 0)
        ..rotateX(-_pitch * 0.18) // Natural tilt
        ..rotateY(_roll * 0.18);
    });
    SettingsService().parallaxEnabled.addListener(_onParallaxSettingChanged);
    if (SettingsService().parallaxEnabled.value) {
      _ticker.start();
    }

    _gyroSubscription = supportsTiltSensors
        ? gyroscopeEventStream().listen((event) {
            if (!mounted || !SettingsService().parallaxEnabled.value) return;
            // Set the target, ticker handles the smooth transition
            _targetRoll = event.y;
            _targetPitch = event.x;
          })
        : null;
  }

  void _onParallaxSettingChanged() {
    if (!mounted) return;
    if (SettingsService().parallaxEnabled.value) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _roll = 0;
      _pitch = 0;
      _targetRoll = 0;
      _targetPitch = 0;
      _parallaxTransform.value = Matrix4.identity();
      if (_ticker.isActive) _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.positionNotifier != oldWidget.positionNotifier) {
      oldWidget.positionNotifier.removeListener(_onPositionChanged);
      widget.positionNotifier.addListener(_onPositionChanged);
    }
    
    final trackChanged = widget.trackKey != oldWidget.trackKey;
    final lyricsChanged = widget.lyricsData != oldWidget.lyricsData;

    if (trackChanged || lyricsChanged) {
      if (trackChanged) {
        _waitingForNewTrackLyrics = true;
        _activeIndices = [];
        _focusIndex = -1;
        _focusDisplayIndex = -1;

        // Safety net: if new lyrics never arrive (cached track, API miss, a
        // track change that doesn't produce new data), the wait must end
        // anyway. Otherwise focus and scrolling stay frozen for the rest of
        // the session.
        _trackWaitTimer?.cancel();
        _trackWaitTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted && _waitingForNewTrackLyrics) {
            _waitingForNewTrackLyrics = false;
            _queueStartupFocusJump();
          }
        });

        _smoothSeconds.value = widget.positionNotifier.value.inMicroseconds / 1e6;
        _firstScroll = true;
        _startupSettling = true;
        _isAutoLocked = true;
        _scrollQueued = false;
        _pendingScrollToTop = false;
        _searchAttempts = 0;
        _autoScrollController.stop();
        _autoScrollController.value = 0.0;
        _waveController.reset();
        _syncWaveEnabled();
        
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _autoScrollController.stop();
            _autoScrollController.value = 0.0;
            _waveController.reset();
            _scrollController.jumpTo(0.0);
          }
        });
      }

      _buildDisplayItems();
      
      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _calculateFocus(_smoothSeconds.value);
      });

      if (lyricsChanged) {
        _waitingForNewTrackLyrics = false;
        _trackWaitTimer?.cancel();
        _queueStartupFocusJump();
      }
    }

    if (_waitingForNewTrackLyrics) return;

    if (widget.duration != oldWidget.duration || trackChanged) {
      _applyPosition(widget.positionNotifier.value, widget.duration);
    }
  }

  void _onPositionChanged() {
    _applyPosition(widget.positionNotifier.value, widget.duration);
  }

  void _queueStartupFocusJump() {
    _firstScroll = true;
    _startupSettling = true;
    _isAutoLocked = true;
    _searchAttempts = 0;
    _waveController.reset();
    _syncWaveEnabled();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _calculateFocus(_smoothSeconds.value);
      _scrollToFocusLine();
    });
  }

  void resetAutoScroll() {
    if (!mounted) return;
    setState(() {
      _isAutoLocked = true;
      _firstScroll = true; // Force jump instead of smooth animate for immediate response
    });
    _autoScrollController.stop();
    _waveController.reset();
    _syncWaveEnabled();
    _calculateFocus(_smoothSeconds.value);
    _scrollToFocusLine();
  }

  void _onAutoScrollTick() {
    if (!mounted ||
        !_isAutoLocked ||
        _userIsTouching ||
        _pendingScrollToTop ||
        !_scrollController.hasClients) {
      if (_autoScrollController.isAnimating) {
        _autoScrollController.stop();
      }
      return;
    }
    final pos = _scrollController.position;
    final clamped = _autoScrollController.value.clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _scrollController.jumpTo(clamped);
  }

  void _syncWaveEnabled() {
    _waveController.setEnabled(
      _isAutoLocked &&
          !_userIsTouching &&
          !_firstScroll &&
          !_startupSettling &&
          !_pendingScrollToTop &&
          (widget.lyricsData?.timingType ?? LyricsTimingType.none) !=
              LyricsTimingType.none,
    );
  }

  void _scheduleAutoRelock() {
    _autoRelockTimer?.cancel();
    if (_isAutoLocked || _userIsTouching) return;
    _autoRelockTimer = Timer(const Duration(milliseconds: 4500), () {
      if (!mounted || _isAutoLocked || _userIsTouching) return;
      setState(() => _isAutoLocked = true);
      _syncWaveEnabled();
      _calculateFocus(_smoothSeconds.value);
      _scrollToFocusLine();
    });
  }

  @override
  void dispose() {
    SettingsService().parallaxEnabled.removeListener(_onParallaxSettingChanged);
    widget.positionNotifier.removeListener(_onPositionChanged);
    _autoScrollController.dispose();
    _waveController.dispose();
    _ticker.dispose();
    _trackWaitTimer?.cancel();
    _autoRelockTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _gyroSubscription?.cancel();
    _smoothSeconds.dispose();
    _parallaxTransform.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyPosition(Duration position, Duration duration) {
    if (!mounted) return;

    final sec = position.inMicroseconds / 1e6;

    // Always publish the playback time first. Every karaoke fill, word lift and
    // "lit" state reads _smoothSeconds, so anything below that returns early
    // used to freeze the animation outright — including the end-of-song branch
    // and the track-change wait flag.
    _smoothSeconds.value = sec;

    // If the song is essentially over, scroll lyrics view to the top
    if (duration.inMilliseconds > 0) {
      final durationSec = duration.inMicroseconds / 1e6;
      // within 250ms of end -> treat as finished
      if (sec >= durationSec - 0.25) {
        if (!_pendingScrollToTop) {
          _pendingScrollToTop = true;
          _autoScrollController.stop();
          _syncWaveEnabled();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_scrollController.hasClients) {
              try {
                _scrollController.animateTo(
                  _scrollController.position.minScrollExtent,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                );
              } catch (_) {
                // ignore any controller errors
              }
            }

            // Reset focus and active indices so lyrics show top state
            _activeIndices = [];
            _focusIndex = -1;
            _focusDisplayIndex = -1;
            _firstScroll = true;
            _isAutoLocked = true;
            _pendingScrollToTop = false;
            _waveController.reset();
            _syncWaveEnabled();
            if (mounted) setState(() {});
          });
        }
        return;
      }
    }

    final data = widget.lyricsData;
    if (data == null || data.isEmpty) return;

    // Deferring only focus and scrolling is safe; the highlight clock above
    // has already been kept in step.
    if (_waitingForNewTrackLyrics) return;

    _calculateFocus(_smoothSeconds.value);
  }

  void _calculateFocus(double sec) {
    final data = widget.lyricsData;
    if (data == null || data.isEmpty) return;

    final newIndices = data.activeLineIndices(
      Duration(microseconds: (sec * 1e6).round()),
    );

    int newFocus = -1;
    for (int i = 0; i < data.lines.length; i++) {
      // Look-ahead: Set focus to the next line 0.2s before it starts.
      if (data.lines[i].startTime <= sec + 0.2) {
        if (!data.lines[i].isBackground) {
          newFocus = i;
        }
      } else {
        break;
      }
    }

    bool focusChanged = newFocus != _focusIndex;
    bool indicesChanged = !listEquals(newIndices, _activeIndices);

    if (indicesChanged || focusChanged || _firstScroll) {
      _activeIndices = newIndices;
      if (focusChanged || _firstScroll) {
        _focusIndex = newFocus;
        _focusDisplayIndex = _focusIndex >= 0 && _focusIndex < _lineToDisplayIndex.length
            ? _lineToDisplayIndex[_focusIndex]
            : -1;
            
        if (_focusIndex >= 0 && focusChanged) {
          final settings = SettingsService();
          if (settings.hapticLyricsEnabled.value) {
            // Trigger a sharp, distinct "Line Start" vibration
            // Scale intensity by the squared user setting for better low-end control
            final curve = settings.hapticIntensity.value * settings.hapticIntensity.value;
            final intensity = (255 * curve).toInt().clamp(0, 255);
            
            // Only vibrate if intensity is above a negligible threshold
            if (intensity > 10 && supportsHaptics) {
              Vibration.vibrate(duration: 48, amplitude: intensity);
            }
            
            // Also trigger standard HapticFeedback for consistency
            HapticFeedback.lightImpact();
          }
        }

        if (!_scrollQueued && !_pendingScrollToTop && _isAutoLocked) {
          _scrollQueued = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollQueued = false;
            _scrollToFocusLine();
          });
        }
      }
      if (mounted) setState(() {});
    }
  }

  void _buildDisplayItems() {
    final data = widget.lyricsData;
    if (data == null || data.isEmpty) {
      _displayItems = [];
      _lineKeys = [];
      _lineToDisplayIndex = [];
      _interludeStarts = [];
      _interludeEnds = [];
      return;
    }

    final items = <int>[];
    final iStarts = <double>[];
    final iEnds = <double>[];
    final lineToDisplay = <int>[];

    if (data.lines.isNotEmpty && data.lines.first.startTime >= 5.0) {
      items.add(-1);
      iStarts.add(0.0);
      iEnds.add(data.lines.first.startTime);
    }

    for (int i = 0; i < data.lines.length; i++) {
      if (i > 0) {
        final prevEnd = data.lines[i - 1].endTime;
        final thisStart = data.lines[i].startTime;
        if (thisStart - prevEnd >= 5.0) {
          items.add(-1);
          iStarts.add(prevEnd);
          iEnds.add(thisStart);
        }
      }
      lineToDisplay.add(items.length);
      items.add(i);
    }

    _displayItems = items;
    _interludeStarts = iStarts;
    _interludeEnds = iEnds;
    _lineToDisplayIndex = lineToDisplay;
    _lineKeys = List.generate(items.length, (_) => GlobalKey());
  }

  void _checkIfUserScrolledIntoRange() {
    if (_focusDisplayIndex < 0 || _focusDisplayIndex >= _lineKeys.length) return;
    if (!_scrollController.hasClients) return;
    
    final ctx = _lineKeys[_focusDisplayIndex].currentContext;
    if (ctx == null) return;
    final renderObject = ctx.findRenderObject();
    if (renderObject == null) return;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return;

    final targetOffset = viewport.getOffsetToReveal(renderObject, _focusViewportAlignment).offset;
    final currentOffset = _scrollController.offset;

    if ((currentOffset - targetOffset).abs() < 120.0) {
      if (!_isAutoLocked) {
        HapticFeedback.lightImpact();
        setState(() => _isAutoLocked = true);
        _syncWaveEnabled();
      }
    }
  }

  void _triggerSeek(int seconds) {
    if (widget.lyricsData == null) return;
    
    widget.onLyricsInteraction();
    final currentPos = widget.positionNotifier.value;
    final newPos = Duration(seconds: (currentPos.inSeconds + seconds).clamp(0, widget.duration.inSeconds));
    
    widget.service.seekTo(newPos);
    HapticFeedback.mediumImpact();
    
    setState(() {
      _showSeekIndicator = true;
      _seekDelta = seconds;
    });
    
    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showSeekIndicator = false);
    });
  }

  void _scrollToFocusLine() {
    if (widget.lyricsData?.timingType == LyricsTimingType.none) return;
    if (!_isAutoLocked || !_scrollController.hasClients || _pendingScrollToTop) return;
    if (_focusDisplayIndex < 0 || _focusDisplayIndex >= _lineKeys.length) return;

    final ctx = _lineKeys[_focusDisplayIndex].currentContext;
    if (ctx == null) {
      // Widget not yet built. On first scroll attempt, estimate the position.
      if (_firstScroll && _searchAttempts < 8) {
        _searchAttempts++;
        final maxExtent = _scrollController.position.maxScrollExtent;

        if (maxExtent <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToFocusLine();
          });
          return;
        }

        final progress = _displayItems.length <= 1
            ? 0.0
            : _focusDisplayIndex / (_displayItems.length - 1);
        final estimatedOffset = maxExtent * progress;
        final targetOffset = estimatedOffset.clamp(0.0, maxExtent);
        
        _autoScrollController.stop();
        _autoScrollController.value = targetOffset;
        _waveController.reset();
        _scrollController.jumpTo(targetOffset);
        
        // Retry after next frame to find the actual render object
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToFocusLine();
        });
      }
      return;
    }

    final renderObject = ctx.findRenderObject();
    if (renderObject == null) return;

    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return;

    final position = _scrollController.position;
    final targetOffset = viewport.getOffsetToReveal(renderObject, _focusViewportAlignment).offset;
    final clampedOffset = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (_firstScroll) {
      _firstScroll = false;
      _isAutoLocked = true;
      _startupSettling = false;
      _autoScrollController.stop();
      _autoScrollController.value = clampedOffset;
      _waveController.reset();
      _scrollController.jumpTo(clampedOffset);
      _syncWaveEnabled();
      return;
    }

    final currentOffset = _scrollController.offset;
    final distance = (currentOffset - clampedOffset).abs();
    if (distance < 1.0) return;

    // Weighty, inertial spring simulation that carries velocity across rapid
    // line changes like Apple Music lyrics instead of restarting from 0 speed.
    final currentVelocity = _autoScrollController.isAnimating
        ? _autoScrollController.velocity
        : 0.0;
    _autoScrollController.value = currentOffset;
    const scrollSpring = SpringDescription(
      mass: 1.15,
      stiffness: 62.0,
      damping: 16.4,
    );
    _autoScrollController.animateWith(
      SpringSimulation(
        scrollSpring,
        currentOffset,
        clampedOffset,
        currentVelocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white24));
    }
    if (widget.errorMessage != null) {
      return Center(
        child: material.Text(widget.errorMessage!, style: const TextStyle(color: Colors.white30)),
      );
    }

    final data = widget.lyricsData;
    if (data == null || data.isEmpty) {
      return Center(
        child: material.Text('Play music to see lyrics',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 18)),
      );
    }

    return Listener(
      onPointerDown: (_) {
        _userIsTouching = true;
        _autoRelockTimer?.cancel();
        _autoScrollController.stop();
        _syncWaveEnabled();
      },
      onPointerUp: (_) {
        _userIsTouching = false;
        _syncWaveEnabled();
        if (!_isAutoLocked) _scheduleAutoRelock();
      },
      onPointerCancel: (_) {
        _userIsTouching = false;
        _syncWaveEnabled();
        if (!_isAutoLocked) _scheduleAutoRelock();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            if (_userIsTouching && notification.dragDetails != null && _isAutoLocked) {
              _autoRelockTimer?.cancel();
              setState(() => _isAutoLocked = false);
              _syncWaveEnabled();
            }
            if (!_isAutoLocked && notification.dragDetails != null) {
              _scheduleAutoRelock();
              _checkIfUserScrolledIntoRange();
              
              // NEW: Magnetic Haptic Scroll
              // Trigger a tiny click when a new line passes the center
              final centerOffset = _scrollController.offset + (_scrollController.position.viewportDimension * _focusViewportAlignment);
              int currentlyHoveredLine = -1;
              
              // Find which line is closest to the focus center
              if (widget.lyricsData != null) {
                // This is a simplified estimation for performance
                final maxExtent = _scrollController.position.maxScrollExtent;
                if (maxExtent > 0) {
                  final approxIndex = (_displayItems.length * (centerOffset / maxExtent)).toInt();
                  currentlyHoveredLine = approxIndex.clamp(0, _displayItems.length - 1);
                } else {
                  currentlyHoveredLine = 0;
                }
              }

              if (currentlyHoveredLine != _lastHoveredLine && currentlyHoveredLine != -1) {
                _lastHoveredLine = currentlyHoveredLine;
                if (SettingsService().hapticLyricsEnabled.value) {
                  HapticFeedback.selectionClick(); // The "Magnetic" click
                }
              }
            }
          }
          return false;
        },
        child: GestureDetector(
          onHorizontalDragStart: (details) {
            _dragStartX = details.globalPosition.dx;
          },
          onHorizontalDragEnd: (details) {
            if (_dragStartX == null) return;
            
            final screenWidth = MediaQuery.of(context).size.width;
            const deadZone = 45.0; // Avoid triggering system back gestures
            
            if (_dragStartX! < deadZone || _dragStartX! > screenWidth - deadZone) {
              return;
            }

            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -300) {
              _triggerSeek(-10); // Swipe Left -> Backward
            } else if (velocity > 300) {
              _triggerSeek(10); // Swipe Right -> Forward
            }
          },
          child: Stack(
            children: [
              RepaintBoundary(
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: _parallaxTransform,
            builder: (context, transform, child) {
              return Transform(
                transform: transform,
                alignment: Alignment.center,
                child: child,
              );
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const CinematicScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                if (data.timingType == LyricsTimingType.none && data.songwriters.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 28.0, right: 28.0, top: 140.0, bottom: 20.0),
                      child: RichText(
                        textAlign: TextAlign.left,
                        text: TextSpan(
                          style: TextStyle(
                            fontFamily: hasComplexScript(data.songwriters.join(', ')) ? null : 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 18,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Written by: ',
                              style: TextStyle(
                                fontFamily: 'Heavy', fontFamilyFallback: kGlobalFontFallbacks,
                                fontWeight: FontWeight(1000),
                                letterSpacing: 0.1,
                              ),
                            ),
                            TextSpan(
                              text: data.songwriters.join(', '),
                              style: TextStyle(
                                fontFamily: hasComplexScript(data.songwriters.join(', ')) ? 'Roboto' : 'Heavy',
                                fontFamilyFallback: hasComplexScript(data.songwriters.join(', ')) ? null : kGlobalFontFallbacks,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: data.timingType == LyricsTimingType.none ? 28 : 18,
                    vertical: data.timingType == LyricsTimingType.none ? 0 : 140,
                  ),
                  sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, displayIndex) {
                      final itemValue = _displayItems[displayIndex];

                      if (itemValue < 0) {
                        int interludeIdx = 0;
                        for (int d = 0; d < displayIndex; d++) {
                          if (_displayItems[d] < 0) interludeIdx++;
                        }
                        return KeyedSubtree(
                          key: _lineKeys[displayIndex],
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: data.timingType == LyricsTimingType.none ? 0 : 10,
                            ),
                            child: RepaintBoundary(
                              child: _DominoWaveItem(
                                controller: _waveController,
                                displayIndex: displayIndex,
                                focusDisplayIndex: _focusDisplayIndex,
                                enabled: data.timingType != LyricsTimingType.none &&
                                    !_startupSettling &&
                                    !_firstScroll,
                                child: RepaintBoundary(
                                  child: _InterludeDots(
                                    smoothSeconds: _smoothSeconds,
                                    gapStart: _interludeStarts[interludeIdx],
                                    gapEnd: _interludeEnds[interludeIdx],
                                    service: widget.service,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final lineIndex = itemValue;
                      final line = data.lines[lineIndex];
                      final isActive = _activeIndices.contains(lineIndex);
                      final isFocused = lineIndex == _focusIndex;
                      final distance = _focusDisplayIndex >= 0 ? (displayIndex - _focusDisplayIndex).abs() : 0;
                      
                      final blurSigma = (data.timingType != LyricsTimingType.none && _isAutoLocked && !_startupSettling && !_firstScroll && !isActive) 
                          ? distance.toDouble() * 2.5 
                          : 0.0;
                      final clampedBlur = blurSigma.clamp(0.0, 8.0);
                        final edgeFade = (_isAutoLocked && !_startupSettling && !_firstScroll)
                          ? (1.0 - (distance / 15.0)).clamp(0.0, 1.0)
                          : 1.0;

                      Widget buildLine(_LinePhase phase) {
                        final double targetOpacity;
                        switch (phase) {
                          case _LinePhase.active:
                            targetOpacity = line.isBackground ? 0.88 : 1.0;
                            break;
                          case _LinePhase.upcoming:
                            targetOpacity = (line.isBackground ? 0.34 : 0.48) * edgeFade;
                            break;
                          case _LinePhase.future:
                            targetOpacity = (line.isBackground ? 0.20 : 0.32) * edgeFade;
                            break;
                          case _LinePhase.past:
                            targetOpacity = (line.isBackground ? 0.16 : 0.22) * edgeFade;
                            break;
                        }

                        return KeyedSubtree(
                          key: _lineKeys[displayIndex],
                          child: RepaintBoundary(
                            child: _DominoWaveItem(
                              controller: _waveController,
                              displayIndex: displayIndex,
                              focusDisplayIndex: _focusDisplayIndex,
                              enabled: data.timingType != LyricsTimingType.none &&
                                  !_startupSettling &&
                                  !_firstScroll,
                              child: RepaintBoundary(
                                child: _PressableLyricLine(
                                  enabled: data.timingType != LyricsTimingType.none,
                                  onTap: () {
                                    if (data.timingType == LyricsTimingType.none) return;

                                    HapticFeedback.selectionClick();
                                    widget.onLyricsInteraction();
                                    widget.service.notifyUserInteraction();
                                    widget.service.seekTo(
                                      Duration(milliseconds: (line.startTime * 1000).toInt()),
                                    );
                                  },
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                    opacity: targetOpacity,
                                    child: AnimatedScale(
                                      scale: (!_startupSettling && isFocused && !line.isBackground)
                                          ? 1.045
                                          : (line.isBackground && phase == _LinePhase.active
                                              ? 1.0
                                              : (line.isBackground ? 0.96 : 1.0)),
                                      alignment: line.alignment == LyricsLineAlignment.right
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      duration: const Duration(milliseconds: 420),
                                      curve: Curves.easeOutCubic,
                                      child: Padding(
                                          padding: EdgeInsets.only(
                                            top: isFocused && !line.isBackground ? 2.0 : (data.timingType == LyricsTimingType.none ? 8.0 : 0.0),
                                            bottom: isFocused && !line.isBackground ? 8.0 : (data.timingType == LyricsTimingType.none ? 8.0 : 2.0),
                                          ),
                                        child: Builder(builder: (context) {
                                          final innerLine = ValueListenableBuilder<bool>(
                                            valueListenable: SettingsService().romanizationEnabled,
                                            builder: (context, romanize, _) {
                                              final effectiveText = (romanize && line.transliteratedText != null)
                                                  ? line.transliteratedText!
                                                  : line.text;
                                              
                                              // If timing is 'none', we use a smaller, static style
                                              if (data.timingType == LyricsTimingType.none) {
                                                return ValueListenableBuilder<double>(
                                                  valueListenable: SettingsService().lyricsFontSize,
                                                  builder: (context, fontSize, _) {
                                                    final staticSize =
                                                        (line.isBackground ? fontSize * 0.8 : fontSize) * 0.8;
                                                    return Align(
                                                      alignment: line.alignment == LyricsLineAlignment.right
                                                          ? Alignment.centerRight
                                                          : Alignment.centerLeft,
                                                      child: material.Text(
                                                        effectiveText,
                                                        textAlign: line.alignment == LyricsLineAlignment.right
                                                            ? TextAlign.right
                                                            : TextAlign.left,
                                                        style: _lyricTextStyle(
                                                          text: effectiveText,
                                                          fontSize: staticSize,
                                                          color: Colors.white.withValues(alpha: 0.95),
                                                          height: 1.45,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                );
                                              }

                                              // If romanized text is being used, we check if word-level transliterations exist.
                                              // If the line has word timing, we animate it word-by-word.
                                              if (line.hasWordTiming && isActive) {
                                                // This is the line that rebuilds and repaints every frame, so it is
                                                // the one that needs the boundary — otherwise its layer is merged with
                                                // the ancestors (blur, background) and drags them into every repaint.
                                                return RepaintBoundary(
                                                  child: _ActiveWordLine(
                                                    line: line,
                                                    smoothSeconds: _smoothSeconds,
                                                    romanize: romanize,
                                                  ),
                                                );
                                              } else {
                                                return RepaintBoundary(
                                                  child: line.hasWordTiming
                                                    ? _ActiveWordLine(
                                                        line: line, 
                                                        smoothSeconds: _smoothSeconds,
                                                        romanize: romanize,
                                                      )
                                                    : _StaticLine(line: line, text: effectiveText),
                                                );
                                              }
                                            },
                                          );

                                          return TweenAnimationBuilder<double>(
                                            tween: Tween<double>(begin: clampedBlur, end: clampedBlur),
                                            duration: const Duration(milliseconds: 340),
                                            curve: Curves.easeOutCubic,
                                            builder: (context, blurValue, child) {
                                              if (blurValue <= 0.1) return child!;
                                              return ImageFiltered(
                                                imageFilter: ui.ImageFilter.blur(
                                                  sigmaX: blurValue,
                                                  sigmaY: blurValue,
                                                ),
                                                child: child!,
                                              );
                                            },
                                            child: innerLine,
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return _LitLine(
                        position: _smoothSeconds,
                        timingType: data.timingType,
                        startTime: line.startTime,
                        endTime: line.endTime,
                        builder: buildLine,
                      );
                    },
                    childCount: _displayItems.length,
                  ),
                ),
              ),
              if (data.songwriters.isNotEmpty && data.timingType != LyricsTimingType.none)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 28.0, right: 28.0, bottom: 60.0),
                    child: RichText(
                      textAlign: TextAlign.left,
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 15,
                        ),
                        children: [
                          const TextSpan(
                            text: 'WRITTEN BY: ',
                            style: TextStyle(
                              fontFamily: 'Heavy', fontFamilyFallback: kGlobalFontFallbacks,
                              fontWeight: FontWeight(1000),
                              letterSpacing: 0.3,
                            ),
                          ),
                          TextSpan(
                            text: data.songwriters.join(', ').toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
              // Seek Indicator Overlay
              if (_showSeekIndicator)
                IgnorePointer(
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 200),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.scale(
                            scale: 0.8 + (value * 0.2),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _seekDelta > 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                            const SizedBox(height: 4),
                            material.Text(
                              '${_seekDelta > 0 ? '+' : ''}$_seekDelta',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveWordLine extends StatefulWidget {
  final LyricsLine line;
  final ValueNotifier<double> smoothSeconds;
  final bool romanize;

  const _ActiveWordLine({
    required this.line,
    required this.smoothSeconds,
    this.romanize = false,
  });

  @override
  State<_ActiveWordLine> createState() => _ActiveWordLineState();
}

class _WordSyllableGroup {
  final String text;
  final double startTime;
  final double endTime;
  final List<({double startTime, double endTime, double weight})> syllables;

  const _WordSyllableGroup({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.syllables,
  });

  double progressAt(double sec) {
    if (sec >= endTime) return 1.0;
    if (sec <= startTime) return 0.0;

    if (syllables.length == 1) {
      final dur = endTime - startTime;
      return dur > 0.01 ? ((sec - startTime) / dur).clamp(0.0, 1.0) : 1.0;
    }

    double total = 0.0;
    for (final s in syllables) {
      if (sec >= s.endTime) {
        total += s.weight;
      } else if (sec > s.startTime) {
        final dur = s.endTime - s.startTime;
        final p = dur > 0.01 ? ((sec - s.startTime) / dur).clamp(0.0, 1.0) : 1.0;
        total += s.weight * p;
      }
    }
    return total.clamp(0.0, 1.0);
  }
}

class _ActiveWordLineState extends State<_ActiveWordLine> {
  int _lastVibratedWordIndex = -1;
  bool _isWordVibrating = false;
  int _windowState = -2;
  double _renderedSec = 0.0;
  late List<_WordSyllableGroup> _wordGroups;

  double get _windowStart => widget.line.startTime - 0.12;

  double get _windowEnd {
    final lastWordLiftEnd = _wordGroups.isNotEmpty
        ? _wordGroups.last.startTime + KaraokeTextFill.liftSpanSeconds + 0.70
        : widget.line.endTime + 0.5;
    final lineTailEnd = widget.line.endTime + 0.5;
    return lineTailEnd > lastWordLiftEnd ? lineTailEnd : lastWordLiftEnd;
  }

  int _computeWindowState(double sec) {
    if (sec < _windowStart) return -1;
    if (sec <= _windowEnd) return 0;
    return 1;
  }

  List<_WordSyllableGroup> _buildWordGroups() {
    final useTranslit = widget.romanize &&
        widget.line.transliteratedWords != null &&
        widget.line.transliteratedWords!.isNotEmpty;
    final source =
        useTranslit ? widget.line.transliteratedWords! : widget.line.words;
    if (source.isEmpty) return const [];

    String wordText(LyricsWord w) =>
        (widget.romanize && w.transliteratedText != null)
            ? w.transliteratedText!
            : w.text;

    final groups = <_WordSyllableGroup>[];
    final current = <LyricsWord>[];

    void flushGroup() {
      if (current.isEmpty) return;
      final texts = current.map(wordText).toList();
      final fullText = texts.join();
      final trimmedLengths =
          texts.map((t) => t.trimRight().length.clamp(1, 999)).toList();
      final totalChars = trimmedLengths.fold<int>(0, (a, b) => a + b);

      final syllables = <({double startTime, double endTime, double weight})>[
        for (int i = 0; i < current.length; i++)
          (
            startTime: current[i].startTime,
            endTime: current[i].endTime,
            weight: totalChars > 0 ? trimmedLengths[i] / totalChars : 1.0 / current.length,
          ),
      ];

      groups.add(
        _WordSyllableGroup(
          text: fullText,
          startTime: current.first.startTime,
          endTime: current.last.endTime,
          syllables: syllables,
        ),
      );
      current.clear();
    }

    for (final w in source) {
      final t = wordText(w);
      current.add(w);
      // Only merge consecutive syllable spans that have no trailing whitespace.
      if (t != t.trimRight()) {
        flushGroup();
      }
    }
    flushGroup();
    return groups;
  }

  @override
  void initState() {
    super.initState();
    _wordGroups = _buildWordGroups();
    _renderedSec = widget.smoothSeconds.value;
    _windowState = _computeWindowState(_renderedSec);
    widget.smoothSeconds.addListener(_handleSecondsChange);
  }

  @override
  void didUpdateWidget(_ActiveWordLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line || oldWidget.romanize != widget.romanize) {
      _lastVibratedWordIndex = -1;
      _wordGroups = _buildWordGroups();
      _renderedSec = widget.smoothSeconds.value;
      _windowState = _computeWindowState(_renderedSec);
    }
    if (oldWidget.smoothSeconds != widget.smoothSeconds) {
      oldWidget.smoothSeconds.removeListener(_handleSecondsChange);
      widget.smoothSeconds.addListener(_handleSecondsChange);
      _renderedSec = widget.smoothSeconds.value;
      _windowState = _computeWindowState(_renderedSec);
    }
  }

  @override
  void dispose() {
    widget.smoothSeconds.removeListener(_handleSecondsChange);
    super.dispose();
  }

  void _handleSecondsChange() {
    if (!mounted) return;
    final sec = widget.smoothSeconds.value;
    final nextState = _computeWindowState(sec);

    if (nextState == 0 || nextState != _windowState) {
      setState(() {
        _windowState = nextState;
        _renderedSec = sec;
      });
    }

    final settings = SettingsService();
    if (!settings.hapticLyricsEnabled.value || !settings.wordToWordHapticsEnabled.value) return;

    int activeIdx = -1;
    for (int i = 0; i < widget.line.words.length; i++) {
      if (sec >= widget.line.words[i].startTime && sec < widget.line.words[i].endTime) {
        activeIdx = i;
        break;
      }
    }

    if (activeIdx != -1 && activeIdx != _lastVibratedWordIndex) {
      _lastVibratedWordIndex = activeIdx;
      _triggerWordHaptic(widget.line.words[activeIdx]);
    }
  }

  Future<void> _triggerWordHaptic(LyricsWord word) async {
    if (!supportsHaptics) return;

    if (_isWordVibrating) {
      Vibration.cancel();
    }
    _isWordVibrating = true;
    
    final durationMs = ((word.endTime - word.startTime) * 1000).toInt();
    if (durationMs <= 20) {
      _isWordVibrating = false;
      return;
    }

    // We split the word duration into several segments of increasing intensity
    const steps = 5;
    final stepDur = (durationMs / steps).floor();
    if (stepDur < 12) return; // Too short for a ramp

    final settings = SettingsService();
    final globalIntensity = settings.hapticIntensity.value;
    
    // If intensity is very low, skip to save battery/cycles
    if (globalIntensity < 0.05) {
      _isWordVibrating = false;
      return;
    }

    // Smart Scaling: Use a power curve (1.5) so that low slider values 
    // feel significantly weaker, while high values stay powerful.
    final curvedIntensity = globalIntensity * globalIntensity; // squared for better low-end control

    for (int i = 1; i <= steps; i++) {
      // Re-read intensity in case it changed mid-word
      final currentGlobal = settings.hapticIntensity.value;
      final currentCurve = currentGlobal * currentGlobal;
      
      // Smart Ramp: Scale both the starting point and the peak.
      // At low slider values, the 'start' becomes very faint (near 0).
      final startFloor = 20 * currentCurve; 
      final peakCeiling = 255 * currentCurve;
      
      final baseIntensity = startFloor + (peakCeiling - startFloor) * (i / steps);
      final intensity = baseIntensity.toInt().clamp(0, 255);
      
      // If the hardware doesn't support amplitude, we can't do much, 
      // but individual calls with amplitude are the most compatible way.
      Vibration.vibrate(duration: stepDur, amplitude: intensity);
      
      await Future.delayed(Duration(milliseconds: stepDur));
    }
    
    _isWordVibrating = false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();
    final alignment = widget.line.alignment == LyricsLineAlignment.right
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return ValueListenableBuilder<double>(
      valueListenable: settings.lyricsFontSize,
      builder: (context, fontSize, _) {
        final effectiveFontSize = widget.line.isBackground ? fontSize * 0.8 : fontSize;

        Widget buildWrap(double lineSeconds) {
          // Each word creeps up over a fixed span and then stays there —
          // sung words sit above the line, unsung words stay on the baseline.
          // The span is deliberately much longer than a single word: the lift
          // keeps resolving across the words that follow, which is what gives
          // the slow drift rather than a per-word pop. Letter-by-letter runs
          // take the same rule inside KaraokeTextFill and apply it per letter.
          const liftDistance = KaraokeTextFill.liftDistance;
          const liftSpanSeconds = KaraokeTextFill.liftSpanSeconds;

          return Wrap(
            alignment: widget.line.alignment == LyricsLineAlignment.right
                ? WrapAlignment.end
                : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 0,
            runSpacing: 4,
            children: _wordGroups.map((group) {
              final dur = group.endTime - group.startTime;
              final progress = group.progressAt(lineSeconds);

              final isLongHold = dur >= 1.0;
              final liftProgress =
                  ((lineSeconds - group.startTime) / liftSpanSeconds)
                      .clamp(0.0, 1.0);
              final liftOffset = -liftDistance *
                  (isLongHold ? Curves.easeInOutCubic : Curves.easeOutCubic)
                      .transform(liftProgress);

              return KaraokeTextFill(
                text: group.text,
                progress: progress,
                longHold: isLongHold,
                elapsedSeconds: lineSeconds - group.startTime,
                wordDuration: dur,
                liftOffset: liftOffset,
                style: _lyricTextStyle(
                  text: group.text,
                  fontSize: effectiveFontSize,
                ),
              );
            }).toList(),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            top: widget.line.isBackground ? 0 : 16,
            bottom: widget.line.isBackground ? 4 : 16,
          ),
          child: Align(
            alignment: alignment,
            child: buildWrap(_renderedSec),
          ),
        );
      },
    );
  }
}

enum _LinePhase { past, upcoming, future, active }

/// Rebuilds a lyric line only when its phase ([_LinePhase]) flips.
class _LitLine extends StatefulWidget {
  final ValueListenable<double> position;
  final LyricsTimingType timingType;
  final double startTime;
  final double endTime;
  final Widget Function(_LinePhase phase) builder;

  const _LitLine({
    required this.position,
    required this.timingType,
    required this.startTime,
    required this.endTime,
    required this.builder,
  });

  @override
  State<_LitLine> createState() => _LitLineState();
}

class _LitLineState extends State<_LitLine> {
  late _LinePhase _phase;

  @override
  void initState() {
    super.initState();
    _phase = _compute();
    widget.position.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(_LitLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime ||
        oldWidget.endTime != widget.endTime ||
        oldWidget.timingType != widget.timingType) {
      _phase = _compute();
    }
    if (!identical(oldWidget.position, widget.position)) {
      oldWidget.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    super.dispose();
  }

  _LinePhase _compute() {
    if (widget.timingType == LyricsTimingType.none) return _LinePhase.active;
    final sec = widget.position.value;
    if (sec >= widget.startTime && sec <= widget.endTime) {
      return _LinePhase.active;
    }
    if (sec > widget.endTime) return _LinePhase.past;
    if (sec >= widget.startTime - 0.35) return _LinePhase.upcoming;
    return _LinePhase.future;
  }

  void _onPosition() {
    if (!mounted) return;
    final next = _compute();
    if (next == _phase) return;
    setState(() => _phase = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(_phase);
}

class _PressableLyricLine extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  const _PressableLyricLine({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  @override
  State<_PressableLyricLine> createState() => _PressableLyricLineState();
}

class _PressableLyricLineState extends State<_PressableLyricLine> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _StaticLine extends StatelessWidget {
  final LyricsLine line;
  final String? text;

  const _StaticLine({
    required this.line,
    this.text,
  });

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();
    final alignment = line.alignment == LyricsLineAlignment.right
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return ValueListenableBuilder<double>(
      valueListenable: settings.lyricsFontSize,
      builder: (context, fontSize, _) {
        final effectiveFontSize = line.isBackground ? fontSize * 0.8 : fontSize;
        final content = text ?? line.text;

        return Padding(
          padding: EdgeInsets.only(
            top: line.isBackground ? 0 : 16,
            bottom: line.isBackground ? 4 : 16,
          ),
          child: Align(
            alignment: alignment,
            child: material.Text(
              content,
              textAlign: line.alignment == LyricsLineAlignment.right
                  ? TextAlign.right
                  : TextAlign.left,
              style: _lyricTextStyle(
                text: content,
                fontSize: effectiveFontSize,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

TextStyle _lyricTextStyle({
  required String text,
  required double fontSize,
  Color? color,
  double? height,
}) {
  final complex = hasComplexScript(text);
  return TextStyle(
    fontFamily: complex ? 'Roboto' : 'Heavy',
    fontFamilyFallback: complex ? null : kGlobalFontFallbacks,
    fontSize: fontSize,
    fontWeight: const FontWeight(1000),
    letterSpacing: -0.6,
    color: color,
    height: height,
  );
}

class _InterludeDots extends StatefulWidget {
  final ValueNotifier<double> smoothSeconds;
  final double gapStart;
  final double gapEnd;
  final MediaSessionService service;

  const _InterludeDots({
    required this.smoothSeconds,
    required this.gapStart,
    required this.gapEnd,
    required this.service,
  });

  @override
  State<_InterludeDots> createState() => _InterludeDotsState();
}

class _InterludeDotsState extends State<_InterludeDots> {
  bool _inGap = false;
  double _sec = 0.0;

  @override
  void initState() {
    super.initState();
    _sec = widget.smoothSeconds.value;
    _inGap = _isInGap(_sec);
    widget.smoothSeconds.addListener(_onSeconds);
  }

  @override
  void didUpdateWidget(_InterludeDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.smoothSeconds, widget.smoothSeconds)) {
      oldWidget.smoothSeconds.removeListener(_onSeconds);
      widget.smoothSeconds.addListener(_onSeconds);
    }
    _sec = widget.smoothSeconds.value;
    _inGap = _isInGap(_sec);
  }

  @override
  void dispose() {
    widget.smoothSeconds.removeListener(_onSeconds);
    super.dispose();
  }

  bool _isInGap(double s) => s >= widget.gapStart && s < widget.gapEnd;

  void _onSeconds() {
    if (!mounted) return;
    final nextSec = widget.smoothSeconds.value;
    final nextInGap = _isInGap(nextSec);
    if (nextInGap || nextInGap != _inGap) {
      setState(() {
        _sec = nextSec;
        _inGap = nextInGap;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_inGap) return const SizedBox.shrink();
    const fadeDuration = 0.45;

    return ValueListenableBuilder<bool>(
      valueListenable: widget.service.userInteractingNotifier,
      builder: (context, isInteracting, child) {
        if (isInteracting) return const SizedBox.shrink();

        final gapDuration = widget.gapEnd - widget.gapStart;
        if (gapDuration <= 0) return const SizedBox.shrink();

        final fadeInEnd = widget.gapStart + fadeDuration;
        final fadeOutStart = widget.gapEnd - fadeDuration;
        final animStart = fadeInEnd;
        final animEnd = fadeOutStart;

        double opacity;
        if (_sec < fadeInEnd) {
          opacity = ((_sec - widget.gapStart) / fadeDuration).clamp(0.0, 1.0);
        } else if (_sec > fadeOutStart) {
          opacity = ((widget.gapEnd - _sec) / fadeDuration).clamp(0.0, 1.0);
        } else {
          opacity = 1.0;
        }

        const maxHeight = 56.0;
        final easedOpacity = Curves.easeInOutCubic.transform(opacity);
        final height = maxHeight * easedOpacity;

        final animDuration = animEnd - animStart;
        final animProgress = animDuration > 0
            ? ((_sec - animStart) / animDuration).clamp(0.0, 1.0)
            : 0.0;

        return SizedBox(
          height: height,
          child: Opacity(
            opacity: easedOpacity,
            child: Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final dotThreshold = i / 3.0;
                    final dotBrightness =
                        ((animProgress - dotThreshold) / 0.33).clamp(0.0, 1.0);
                    final lit = Curves.easeOutCubic.transform(dotBrightness);

                    // Breathing pulse as each dot lights + subtle floating wave.
                    final pulse = math.sin(lit * math.pi) * 0.16;
                    final dotScale = 0.88 + 0.14 * lit + pulse;
                    final bobY =
                        math.sin((_sec * 2.6) - (i * 0.9)) * 1.8 * opacity;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5.0),
                      child: Transform.translate(
                        offset: Offset(0, bobY),
                        child: Transform.scale(
                          scale: dotScale,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  Colors.white.withValues(alpha: 0.18 + 0.82 * lit),
                              boxShadow: lit > 0.2
                                  ? [
                                      BoxShadow(
                                        color: Colors.white.withValues(
                                          alpha: 0.35 * lit * easedOpacity,
                                        ),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CinematicScrollPhysics extends BouncingScrollPhysics {
  const CinematicScrollPhysics({super.parent});

  @override
  CinematicScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CinematicScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double carriedMomentum(double existingVelocity) {
    return super.carriedMomentum(existingVelocity) * 1.15;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final inBounds = position.pixels >= position.minScrollExtent &&
        position.pixels <= position.maxScrollExtent;
    final boostedVelocity = inBounds && velocity.abs() > minFlingVelocity
        ? velocity * 1.18
        : velocity;
    return super.createBallisticSimulation(position, boostedVelocity);
  }

  // Weighty, damped overscroll spring for an Apple-like plush bounce.
  @override
  SpringDescription get spring => const SpringDescription(
        mass: 1.25,
        stiffness: 110.0,
        damping: 22.0,
      );
}

/// Tracks recent auto-scroll offsets so lines below the active focus can trail
/// slightly behind in a domino/wave ripple without touching layout or blur.
class _LyricsWaveController extends ChangeNotifier {
  static const double staggerPerLine = 0.036;
  static const int maxWaveLines = 7;
  static const double _maxDelaySec = staggerPerLine * maxWaveLines;
  static const double _maxHistorySec = _maxDelaySec + 0.25;
  static const double _maxPosAmp = 34.0;
  static const double _maxNegAmp = 16.0;

  final ScrollController _scrollController;
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch()..start();
  final List<({double time, double offset})> _samples = [];

  bool _enabled = true;
  bool _disposed = false;
  double _gain = 1.0;
  double _lastTickTime = 0.0;
  double _lastScrollMoveTime = 0.0;
  double _lastRecordedOffset = 0.0;

  _LyricsWaveController({
    required ScrollController scrollController,
    required TickerProvider vsync,
  }) : _scrollController = scrollController {
    _scrollController.addListener(_onScroll);
    _ticker = vsync.createTicker(_onTick);
  }

  bool get isIdle => _samples.isEmpty || !_ticker.isActive;

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    final now = _clock.elapsedMicroseconds / 1e6;
    if (!enabled) {
      if (_samples.isNotEmpty && _gain > 0.001 && !_ticker.isActive) {
        _lastTickTime = now;
        _ticker.start();
      }
    } else if (_samples.isEmpty) {
      _gain = 1.0;
    }
  }

  void reset() {
    if (_disposed) return;
    final hadSamples = _samples.isNotEmpty;
    _samples.clear();
    if (_ticker.isActive) _ticker.stop();
    _lastRecordedOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    _gain = _enabled ? 1.0 : 0.0;
    if (hadSamples &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      notifyListeners();
    }
  }

  void _onScroll() {
    if (_disposed || !_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final now = _clock.elapsedMicroseconds / 1e6;

    if (!_enabled) {
      _lastRecordedOffset = offset;
      return;
    }

    if ((offset - _lastRecordedOffset).abs() < 0.05) return;

    if (_samples.isEmpty) {
      _samples.add((time: now - _maxHistorySec, offset: _lastRecordedOffset));
      _gain = 1.0;
    }

    if (_samples.isNotEmpty && now - _samples.last.time < 0.001) {
      _samples[_samples.length - 1] = (time: now, offset: offset);
    } else {
      _samples.add((time: now, offset: offset));
    }

    _lastScrollMoveTime = now;
    _lastRecordedOffset = offset;
    _prune(now);

    if (!_ticker.isActive) {
      _lastTickTime = now;
      _ticker.start();
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.transientCallbacks) {
      notifyListeners();
    }
  }

  void _onTick(Duration _) {
    if (_disposed) return;
    final now = _clock.elapsedMicroseconds / 1e6;
    final dt = (now - _lastTickTime).clamp(0.0, 0.05);
    _lastTickTime = now;

    if (!_enabled) {
      _gain = (_gain - dt * 8.0).clamp(0.0, 1.0);
    } else if (_gain < 1.0) {
      _gain = (_gain + dt * 8.0).clamp(0.0, 1.0);
    }

    if (_enabled && _scrollController.hasClients && _samples.isNotEmpty) {
      final offset = _scrollController.offset;
      if ((offset - _lastRecordedOffset).abs() >= 0.05) {
        _lastScrollMoveTime = now;
        _lastRecordedOffset = offset;
      }
      if (now - _samples.last.time >= 0.001) {
        _samples.add((time: now, offset: offset));
      } else {
        _samples[_samples.length - 1] = (time: now, offset: offset);
      }
    }

    const settleWindow = _maxDelaySec + 0.08;
    if (_samples.isEmpty ||
        (!_enabled && _gain <= 0.001) ||
        (_enabled && now - _lastScrollMoveTime > settleWindow)) {
      _samples.clear();
      _ticker.stop();
      if (_enabled) _gain = 1.0;
      notifyListeners();
      return;
    }

    _prune(now);
    notifyListeners();
  }

  void _prune(double now) {
    final cutoff = now - _maxHistorySec;
    while (_samples.length > 2 && _samples[1].time <= cutoff) {
      _samples.removeAt(0);
    }
  }

  double offsetForDelay(double delaySec) {
    if (_samples.isEmpty || delaySec <= 0.0001 || _gain <= 0.001) {
      return 0.0;
    }
    final now = _clock.elapsedMicroseconds / 1e6;
    final currentOffset = _samples.last.offset;
    final pastOffset = _sampleAt(now - delaySec);
    final rawDelta = currentOffset - pastOffset;
    if (rawDelta.abs() < 0.05) return 0.0;

    final limit = rawDelta >= 0 ? _maxPosAmp : _maxNegAmp;
    final saturated = (limit * rawDelta) / (limit + rawDelta.abs());
    return saturated * _gain;
  }

  double _sampleAt(double targetTime) {
    if (targetTime <= _samples.first.time) return _samples.first.offset;
    if (targetTime >= _samples.last.time) return _samples.last.offset;

    for (int i = _samples.length - 2; i >= 0; i--) {
      final a = _samples[i];
      if (a.time <= targetTime) {
        final b = _samples[i + 1];
        final span = b.time - a.time;
        final t = span > 1e-6 ? (targetTime - a.time) / span : 1.0;
        return ui.lerpDouble(a.offset, b.offset, t)!;
      }
    }
    return _samples.first.offset;
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.removeListener(_onScroll);
    _ticker.dispose();
    _samples.clear();
    super.dispose();
  }
}

/// Applies the GPU-only vertical wave offset for a single lyrics item.
class _DominoWaveItem extends StatefulWidget {
  final _LyricsWaveController controller;
  final int displayIndex;
  final int focusDisplayIndex;
  final bool enabled;
  final Widget child;

  const _DominoWaveItem({
    required this.controller,
    required this.displayIndex,
    required this.focusDisplayIndex,
    required this.enabled,
    required this.child,
  });

  @override
  State<_DominoWaveItem> createState() => _DominoWaveItemState();
}

class _DominoWaveItemState extends State<_DominoWaveItem> {
  double _dy = 0.0;
  double _effectiveDelay = 0.0;

  double get _targetDelay {
    if (!widget.enabled || widget.focusDisplayIndex < 0) return 0.0;
    final delta = widget.displayIndex - widget.focusDisplayIndex;
    if (delta <= 0) return 0.0;
    final clamped = delta > _LyricsWaveController.maxWaveLines
        ? _LyricsWaveController.maxWaveLines
        : delta;
    return clamped * _LyricsWaveController.staggerPerLine;
  }

  @override
  void initState() {
    super.initState();
    _effectiveDelay = _targetDelay;
    _dy = _computeDy();
    widget.controller.addListener(_onWaveTick);
  }

  @override
  void didUpdateWidget(_DominoWaveItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onWaveTick);
      widget.controller.addListener(_onWaveTick);
    }
    if (widget.controller.isIdle) {
      _effectiveDelay = _targetDelay;
      _dy = 0.0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onWaveTick);
    super.dispose();
  }

  double _computeDy() {
    if (_effectiveDelay <= 0.0005) return 0.0;
    final next = widget.controller.offsetForDelay(_effectiveDelay);
    return next.abs() < 0.05 ? 0.0 : next;
  }

  void _onWaveTick() {
    if (!mounted) return;
    final target = _targetDelay;
    if (widget.controller.isIdle) {
      _effectiveDelay = target;
    } else {
      _effectiveDelay += (target - _effectiveDelay) * 0.35;
      if ((target - _effectiveDelay).abs() < 0.001) {
        _effectiveDelay = target;
      }
    }

    final nextDy = _computeDy();
    if ((nextDy - _dy).abs() >= 0.05 || (nextDy == 0.0 && _dy != 0.0)) {
      setState(() => _dy = nextDy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0.0, _dy),
      child: widget.child,
    );
  }
}
