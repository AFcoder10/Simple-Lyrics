/// The type of timing in the TTML lyrics.
enum LyricsTimingType {
  /// Each word within a line has individual timing.
  word,

  /// Only entire lines have timing (no per-word data).
  line,

  /// No timing at all — purely static lyrics text.
  none,
}

/// Horizontal placement for Apple Music vocal agents.
enum LyricsLineAlignment {
  left,
  right,
}

/// Represents a single word/syllable with its own timing.
class LyricsWord {
  final String text;
  final double startTime;
  final double endTime;
  final String? transliteratedText;

  const LyricsWord({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.transliteratedText,
  });

  /// Check if this word should be highlighted at the given position.
  bool isActiveAt(double seconds) {
    return seconds >= startTime && seconds < endTime;
  }

  /// Check if this word has already been sung.
  bool isPastAt(double seconds) {
    return seconds >= endTime;
  }
}

/// Represents a single line of lyrics with timing information.
class LyricsLine {
  /// The full text content of this lyrics line.
  final String text;

  /// Start time of this line in seconds.
  final double startTime;

  /// End time of this line in seconds.
  final double endTime;

  /// Individual words with timing (populated for word-timed lyrics).
  final List<LyricsWord> words;

  /// Whether this line is a background vocal line.
  final bool isBackground;

  /// Horizontal placement derived from `ttm:agent`.
  final LyricsLineAlignment alignment;

  /// Transliterated version of the text (e.g. Romanized), if available.
  final String? transliteratedText;

  /// Individual transliterated words with their own timings.
  final List<LyricsWord>? transliteratedWords;

  const LyricsLine({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.words = const [],
    this.isBackground = false,
    this.alignment = LyricsLineAlignment.left,
    this.transliteratedText,
    this.transliteratedWords,
  });

  /// Whether this line has per-word timing data.
  bool get hasWordTiming => words.isNotEmpty;

  /// Check if this line should be active at the given position.
  bool isActiveAt(Duration position) {
    final seconds = position.inMilliseconds / 1000.0;
    return seconds >= startTime && seconds < endTime;
  }

  @override
  String toString() =>
      'LyricsLine(${startTime.toStringAsFixed(1)}s–${endTime.toStringAsFixed(1)}s: "$text")';
}

/// Holds parsed lyrics data — a list of timed lines.
class LyricsData {
  final List<LyricsLine> lines;
  final LyricsTimingType timingType;
  final bool isEmpty;
  final List<String> songwriters;

  const LyricsData({
    required this.lines,
    this.timingType = LyricsTimingType.line,
    this.isEmpty = false,
    this.songwriters = const [],
  });

  factory LyricsData.empty() =>
      const LyricsData(lines: [], isEmpty: true, songwriters: []);

  /// Returns all indices of lines active at [position] (allows overlapping lines).
  List<int> activeLineIndices(Duration position) {
    if (lines.isEmpty) return [];
    final seconds = position.inMilliseconds / 1000.0;
    
    final active = <int>[];
    for (int i = 0; i < lines.length; i++) {
      if (seconds >= lines[i].startTime && seconds < lines[i].endTime) {
        active.add(i);
      }
    }
    return active;
  }
}
