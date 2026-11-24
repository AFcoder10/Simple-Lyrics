import 'dart:io' show Platform;

/// Runtime capability checks for packages that have no Windows/desktop
/// implementation.
///
/// `sensors_plus`, `vibration` and `video_player` only ship Android and iOS
/// backends. On Windows every call into them throws MissingPluginException, so
/// callers must gate on these before touching the plugin APIs.

/// Whether the platform has a gyroscope/accelerometer for the tilt effect.
bool get supportsTiltSensors => Platform.isAndroid || Platform.isIOS;

/// Whether the platform has a vibrator for word-level haptics.
bool get supportsHaptics => Platform.isAndroid || Platform.isIOS;

/// Whether animated HLS artwork can be played.
///
/// Android/iOS use `video_player`; desktop uses `media_kit` (libmpv), since
/// `video_player` ships no Windows/macOS/Linux implementation at all.
bool get supportsVideoPlayback => Platform.isAndroid || Platform.isIOS;

/// Whether animated artwork can be played via `media_kit`.
bool get supportsAnimatedArtwork =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Whether animated artwork can be played by either backend.
bool get canPlayAnimatedArtwork =>
    supportsVideoPlayback || supportsAnimatedArtwork;

/// Whether the in-app APK updater is meaningful on this platform.
bool get supportsApkUpdater => Platform.isAndroid;

/// Built-in media position lag compensation.
///
/// Windows GSMTC does not extrapolate position between samples, so reports lag
/// behind the audible playhead by ~500ms. Android's MediaNotificationListener
/// already extrapolates elapsed time since `lastPositionUpdateTime`, so adding
/// extra lag there pushes the UI ahead of audio and fights seek confirmation.
Duration get defaultNativeLag =>
    Platform.isWindows ? const Duration(milliseconds: 500) : Duration.zero;