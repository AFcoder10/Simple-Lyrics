import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../services/settings_service.dart';

class StaticColorBackground extends StatefulWidget {
  final Uint8List? albumArtBytes;

  const StaticColorBackground({super.key, required this.albumArtBytes});

  @override
  State<StaticColorBackground> createState() => _StaticColorBackgroundState();
}

class _StaticColorBackgroundState extends State<StaticColorBackground> {
  Color _backgroundColor = const Color(0xFF0A0A0A);

  @override
  void initState() {
    super.initState();
    SettingsService().staticVibrancy.addListener(_extractColor);
    SettingsService().staticContrast.addListener(_extractColor);
    _extractColor();
  }

  @override
  void dispose() {
    SettingsService().staticVibrancy.removeListener(_extractColor);
    SettingsService().staticContrast.removeListener(_extractColor);
    super.dispose();
  }

  @override
  void didUpdateWidget(StaticColorBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumArtBytes != widget.albumArtBytes) {
      _extractColor();
    }
  }

  Future<void> _extractColor() async {
    if (widget.albumArtBytes == null || widget.albumArtBytes!.isEmpty) return;

    try {
      final imageProvider = MemoryImage(widget.albumArtBytes!);
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 16,
      );

      Color picked = palette.vibrantColor?.color ?? 
                     palette.dominantColor?.color ?? 
                     const Color(0xFF0A0A0A);

      final vibrancy = SettingsService().staticVibrancy.value;
      final contrast = SettingsService().staticContrast.value;

      final hsl = HSLColor.fromColor(picked);
      
      // Calculate new lightness with contrast adjustment
      // Centralize around 0.25 since that's roughly the middle of previous 0.18-0.32 range
      final centeredLightness = (hsl.lightness - 0.25) * contrast + 0.25;
      
      final adjustedHsl = hsl
          .withSaturation((hsl.saturation * vibrancy).clamp(0.0, 1.0))
          .withLightness(centeredLightness.clamp(0.05, 0.8)); 
      
      if (mounted) {
        setState(() {
          _backgroundColor = adjustedHsl.toColor();
        });
      }
    } catch (e) {
      // Fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      child: Container(
        key: ValueKey(_backgroundColor),
        decoration: BoxDecoration(
          color: _backgroundColor,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _backgroundColor,
              _backgroundColor.withValues(alpha: 0.6),
            ],
          ),
        ),
      ),
    );
  }
}
