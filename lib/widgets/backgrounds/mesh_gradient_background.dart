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
      final imageProvider = MemoryImage(widget.albumArtBytes!);
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 16,
      );

      final List<Color> extracted = [];
      if (palette.vibrantColor != null) extracted.add(palette.vibrantColor!.color);
      if (palette.lightVibrantColor != null) extracted.add(palette.lightVibrantColor!.color);
      if (palette.darkVibrantColor != null) extracted.add(palette.darkVibrantColor!.color);
      if (palette.mutedColor != null) extracted.add(palette.mutedColor!.color);

      // Fill up to 4 colors if needed
      if (extracted.isEmpty) {
        extracted.add(palette.dominantColor?.color ?? const Color(0xFF0A0A0A));
      }
      
      // Normalize colors to be dark enough
      final List<Color> normalized = extracted.map((c) {
        final hsl = HSLColor.fromColor(c);
        return hsl.withLightness(hsl.lightness.clamp(0.05, 0.15)).toColor();
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
    final paint = Paint()..style = PaintingStyle.fill;
    
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
