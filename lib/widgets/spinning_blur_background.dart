import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  late final Ticker _spinTicker;
  final ValueNotifier<double> _spinPhase = ValueNotifier<double>(0.0);
  Duration _lastSpinElapsed = Duration.zero;
  late final AnimationController _fadeController;

  ui.Image? _currentImage;
  ui.Image? _previousImage;
  int _artworkGeneration = 0;
  late final _MotionSeed _motion;

  @override
  void initState() {
    super.initState();
    _spinTicker = createTicker((elapsed) {
      final dt = (elapsed - _lastSpinElapsed).inMicroseconds / 1e6;
      _lastSpinElapsed = elapsed;
      if (dt <= 0 || dt > 0.25) return;
      final speed = SettingsService().blurAnimationSpeed.value.clamp(0.1, 10.0);
      _spinPhase.value += dt * (speed / 26.0);
    })..start();

    _motion = _MotionSeed.random();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1.0,
    );

    SettingsService().blurIntensity.addListener(_onBlurIntensityChanged);

    _updateArtworkImage();
  }

  @override
  void dispose() {
    SettingsService().blurIntensity.removeListener(_onBlurIntensityChanged);
    _spinTicker.dispose();
    _spinPhase.dispose();
    _fadeController.dispose();
    _currentImage?.dispose();
    _previousImage?.dispose();
    super.dispose();
  }

  void _onBlurIntensityChanged() {
    _updateArtworkImage(); // Re-blur with new intensity
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
    final pixelCount = pixels.length ~/ 4;

    // Measure average cover brightness so dark covers keep their full glow
    // while bright/white/pastel covers get stronger highlight compression.
    double totalLuma = 0.0;
    for (int i = 0; i < pixels.length; i += 4) {
      totalLuma += _luma(
        pixels[i] / 255.0,
        pixels[i + 1] / 255.0,
        pixels[i + 2] / 255.0,
      );
    }
    final avgLuma = pixelCount > 0 ? totalLuma / pixelCount : 0.3;
    final brightFactor = _smoothstep(0.22, 0.65, avgLuma);
    final lumaCeiling = _lerpDouble(0.60, 0.48, brightFactor);

    for (int i = 0; i < pixels.length; i += 4) {
      final or = pixels[i] / 255.0;
      final og = pixels[i + 1] / 255.0;
      final ob = pixels[i + 2] / 255.0;

      final luma = _luma(or, og, ob);
      final maxc = or > og ? (or > ob ? or : ob) : (og > ob ? og : ob);
      final minc = or < og ? (or < ob ? or : ob) : (og < ob ? og : ob);
      final chroma = maxc - minc;

      // Near-gray, near-black and near-white pixels stay neutral. Vibrance
      // only boosts colorful pixels so album whites/blacks don't gain a tint.
      final toneProtect = _smoothstep(0.04, 0.14, luma) *
          (1.0 - _smoothstep(0.86, 0.96, luma));
      final colorProtect = _smoothstep(0.03, 0.14, chroma);
      final protect = toneProtect * colorProtect;

      // Rich vibrance boost (slightly stronger on bright pastel covers so
      // compressed highlights turn into deep jewel tones instead of gray).
      final vibrance = 1.0 + ((1.45 + 0.35 * brightFactor) * (1.0 - chroma) * protect);

      var r = _clamp01(luma + (or - luma) * vibrance);
      var g = _clamp01(luma + (og - luma) * vibrance);
      var b = _clamp01(luma + (ob - luma) * vibrance);

      // Restore original luma first, then apply midtone contrast + soft-knee
      // highlight compression so lyrics stay readable over bright covers.
      var newLuma = _luma(r, g, b);
      if (newLuma > 1e-5) {
        final scale = luma / newLuma;
        r = _clamp01(r * scale);
        g = _clamp01(g * scale);
        b = _clamp01(b * scale);
      }

      final contrasted = _midtoneContrast(luma, 0.28 * protect);
      final targetLuma = _compressHighlights(contrasted, 0.26, lumaCeiling);
      if (luma > 1e-5) {
        final scale = targetLuma / luma;
        r = _clamp01(r * scale);
        g = _clamp01(g * scale);
        b = _clamp01(b * scale);
      }

      pixels[i] = (_clamp01(r) * 255).round();
      pixels[i + 1] = (_clamp01(g) * 255).round();
      pixels[i + 2] = (_clamp01(b) * 255).round();
    }

    return _decodeRgbaImage(pixels, source.width, source.height);
  }

  /// Soft-knee roll-off above [knee] so bright areas never blow out to blinding
  /// white behind lyrics while keeping rich hues intact.
  double _compressHighlights(double x, double knee, double ceiling) {
    if (x <= knee) return x;
    final headroom = (ceiling - knee).clamp(0.05, 1.0);
    final normalized = ((x - knee) / (1.0 - knee)).clamp(0.0, 1.0);
    final compressed = 1.0 - math.pow(1.0 - normalized, 2.2);
    return knee + headroom * compressed;
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

  double _smoothstep(double edge0, double edge1, double x) {
    final t = _clamp01((x - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
  }

  /// Contrast curve that is exactly identity at 0 and 1, so blacks and whites
  /// do not move. [amount] 0 = original, 1 = full smoothstep.
  double _midtoneContrast(double x, double amount) {
    if (amount <= 0) return x;
    final curved = x * x * (3.0 - 2.0 * x);
    return _lerpDouble(x, curved, amount.clamp(0.0, 1.0));
  }

  Future<void> _updateArtworkImage() async {
    if (widget.albumArtBytes == null || widget.albumArtBytes!.isEmpty) {
      return;
    }

    final gen = ++_artworkGeneration;

    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        widget.albumArtBytes!,
        targetWidth: 128,
        targetHeight: 128,
        allowUpscaling: false,
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image rawImage = frameInfo.image;
      if (!mounted || gen != _artworkGeneration) {
        rawImage.dispose();
        return;
      }

      // Pre-blur the image so the painter just draws an already-blurred bitmap.
      final ui.Image blurredImage = await _preBlurImage(rawImage);
      rawImage.dispose(); // no longer needed
      if (!mounted || gen != _artworkGeneration) {
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
                    animation: _spinPhase,
                    currentImage: _currentImage,
                    previousImage: _previousImage,
                    crossfade: _fadeController.value,
                    motion: _motion,
                  ),
                ),
                // Subtle contrast vignette: keeps the center colors glowing while
                // giving top/bottom dimmed lyrics lines extra contrast.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.24),
                      ],
                      stops: const [0.0, 0.28, 0.72, 1.0],
                    ),
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

class _MotionSeed {
  _MotionSeed({
    required this.xPhase,
    required this.yPhase,
    required this.spinPhase,
  });

  factory _MotionSeed.random() {
    final rng = math.Random();
    return _MotionSeed(
      xPhase: List<double>.generate(5, (_) => rng.nextDouble() * math.pi * 2),
      yPhase: List<double>.generate(5, (_) => rng.nextDouble() * math.pi * 2),
      spinPhase: List<double>.generate(3, (_) => rng.nextDouble() * math.pi * 2),
    );
  }

  final List<double> xPhase;
  final List<double> yPhase;
  final List<double> spinPhase;
}

class _ArtworkBackgroundPainter extends CustomPainter {
  final ValueListenable<double> animation;
  final ui.Image? currentImage;
  final ui.Image? previousImage;
  final double crossfade;
  final _MotionSeed motion;

  _ArtworkBackgroundPainter({
    required this.animation,
    required this.currentImage,
    required this.previousImage,
    required this.crossfade,
    required this.motion,
  }) : super(repaint: animation);

  // Incommensurate frequencies so the path does not close on the 26s loop.
  static const _fx = <double>[0.37, 0.71, 1.13, 1.87, 2.63];
  static const _fy = <double>[0.53, 0.89, 1.31, 1.97, 2.81];
  static const _amp = <double>[0.36, 0.24, 0.18, 0.13, 0.09];
  static const _spinFreq = <double>[0.41, 0.79, 1.23];
  static const _spinAmp = <double>[0.42, 0.22, 0.12];

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

    if (hasPrevious && crossfade < 1.0) {
      _drawImage(canvas, size, previousImage!, (1.0 - crossfade).clamp(0.0, 1.0));
    }

    if (hasCurrent) {
      final opacity = hasPrevious ? crossfade.clamp(0.0, 1.0) : 1.0;
      _drawImage(canvas, size, currentImage!, opacity);
    }
  }

  void _drawImage(Canvas canvas, Size size, ui.Image image, double opacity) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final minImgDim = math.min(imgW, imgH);

    // After any rotation, only the inscribed circle of the square is
    // guaranteed to cover the screen. Cover that circle, then add pan room
    // and a filter-safety margin so corners never flash the clear color.
    final coverRadius =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;
    const safety = 1.08;
    final panBudget = coverRadius * 0.22;
    final neededRadius = coverRadius * safety + panBudget;
    final baseScale = (neededRadius * 2) / minImgDim;

    final t = math.pi * 2 * animation.value;
    var rawDx1 = 0.0;
    var rawDy1 = 0.0;
    var rawDx2 = 0.0;
    var rawDy2 = 0.0;
    for (var i = 0; i < _fx.length; i++) {
      rawDx1 += math.sin(t * _fx[i] + motion.xPhase[i]) * _amp[i];
      rawDy1 += math.cos(t * _fy[i] + motion.yPhase[i]) * _amp[i];
      rawDx2 += math.cos(t * _fy[i] + motion.yPhase[i] + 1.7) * _amp[i];
      rawDy2 += math.sin(t * _fx[i] + motion.xPhase[i] + 2.3) * _amp[i];
    }

    // Clamp onto the unit disk so X+Y never exceed the pan budget even when
    // every oscillator peaks at once.
    final mag1 = math.sqrt(rawDx1 * rawDx1 + rawDy1 * rawDy1);
    if (mag1 > 1.0) {
      rawDx1 /= mag1;
      rawDy1 /= mag1;
    }
    final mag2 = math.sqrt(rawDx2 * rawDx2 + rawDy2 * rawDy2);
    if (mag2 > 1.0) {
      rawDx2 /= mag2;
      rawDy2 /= mag2;
    }

    var angle1 = t * 0.83;
    var angle2 = -t * 0.61 + 1.4;
    for (var i = 0; i < _spinFreq.length; i++) {
      angle1 += math.sin(t * _spinFreq[i] + motion.spinPhase[i]) * _spinAmp[i];
      angle2 +=
          math.cos(t * (_spinFreq[i] * 0.9) + motion.spinPhase[i] + 0.9) *
              _spinAmp[i];
    }

    // Gentle scale breathing (>= 1.0 so corners remain strictly covered).
    final breath1 = 1.0 + 0.08 * (0.5 + 0.5 * math.sin(t * 0.67 + motion.xPhase[0]));
    final breath2 = 1.04 + 0.10 * (0.5 + 0.5 * math.cos(t * 0.53 + motion.yPhase[1]));

    final center = Offset(size.width / 2, size.height / 2);

    // Base drifting layer
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      center.dx + rawDx1 * panBudget,
      center.dy + rawDy1 * panBudget,
    );
    canvas.rotate(angle1);
    canvas.scale(baseScale * breath1, baseScale * breath1);
    canvas.translate(-imgW / 2, -imgH / 2);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    canvas.restore();

    // Counter-moving mirrored layer so color blobs morph organically
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      center.dx + rawDx2 * panBudget,
      center.dy + rawDy2 * panBudget,
    );
    canvas.rotate(angle2);
    canvas.scale(-baseScale * breath2, baseScale * breath2);
    canvas.translate(-imgW / 2, -imgH / 2);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true
        ..color = Color.fromRGBO(255, 255, 255, (opacity * 0.42).clamp(0.0, 1.0)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtworkBackgroundPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.currentImage != currentImage ||
        oldDelegate.previousImage != previousImage ||
        oldDelegate.crossfade != crossfade ||
        oldDelegate.motion != motion;
  }
}
