import 'package:simple_lyrics/core/font_fallbacks.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/media_state.dart';
import '../services/media_session_service.dart';

/// Floating playback controls overlay with modern glassmorphism.
class PlaybackControls extends StatefulWidget {
  final MediaState mediaState;
  final MediaSessionService service;
  final bool visible;
  final VoidCallback onInteraction;
  final ValueChanged<Duration> onPositionPreview;
  final ValueChanged<bool> onPositionPreviewing;
  final ValueNotifier<Duration> positionNotifier;

  final bool transparentBackground;

  const PlaybackControls({
    super.key,
    required this.mediaState,
    required this.service,
    required this.visible,
    required this.onInteraction,
    required this.onPositionPreview,
    required this.onPositionPreviewing,
    required this.positionNotifier,
    this.transparentBackground = false,
  });

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  double _smoothPositionMs = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _smoothPositionMs = widget.positionNotifier.value.inMilliseconds.toDouble();
  }

  @override
  void didUpdateWidget(PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final songChanged = widget.mediaState.title != oldWidget.mediaState.title ||
        widget.mediaState.artist != oldWidget.mediaState.artist;

    if (songChanged) {
      _smoothPositionMs = widget.positionNotifier.value.inMilliseconds.toDouble();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Widget content = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSeekBar(context),
            const SizedBox(height: 12),
            _buildMainControlsRow(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    content = Container(
      width: double.infinity,
      color: Colors.transparent,
      child: content,
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          child: content,
        ),
      ),
    );
  }

  Widget _buildSeekBar(BuildContext context) {
    final durationMs = widget.mediaState.duration.inMilliseconds.toDouble();
    final maxVal = durationMs > 0 ? durationMs : 1.0;

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.positionNotifier,
      builder: (context, visualPosition, _) {
        final positionMs = _isDragging
            ? _smoothPositionMs
            : visualPosition.inMilliseconds.toDouble();
        final currentVal = positionMs.clamp(0.0, maxVal);

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                trackShape: const RoundedRectSliderTrackShape(),
                thumbShape: SliderComponentShape.noThumb,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: currentVal,
                min: 0.0,
                max: maxVal,
                onChanged: (value) {
                  widget.onInteraction();
                  setState(() {
                    _isDragging = true;
                    _smoothPositionMs = value;
                  });
                  widget.onPositionPreviewing(true);
                  widget.onPositionPreview(Duration(milliseconds: value.toInt()));
                },
                onChangeEnd: (value) {
                  widget.onInteraction();
                  _isDragging = false;
                  widget.onPositionPreviewing(false);
                  widget.service.seekTo(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(Duration(milliseconds: currentVal.toInt())),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                    ),
                  ),
                  Text(
                    _formatDuration(widget.mediaState.duration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Display', fontFamilyFallback: kGlobalFontFallbacks,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMainControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TransportButton(
          type: 'previous',
          size: 32,
          onTap: () {
            widget.onInteraction();
            widget.service.previous();
          },
        ),
        const SizedBox(width: 40),
        _PlayPauseButton(
          isPlaying: widget.mediaState.isPlaying,
          onTap: () {
            widget.onInteraction();
            if (widget.mediaState.isPlaying) {
              widget.service.pause();
            } else {
              widget.service.play();
            }
          },
        ),
        const SizedBox(width: 40),
        _TransportButton(
          type: 'next',
          size: 32,
          onTap: () {
            widget.onInteraction();
            widget.service.next();
          },
        ),
      ],
    );
  }
}

class _TransportButton extends StatefulWidget {
  final String type;
  final double size;
  final VoidCallback onTap;

