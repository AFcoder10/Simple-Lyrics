import 'package:flutter/material.dart';

/// Snappy, GPU-composited "3D" bottom-slide route for opaque settings pages.
///
/// Marks the route [opaque: true] so covered routes (including animated
/// playback backgrounds behind settings) stop compositing once the transition
/// completes, and uses a stateful transition widget with reused matrices and
/// compositor-backed [FadeTransition] to eliminate `saveLayer` and per-frame
/// allocations at 60-120Hz.
PageRoute<T> buildSettingsRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: true,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return buildSettingsTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    },
  );
}

/// Shared transition builder used by both mobile settings routes and the
/// desktop settings overlay.
Widget buildSettingsTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  bool includeSecondary = true,
  bool compact = false,
}) {
  return _SettingsRouteTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    includeSecondary: includeSecondary,
    compact: compact,
    child: child,
  );
}

class _SettingsRouteTransition extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool includeSecondary;
  final bool compact;
  final Widget child;

  const _SettingsRouteTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.includeSecondary,
    required this.compact,
    required this.child,
  });

  @override
  State<_SettingsRouteTransition> createState() =>
      _SettingsRouteTransitionState();
}

class _SettingsRouteTransitionState extends State<_SettingsRouteTransition> {
  static const Cubic _motionCurve = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Cubic _reverseCurve = Cubic(0.4, 0.0, 0.2, 1.0);
  static final Tween<double> _outOpacityTween = Tween<double>(begin: 1.0, end: 0.62);

  late CurvedAnimation _curvedIn;
  late CurvedAnimation _fadeIn;
  late CurvedAnimation _curvedOut;
  late Animation<double> _fadeOut;

  final Matrix4 _inMatrix = Matrix4.identity();
  final Matrix4 _outMatrix = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _curvedIn = CurvedAnimation(
      parent: widget.animation,
      curve: _motionCurve,
      reverseCurve: _reverseCurve,
    );
    _fadeIn = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.45, 1.0, curve: Curves.easeInCubic),
    );
    _curvedOut = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: _motionCurve,
      reverseCurve: _reverseCurve,
    );
    _fadeOut = _outOpacityTween.animate(_curvedOut);
  }

  void _disposeAnimations() {
    _curvedIn.dispose();
    _fadeIn.dispose();
    _curvedOut.dispose();
  }

  @override
  void didUpdateWidget(covariant _SettingsRouteTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _disposeAnimations();
      _initAnimations();
    }
  }

  @override
  void dispose() {
    _disposeAnimations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = RepaintBoundary(child: widget.child);

    if (widget.includeSecondary) {
      result = FadeTransition(
        opacity: _fadeOut,
        child: AnimatedBuilder(
          animation: _curvedOut,
          child: result,
          builder: (context, inner) {
            final tOut = _curvedOut.value;
            _outMatrix.setIdentity();
            if (tOut > 0.0001) {
              final outScale = 1.0 - 0.04 * tOut;
              final outTiltX = -0.03 * tOut;
              final outShiftY = -16.0 * tOut;
              _outMatrix
                ..setEntry(3, 2, 0.0010)
                ..translateByDouble(0.0, outShiftY, 0.0, 1.0)
                ..rotateX(outTiltX)
                ..scaleByDouble(outScale, outScale, 1.0, 1.0);
            }
            return Transform(
              alignment: Alignment.center,
              transform: _outMatrix,
              child: inner,
            );
          },
        ),
      );
    }

    final slideExtent = widget.compact ? 0.10 : 0.24;
    final baseScale = widget.compact ? 0.96 : 0.95;
    final scaleSpan = 1.0 - baseScale;
    final maxTiltX = widget.compact ? 0.035 : 0.06;

    return FadeTransition(
      opacity: _fadeIn,
      child: AnimatedBuilder(
        animation: _curvedIn,
        child: result,
        builder: (context, inner) {
          final t = _curvedIn.value;
          final inv = 1.0 - t;
          _inMatrix.setIdentity();
          if (inv > 0.0001) {
            final inScale = baseScale + scaleSpan * t;
            final inTiltX = maxTiltX * inv;
            _inMatrix
              ..setEntry(3, 2, 0.0011)
              ..rotateX(inTiltX)
              ..scaleByDouble(inScale, inScale, 1.0, 1.0);
          }

          return FractionalTranslation(
            translation: Offset(0.0, slideExtent * inv),
            child: Transform(
              alignment: Alignment.center,
              transform: _inMatrix,
              child: inner,
            ),
          );
        },
      ),
    );
  }
}
