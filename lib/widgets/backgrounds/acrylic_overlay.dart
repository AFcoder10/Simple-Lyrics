import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

ui.Image? _cachedNoiseImage;

class StaticAcrylicOverlay extends StatefulWidget {
  const StaticAcrylicOverlay({super.key});

  @override
  State<StaticAcrylicOverlay> createState() => _StaticAcrylicOverlayState();
}

class _StaticAcrylicOverlayState extends State<StaticAcrylicOverlay> {
  @override
  void initState() {
    super.initState();
    if (_cachedNoiseImage == null) {
      _generateNoise().then((image) {
        if (mounted) {
          setState(() {
            _cachedNoiseImage = image;
          });
        } else {
          _cachedNoiseImage = image;
        }
      });
    }
  }

  Future<ui.Image> _generateNoise() async {
    const size = 64;
    final pixels = Uint8List(size * size * 4);
    final random = math.Random();
    
    for (int i = 0; i < pixels.length; i += 4) {
      final gray = random.nextInt(256);
      pixels[i] = gray;     // R
      pixels[i + 1] = gray; // G
      pixels[i + 2] = gray; // B
      pixels[i + 3] = 255;  // A (fully opaque, we will use Opacity widget instead)
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Acrylic tint layer
          Container(
            color: Colors.black.withValues(alpha: 0.15),
          ),
          // Noise layer
          if (_cachedNoiseImage != null)
            Opacity(
              opacity: 0.04, // Very subtle grain
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _NoisePainter(_cachedNoiseImage!),
                  child: Container(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  final ui.Image noiseImage;

  _NoisePainter(this.noiseImage);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ImageShader(
        noiseImage,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      );
      
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_NoisePainter oldDelegate) => noiseImage != oldDelegate.noiseImage;
}
