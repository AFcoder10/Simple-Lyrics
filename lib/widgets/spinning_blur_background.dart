import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// Full-screen animated blob background.
///
/// This intentionally avoids image layers, blur filters, rotated squares, and
/// clipped stacks. Every blob is painted as a radial circle directly on canvas,
/// so there are no rectangular layer bounds to leak into the animation.
class SpinningBlurBackground extends StatefulWidget {
  final Uint8List? albumArtBytes;

  const SpinningBlurBackground({
    super.key,
    required this.albumArtBytes,
  });

  @override
  State<SpinningBlurBackground> createState() => _SpinningBlurBackgroundState();
}

class _SpinningBlurBackgroundState extends State<SpinningBlurBackground>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _fadeController;

  ui.Image? _currentImage;
  ui.Image? _previousImage;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: _calculateDuration(),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1.0,
    );

    SettingsService().blurIntensity.addListener(_onSettingsChanged);
    SettingsService().blurAnimationSpeed.addListener(_onSettingsChanged);

    _updateArtworkImage();
  }

  @override
  void dispose() {
    SettingsService().blurIntensity.removeListener(_onSettingsChanged);
    SettingsService().blurAnimationSpeed.removeListener(_onSettingsChanged);
    _spinController.dispose();
    _fadeController.dispose();
    _currentImage?.dispose();
    _previousImage?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    _spinController.duration = _calculateDuration();
    if (_spinController.isAnimating) {
      _spinController.repeat(); // Restart with new duration
    }
    _updateArtworkImage(); // Re-blur with new intensity
  }

  Duration _calculateDuration() {
    // defaults to 26s when speed is 1.0. 
    // Higher speed means shorter duration
    final speed = SettingsService().blurAnimationSpeed.value.clamp(0.1, 10.0);
    return Duration(milliseconds: (26000 ~/ speed));
  }

  @override
  void didUpdateWidget(SpinningBlurBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumArtBytes != widget.albumArtBytes) {
      _updateArtworkImage();
    }
  }

  /// Pre-blur the image so the painter never needs a GPU ImageFilter.
  /// First boosts saturation and contrast, then two passes at
  /// high sigma produce the deep, diffuse, vibrant blur for the background.
  Future<ui.Image> _preBlurImage(ui.Image source) async {
    final w = source.width;
    final h = source.height;
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

    final vibrant = await _createVibrantHighlightSafeImage(source);
    final double sigma = SettingsService().blurIntensity.value;

    if (sigma <= 0.05) {
      return vibrant;
    }

    // --- Pass 1: heavy blur ---
    final r1 = ui.PictureRecorder();
    final c1 = Canvas(r1, rect);
    c1.drawImage(
      vibrant,
      Offset.zero,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    final p1 = r1.endRecording();
    final pass1 = await p1.toImage(w, h);
    p1.dispose();
    vibrant.dispose();

    // --- Pass 2: second blur pass for deeper diffusion ---
    final r2 = ui.PictureRecorder();
    final c2 = Canvas(r2, rect);
    c2.drawImage(
      pass1,
      Offset.zero,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    final p2 = r2.endRecording();
    final pass2 = await p2.toImage(w, h);
    p2.dispose();
    pass1.dispose();

    return pass2;
  }

  Future<ui.Image> _createVibrantHighlightSafeImage(ui.Image source) async {
    final byteData = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return _copyImage(source);

    final pixels = Uint8List.fromList(byteData.buffer.asUint8List());
    const sat = 1.55;
    const con = 1.18;
    const highlightStart = 0.72;
    const highlightCeiling = 0.68;

    for (int i = 0; i < pixels.length; i += 4) {
      var r = pixels[i] / 255.0;
      var g = pixels[i + 1] / 255.0;
      var b = pixels[i + 2] / 255.0;

      final luma = _luma(r, g, b);
      r = _clamp01(luma + (r - luma) * sat);
      g = _clamp01(luma + (g - luma) * sat);
      b = _clamp01(luma + (b - luma) * sat);

      r = _clamp01((r - 0.5) * con + 0.5);
      g = _clamp01((g - 0.5) * con + 0.5);
      b = _clamp01((b - 0.5) * con + 0.5);

      final brightLuma = _luma(r, g, b);
      if (brightLuma > highlightStart) {
        final amount =
            ((brightLuma - highlightStart) / (1.0 - highlightStart))
                .clamp(0.0, 1.0);
        final targetLuma = _lerpDouble(
          brightLuma,
          highlightCeiling,
          Curves.easeOutCubic.transform(amount),
        );
        final scale = targetLuma / brightLuma;
        r *= scale;
        g *= scale;
        b *= scale;
      }

      pixels[i] = (_clamp01(r) * 255).round();
      pixels[i + 1] = (_clamp01(g) * 255).round();
      pixels[i + 2] = (_clamp01(b) * 255).round();
    }

    return _decodeRgbaImage(pixels, source.width, source.height);
  }

  Future<ui.Image> _copyImage(ui.Image source) async {
    final rect = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);
    canvas.drawImage(source, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(source.width, source.height);
    picture.dispose();
    return image;
  }

  Future<ui.Image> _decodeRgbaImage(Uint8List pixels, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  double _luma(double r, double g, double b) {
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  Future<void> _updateArtworkImage() async {
    if (widget.albumArtBytes == null || widget.albumArtBytes!.isEmpty) {
      return;
    }

    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        widget.albumArtBytes!,
        targetWidth: 128,
        targetHeight: 128,
        allowUpscaling: false,
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image rawImage = frameInfo.image;
      if (!mounted) {
        rawImage.dispose();
        return;
      }

      // Pre-blur the image so the painter just draws an already-blurred bitmap.
      final ui.Image blurredImage = await _preBlurImage(rawImage);
      rawImage.dispose(); // no longer needed
      if (!mounted) {
        blurredImage.dispose();
        return;
      }

      // IMPORTANT: set fade to 0 BEFORE updating images in setState,
      // so the painter never sees the new image at full opacity for a frame.
      _fadeController.value = 0.0;

      final oldPrevious = _previousImage;
      setState(() {
        _previousImage = _currentImage;
        _currentImage = blurredImage;
      });
      oldPrevious?.dispose();

      // Smooth ease-out crossfade
      _fadeController.forward(from: 0.0).then((_) {
        if (mounted) {
          final done = _previousImage;
          if (done != null) {
            setState(() => _previousImage = null);
            done.dispose();
          }
        }
      });
    } catch (e) {
      // Keep the last good image to avoid random interim colors.
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _fadeController,
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _ArtworkBackgroundPainter(
                    animation: _spinController,
                    currentImage: _currentImage,
                    previousImage: _previousImage,
                    crossfade: _fadeController.value,
                  ),
                ),
                // Small floor for text contrast; bright pixels are handled
                // per-artwork before blur so colors stay vibrant.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.10),
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }
}

class _ArtworkBackgroundPainter extends CustomPainter {
  final Animation<double> animation;
  final ui.Image? currentImage;
  final ui.Image? previousImage;
  final double crossfade;

  _ArtworkBackgroundPainter({
    required this.animation,
    required this.currentImage,
    required this.previousImage,
    required this.crossfade,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final hasCurrent = currentImage != null;
    final hasPrevious = previousImage != null;

    if (!hasCurrent && !hasPrevious) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF0A0A0A),
      );
      return;
    }

    // Draw previous image fading out
    if (hasPrevious && crossfade < 1.0) {
      _drawImage(canvas, size, previousImage!, (1.0 - crossfade).clamp(0.0, 1.0));
    }

    // Draw current image fading in
    if (hasCurrent) {
      final opacity = hasPrevious ? crossfade.clamp(0.0, 1.0) : 1.0;
      _drawImage(canvas, size, currentImage!, opacity);
    }
  }

  void _drawImage(Canvas canvas, Size size, ui.Image image, double opacity) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // The absolute maximum distance from the center to any screen corner is half the diagonal.
    // So the diagonal itself is the minimum size the image needs to be to cover the screen at ANY rotation.
    final screenDiagonal = math.sqrt(size.width * size.width + size.height * size.height);
    final minImgDim = math.min(imgW, imgH);
    
    // The scale required to make the image large enough to cover the entire diagonal
    final requiredScale = screenDiagonal / minImgDim;
    
    // Add 25% extra scale so we have plenty of room to pan around
    final scale = requiredScale * 1.25;
    
    // The surplus physical pixels we have available for panning.
    // This is the maximum distance the center of the image can move in ANY direction.
    final maxPan = ((minImgDim * scale) - screenDiagonal) / 2;
    
    // Because the image can pan in X and Y SIMULTANEOUSLY (moving diagonally),
    // the maximum diagonal distance is sqrt(maxX^2 + maxY^2).
    // To ensure this never exceeds maxPan, we divide by sqrt(2).
    final safeMaxPan = maxPan / math.sqrt(2);
    final maxX = safeMaxPan;
    final maxY = safeMaxPan;

    final time = math.pi * 2 * animation.value;
    
    // Create an extremely liquid, pseudo-random path using 5 "octaves" of waves (fractal noise).
    // The larger, slower waves provide the main sweeping motions, while the higher frequency 
    // waves add intricate, unpredictable wiggles on top.
    // The amplitudes (0.35 + 0.25 + 0.20 + 0.12 + 0.08) sum exactly to 1.0.
    final rawDx = math.sin(time * 1) * 0.35 + 
                  math.sin(time * 2 + 1.0) * 0.25 + 
                  math.sin(time * 3 + 2.0) * 0.20 +
                  math.sin(time * 4 + 3.0) * 0.12 +
                  math.sin(time * 5 + 4.0) * 0.08;
                  
    final rawDy = math.cos(time * 1 + 0.5) * 0.35 + 
                  math.cos(time * 2 + 1.5) * 0.25 + 
                  math.cos(time * 3 + 2.5) * 0.20 +
                  math.cos(time * 4 + 3.5) * 0.12 +
                  math.cos(time * 5 + 4.5) * 0.08;
    
    final dx = rawDx * maxX;
    final dy = rawDy * maxY;
    
    // Full 360-degree rotation, heavily modulated by two overlapping waves for a deeply organic "surge"
    final angleNoise = math.sin(time * 2) * 0.25 + math.cos(time * 3 + 1.0) * 0.15;
    final angle = time + angleNoise;

    final center = Offset(size.width / 2, size.height / 2);
    // No ImageFilter needed — the image is already pre-blurred.
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, opacity);

    canvas.save();
    canvas.translate(center.dx + dx, center.dy + dy);
    canvas.rotate(angle);
    canvas.scale(scale, scale);
    canvas.translate(-imgW / 2, -imgH / 2);

    canvas.drawImage(image, Offset.zero, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtworkBackgroundPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.currentImage != currentImage ||
        oldDelegate.previousImage != previousImage ||
        oldDelegate.crossfade != crossfade;
  }
}
