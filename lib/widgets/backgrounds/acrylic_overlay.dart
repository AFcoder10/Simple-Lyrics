import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../services/settings_service.dart';

// Cached images to switch quickly
ui.Image? _cachedFineGrain;
ui.Image? _cachedRipple;
ui.Image? _cachedCrystalline;

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
    if (_cachedRipple == null) {
      _cachedRipple = await _generateRipple();
    }
    if (_cachedCrystalline == null) {
      _cachedCrystalline = await _generateCrystalline();
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

  Future<ui.Image> _generateRipple() async {
    const size = 128;
    final pixels = Uint8List(size * size * 4);
    
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final i = (y * size + x) * 4;
        // Simple organic ripple generation using interacting sine waves
        double val = math.sin(x * 0.1) + math.sin(y * 0.1) + math.sin((x + y) * 0.07);
        val += math.sin(math.sqrt(x * x + y * y) * 0.15); // Radial
        
        final gray = ((val + 4.0) / 8.0 * 255).clamp(0, 255).toInt();
        pixels[i] = gray;
        pixels[i + 1] = gray;
        pixels[i + 2] = gray;
        pixels[i + 3] = 255;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels, size, size, ui.PixelFormat.rgba8888, completer.complete,
    );
    return completer.future;
  }

  Future<ui.Image> _generateCrystalline() async {
    const size = 128.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    final random = math.Random();

    canvas.drawColor(Colors.black, BlendMode.src);
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw random geometric shapes (Voronoi/crystal approximation)
    for (int i = 0; i < 60; i++) {
      final path = Path();
      final cx = random.nextDouble() * size;
      final cy = random.nextDouble() * size;
      final radius = 10.0 + random.nextDouble() * 20.0;
      
      path.moveTo(cx + radius * math.cos(0), cy + radius * math.sin(0));
      for (int j = 1; j < 5; j++) {
        final angle = j * math.pi * 2 / (3 + random.nextInt(4));
        path.lineTo(cx + radius * math.cos(angle), cy + radius * math.sin(angle));
      }
      path.close();
      
      paint.color = Colors.white.withValues(alpha: 0.1 + random.nextDouble() * 0.4);
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    return await picture.toImage(size.toInt(), size.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<AcrylicTexture>(
        valueListenable: SettingsService().acrylicTexture,
        builder: (context, texture, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Tint Layer depending on style
              Container(
                color: _getTintForTexture(texture),
              ),
              // Texture Layer
              if (_getTextureImage(texture) != null)
                Opacity(
                  opacity: _getOpacityForTexture(texture),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _TexturePainter(_getTextureImage(texture)!, texture),
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

  ui.Image? _getTextureImage(AcrylicTexture texture) {
    switch (texture) {
      case AcrylicTexture.fineGrain: return _cachedFineGrain;
      case AcrylicTexture.frosted: return null; // Frosted is just pure tint/blur
      case AcrylicTexture.ripple: return _cachedRipple;
      case AcrylicTexture.crystalline: return _cachedCrystalline;
    }
  }

  double _getOpacityForTexture(AcrylicTexture texture) {
    switch (texture) {
      case AcrylicTexture.fineGrain: return 0.04;
      case AcrylicTexture.frosted: return 0.0;
      case AcrylicTexture.ripple: return 0.07;
      case AcrylicTexture.crystalline: return 0.25;
    }
  }

  Color _getTintForTexture(AcrylicTexture texture) {
    switch (texture) {
      case AcrylicTexture.fineGrain: return Colors.black.withValues(alpha: 0.15);
      case AcrylicTexture.frosted: return Colors.white.withValues(alpha: 0.08); // Whitish soft tint
      case AcrylicTexture.ripple: return Colors.black.withValues(alpha: 0.20);
      case AcrylicTexture.crystalline: return Colors.black.withValues(alpha: 0.10);
    }
  }
}

class _TexturePainter extends CustomPainter {
  final ui.Image textureImage;
  final AcrylicTexture textureType;

  _TexturePainter(this.textureImage, this.textureType);

  @override
  void paint(Canvas canvas, Size size) {
    // Scale up the larger textures so they don't look tiny
    final double scale = textureType == AcrylicTexture.fineGrain ? 1.0 : 3.0;
    
    // Use mirror tiling for ripple/crystalline to hide seams
    final TileMode tileMode = textureType == AcrylicTexture.fineGrain 
        ? TileMode.repeated 
        : TileMode.mirror;

    final matrix = Matrix4.identity()..scale(scale, scale);

    final paint = Paint()
      ..shader = ImageShader(
        textureImage,
        tileMode,
        tileMode,
        matrix.storage,
      );
      
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_TexturePainter oldDelegate) => 
      textureImage != oldDelegate.textureImage || textureType != oldDelegate.textureType;
}
