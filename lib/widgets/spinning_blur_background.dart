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
  final bool isPlaying;

  const SpinningBlurBackground({
    super.key,
    required this.albumArtBytes,
    this.isPlaying = true,
  });

  @override
  State<SpinningBlurBackground> createState() => _SpinningBlurBackgroundState();
}

class _SpinningBlurBackgroundState extends State<SpinningBlurBackground>
    with TickerProviderStateMixin {
  late final Ticker _spinTicker;
  final ValueNotifier<double> _spinPhase = ValueNotifier<double>(0.0);
  Duration _lastSpinElapsed = Duration.zero;
  double _playMomentum = 1.0;
  late final AnimationController _fadeController;

  ui.Image? _cachedVibrantImage;
  ui.Image? _currentImage;
  ui.Image? _previousImage;
  int _artworkGeneration = 0;
  int _blurGeneration = 0;
  Timer? _blurDebounceTimer;
  late final _MotionSeed _motion;

  @override
  void initState() {
    super.initState();
    _playMomentum = widget.isPlaying ? 1.0 : 0.14;
    _spinTicker = createTicker((elapsed) {
      final dt = (elapsed - _lastSpinElapsed).inMicroseconds / 1e6;
      _lastSpinElapsed = elapsed;
      if (dt <= 0 || dt > 0.25) return;

      final targetMomentum = widget.isPlaying ? 1.0 : 0.14;
      final damp = 1.0 - math.exp(-dt * 2.4);
      _playMomentum += (targetMomentum - _playMomentum) * damp;
      if ((targetMomentum - _playMomentum).abs() < 0.002) {
        _playMomentum = targetMomentum;
      }

      final speed = SettingsService().blurAnimationSpeed.value.clamp(0.1, 10.0);
      _spinPhase.value += dt * (speed / 26.0) * _playMomentum;
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
    _blurDebounceTimer?.cancel();
    _spinTicker.dispose();
    _spinPhase.dispose();
    _fadeController.dispose();
    _cachedVibrantImage?.dispose();
    _currentImage?.dispose();
    _previousImage?.dispose();
    super.dispose();
  }

  void _onBlurIntensityChanged() {
    _blurDebounceTimer?.cancel();
    _blurDebounceTimer = Timer(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      if (_cachedVibrantImage != null) {
        _reblurCachedVibrant();
      } else {
        _updateArtworkImage();
      }
    });
  }

  @override
  void didUpdateWidget(SpinningBlurBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumArtBytes != widget.albumArtBytes) {
      _updateArtworkImage();
    }
  }

  /// Runs the two-pass blur directly on an already tone-mapped [vibrant]
  /// image without disposing [vibrant], so blur slider changes skip decode and
  /// pixel tone-mapping entirely.
  Future<ui.Image> _preBlurFromVibrant(ui.Image vibrant, double sigma) async {
    final w = vibrant.width;
    final h = vibrant.height;
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

    if (sigma <= 0.05) {
      return _copyImage(vibrant);
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

    final inputBytes = Uint8List.fromList(byteData.buffer.asUint8List());
    final processed = await compute(_processVibrantRgbaBytes, inputBytes);
    return _decodeRgbaImage(processed, source.width, source.height);
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

  Future<void> _reblurCachedVibrant() async {
    final vibrant = _cachedVibrantImage;
    if (vibrant == null) return;

    final blurGen = ++_blurGeneration;
    final artGen = _artworkGeneration;

    try {
      final sigma = SettingsService().blurIntensity.value;
      final blurred = await _preBlurFromVibrant(vibrant, sigma);
      if (!mounted || artGen != _artworkGeneration || blurGen != _blurGeneration) {
        blurred.dispose();
        return;
      }
      final oldCurrent = _currentImage;
      setState(() {
        _currentImage = blurred;
      });
      oldCurrent?.dispose();
    } catch (e) {
      // Keep the existing image if blur fails mid-drag.
    }
  }

  Future<void> _updateArtworkImage() async {
    if (widget.albumArtBytes == null || widget.albumArtBytes!.isEmpty) {
      return;
    }

    final gen = ++_artworkGeneration;
    final blurGen = ++_blurGeneration;

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

      final ui.Image vibrant = await _createVibrantHighlightSafeImage(rawImage);
      rawImage.dispose();
      if (!mounted || gen != _artworkGeneration) {
        vibrant.dispose();
        return;
      }

      final sigma = SettingsService().blurIntensity.value;
      final ui.Image blurredImage = await _preBlurFromVibrant(vibrant, sigma);
      if (!mounted || gen != _artworkGeneration || blurGen != _blurGeneration) {
        vibrant.dispose();
        blurredImage.dispose();
        return;
      }

      final oldVibrant = _cachedVibrantImage;
      _cachedVibrantImage = vibrant;
      oldVibrant?.dispose();

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: _fadeController,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _ArtworkBackgroundPainter(
                      animation: _spinPhase,
                      currentImage: _currentImage,
                      previousImage: _previousImage,
                      crossfade: _fadeController.value,
                      motion: _motion,
                    ),
                  );
                },
              );
            },
          ),
          // Subtle contrast vignette: keeps the center colors glowing while
          // giving top/bottom dimmed lyrics lines extra contrast.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x38000000),
                    Color(0x14000000),
                    Color(0x14000000),
                    Color(0x3D000000),
                  ],
                  stops: [0.0, 0.28, 0.72, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
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

  final Paint _layerPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;

  final Paint _accentPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true
    ..blendMode = BlendMode.plus;

  final Paint _fallbackPaint = Paint()..color = const Color(0xFF0A0A0A);

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
      canvas.drawRect(Offset.zero & size, _fallbackPaint);
      return;
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    if (hasPrevious && crossfade < 1.0) {
      _drawImage(canvas, size, previousImage!, (1.0 - crossfade).clamp(0.0, 1.0));
    }

    if (hasCurrent) {
      final opacity = hasPrevious ? crossfade.clamp(0.0, 1.0) : 1.0;
      _drawImage(canvas, size, currentImage!, opacity);
    }

    canvas.restore();
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
    final breath3 = 1.16 + 0.10 * (0.5 + 0.5 * math.sin(t * 0.37 + motion.xPhase[2]));

    final center = Offset(size.width / 2, size.height / 2);

    // Base drifting layer
    _layerPaint.color = Color.fromRGBO(255, 255, 255, opacity);
    canvas.save();
    canvas.translate(
      center.dx + rawDx1 * panBudget,
      center.dy + rawDy1 * panBudget,
    );
    canvas.rotate(angle1);
    canvas.scale(baseScale * breath1, baseScale * breath1);
    canvas.translate(-imgW / 2, -imgH / 2);
    canvas.drawImage(image, Offset.zero, _layerPaint);
    canvas.restore();

    // Counter-moving mirrored layer so color blobs morph organically
    _layerPaint.color = Color.fromRGBO(255, 255, 255, (opacity * 0.42).clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(
      center.dx + rawDx2 * panBudget,
      center.dy + rawDy2 * panBudget,
    );
    canvas.rotate(angle2);
    canvas.scale(-baseScale * breath2, baseScale * breath2);
    canvas.translate(-imgW / 2, -imgH / 2);
    canvas.drawImage(image, Offset.zero, _layerPaint);
    canvas.restore();

    // Soft additive chromatic pool floating higher behind the active lyrics
    _accentPaint.color = Color.fromRGBO(255, 255, 255, (opacity * 0.12).clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(
      center.dx - rawDx2 * (panBudget * 0.7),
      size.height * 0.38 + rawDy1 * (panBudget * 0.65),
    );
    canvas.rotate(angle1 * 0.55 + 2.2);
    canvas.scale(baseScale * breath3, baseScale * breath3);
    canvas.translate(-imgW / 2, -imgH / 2);
    canvas.drawImage(image, Offset.zero, _accentPaint);
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

/// Top-level isolate worker that boosts vibrance and compresses highlights on a
/// 128x128 RGBA image without stalling the main UI thread.
Uint8List _processVibrantRgbaBytes(Uint8List pixels) {
  final pixelCount = pixels.length ~/ 4;

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

    final toneProtect = _smoothstep(0.04, 0.14, luma) *
        (1.0 - _smoothstep(0.86, 0.96, luma));
    final colorProtect = _smoothstep(0.03, 0.14, chroma);
    final protect = toneProtect * colorProtect;

    final vibrance =
        1.0 + ((1.45 + 0.35 * brightFactor) * (1.0 - chroma) * protect);

    var r = _clamp01(luma + (or - luma) * vibrance);
    var g = _clamp01(luma + (og - luma) * vibrance);
    var b = _clamp01(luma + (ob - luma) * vibrance);

    final newLuma = _luma(r, g, b);
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

  return pixels;
}

double _compressHighlights(double x, double knee, double ceiling) {
  if (x <= knee) return x;
  final headroom = (ceiling - knee).clamp(0.05, 1.0);
  final normalized = ((x - knee) / (1.0 - knee)).clamp(0.0, 1.0);
  final compressed = 1.0 - math.pow(1.0 - normalized, 2.2);
  return knee + headroom * compressed;
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

double _midtoneContrast(double x, double amount) {
  if (amount <= 0) return x;
  final curved = x * x * (3.0 - 2.0 * x);
  return _lerpDouble(x, curved, amount.clamp(0.0, 1.0));
}
