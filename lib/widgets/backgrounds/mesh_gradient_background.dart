import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class MeshGradientBackground extends StatefulWidget {
  final Uint8List? albumArtBytes;

  const MeshGradientBackground({super.key, required this.albumArtBytes});

  @override
  State<MeshGradientBackground> createState() => _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Color> _colors = [const Color(0xFF0A0A0A)];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _extractColors();
  }

  @override
  void didUpdateWidget(MeshGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumArtBytes != widget.albumArtBytes) {
      _extractColors();
    }
  }

  Future<void> _extractColors() async {
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
      // FIXED: replaced || with && so that album covers with dark backgrounds and colorful accents are parsed as colorful.
      final bool isArtworkGrayscale = dominantHsl.saturation < 0.08 && maxPaletteSaturation < 0.12;

      final List<Color> extracted = [];
      if (isArtworkGrayscale) {
        extracted.add(dominantColor);
      } else {
        // Collect all distinct colorful swatches
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

        // Query swatches in preference order
        addCandidate(palette.vibrantColor);
        addCandidate(palette.darkVibrantColor);
        addCandidate(palette.lightVibrantColor);
        addCandidate(palette.mutedColor);
        addCandidate(palette.darkMutedColor);
        addCandidate(palette.lightMutedColor);

        // Scan other raw palette colors for highly populated accents
        for (final pc in palette.paletteColors) {
          final sat = HSLColor.fromColor(pc.color).saturation;
          if (pc.population >= totalPopulation * 0.02 && sat >= 0.15) {
            if (!candidates.any((c) => c.color == pc.color)) {
              candidates.add(pc);
            }
          }
        }

        // Sort candidates by population descending so the most prominent colors are used
        candidates.sort((a, b) => b.population.compareTo(a.population));

        for (final pc in candidates) {
          extracted.add(pc.color);
        }

        // Fallback to dominant color
        if (extracted.isEmpty) {
          extracted.add(dominantColor);
        }
      }
      
      // Normalize colors to be dark enough but still vibrant/glowing
      final List<Color> normalized = extracted.map((c) {
        final hsl = HSLColor.fromColor(c);
        if (isArtworkGrayscale) {
          return hsl.withSaturation(0.0).withLightness(hsl.lightness.clamp(0.04, 0.08)).toColor();
        } else {
          // Saturation protection: if saturation is low (below 0.15), it is mostly a neutral color.
          // Scale down saturation to prevent noise leak.
          final double satFactor = (hsl.saturation / 0.15).clamp(0.0, 1.0);
          final double finalSaturation = hsl.saturation * satFactor;
          // Clamp lightness to 0.18 to 0.32 so blobs are beautiful glowing accents
          return hsl.withSaturation(finalSaturation).withLightness(hsl.lightness.clamp(0.18, 0.32)).toColor();
        }
      }).toList();

      if (mounted) {
        setState(() {
          _colors = normalized;
        });
      }
    } catch (e) {
      // Fallback
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _MeshPainter(
            animationValue: _controller.value,
            colors: _colors,
          ),
          child: Container(),
        );
      },
    );
  }
}

class _MeshPainter extends CustomPainter {
  final double animationValue;
  final List<Color> colors;

  _MeshPainter({required this.animationValue, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0A0A));

    if (colors.isEmpty) return;

    final random = math.Random(42); // Seed for consistency

    // Draw multiple blobs
    for (int i = 0; i < 5; i++) {
      final color = colors[i % colors.length];
      
      // Each blob has its own orbit
      final orbitRadiusX = size.width * (0.3 + random.nextDouble() * 0.4);
      final orbitRadiusY = size.height * (0.3 + random.nextDouble() * 0.4);
      final speed = 0.5 + random.nextDouble() * 1.5;
      final phase = random.nextDouble() * math.pi * 2;
      
      final dx = size.width / 2 + math.cos(animationValue * math.pi * 2 * speed + phase) * orbitRadiusX;
      final dy = size.height / 2 + math.sin(animationValue * math.pi * 2 * (speed * 0.8) + phase) * orbitRadiusY;
      
      final blobSize = size.width * (0.8 + random.nextDouble() * 0.6);

      final gradient = RadialGradient(
        colors: [
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(dx, dy), radius: blobSize));

      canvas.drawCircle(
        Offset(dx, dy),
        blobSize,
        Paint()..shader = gradient..blendMode = BlendMode.screen,
      );
    }
    
    // Add a dark overlay to ensure text contrast
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.2),
    );
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.colors != colors;
  }
}
