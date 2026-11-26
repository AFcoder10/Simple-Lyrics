import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../spinning_blur_background.dart';
import 'static_accent_background.dart';
import 'acrylic_overlay.dart';

class BackgroundController extends StatelessWidget {
  final Uint8List? albumArtBytes;
  final bool forceStatic;
  final bool isPlaying;

  const BackgroundController({
    super.key,
    required this.albumArtBytes,
    this.forceStatic = false,
    this.isPlaying = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackgroundStyle>(
      valueListenable: SettingsService().backgroundStyle,
      builder: (context, style, _) {
        if (forceStatic) {
          return StaticColorBackground(
            albumArtBytes: albumArtBytes,
            forceStatic: true,
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          child: _buildBackground(style),
        );
      },
    );
  }

  Widget _buildBackground(BackgroundStyle style) {
    switch (style) {
      case BackgroundStyle.spinningBlur:
        return SpinningBlurBackground(
          key: const ValueKey('spinningBlur'),
          albumArtBytes: albumArtBytes,
          isPlaying: isPlaying,
        );
      case BackgroundStyle.acrylic:
        return Stack(
          key: const ValueKey('acrylic'),
          fit: StackFit.expand,
          children: [
            SpinningBlurBackground(
              albumArtBytes: albumArtBytes,
              isPlaying: isPlaying,
            ),
            const StaticAcrylicOverlay(),
          ],
        );
      case BackgroundStyle.staticColor:
        return StaticColorBackground(
          key: const ValueKey('staticColor'),
          albumArtBytes: albumArtBytes,
        );
    }
  }
}
