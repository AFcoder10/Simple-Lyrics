import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackgroundStyle {
  spinningBlur,
  acrylic,
  staticColor,
}

enum AcrylicTexture {
  fineGrain,
  frosted,
  ripple,
  crystalline,
}

/// Manages application settings and persistence.
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;
  
  final ValueNotifier<bool> romanizationEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<double> lyricsFontSize = ValueNotifier<double>(35.0);
  final ValueNotifier<bool> hapticLyricsEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<double> hapticIntensity = ValueNotifier<double>(0.5); // 0.0 to 1.0
  final ValueNotifier<bool> wordToWordHapticsEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> parallaxEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<BackgroundStyle> backgroundStyle = ValueNotifier<BackgroundStyle>(BackgroundStyle.spinningBlur);
  final ValueNotifier<AcrylicTexture> acrylicTexture = ValueNotifier<AcrylicTexture>(AcrylicTexture.fineGrain);

  /// Initialize the service and load persisted settings.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    romanizationEnabled.value = _prefs.getBool('romanization_enabled') ?? true;
    lyricsFontSize.value = _prefs.getDouble('lyrics_font_size') ?? 35.0;
    hapticLyricsEnabled.value = _prefs.getBool('haptic_lyrics_enabled') ?? false;
    hapticIntensity.value = _prefs.getDouble('haptic_intensity') ?? 0.5;
    wordToWordHapticsEnabled.value = _prefs.getBool('word_to_word_haptics_enabled') ?? true;
    parallaxEnabled.value = _prefs.getBool('parallax_enabled') ?? false;
    
    final styleIndex = _prefs.getInt('background_style') ?? 0;
    backgroundStyle.value = BackgroundStyle.values[styleIndex.clamp(0, BackgroundStyle.values.length - 1)];

    final textureIndex = _prefs.getInt('acrylic_texture') ?? 0;
    acrylicTexture.value = AcrylicTexture.values[textureIndex.clamp(0, AcrylicTexture.values.length - 1)];

    // Listen for changes and persist them
    romanizationEnabled.addListener(() {
      _prefs.setBool('romanization_enabled', romanizationEnabled.value);
    });
    lyricsFontSize.addListener(() {
      _prefs.setDouble('lyrics_font_size', lyricsFontSize.value);
    });
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
    backgroundStyle.addListener(() {
      _prefs.setInt('background_style', backgroundStyle.value.index);
    });
    acrylicTexture.addListener(() {
      _prefs.setInt('acrylic_texture', acrylicTexture.value.index);
    });
  }

  void toggleRomanization() {
    romanizationEnabled.value = !romanizationEnabled.value;
  }

  void updateFontSize(double delta) {
    final newValue = (lyricsFontSize.value + delta).clamp(20.0, 60.0);
    lyricsFontSize.value = newValue;
  }
}
