import 'dart:math' as math;
import 'package:flutter/material.dart';

class PieChart3D extends StatefulWidget {
  final List<PieSlice3D> slices;
  final double height;

  const PieChart3D({
    super.key,
    required this.slices,
    this.height = 40.0,
  });

  @override
  State<PieChart3D> createState() => _PieChart3DState();
}

class _PieChart3DState extends State<PieChart3D> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(double.infinity, 250),
            painter: _PieChart3DPainter(
              slices: widget.slices,
              chartHeight: widget.height,
              progress: _animation.value,
            ),
          );
        },
      ),
    );
  }
}

class PieSlice3D {
  final double value;
  final Color color;

  PieSlice3D({
    required this.value,
    required this.color,
  });
}

class _PieChart3DPainter extends CustomPainter {
  final List<PieSlice3D> slices;
  final double chartHeight;
  final double progress;

  _PieChart3DPainter({
    required this.slices,
    required this.chartHeight,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    // We want the entire 3D cylinder (which spans from centerY to centerY + chartHeight)
    // to be perfectly centered in the canvas.
    final centerY = (size.height - chartHeight) / 2;
    final radius = size.width * 0.35;
    
    // We squash the Y axis to simulate viewing the chart at an angle (isometric perspective)
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: radius * 2,
      height: radius * 2 * 0.5,
    );

    double total = 0;
    for (final slice in slices) {
      total += slice.value;
    }
    if (total == 0) return;

    // Precompute sweeps & HSL colors once per paint instead of per layer (~35x fewer allocations).
    final int sliceCount = slices.length;
    final List<double> sweeps = List<double>.filled(sliceCount, 0);
    final List<HSLColor> hslColors = List<HSLColor>.generate(
      sliceCount,
      (i) => HSLColor.fromColor(slices[i].color),
    );
    final List<Color> topColors = List<Color>.generate(
      sliceCount,
      (i) => hslColors[i].withLightness((hslColors[i].lightness + 0.05).clamp(0.0, 1.0)).toColor(),
    );

    double angle = -math.pi / 2;
    final List<Color> wallColors = List<Color>.generate(sliceCount, (i) {
      final sweepAngle = (slices[i].value / total) * 2 * math.pi * progress;
      sweeps[i] = sweepAngle;
      final midAngle = angle + (sweepAngle / 2);
      angle += sweepAngle;
      final normalizedAngle = (midAngle % (2 * math.pi) + (2 * math.pi)) % (2 * math.pi);
      final lightIntensity = math.cos(normalizedAngle + math.pi / 4);
      final shadowAmt = 0.15 - (lightIntensity * 0.1);
      final hsl = hslColors[i];
      return hsl.withLightness((hsl.lightness - shadowAmt).clamp(0.0, 1.0)).toColor();
    });

    final int layers = chartHeight.toInt();
    final Path path = Path();
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    final Paint topHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.3);
    final Paint bottomShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.5);
    final Paint wallLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.black.withValues(alpha: 0.05);

    for (int layer = layers; layer >= 0; layer--) {
      final currentRect = rect.shift(Offset(0, layer.toDouble()));
      double startAngle = -math.pi / 2;

      for (int i = 0; i < sliceCount; i++) {
        final sweepAngle = sweeps[i];
        path
          ..reset()
          ..moveTo(currentRect.center.dx, currentRect.center.dy)
          ..arcTo(currentRect, startAngle, sweepAngle, false)
          ..close();

        fillPaint.color = layer > 0 ? wallColors[i] : topColors[i];
        canvas.drawPath(path, fillPaint);

        if (layer == 0) {
          canvas.drawPath(path, topHighlight);
        } else if (layer == layers) {
          canvas.drawPath(path, bottomShadow);
        } else if (layer % 5 == 0) {
          canvas.drawPath(path, wallLine);
        }

        startAngle += sweepAngle;
      }
    }
  }

  @override
  bool shouldRepaint(_PieChart3DPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.slices != slices;
  }
}
