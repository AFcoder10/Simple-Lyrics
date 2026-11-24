import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How the desktop window is currently presented.
///
/// The app has one window, so these are mutually exclusive: a compact floating
/// mini player, the normal desktop window, or filling the monitor. Each mode
/// owns its own client size and pinning, which is why switching is a single
/// call rather than a sequence the caller has to get right.
enum WindowMode {
  /// Small, always-on-top single-pane player meant to float over other apps.
  compact,

  /// The default desktop window: artwork and metadata on the left, lyrics on
  /// the right.
  windowed,

  /// The same two-pane layout, stretched to the monitor.
  fullscreen,
}

/// Native window controls exposed by `windows/runner/window_bridge.cpp`.
///
/// Everything here is a no-op on platforms other than Windows, so call sites do
/// not need to guard each invocation.
class WindowService {
  static const _channel = MethodChannel('com.simplelyrics/window');

  /// Client size of each mode, in logical pixels at 96 DPI. The native layer
  /// scales these by the monitor's DPI and centres the result.
  static const (int, int) compactSize = (400, 640);
  static const (int, int) windowedSize = (1280, 800);

  /// Whether the app runs as a Windows desktop app.
  static bool get isSupported => Platform.isWindows;

  /// Current presentation mode. Listen to this to swap layouts.
  static final ValueNotifier<WindowMode> mode =
      ValueNotifier<WindowMode>(WindowMode.windowed);

  /// True while the window is covering the whole monitor.
  static bool get isFullscreen => mode.value == WindowMode.fullscreen;

  /// True while the window is the small pinned floating player.
  static bool get isCompact => mode.value == WindowMode.compact;

  /// Whether the window is pinned above other applications.
  static bool get isAlwaysOnTop => _alwaysOnTop;
  static bool _alwaysOnTop = false;

  /// Mode to return to when leaving fullscreen. Fullscreen is a view of
  /// whatever the user was doing, not a place they live in.
  static WindowMode _modeBeforeFullscreen = WindowMode.windowed;

  /// Switches presentation, applying size, pinning and chrome together.
  static Future<void> setMode(WindowMode next) async {
    if (!isSupported) return;
    final current = mode.value;
    if (next == current) return;

    // Leaving fullscreen first means the restore rectangle below is the real
    // windowed/compact geometry rather than the monitor-sized one.
    if (current == WindowMode.fullscreen) {
      await _setFullscreen(false);
    }

    switch (next) {
      case WindowMode.compact:
        await setFixedSize(compactSize.$1, compactSize.$2);
        await _setAlwaysOnTop(true);
        break;
      case WindowMode.windowed:
        await setFixedSize(windowedSize.$1, windowedSize.$2);
        await _setAlwaysOnTop(false);
        break;
      case WindowMode.fullscreen:
        // Pinning is meaningless once the window owns the whole monitor, and
        // leaving it set would keep the restore-to-windowed path topmost.
        await _setAlwaysOnTop(false);
        await _setFullscreen(true);
        break;
    }

    mode.value = next;
  }

  /// Flips between fullscreen and whatever mode was showing before it.
  static Future<void> toggleFullscreen() async {
    if (mode.value == WindowMode.fullscreen) {
      await setMode(_modeBeforeFullscreen);
    } else {
      _modeBeforeFullscreen = mode.value;
      await setMode(WindowMode.fullscreen);
    }
  }

  /// Flips between the floating mini player and the desktop window.
  static Future<void> toggleCompact() async {
    await setMode(mode.value == WindowMode.compact
        ? WindowMode.windowed
        : WindowMode.compact);
  }

  // --- Low level primitives -------------------------------------------------

  static Future<bool> _setFullscreen(bool value) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('setFullscreen', value);
      return result ?? value;
    } on PlatformException catch (e) {
      debugPrint('setFullscreen() failed: ${e.message}');
      return value;
    } on MissingPluginException {
      return value;
    }
  }

  static Future<bool> _setAlwaysOnTop(bool value) async {
    if (!isSupported) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('setAlwaysOnTop', value);
      _alwaysOnTop = result ?? value;
      return _alwaysOnTop;
    } on PlatformException catch (e) {
      debugPrint('setAlwaysOnTop() failed: ${e.message}');
      return _alwaysOnTop;
    } on MissingPluginException {
      return _alwaysOnTop;
    }
  }

  /// Resizes the window to an explicit client size in logical pixels. The
  /// window stays non-resizable afterwards.
  static Future<void> setFixedSize(int width, int height) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setFixedSize', [width, height]);
    } on PlatformException catch (e) {
      debugPrint('setFixedSize() failed: ${e.message}');
    } on MissingPluginException {
      // Nothing to do.
    }
  }
}
