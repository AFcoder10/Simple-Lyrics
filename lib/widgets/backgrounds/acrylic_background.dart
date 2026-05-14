import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class AcrylicBackground extends StatefulWidget {
  final Uint8List? albumArtBytes;

  const AcrylicBackground({super.key, required this.albumArtBytes});

  @override
  State<AcrylicBackground> createState() => _AcrylicBackgroundState();
}

class _AcrylicBackgroundState extends State<AcrylicBackground> {
  ui.Image? _currentImage;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(AcrylicBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumArtBytes != widget.albumArtBytes) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.albumArtBytes == null || widget.albumArtBytes!.isEmpty) return;

    final codec = await ui.instantiateImageCodec(
      widget.albumArtBytes!,
      targetWidth: 300, // Downscale for performance since it will be blurred anyway
      targetHeight: 300,
    );
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _currentImage = frame.image;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base Color
        Container(color: const Color(0xFF0A0A0A)),
        
        // Blurred Artwork
        if (_currentImage != null)
          RawImage(
            image: _currentImage,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
          ),

        // Blur Filter & Tint
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),

        // Noise Texture Layer
        const _NoiseOverlay(),

        // Subtle gradient for depth
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.1),
                Colors.black.withValues(alpha: 0.4),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoiseOverlay extends StatelessWidget {
  const _NoiseOverlay();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _NoisePainter(),
        child: Container(),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1.0;

    final random = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), [Colors.transparent, Colors.transparent]); // Not using this for random

    // Draw sparse points to simulate grain
    // For performance, we use a fixed pattern or just a few points
    // A better way is to use a pre-generated noise image, but we'll try a simple pattern
    for (double i = 0; i < size.width; i += 3) {
      for (double j = 0; j < size.height; j += 3) {
        if ((i + j) % 7 == 0) {
          canvas.drawPoints(ui.PointMode.points, [Offset(i, j)], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
