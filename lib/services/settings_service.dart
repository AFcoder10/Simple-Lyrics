import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackgroundStyle {
  spinningBlur,
  acrylic,
  staticColor,
}

/// Manages application settings and persistence.
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;
  
  final ValueNotifier<bool> romanizationEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<double> lyricsFontSize = ValueNotifier<double>(35.0);
  final ValueNotifier<int> lyricsOffsetMs = ValueNotifier<int>(0); // ±50ms offset
  final ValueNotifier<bool> hapticLyricsEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<double> hapticIntensity = ValueNotifier<double>(0.5); // 0.0 to 1.0
  final ValueNotifier<bool> wordToWordHapticsEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> parallaxEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<double> parallaxStrength = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> performanceModeEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> animatedArtworkEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> showBackgroundInFullScreenArtwork = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isFullScreenArtworkOpen = ValueNotifier<bool>(false);
  
  final ValueNotifier<BackgroundStyle> backgroundStyle = ValueNotifier<BackgroundStyle>(BackgroundStyle.spinningBlur);
  
  final ValueNotifier<double> blurIntensity = ValueNotifier<double>(10.0);
  final ValueNotifier<double> blurAnimationSpeed = ValueNotifier<double>(1.0); // 1.0 is default (26s)
  
  final ValueNotifier<double> grainIntensity = ValueNotifier<double>(0.04);
  
  final ValueNotifier<double> staticVibrancy = ValueNotifier<double>(1.8);
  final ValueNotifier<double> staticContrast = ValueNotifier<double>(1.0);

  /// Initialize the service and load persisted settings.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    romanizationEnabled.value = _readBool('romanization_enabled') ?? true;
    lyricsFontSize.value = _readDouble('lyrics_font_size') ?? 35.0;
    lyricsOffsetMs.value = _readInt('lyrics_offset_ms') ?? 0;
    hapticLyricsEnabled.value = _readBool('haptic_lyrics_enabled') ?? false;
    hapticIntensity.value = _readDouble('haptic_intensity') ?? 0.5;
    wordToWordHapticsEnabled.value = _readBool('word_to_word_haptics_enabled') ?? true;
    parallaxEnabled.value = _readBool('parallax_enabled') ?? false;
    parallaxStrength.value = _readDouble('parallax_strength') ?? 1.0;
    performanceModeEnabled.value = _readBool('performance_mode_enabled') ?? false;
    animatedArtworkEnabled.value = _readBool('animated_artwork_enabled') ?? true;
    showBackgroundInFullScreenArtwork.value = _readBool('show_background_in_full_screen_artwork') ?? false;
    
    final styleIndex = _readInt('background_style') ?? 0;
    backgroundStyle.value = BackgroundStyle.values[styleIndex.clamp(0, BackgroundStyle.values.length - 1)];

    blurIntensity.value = _readDouble('blur_intensity') ?? 10.0;
    blurAnimationSpeed.value = _readDouble('blur_animation_speed') ?? 1.0;
    
    grainIntensity.value = _readDouble('grain_intensity') ?? 0.04;
    staticVibrancy.value = _readDouble('static_vibrancy') ?? 1.8;
    staticContrast.value = _readDouble('static_contrast') ?? 1.0;

    // Listen for changes and persist them
    romanizationEnabled.addListener(() {
      _prefs.setBool('romanization_enabled', romanizationEnabled.value);
    });
    lyricsFontSize.addListener(() {
      _prefs.setDouble('lyrics_font_size', lyricsFontSize.value);
    });
    lyricsOffsetMs.addListener(() {
      _prefs.setInt('lyrics_offset_ms', lyricsOffsetMs.value);
    });
    // oledProtection removed
    hapticLyricsEnabled.addListener(() {
      _prefs.setBool('haptic_lyrics_enabled', hapticLyricsEnabled.value);
    });
    hapticIntensity.addListener(() {
      _prefs.setDouble('haptic_intensity', hapticIntensity.value);
    });
    wordToWordHapticsEnabled.addListener(() {
      _prefs.setBool('word_to_word_haptics_enabled', wordToWordHapticsEnabled.value);
    });
    parallaxEnabled.addListener(() {
      _prefs.setBool('parallax_enabled', parallaxEnabled.value);
    });
    parallaxStrength.addListener(() {
      _prefs.setDouble('parallax_strength', parallaxStrength.value);
    });
    performanceModeEnabled.addListener(() {
      _prefs.setBool('performance_mode_enabled', performanceModeEnabled.value);
    });
    animatedArtworkEnabled.addListener(() {
      _prefs.setBool('animated_artwork_enabled', animatedArtworkEnabled.value);
    });
    showBackgroundInFullScreenArtwork.addListener(() {
      _prefs.setBool('show_background_in_full_screen_artwork', showBackgroundInFullScreenArtwork.value);
    });
    backgroundStyle.addListener(() {
      _prefs.setInt('background_style', backgroundStyle.value.index);
    });
    blurIntensity.addListener(() {
      _prefs.setDouble('blur_intensity', blurIntensity.value);
    });
    blurAnimationSpeed.addListener(() {
      _prefs.setDouble('blur_animation_speed', blurAnimationSpeed.value);
    });
    grainIntensity.addListener(() {
      _prefs.setDouble('grain_intensity', grainIntensity.value);
    });
    staticVibrancy.addListener(() {
      _prefs.setDouble('static_vibrancy', staticVibrancy.value);
    });
    staticContrast.addListener(() {
      _prefs.setDouble('static_contrast', staticContrast.value);
    });
  }

  void toggleRomanization() {
    romanizationEnabled.value = !romanizationEnabled.value;
  }

  void updateFontSize(double delta) {
    final newValue = (lyricsFontSize.value + delta).clamp(20.0, 60.0);
    lyricsFontSize.value = newValue;
  }

  int? _readInt(String key) {
    final value = _prefs.get(key);
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _readDouble(String key) {
    final value = _prefs.get(key);
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool? _readBool(String key) {
    final value = _prefs.get(key);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return null;
  }
}
