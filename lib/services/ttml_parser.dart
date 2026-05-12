import 'package:flutter/foundation.dart';
import 'lyrics_models.dart';

/// Parses Apple Music TTML (Timed Text Markup Language) into [LyricsData].
///
/// Supports both timing modes:
/// - `itunes:timing="Word"` — each `<span>` has individual word timings
/// - `itunes:timing="Line"` — only `<p>` elements have timing
///
/// Each `<p>` element becomes a [LyricsLine], and each `<span>` inside
/// becomes a [LyricsWord] (when word-timed).
class TtmlParser {
  static final RegExp _paragraphRegex = RegExp(
    r'<p\s+([^>]*?)>(.*?)</p>',
    dotAll: true,
  );
  static final RegExp _untimedParagraphRegex = RegExp(
    r'<p>(.*?)</p>',
    dotAll: true,
  );
  static final RegExp _beginRegex = RegExp(r'begin="([^"]+)"');
  static final RegExp _endRegex = RegExp(r'end="([^"]+)"');
  static final RegExp _timingRegex = RegExp(r'itunes:timing="(\w+)"');
  static final RegExp _timedSpanDetector =
      RegExp(r'<span\s+begin="[^"]+"\s+end="[^"]+"');
  static final RegExp _tagRegex = RegExp(r'<[^>]+>');
  static final RegExp _agentRegex = RegExp(r'ttm:agent="([^"]+)"');
  static final RegExp _songwriterRegex = RegExp(r'<songwriter>(.*?)</songwriter>', dotAll: true);
  static final RegExp _backgroundRoleRegex =
      RegExp(r'<span\b[^>]*ttm:role="x-bg"[^>]*>', dotAll: true);

  /// Parse a TTML XML string into [LyricsData].
  static LyricsData parse(String ttml) {
    try {
      // Detect timing type from the <tt> root element
      final timingType = _detectTimingType(ttml);
      final lines = <LyricsLine>[];

      // Parse transliteration map from <metadata>
      final transliterationMap = _parseTransliteration(ttml);

      // Extract all <p> elements with their attributes and content
      if (timingType == LyricsTimingType.none) {
        // Static lyrics: <p> tags have no begin/end attributes.
        for (final match in _untimedParagraphRegex.allMatches(ttml)) {
          final attributes = match.group(0)!; // Full tag for key extraction
          final innerHtml = match.group(1)!;
          final text = _extractText(innerHtml).trim();
          if (text.isEmpty) continue;

          final key = _extractAttribute(attributes, 'itunes:key');
          final transliterated = key != null ? transliterationMap[key] : null;

          lines.add(LyricsLine(
            text: text,
            startTime: 0,
            endTime: 0,
            words: const [],
            isBackground: false,
            alignment: LyricsLineAlignment.left,
            transliteratedText: transliterated,
          ));
        }
      } else {
        for (final match in _paragraphRegex.allMatches(ttml)) {
          final attributes = match.group(1)!;
          final innerHtml = match.group(2)!;

          // Extract begin and end times from attributes
          final beginMatch = _beginRegex.firstMatch(attributes);
          final endMatch = _endRegex.firstMatch(attributes);

          if (beginMatch == null || endMatch == null) continue;

          final begin = _parseTime(beginMatch.group(1)!);
          final end = _parseTime(endMatch.group(1)!);
          final alignment = _parseAlignment(attributes);
          final key = _extractAttribute(attributes, 'itunes:key');
          final transliterated = key != null ? transliterationMap[key] : null;

          final splitHtml = _splitBackgroundHtml(innerHtml);

          // Check for background vocal markers either in <p> attributes or inside <span> tags
          final isParagraphBackground =
              attributes.contains('itunes:songPart="BackgroundVocals"') ||
              attributes.contains('itunes:songPart="Background"') ||
              attributes.contains('x-bg') ||
              attributes.contains('ttm:role="x-bg"');

          _addLine(
            lines: lines,
            html: isParagraphBackground ? innerHtml : splitHtml.foregroundHtml,
            begin: begin,
            end: end,
            timingType: timingType,
            isBackground: isParagraphBackground,
            alignment: alignment,
            transliteratedText: transliterated,
          );

          if (!isParagraphBackground) {
            for (final backgroundHtml in splitHtml.backgroundHtmlBlocks) {
              _addLine(
                lines: lines,
                html: backgroundHtml,
                begin: begin,
                end: end,
                timingType: timingType,
                isBackground: true,
                alignment: alignment,
                transliteratedText: null, // Transliteration usually only applies to lead vocals in AM TTML
              );
            }
          }
        }
      }

      if (lines.isEmpty) {
        return LyricsData.empty();
      }

      final songwriters = <String>[];
      for (final match in _songwriterRegex.allMatches(ttml)) {
        final name = match.group(1)?.trim();
        if (name != null && name.isNotEmpty) {
          // Decode HTML entities if any
          songwriters.add(_extractText(name).trim());
        }
      }

      return LyricsData(
        lines: lines, 
        timingType: timingType,
        songwriters: songwriters,
      );
    } catch (e) {
      debugPrint('TtmlParser.parse error: $e');
      return LyricsData.empty();
    }
  }

