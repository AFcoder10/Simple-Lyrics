import 'package:flutter/material.dart';
import '../core/font_fallbacks.dart';

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

  /// Vertical lift already computed by the caller for this word. Only applied
  /// when the run is rendered as one piece — letter-by-letter runs lift each
  /// letter on its own staggered schedule instead, and doubling up would move
  /// them twice.
  final double liftOffset;

  /// How far a word/letter creeps up, over [liftSpanSeconds], then holds.
  static const double liftDistance = 5.0;
  static const double liftSpanSeconds = 2.3;

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
    this.liftOffset = 0,
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

    // Fast path for completely idle unsung words.
    if (trail <= 0.0) {
      final idleText = Text(text, style: dimStyle);
      if (liftOffset == 0.0) return idleText;
      return Transform.translate(offset: Offset(0, liftOffset), child: idleText);
    }

    // Remastered glow for long-hold words.
    final TextStyle glowingActiveStyle;
    if (longHold && trail > 0.0) {
      final fadeIn = (trail / 0.15).clamp(0.0, 1.0);
      final fadeOut =
          (1.0 - (trail - 0.75).clamp(0.0, 0.25) / 0.25).clamp(0.0, 1.0);
      final glow = fadeIn * fadeOut;
      glowingActiveStyle = activeStyle.copyWith(
        shadows: glow > 0.01
            ? [
                Shadow(
                  color: activeColor.withValues(
                    alpha: (0.6 * glow).clamp(0.0, 1.0),
                  ),
                  blurRadius: 16.0,
                ),
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

    // Complex scripts (Hindi, Arabic, etc.) cannot be split into letters
    // because it breaks text shaping and creates dotted circles.
    final bool useLetterSettle = longHold && !hasComplexScript(text);

    // Slow, smooth whole-word pop-out scale for non-letter-settle words.
    double wordScale = 1.0;
    if (!useLetterSettle && elapsedSeconds >= 0 && wordDuration > 0.02) {
      final holdFactor = ((wordDuration - 0.30) / 0.80).clamp(0.0, 1.0);
      final maxPop = 0.018 + 0.018 * holdFactor;
      final growSec = (wordDuration * 0.60).clamp(0.26, 0.65);
      final settleSec = (wordDuration * 1.35).clamp(0.75, 2.10);
      if (elapsedSeconds < growSec + settleSec) {
        final double pulse;
        if (elapsedSeconds < growSec) {
          pulse = Curves.easeInOutSine.transform(elapsedSeconds / growSec);
        } else {
          final settleT =
              ((elapsedSeconds - growSec) / settleSec).clamp(0.0, 1.0);
          pulse = Curves.easeInOutSine.transform(1.0 - settleT);
        }
        wordScale = 1.0 + maxPop * pulse;
      }
    }

    Widget wordWidget = _buildFillText(
      text: text,
      visualTrail: trail,
      activeStyle: activeStyle,
      glowingActiveStyle: glowingActiveStyle,
      dimStyle: dimStyle,
      featherStart: featherStart,
      featherEnd: featherEnd,
      useLetterSettle: useLetterSettle,
    );

    if (wordScale != 1.0) {
      wordWidget = Transform.scale(
        scale: wordScale,
        alignment: Alignment.center,
        child: wordWidget,
      );
    }

    return _wrapLift(wordWidget, useLetterSettle);
  }

  Widget _wrapLift(Widget child, bool useLetterSettle) {
    // Letter-by-letter runs lift each letter individually, so a whole-word
    // offset on top of that would shift the entire run again.
    if (useLetterSettle) return child;
    if (liftOffset == 0.0) return child;
    return Transform.translate(offset: Offset(0, liftOffset), child: child);
  }

  Widget _buildFillText({
    required String text,
    required double visualTrail,
    required TextStyle activeStyle,
    required TextStyle glowingActiveStyle,
    required TextStyle dimStyle,
    required double featherStart,
    required double featherEnd,
    required bool useLetterSettle,
  }) {
    if (visualTrail <= 0.0) {
      return useLetterSettle
          ? _LetterSettleText(
              text: text,
              style: dimStyle,
              elapsedSeconds: elapsedSeconds,
              wordDuration: wordDuration,
            )
          : Text(text, style: dimStyle);
    }
    if (visualTrail >= 1.0) {
      return useLetterSettle
          ? _LetterSettleText(
              text: text,
              style: glowingActiveStyle,
              elapsedSeconds: elapsedSeconds,
              wordDuration: wordDuration,
            )
          : Text(text, style: glowingActiveStyle);
    }

    final hasGlow = glowingActiveStyle.shadows != null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        useLetterSettle
            ? _LetterSettleText(
                text: text,
                style: dimStyle,
                elapsedSeconds: elapsedSeconds,
                wordDuration: wordDuration,
              )
            : Text(text, style: dimStyle),
        Positioned(
          top: hasGlow ? -48 : 0,
          bottom: hasGlow ? -48 : 0,
          left: hasGlow ? -48 : 0,
          right: hasGlow ? -48 : 0,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              final pad = hasGlow ? 48.0 : 0.0;
              final w = bounds.width - (pad * 2);
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
              ).createShader(
                Rect.fromLTWH(pad, pad, expandedW, bounds.height - (pad * 2)),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(hasGlow ? 48.0 : 0.0),
              child: useLetterSettle
                  ? _LetterSettleText(
                      text: text,
                      style: glowingActiveStyle,
                      elapsedSeconds: elapsedSeconds,
                      wordDuration: wordDuration,
                    )
                  : Text(text, style: glowingActiveStyle),
            ),
          ),
        ),
      ],
    );
  }
}

