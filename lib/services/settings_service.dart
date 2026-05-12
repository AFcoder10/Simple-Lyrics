import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final ValueNotifier<bool> parallaxEnabled = ValueNotifier<bool>(false);

  /// Initialize the service and load persisted settings.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    romanizationEnabled.value = _prefs.getBool('romanization_enabled') ?? true;
    lyricsFontSize.value = _prefs.getDouble('lyrics_font_size') ?? 35.0;
    hapticLyricsEnabled.value = _prefs.getBool('haptic_lyrics_enabled') ?? false;
    hapticIntensity.value = _prefs.getDouble('haptic_intensity') ?? 0.5;
    parallaxEnabled.value = _prefs.getBool('parallax_enabled') ?? false;

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
    parallaxEnabled.addListener(() {
      _prefs.setBool('parallax_enabled', parallaxEnabled.value);
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
