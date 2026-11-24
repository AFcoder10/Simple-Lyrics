import 'package:flutter/material.dart';

/// Slow, smooth 2D-composited "3D" bottom-slide route for settings pages.
///
/// Uses a cached [RepaintBoundary] and pure GPU [Transform] matrices
/// (perspective + X-tilt + scale + slide) so the transition feels 3D while
/// staying completely lag-free at 60-120Hz.
PageRoute<T> buildSettingsRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 440),
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
}) {
  // Smooth Apple-style deceleration curve (fast launch, long gentle settle).
  final curvedIn = CurvedAnimation(
    parent: animation,
    curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    reverseCurve: const Cubic(0.4, 0.0, 0.2, 1.0),
  );

  final fadeIn = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0.5, 1.0, curve: Curves.easeInCubic),
  );

  final curvedOut = CurvedAnimation(
    parent: secondaryAnimation,
    curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    reverseCurve: const Cubic(0.4, 0.0, 0.2, 1.0),
  );

  Widget result = RepaintBoundary(child: child);

  if (includeSecondary) {
    result = AnimatedBuilder(
      animation: curvedOut,
      child: result,
      builder: (context, inner) {
        final tOut = curvedOut.value;
        if (tOut <= 0.0001) return inner!;

        final outScale = 1.0 - 0.06 * tOut;
        final outTiltX = -0.06 * tOut;
        final outOpacity = (1.0 - 0.42 * tOut).clamp(0.0, 1.0);
        final outShiftY = -22.0 * tOut;

        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0010)
          ..translateByDouble(0.0, outShiftY, 0.0, 1.0)
          ..rotateX(outTiltX)
          ..scaleByDouble(outScale, outScale, 1.0, 1.0);

        return Opacity(
          opacity: outOpacity,
          child: Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: inner,
          ),
        );
      },
    );
  }

  return AnimatedBuilder(
    animation: Listenable.merge([curvedIn, fadeIn]),
    child: result,
    builder: (context, inner) {
      final t = curvedIn.value;
      final inv = 1.0 - t;
      final inScale = 0.92 + 0.08 * t;
      final inTiltX = 0.20 * inv; // Tilted slightly away at top, flattens in

      return FadeTransition(
        opacity: fadeIn,
        child: FractionalTranslation(
          translation: Offset(0.0, 0.90 * inv),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0011)
              ..rotateX(inTiltX)
              ..scaleByDouble(inScale, inScale, 1.0, 1.0),
            child: inner,
          ),
        ),
      );
    },
  );
}