  /// Detect whether the TTML uses word-level or line-level timing.
  static LyricsTimingType _detectTimingType(String ttml) {
    // Check for itunes:timing attribute in the <tt> root
    final timingMatch = _timingRegex.firstMatch(ttml);
    if (timingMatch != null) {
      final value = timingMatch.group(1)!.toLowerCase();
      if (value == 'word') return LyricsTimingType.word;
      if (value == 'line') return LyricsTimingType.line;
      if (value == 'none') return LyricsTimingType.none;
    }

    // Fallback: check if spans have begin/end attributes
    final hasTimedSpans = _timedSpanDetector.hasMatch(ttml);
    return hasTimedSpans ? LyricsTimingType.word : LyricsTimingType.line;
  }

  static LyricsLineAlignment _parseAlignment(String attributes) {
    final agent = _agentRegex.firstMatch(attributes)?.group(1);
    return agent == 'v2' ? LyricsLineAlignment.right : LyricsLineAlignment.left;
  }

  static void _addLine({
    required List<LyricsLine> lines,
    required String html,
    required double begin,
    required double end,
    required LyricsTimingType timingType,
    required bool isBackground,
    required LyricsLineAlignment alignment,
    String? transliteratedText,
  }) {
    final parsedWords = _parseWords(html);
    final words = isBackground
        ? parsedWords
            .map(
              (word) => LyricsWord(
                text: word.text.replaceAll('(', '').replaceAll(')', ''),
                startTime: word.startTime,
                endTime: word.endTime,
              ),
            )
            .toList()
        : parsedWords;
    var text = words.isNotEmpty
        ? words.map((w) => w.text).join(' ')
        : _extractText(html).trim();

    if (isBackground || (text.startsWith('(') && text.endsWith(')'))) {
      text = text.replaceAll('(', '').replaceAll(')', '').trim();
    }

    if (text.isEmpty) return;

    double trueBegin = begin;
    double trueEnd = end;
    if (timingType == LyricsTimingType.word && words.isNotEmpty) {
      // Use the actual bounds of the words for the line timing.
      // This is crucial for background vocals that may start much later than their parent paragraph.
      trueBegin = words.first.startTime;
      trueEnd = words.last.endTime;
      for (final word in words) {
        if (word.startTime < trueBegin) trueBegin = word.startTime;
        if (word.endTime > trueEnd) trueEnd = word.endTime;
      }
    }

    lines.add(
      LyricsLine(
        text: text,
        startTime: trueBegin,
        endTime: trueEnd,
        words: timingType == LyricsTimingType.word ? words : [],
        isBackground: isBackground,
        alignment: alignment,
        transliteratedText: transliteratedText,
      ),
    );
  }

  static String? _extractAttribute(String attributes, String name) {
    final regex = RegExp('$name="([^"]+)"');
    return regex.firstMatch(attributes)?.group(1);
  }

  static Map<String, String> _parseTransliteration(String ttml) {
    final map = <String, String>{};
    // Match the transliteration block
    final blockRegex = RegExp(r'<transliteration\b[^>]*>(.*?)</transliteration>', dotAll: true);
    final blockMatch = blockRegex.firstMatch(ttml);
    if (blockMatch == null) return map;

    final inner = blockMatch.group(1)!;
    // Match each <text for="..."> element
    final entryRegex = RegExp(r'<text\b[^>]*for="([^"]+)"[^>]*>(.*?)</text>', dotAll: true);
    for (final match in entryRegex.allMatches(inner)) {
      final key = match.group(1)!;
      final text = _extractText(match.group(2)!).trim();
      if (text.isNotEmpty) {
        map[key] = text;
      }
    }
    return map;
  }

