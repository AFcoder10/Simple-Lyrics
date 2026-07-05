const List<String> kGlobalFontFallbacks = [
  'system-ui',
  'San Francisco',
  'Helvetica Neue',
  'Roboto',
  'Arial',
  'Noto Sans',
  'Noto Sans Devanagari',
  'Noto Sans CJK SC',
  'Noto Sans CJK TC',
  'Noto Sans CJK JP',
  'Noto Sans CJK KR',
  'Apple Color Emoji',
  'Noto Color Emoji',
];

/// Returns true if the text contains characters from scripts that require complex shaping
/// (e.g., Devanagari, Arabic, Thai, Tamil, Bengali, etc.).
/// Custom fonts often break the shaping engine (HarfBuzz) for these scripts.
bool hasComplexScript(String text) {
  // Matches Arabic (\u0600-\u06FF) through Sinhala (\u0DFF) and Thai (\u0E00-\u0E7F)
  return RegExp(r'[\u0600-\u0DFF\u0E00-\u0E7F]').hasMatch(text);
}
