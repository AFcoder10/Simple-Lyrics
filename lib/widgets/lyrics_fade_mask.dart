import 'package:flutter/material.dart';

/// Dissolves the top and bottom edges of the lyrics pane into the background.
///
/// The scroll viewport clips whatever it renders, so the first and last visible
/// lines end in a hard horizontal cut — the lyric pane reads as a box with a
/// sharp rule drawn across both ends. Re-masking the already-clipped result
/// with a transparent → opaque → transparent gradient makes those same lines
/// fade out instead, without touching hit testing or the scroll physics.
class LyricsFadeMask extends StatelessWidget {
  final Widget child;

  /// Share of the pane's height given to each fade.
  final double fadeExtent;

  const LyricsFadeMask({
    super.key,
    required this.child,
    this.fadeExtent = 0.16,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final height = bounds.height;
        final edge = height >= 2.0
            ? (height * fadeExtent).clamp(1.0, height / 2) / height
            : 0.5;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, edge, 1.0 - edge, 1.0],
        ).createShader(Offset.zero & bounds.size);
      },
      child: child,
    );
  }
}
