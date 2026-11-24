import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/media_session_service.dart';
import '../services/window_service.dart';

/// Desktop keyboard shortcuts, active only on Windows.
///
/// Deliberately built on [CallbackShortcuts] rather than a raw [KeyboardListener]
/// so the bindings only fire when nothing else claims the key: pressing Space
/// inside the search field still types a space instead of pausing playback.
class DesktopShortcuts extends StatelessWidget {
  final MediaSessionService mediaService;
  final Widget child;

  const DesktopShortcuts({
    super.key,
    required this.mediaService,
    required this.child,
  });

  static const _shortSeek = Duration(seconds: 5);
  static const _longSeek = Duration(seconds: 15);

  void _seek(MediaSessionService service, Duration delta) {
    final target = service.displayPosition + delta;
    final duration = service.currentState.duration;
    if (duration > Duration.zero && target > duration) {
      return;
    }
    if (target < Duration.zero) {
      return;
    }
    service.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowService.isSupported) {
      return child;
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Playback
        const SingleActivator(LogicalKeyboardKey.space):
            _togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.keyK):
            _togglePlayPause,

        // Seeking
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            () => _seek(mediaService, -_shortSeek),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            () => _seek(mediaService, _shortSeek),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            () => _seek(mediaService, -_longSeek),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            () => _seek(mediaService, _longSeek),

        // Track navigation. On a phone these need a tap target, on a desktop
        // the arrow keys next to seek are the obvious home for them.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            mediaService.previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            mediaService.next,

        // Window. F11 toggles fullscreen over whatever mode is showing, Ctrl+M
        // swaps to the floating mini player, Esc backs out of either.
        const SingleActivator(LogicalKeyboardKey.f11):
            WindowService.toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyM, control: true):
            WindowService.toggleCompact,
        const SingleActivator(LogicalKeyboardKey.escape): _exitOverlayMode,
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  void _togglePlayPause() {
    if (mediaService.currentState.isPlaying) {
      mediaService.pause();
    } else {
      mediaService.play();
    }
  }

  void _exitOverlayMode() {
    // Esc only backs out of the modes layered on top of the desktop window —
    // it must not close the app when the plain window is showing.
    final current = WindowService.mode.value;
    if (current == WindowMode.fullscreen || current == WindowMode.compact) {
      WindowService.setMode(WindowMode.windowed);
    }
  }
}