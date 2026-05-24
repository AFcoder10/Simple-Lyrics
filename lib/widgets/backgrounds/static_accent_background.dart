import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../services/settings_service.dart';

class StaticColorBackground extends StatefulWidget {
  final Uint8List? albumArtBytes;
  final bool forceStatic;

  const StaticColorBackground({
    super.key,
    required this.albumArtBytes,
    this.forceStatic = false,
  });

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
      final imageProvider = ResizeImage(
        MemoryImage(widget.albumArtBytes!),
        width: 64,
        height: 64,
      );
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 16,
      );

      final dominantColor = palette.dominantColor?.color ?? const Color(0xFF0A0A0A);
      final dominantHsl = HSLColor.fromColor(dominantColor);
      
      final totalPopulation = palette.paletteColors.fold<int>(0, (sum, c) => sum + c.population);

      // Calculate max palette saturation for colors representing at least 2% of total pixels to filter compression noise
      double maxPaletteSaturation = 0.0;
      if (totalPopulation > 0) {
        for (final pc in palette.paletteColors) {
          if (pc.population >= totalPopulation * 0.02) {
            final sat = HSLColor.fromColor(pc.color).saturation;
            if (sat > maxPaletteSaturation) {
              maxPaletteSaturation = sat;
            }
          }
        }
      }
      
      // If the dominant color is grayscale (extremely low saturation) AND the maximum saturation among all major colors
      // is extremely low (less than 12%), the entire artwork is overwhelmingly black/white/gray. Keep background neutral.
      final bool isArtworkGrayscale = dominantHsl.saturation < 0.08 && maxPaletteSaturation < 0.12;

      Color picked = dominantColor;
      if (!isArtworkGrayscale) {
        final List<PaletteColor> candidates = [];
        
        void addCandidate(PaletteColor? pc) {
          if (pc == null) return;
          final isAlreadyAdded = candidates.any((c) => c.color == pc.color);
          if (isAlreadyAdded) return;
          
          final matched = palette.paletteColors.firstWhere(
            (c) => c.color == pc.color,
            orElse: () => pc,
          );
          
          final sat = HSLColor.fromColor(pc.color).saturation;
          // Lowered minimum population threshold to 1.5% to capture small beautiful colorful accents/details
          if (matched.population >= totalPopulation * 0.015 && sat >= 0.12) {
            candidates.add(matched);
          }
        }

        // Query swatches in preference order to find the best colorful accent
        addCandidate(palette.vibrantColor);
        addCandidate(palette.darkVibrantColor);
        addCandidate(palette.lightVibrantColor);
        addCandidate(palette.mutedColor);
        addCandidate(palette.darkMutedColor);
        addCandidate(palette.lightMutedColor);

        if (candidates.isNotEmpty) {
          // Sort by population descending to get the most prominent color
          candidates.sort((a, b) => b.population.compareTo(a.population));
          picked = candidates.first.color;
        } else if (dominantHsl.saturation < 0.12) {
          // If dominant color is neutral and no candidate swatches passed the threshold,
          // find ANY color in raw palette colors that has some saturation
          PaletteColor? fallbackColor;
          double maxSat = 0.0;
          for (final pc in palette.paletteColors) {
            final sat = HSLColor.fromColor(pc.color).saturation;
            if (sat > maxSat && sat >= 0.12) {
              maxSat = sat;
              fallbackColor = pc;
            }
          }
          if (fallbackColor != null) {
            picked = fallbackColor.color;
          }
        }
      }

      final vibrancy = SettingsService().staticVibrancy.value;
      final contrast = SettingsService().staticContrast.value;

      final hsl = HSLColor.fromColor(picked);
      
      final double finalSaturation;
      final double finalLightness;

      if (isArtworkGrayscale) {
        finalSaturation = 0.0;
        finalLightness = (hsl.lightness * 0.4).clamp(0.04, 0.08); // Deep neutral dark grey/black
      } else {
        // Saturation-based vibrancy falloff
        final double satFactor = (hsl.saturation / 0.15).clamp(0.0, 1.0);
        final double activeVibrancy = 1.0 + (vibrancy - 1.0) * satFactor;

        finalSaturation = (hsl.saturation * activeVibrancy).clamp(0.0, 1.0);
        final double centeredLightness = (hsl.lightness - 0.25) * contrast + 0.25;
        // Clamp to a safe dark range (0.04 to 0.18) so that white text has perfect contrast and readability
        finalLightness = centeredLightness.clamp(0.04, 0.18);
      }
      
      final adjustedHsl = hsl
          .withSaturation(finalSaturation)
          .withLightness(finalLightness);
      
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
    final decorationWidget = Container(
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
    );

    if (widget.forceStatic) {
      return RepaintBoundary(child: decorationWidget);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      child: decorationWidget,
    );
  }
}

