import 'package:flutter/material.dart';

/// Karaoke-style text fill with a soft feathered edge.
///
/// The fill sweeps left-to-right with a smooth gradient trail
/// at the leading edge instead of a hard cutoff.
/// Fast paths for progress 0/1 skip the shader entirely.
class KaraokeTextFill extends StatelessWidget {
  final String text;
  final double progress;
  final TextStyle style;
  final Color activeColor;
  final Color dimColor;
  final bool longHold;
  final double elapsedSeconds;
  final double wordDuration;

  const KaraokeTextFill({
    super.key,
    required this.text,
    required this.progress,
    required this.style,
    this.activeColor = Colors.white,
    this.dimColor = const Color(0x2BFFFFFF), // 17% opacity
    this.longHold = false,
    this.elapsedSeconds = 0,
    this.wordDuration = 0,
  });

  @override
  Widget build(BuildContext context) {
    final trail = progress.clamp(0.0, 1.0);
    final activeStyle = style.copyWith(color: activeColor);
    final dimStyle = style.copyWith(
      color: dimColor,
      foreground: null,
      background: null,
      shadows: null,
    );

    // Glow for long-hold words
    final TextStyle glowingActiveStyle;
    if (longHold && trail > 0.0 && trail < 1.0) {
      final fadeIn = (trail / 0.15).clamp(0.0, 1.0);
      final fadeOut = (1.0 - (trail - 0.75).clamp(0.0, 0.25) / 0.25).clamp(0.0, 1.0);
      final glow = fadeIn * fadeOut;
      glowingActiveStyle = activeStyle.copyWith(
        shadows: glow > 0.01
            ? [
                Shadow(color: activeColor.withValues(alpha: 0.7 * glow), blurRadius: 10),
                Shadow(color: activeColor.withValues(alpha: 0.4 * glow), blurRadius: 20),
                Shadow(color: activeColor.withValues(alpha: 0.2 * glow), blurRadius: 32),
              ]
            : null,
      );
    } else {
      glowingActiveStyle = activeStyle;
    }

    // Unified feather edge for both normal and longHold words.
    // Smooth 16% width gradient trail — no snapping.
    final featherStart = trail - 0.16;
    final featherEnd = trail + 0.12;

    return _buildFillText(
      text: text,
      visualTrail: trail,
      activeStyle: activeStyle,
      glowingActiveStyle: glowingActiveStyle,
      dimStyle: dimStyle,
      featherStart: featherStart,
      featherEnd: featherEnd,
    );
  }

  Widget _buildFillText({
    required String text,
    required double visualTrail,
    required TextStyle activeStyle,
    required TextStyle glowingActiveStyle,
    required TextStyle dimStyle,
    required double featherStart,
    required double featherEnd,
  }) {
    if (visualTrail <= 0.0) {
      return longHold
          ? _LetterSettleText(text: text, style: dimStyle, elapsedSeconds: elapsedSeconds, wordDuration: wordDuration)
          : Text(text, style: dimStyle);
    }
    if (visualTrail >= 1.0) {
      return longHold
          ? _LetterSettleText(text: text, style: glowingActiveStyle, elapsedSeconds: elapsedSeconds, wordDuration: wordDuration)
          : Text(text, style: activeStyle);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        longHold
            ? _LetterSettleText(text: text, style: dimStyle, elapsedSeconds: elapsedSeconds, wordDuration: wordDuration)
            : Text(text, style: dimStyle),
        Positioned(
          top: -48,
          bottom: -48,
          left: -48,
          right: -48,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              final w = bounds.width - 96.0;
              final expandedW = w + 32.0;
              final s = w > 0 ? (w / expandedW) : 1.0;

              final start = (featherStart * s).clamp(0.0, 1.0);
              final end = (featherEnd * s).clamp(0.0, 1.0);

              return LinearGradient(
                colors: [
                  activeColor,
                  activeColor,
                  activeColor.withValues(alpha: 0.0),
                  Colors.transparent,
                ],
                stops: [0.0, start, end, 1.0],
              ).createShader(Rect.fromLTWH(48, 48, expandedW, bounds.height - 96.0));
            },
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: longHold
                  ? _LetterSettleText(
                      text: text,
                      style: glowingActiveStyle,
                      elapsedSeconds: elapsedSeconds,
                      wordDuration: wordDuration,
                    )
                  : Text(text, style: activeStyle),
            ),
          ),
        ),
      ],
    );
  }
}

/// Per-letter scale animation for long-hold words.
class _LetterSettleText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double elapsedSeconds;
  final double wordDuration;

  const _LetterSettleText({
    required this.text,
    required this.style,
    required this.elapsedSeconds,
    required this.wordDuration,
  });

  @override
  Widget build(BuildContext context) {
    final chars = text.split('');

    return Row(
      mainAxisSize: MainAxisSize.min,
      textBaseline: TextBaseline.alphabetic,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      children: [
        for (var i = 0; i < chars.length; i++)
          Transform.scale(
            scale: _scaleForLetter(i, chars.length),
            alignment: Alignment.bottomCenter,
            child: Text(chars[i], style: style),
          ),
      ],
    );
  }

  double _scaleForLetter(int index, int length) {
    if (length == 0) return 1.0;
    final letterPos = index / length;
    final letterDelay = wordDuration * letterPos;
    final t = elapsedSeconds - letterDelay;

    if (t < 0) return 1.0;

    const growSeconds = 0.35;
    const maxScale = 0.05;

    if (t < growSeconds) {
      final growProgress = t / growSeconds;
      final ease = Curves.easeInOutCubic.transform(growProgress);
      return 1.0 + (maxScale * ease);
    }

    final settleProgress = ((t - growSeconds) / 1.3).clamp(0.0, 1.0);
    final ease = Curves.easeOutCubic.transform(1.0 - settleProgress);
    return 1.0 + (maxScale * ease);
  }
}
