import 'dart:ui' as ui;
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:vibration/vibration.dart';
import '../services/lyrics_models.dart';
import '../services/media_session_service.dart';
import 'karaoke_text_fill.dart';
import '../services/settings_service.dart';

class LyricsView extends StatefulWidget {
  final String trackKey;
  final LyricsData? lyricsData;
  final Duration position;
  final Duration duration;
  final bool isLoading;
  final String? errorMessage;
  final MediaSessionService service;
  final VoidCallback onLyricsInteraction;

  const LyricsView({
    super.key,
    required this.trackKey,
    this.lyricsData,
    required this.position,
    required this.duration,
    required this.service,
    required this.onLyricsInteraction,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  State<LyricsView> createState() => LyricsViewState();
}

class LyricsViewState extends State<LyricsView> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  List<int> _activeIndices = [];
  int _focusIndex = -1;
  int _focusDisplayIndex = -1;
  
  final ValueNotifier<double> _smoothSeconds = ValueNotifier<double>(0.0);
  bool _scrollQueued = false;
  bool _pendingScrollToTop = false;
  List<GlobalKey> _lineKeys = [];

  bool _isAutoLocked = true;
  bool _firstScroll = true;
  bool _startupSettling = false;
  bool _userIsTouching = false;
  bool _waitingForNewTrackLyrics = false;
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
    _smoothSeconds.value = widget.position.inMilliseconds / 1000.0;
    
    SemanticsBinding.instance.ensureSemantics();

    _initParallax();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculateFocus(_smoothSeconds.value);
    });
  }

  void _initParallax() {
    // Ticker runs every frame (60fps to 120fps depending on device)
    _ticker = createTicker((elapsed) {
      if (!SettingsService().parallaxEnabled.value) {
        if (_roll != 0 || _pitch != 0) {
          _roll = 0; _pitch = 0; _targetRoll = 0; _targetPitch = 0;
          _parallaxTransform.value = Matrix4.identity();
        }
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
    _ticker.start();

    _gyroSubscription = gyroscopeEventStream().listen((event) {
      if (!mounted || !SettingsService().parallaxEnabled.value) return;
      // Set the target, ticker handles the smooth transition
      _targetRoll = event.y;
      _targetPitch = event.x;
    });
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final trackChanged = widget.trackKey != oldWidget.trackKey;
    final lyricsChanged = widget.lyricsData != oldWidget.lyricsData;

    if (trackChanged || lyricsChanged) {
      if (trackChanged) {
        _waitingForNewTrackLyrics = true;
        _activeIndices = [];
        _focusIndex = -1;
        _focusDisplayIndex = -1;
        _smoothSeconds.value = widget.position.inMilliseconds / 1000.0;
        _firstScroll = true;
        _startupSettling = true;
        _isAutoLocked = true;
        _scrollQueued = false;
        _pendingScrollToTop = false;
        _searchAttempts = 0;
        
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
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
        _queueStartupFocusJump();
      }
    }

    if (_waitingForNewTrackLyrics) return;

    if (widget.position != oldWidget.position ||
        widget.duration != oldWidget.duration ||
        trackChanged) {
      _applyPosition(widget.position, widget.duration);
    }
  }

  void _queueStartupFocusJump() {
    _firstScroll = true;
    _startupSettling = true;
    _isAutoLocked = true;
    _searchAttempts = 0;

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
    _calculateFocus(_smoothSeconds.value);
    _scrollToFocusLine();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _gyroSubscription?.cancel();
    _smoothSeconds.dispose();
    _parallaxTransform.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyPosition(Duration position, Duration duration) {
    if (!mounted) return;

    final sec = position.inMilliseconds / 1000.0;

    // If the song is essentially over, scroll lyrics view to the top
    if (duration.inMilliseconds > 0) {
      final durationSec = duration.inMilliseconds / 1000.0;
      // within 250ms of end -> treat as finished
      if (sec >= durationSec - 0.25) {
        if (!_pendingScrollToTop) {
          _pendingScrollToTop = true;
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
            if (mounted) setState(() {});
          });
        }
        return;
      }
    }

    final data = widget.lyricsData;
    _smoothSeconds.value = sec;

    if (data == null || data.isEmpty) return;
    _calculateFocus(_smoothSeconds.value);
  }

  void _calculateFocus(double sec) {
    final data = widget.lyricsData;
    if (data == null || data.isEmpty) return;

    final newIndices = data.activeLineIndices(Duration(milliseconds: (sec * 1000).toInt()));

    int newFocus = -1;
    for (int i = 0; i < data.lines.length; i++) {
      // Look-ahead: Set focus to the next line 0.6s before it starts.
      if (data.lines[i].startTime <= sec + 0.6) {
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
            if (intensity > 10) {
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

    final targetOffset = viewport.getOffsetToReveal(renderObject, 0.35).offset;
    final currentOffset = _scrollController.offset;

    if ((currentOffset - targetOffset).abs() < 120.0) {
      if (!_isAutoLocked) {
        HapticFeedback.lightImpact();
        setState(() => _isAutoLocked = true);
      }
    }
  }

  void _triggerSeek(int seconds) {
    if (widget.lyricsData == null) return;
    
    widget.onLyricsInteraction();
    final currentPos = widget.position;
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
    final targetOffset = viewport.getOffsetToReveal(renderObject, 0.35).offset;
    final clampedOffset = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (_firstScroll) {
      _firstScroll = false;
      _isAutoLocked = true;
      _startupSettling = false;
      _scrollController.jumpTo(clampedOffset);
      return;
    }

    final distance = (_scrollController.offset - clampedOffset).abs();
    if (distance < 1.0) return;
    final durationMs = (distance * 3.5).clamp(700.0, 1600.0).toInt();

    _scrollController.animateTo(
      clampedOffset,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeOutQuart,
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
      onPointerDown: (_) => _userIsTouching = true,
      onPointerUp: (_) => _userIsTouching = false,
      onPointerCancel: (_) => _userIsTouching = false,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            if (_userIsTouching && notification.dragDetails != null && _isAutoLocked) {
              setState(() => _isAutoLocked = false);
            }
            if (!_isAutoLocked && notification.dragDetails != null) {
              _checkIfUserScrolledIntoRange();
              
              // NEW: Magnetic Haptic Scroll
              // Trigger a tiny click when a new line passes the center
              final centerOffset = _scrollController.offset + (_scrollController.position.viewportDimension * 0.35);
              int currentlyHoveredLine = -1;
              
              // Find which line is closest to the focus center
              if (widget.lyricsData != null) {
                // This is a simplified estimation for performance
                final approxIndex = (_displayItems.length * (centerOffset / _scrollController.position.maxScrollExtent)).toInt();
                currentlyHoveredLine = approxIndex.clamp(0, _displayItems.length - 1);
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
              physics: const BouncingScrollPhysics(),
              slivers: [
                if (data.timingType == LyricsTimingType.none && data.songwriters.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 28.0, right: 28.0, top: 140.0, bottom: 20.0),
                      child: material.Text(
                        'Written by: ${data.songwriters.join(', ')}',
                        style: TextStyle(
                          fontFamily: 'Display',
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 28, 
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
                          child: _InterludeDots(
                            smoothSeconds: _smoothSeconds,
                            gapStart: _interludeStarts[interludeIdx],
                            gapEnd: _interludeEnds[interludeIdx],
                            service: widget.service,
                          ),
                        );
                      }

                      final lineIndex = itemValue;
                      final line = data.lines[lineIndex];
                      final isActive = _activeIndices.contains(lineIndex);
                      final isFocused = lineIndex == _focusIndex;
                      final distance = _focusDisplayIndex >= 0 ? (displayIndex - _focusDisplayIndex).abs() : 0;
                      
                      final blurSigma = (data.timingType != LyricsTimingType.none && _isAutoLocked && !_startupSettling && !_firstScroll && distance > 1) 
                          ? (distance - 1).toDouble() * 2.5 
                          : 0.0;
                      final clampedBlur = blurSigma.clamp(0.0, 8.0);
                        final edgeFade = (_isAutoLocked && !_startupSettling && !_firstScroll)
                          ? (1.0 - (distance / 15.0)).clamp(0.0, 1.0)
                          : 1.0;

                      Widget buildLine(bool lit) {
                        return KeyedSubtree(
                          key: _lineKeys[displayIndex],
                          child: GestureDetector(
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
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              // LINE IS LIT if it is either Active (animating) OR Focused (centered)
                              opacity: (lit ? 1.0 : 0.2) * edgeFade,
                              child: AnimatedScale(
                                scale: (!_startupSettling && isFocused && !line.isBackground) ? 1.035 : 1.0,
                                alignment: line.alignment == LyricsLineAlignment.right
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                duration: const Duration(milliseconds: 520),
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
                                          return material.Text(
                                            effectiveText,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.95),
                                              fontSize: SettingsService().lyricsFontSize.value * 0.8,
                                              height: 1.6,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          );
                                        }

                                        // If romanized text is being used, we treat it as a static line
                                        // since we don't have word-level timings for the transliteration.
                                        if (line.hasWordTiming && isActive && (!romanize || line.transliteratedText == null)) {
                                          return _ActiveWordLine(
                                            line: line,
                                            smoothSeconds: _smoothSeconds,
                                          );
                                        } else {
                                          return RepaintBoundary(
                                            child: line.hasWordTiming && (!romanize || line.transliteratedText == null)
                                              ? _ActiveWordLine(
                                                  line: line, 
                                                  smoothSeconds: _smoothSeconds,
                                                )
                                              : _StaticLine(line: line, text: effectiveText),
                                          );
                                        }
                                      },
                                    );

                                    if (clampedBlur > 0.1) {
                                      return ImageFiltered(
                                        imageFilter: ui.ImageFilter.blur(
                                          sigmaX: clampedBlur,
                                          sigmaY: clampedBlur,
                                        ),
                                        child: innerLine,
                                      );
                                    }
                                    return innerLine;
                                  }),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return ValueListenableBuilder<double>(
                        valueListenable: _smoothSeconds,
                        builder: (context, lineSeconds, _) {
                          final isStarted = lineSeconds >= line.startTime;
                          final isEnded = lineSeconds > line.endTime;
                          // ONLY lit if the line has actually started and not yet ended.
                          // It will NO LONGER lit up early just because it is in focus.
                           // For untimed lyrics, keep all lines "lit up" at full opacity
                           final lit = (data.timingType == LyricsTimingType.none) ? true : (isStarted && !isEnded);
                           return buildLine(lit);
                        },
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
                    child: material.Text(
                      'WRITTEN BY: ${data.songwriters.join(', ').toUpperCase()}',
                      style: TextStyle(
                        fontFamily: 'Display',
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.left,
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

  const _ActiveWordLine({
    required this.line,
    required this.smoothSeconds,
  });

  @override
  State<_ActiveWordLine> createState() => _ActiveWordLineState();
}

class _ActiveWordLineState extends State<_ActiveWordLine> {
  int _lastVibratedWordIndex = -1;
  bool _isWordVibrating = false;

  @override
  void initState() {
    super.initState();
    widget.smoothSeconds.addListener(_handleSecondsChange);
  }

  @override
  void didUpdateWidget(_ActiveWordLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line) {
      _lastVibratedWordIndex = -1;
    }
    if (oldWidget.smoothSeconds != widget.smoothSeconds) {
      oldWidget.smoothSeconds.removeListener(_handleSecondsChange);
      widget.smoothSeconds.addListener(_handleSecondsChange);
    }
  }

  @override
  void dispose() {
    widget.smoothSeconds.removeListener(_handleSecondsChange);
    super.dispose();
  }

  void _handleSecondsChange() {
    if (!mounted) return;
    final settings = SettingsService();
    if (!settings.hapticLyricsEnabled.value || !settings.wordToWordHapticsEnabled.value) return;

    final sec = widget.smoothSeconds.value;
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
          return Wrap(
            alignment: widget.line.alignment == LyricsLineAlignment.right
                ? WrapAlignment.end
                : WrapAlignment.start,
            spacing: 0,
            runSpacing: 4,
            children: widget.line.words.map((word) {
              final dur = word.endTime - word.startTime;
              double progress;
              
              if (lineSeconds >= word.endTime) {
                progress = 1.0;
              } else if (lineSeconds >= word.startTime) {
                progress = dur > 0.01 ? (lineSeconds - word.startTime) / dur : 1.0;
              } else {
                progress = 0.0;
              }

              final isLongHold = dur >= 1.0;
              final liftProgress = ((lineSeconds - word.startTime) /
                      (isLongHold ? 3.2 : 2.7))
                  .clamp(0.0, 1.0);
              final liftOffset = -4.0 *
                  (isLongHold ? Curves.easeInOutCubic : Curves.easeOutCubic)
                      .transform(liftProgress);

              return Transform.translate(
                offset: Offset(0, liftOffset),
                child: KaraokeTextFill(
                  text: word.text,
                  progress: progress.clamp(0.0, 1.0),
                  longHold: isLongHold,
                  elapsedSeconds: lineSeconds - word.startTime,
                  wordDuration: dur,
                  style: TextStyle(
                    fontFamily: 'Display',
                    fontSize: effectiveFontSize,
                    fontWeight: FontWeight(1000),
                    letterSpacing: -0.6,
                  ),
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
            child: ValueListenableBuilder<double>(
              valueListenable: widget.smoothSeconds,
              builder: (context, lineSeconds, _) => buildWrap(lineSeconds),
            ),
          ),
        );
      },
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

        return Padding(
          padding: EdgeInsets.only(
            top: line.isBackground ? 0 : 16,
            bottom: line.isBackground ? 4 : 16,
          ),
          child: Align(
            alignment: alignment,
            child: material.Text(
              text ?? line.text,
              textAlign: line.alignment == LyricsLineAlignment.right
                  ? TextAlign.right
                  : TextAlign.left,
              style: TextStyle(
                fontFamily: 'Display',
                fontSize: effectiveFontSize,
                fontWeight: FontWeight(1000),
                letterSpacing: -0.6,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InterludeDots extends StatelessWidget {
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
  Widget build(BuildContext context) {
    const fadeDuration = 0.4;

    return ValueListenableBuilder<bool>(
      valueListenable: service.userInteractingNotifier,
      builder: (context, isInteracting, child) {
        if (isInteracting) return const SizedBox.shrink();
        
        return ValueListenableBuilder<double>(
          valueListenable: smoothSeconds,
          builder: (context, seconds, _) {
            final gapDuration = gapEnd - gapStart;
            if (gapDuration <= 0) return const SizedBox.shrink();

            final fadeInEnd = gapStart + fadeDuration;
            final fadeOutStart = gapEnd - fadeDuration;
            final animStart = fadeInEnd;
            final animEnd = fadeOutStart;

            if (seconds < gapStart || seconds >= gapEnd) {
              return const SizedBox.shrink();
            }

            double opacity;
            if (seconds < fadeInEnd) {
              opacity = ((seconds - gapStart) / fadeDuration).clamp(0.0, 1.0);
            } else if (seconds > fadeOutStart) {
              opacity = ((gapEnd - seconds) / fadeDuration).clamp(0.0, 1.0);
            } else {
              opacity = 1.0;
            }

            const maxHeight = 56.0;
            double height;
            if (seconds < fadeInEnd) {
              height = maxHeight * Curves.easeOutCubic.transform(opacity);
            } else if (seconds > fadeOutStart) {
              height = maxHeight * Curves.easeInCubic.transform(opacity);
            } else {
              height = maxHeight;
            }

            final animDuration = animEnd - animStart;
            final animProgress = animDuration > 0
                ? ((seconds - animStart) / animDuration).clamp(0.0, 1.0)
                : 0.0;

            return SizedBox(
              height: height,
              child: Opacity(
                opacity: Curves.easeOutCubic.transform(opacity),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final dotThreshold = i / 3.0;
                        final dotBrightness = ((animProgress - dotThreshold) / 0.33).clamp(0.0, 1.0);
                        final lit = Curves.easeOutCubic.transform(dotBrightness);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.15 + 0.85 * lit),
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
      },
    );
  }
}