/// Per-letter lift & scale animation for long-hold words.
///
/// Measures the monolithic [TextPainter] layout once (and caches it) so each
/// grapheme sits at its exact kerning/advance offset inside a [SizedBox] whose
/// dimensions match plain `Text(text, style: style)`. That guarantees zero
/// width or line-wrap shift when transitioning between idle `Text` and
/// active per-letter animation.
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

  static final Map<_LetterLayoutKey, _MeasuredWordLayout> _layoutCache = {};

  static _MeasuredWordLayout _measureLayout({
    required String text,
    required TextStyle baseStyle,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    final key = _LetterLayoutKey(
      text: text,
      fontFamily: baseStyle.fontFamily,
      fontSize: baseStyle.fontSize,
      fontWeight: baseStyle.fontWeight,
      letterSpacing: baseStyle.letterSpacing,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    final cached = _layoutCache[key];
    if (cached != null) return cached;

    if (_layoutCache.length >= 256) {
      _layoutCache.clear();
    }

    // Measure with visuals stripped so glow/color updates share the cache key.
    final metricsStyle = baseStyle.copyWith(
      color: const Color(0xFFFFFFFF),
      shadows: null,
      foreground: null,
      background: null,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: metricsStyle),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();

    final glyphs = <_MeasuredGlyph>[];
    var utf16Offset = 0;
    for (final cluster in text.characters) {
      final start = utf16Offset;
      final end = start + cluster.length;
      utf16Offset = end;

      if (cluster.trim().isEmpty) continue;

      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      final double dx = boxes.isNotEmpty
          ? boxes.first.left
          : painter
              .getOffsetForCaret(TextPosition(offset: start), Rect.zero)
              .dx;
      glyphs.add(_MeasuredGlyph(text: cluster, dx: dx));
    }

    final measured = _MeasuredWordLayout(
      size: painter.size,
      glyphs: glyphs,
    );
    painter.dispose();
    _layoutCache[key] = measured;
    return measured;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);

    final layout = _measureLayout(
      text: text,
      baseStyle: resolvedStyle,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    final glyphStyle = resolvedStyle.copyWith(letterSpacing: 0);
    final count = layout.glyphs.length;

    return SizedBox(
      width: layout.size.width,
      height: layout.size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: layout.glyphs[i].dx,
              top: 0,
              child: Transform.translate(
                offset: Offset(0, _liftForLetter(i, count)),
                child: Transform.scale(
                  scale: _scaleForLetter(i, count),
                  alignment: Alignment.bottomCenter,
                  child: Text(layout.glyphs[i].text, style: glyphStyle),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Same rule as a whole word — creep up by [KaraokeTextFill.liftDistance]
  /// over [KaraokeTextFill.liftSpanSeconds], then stay there — but keyed to
  /// this letter's own start so the run lifts one letter at a time instead of
  /// jumping as a block.
  double _liftForLetter(int index, int length) {
    if (length == 0) return 0.0;
    final letterDelay = wordDuration * (index / length);
    final progress =
        ((elapsedSeconds - letterDelay) / KaraokeTextFill.liftSpanSeconds)
            .clamp(0.0, 1.0);
    if (progress <= 0.0) return 0.0;
    return -KaraokeTextFill.liftDistance *
        Curves.easeOutCubic.transform(progress);
  }

  double _scaleForLetter(int index, int length) {
    if (length == 0) return 1.0;
    final letterPos = index / length;
    final letterDelay = wordDuration * letterPos;
    final t = elapsedSeconds - letterDelay;

    if (t < 0) return 1.0;

    const growSeconds = 0.45;
    const maxScale = 0.04;

    if (t < growSeconds) {
      final growProgress = t / growSeconds;
      final ease = Curves.easeInOutSine.transform(growProgress);
      return 1.0 + (maxScale * ease);
    }

    final settleProgress = ((t - growSeconds) / 1.65).clamp(0.0, 1.0);
    final ease = Curves.easeInOutSine.transform(1.0 - settleProgress);
    return 1.0 + (maxScale * ease);
  }
}

class _MeasuredGlyph {
  final String text;
  final double dx;

  const _MeasuredGlyph({required this.text, required this.dx});
}

class _MeasuredWordLayout {
  final Size size;
  final List<_MeasuredGlyph> glyphs;

  const _MeasuredWordLayout({required this.size, required this.glyphs});
}

class _LetterLayoutKey {
  final String text;
  final String? fontFamily;
  final double? fontSize;
  final FontWeight? fontWeight;
  final double? letterSpacing;
  final TextScaler textScaler;
  final TextDirection textDirection;

  const _LetterLayoutKey({
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.letterSpacing,
    required this.textScaler,
    required this.textDirection,
  });

  @override
  bool operator ==(Object other) {
    return other is _LetterLayoutKey &&
        other.text == text &&
        other.fontFamily == fontFamily &&
        other.fontSize == fontSize &&
        other.fontWeight == fontWeight &&
        other.letterSpacing == letterSpacing &&
        other.textScaler == textScaler &&
        other.textDirection == textDirection;
  }

  @override
  int get hashCode => Object.hash(
        text,
        fontFamily,
        fontSize,
        fontWeight,
        letterSpacing,
        textScaler,
        textDirection,
      );
}
