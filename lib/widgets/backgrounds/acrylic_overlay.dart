import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../services/settings_service.dart';

ui.Image? _cachedFineGrain;

class StaticAcrylicOverlay extends StatefulWidget {
  const StaticAcrylicOverlay({super.key});

  @override
  State<StaticAcrylicOverlay> createState() => _StaticAcrylicOverlayState();
}

class _StaticAcrylicOverlayState extends State<StaticAcrylicOverlay> {
  @override
  void initState() {
    super.initState();
    _initTextures();
  }

  Future<void> _initTextures() async {
    if (_cachedFineGrain == null) {
      _cachedFineGrain = await _generateFineGrain();
    }
    if (mounted) setState(() {});
  }

  Future<ui.Image> _generateFineGrain() async {
    const size = 64;
    final pixels = Uint8List(size * size * 4);
    final random = math.Random();
    
    for (int i = 0; i < pixels.length; i += 4) {
      final gray = random.nextInt(256);
      pixels[i] = gray;     // R
      pixels[i + 1] = gray; // G
      pixels[i + 2] = gray; // B
      pixels[i + 3] = 255;  // A
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels, size, size, ui.PixelFormat.rgba8888, completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: SettingsService().grainIntensity,
        builder: (context, grainOpacity, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Tint Layer
              Container(
                color: Colors.black.withValues(alpha: 0.15),
              ),
              // Texture Layer
              if (_cachedFineGrain != null)
                Opacity(
                  opacity: grainOpacity,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _TexturePainter(_cachedFineGrain!),
                      child: Container(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TexturePainter extends CustomPainter {
  final ui.Image textureImage;

  _TexturePainter(this.textureImage);

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = Matrix4.identity();

    final paint = Paint()
      ..shader = ImageShader(
        textureImage,
        TileMode.repeated,
        TileMode.repeated,
        matrix.storage,
      );
      
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_TexturePainter oldDelegate) => 
      textureImage != oldDelegate.textureImage;
}