  static _SplitLyricsHtml _splitBackgroundHtml(String html) {
    final blocks = <String>[];
    final foreground = StringBuffer();
    var cursor = 0;

    while (cursor < html.length) {
      final match = _backgroundRoleRegex.matchAsPrefix(html, cursor) ??
          _backgroundRoleRegex.firstMatch(html.substring(cursor));
      if (match == null) {
        foreground.write(html.substring(cursor));
        break;
      }

      final start = match.start + (match.input == html ? 0 : cursor);
      final openingEnd = match.end + (match.input == html ? 0 : cursor);
      foreground.write(html.substring(cursor, start));

      final end = _findClosingSpanEnd(html, openingEnd);
      if (end <= openingEnd) {
        foreground.write(html.substring(start));
        break;
      }

      blocks.add(html.substring(start, end));
      cursor = end;
    }

    return _SplitLyricsHtml(
      foregroundHtml: foreground.toString(),
      backgroundHtmlBlocks: blocks,
    );
  }

  static int _findClosingSpanEnd(String html, int offset) {
    var depth = 1;
    var cursor = offset;

    while (cursor < html.length) {
      final nextOpen = html.indexOf('<span', cursor);
      final nextClose = html.indexOf('</span>', cursor);
      if (nextClose == -1) return -1;

      if (nextOpen != -1 && nextOpen < nextClose) {
        depth++;
        cursor = nextOpen + 5;
      } else {
        depth--;
        cursor = nextClose + 7;
        if (depth == 0) return cursor;
      }
    }

    return -1;
  }

  static final RegExp _timedSpanRegex = RegExp(
    r'<span\b(?=[^>]*begin="[^"]+")(?=[^>]*end="[^"]+")([^>]*)>(.*?)</span>(\s*)',
    dotAll: true,
  );

  /// Parse `<span>` elements within a `<p>` to extract word-level timing.
  static List<LyricsWord> _parseWords(String innerHtml) {
    final words = <LyricsWord>[];

    for (final match in _timedSpanRegex.allMatches(innerHtml)) {
      final attributes = match.group(1)!;
      final rawText = match.group(2)!;
      final trailingSpace = match.group(3) ?? '';

      // Extract begin and end times from attributes regardless of order
      final beginMatch = _beginRegex.firstMatch(attributes);
      final endMatch = _endRegex.firstMatch(attributes);

      if (beginMatch != null && endMatch != null) {
        final begin = _parseTime(beginMatch.group(1)!);
        final end = _parseTime(endMatch.group(1)!);
        
        // Strip any nested tags (syllable tags) and add trailing space
        final text = _extractText(rawText).trim() + trailingSpace;

        if (text.isNotEmpty) {
          words.add(LyricsWord(
            text: text,
            startTime: begin,
            endTime: end,
          ));
        }
      }
    }

    return words;
  }

  /// Parse a TTML time string into seconds.
  /// Supports formats: "27.395" (seconds) or "3:21.570" (min:sec)
  static double _parseTime(String timeStr) {
    if (timeStr.contains(':')) {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final minutes = double.tryParse(parts[0]) ?? 0;
        final seconds = double.tryParse(parts[1]) ?? 0;
        return minutes * 60 + seconds;
      } else if (parts.length == 3) {
        final hours = double.tryParse(parts[0]) ?? 0;
        final minutes = double.tryParse(parts[1]) ?? 0;
        final seconds = double.tryParse(parts[2]) ?? 0;
        return hours * 3600 + minutes * 60 + seconds;
      }
    }
    return double.tryParse(timeStr) ?? 0;
  }

  /// Strip all XML/HTML tags and decode entities to get plain text.
  static String _extractText(String html) {
    final stripped = html.replaceAll(_tagRegex, '');
    return stripped
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('\\u0027', "'");
  }
}

class _SplitLyricsHtml {
  final String foregroundHtml;
  final List<String> backgroundHtmlBlocks;

  const _SplitLyricsHtml({
    required this.foregroundHtml,
    required this.backgroundHtmlBlocks,
  });
}