  const _TransportButton({
    required this.type,
    required this.size,
    required this.onTap,
  });

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _stretchAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120), // Fast enough to visibly stretch before finger lifts
      reverseDuration: const Duration(milliseconds: 400), // Slow and smooth recovery
    );
    
    // Animate from 1.0 (normal) to 1.6 (very noticeable horizontal stretch)
    _stretchAnimation = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutQuart),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapUp() {
    // If the user tapped very quickly, the animation might barely have started.
    // Ensure it stretches visibly before reversing.
    if (_pressController.value < 0.5) {
      _pressController.forward().then((_) {
        if (mounted) _pressController.reverse();
      });
    } else {
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    // If it's 'next', anchor on the left so it stretches forward to the right.
    // If it's 'previous', anchor on the right so it stretches backward to the left.
    final alignment = widget.type == 'next' ? Alignment.centerLeft : Alignment.centerRight;

    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _handleTapUp(),
      onTapCancel: () => _pressController.reverse(),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _stretchAnimation,
        builder: (context, child) {
          return Transform(
            transform: Matrix4.diagonal3Values(
              _stretchAnimation.value,
              1.0 - ((_stretchAnimation.value - 1.0) * 0.25), // vertical squish for physics feel
              1.0,
            ),
            alignment: alignment,
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: widget.type == 'next'
                ? SleekSkipNextPainter(color: Colors.white)
                : SleekSkipPreviousPainter(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.88).animate(
          CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1.0).animate(anim),
                  child: child,
                ),
              );
            },
            child: CustomPaint(
              key: ValueKey(widget.isPlaying),
              size: const Size(40, 40),
              painter: widget.isPlaying
                  ? SleekPausePainter(color: Colors.white)
                  : SleekPlayPainter(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom Sleek Painters

class SleekPlayPainter extends CustomPainter {
  final Color color;
  SleekPlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(size.width * 0.25, size.height * 0.15);
    path.lineTo(size.width * 0.85, size.height * 0.5);
    path.lineTo(size.width * 0.25, size.height * 0.85);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SleekPausePainter extends CustomPainter {
  final Color color;
  SleekPausePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;

    final w = size.width * 0.25;
    final r = Radius.circular(size.width * 0.1);
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(size.width * 0.15, size.height * 0.1, size.width * 0.15 + w, size.height * 0.9), r),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(size.width * 0.85 - w, size.height * 0.1, size.width * 0.85, size.height * 0.9), r),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SleekSkipNextPainter extends CustomPainter {
  final Color color;
  SleekSkipNextPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeJoin = StrokeJoin.round;

    final p1 = Path();
    p1.moveTo(size.width * 0.1, size.height * 0.2);
    p1.lineTo(size.width * 0.45, size.height * 0.5);
    p1.lineTo(size.width * 0.1, size.height * 0.8);
    p1.close();
    canvas.drawPath(p1, paint);
    canvas.drawPath(p1, strokePaint);

    final p2 = Path();
    p2.moveTo(size.width * 0.45, size.height * 0.2);
    p2.lineTo(size.width * 0.8, size.height * 0.5);
    p2.lineTo(size.width * 0.45, size.height * 0.8);
    p2.close();
    canvas.drawPath(p2, paint);
    canvas.drawPath(p2, strokePaint);

    final bar = RRect.fromRectAndRadius(
      Rect.fromLTRB(size.width * 0.85, size.height * 0.15, size.width * 0.95, size.height * 0.85),
      Radius.circular(size.width * 0.05),
    );
    canvas.drawRRect(bar, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SleekSkipPreviousPainter extends CustomPainter {
  final Color color;
  SleekSkipPreviousPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeJoin = StrokeJoin.round;

    final bar = RRect.fromRectAndRadius(
      Rect.fromLTRB(size.width * 0.05, size.height * 0.15, size.width * 0.15, size.height * 0.85),
      Radius.circular(size.width * 0.05),
    );
    canvas.drawRRect(bar, paint);

    final p1 = Path();
    p1.moveTo(size.width * 0.55, size.height * 0.2);
    p1.lineTo(size.width * 0.2, size.height * 0.5);
    p1.lineTo(size.width * 0.55, size.height * 0.8);
    p1.close();
    canvas.drawPath(p1, paint);
    canvas.drawPath(p1, strokePaint);

    final p2 = Path();
    p2.moveTo(size.width * 0.9, size.height * 0.2);
    p2.lineTo(size.width * 0.55, size.height * 0.5);
    p2.lineTo(size.width * 0.9, size.height * 0.8);
    p2.close();
    canvas.drawPath(p2, paint);
    canvas.drawPath(p2, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

