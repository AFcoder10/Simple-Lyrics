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
      duration: const Duration(milliseconds: 1400),
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
    return AnimatedBuilder(
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
    for (var slice in slices) total += slice.value;
    if (total == 0) return;

    // Extrusion technique: We draw the same 2D pie chart repeatedly, moving up the Y axis.
    // We draw from the bottom (chartHeight) to the top (0).
    // This creates a perfect, flawless physical 3D cylinder.
    final int layers = chartHeight.toInt();

    for (int layer = layers; layer >= 0; layer--) {
      // The current layer's bounding box is shifted down by 'layer' pixels.
      // Since we draw layer=layers first and layer=0 last, we are drawing from bottom to top visually.
      final currentRect = rect.shift(Offset(0, layer.toDouble()));
      
      double startAngle = -math.pi / 2;
      
      for (int i = 0; i < slices.length; i++) {
        final slice = slices[i];
        final sweepAngle = (slice.value / total) * 2 * math.pi * progress;
        
        final path = Path()
          ..moveTo(currentRect.center.dx, currentRect.center.dy)
          ..arcTo(currentRect, startAngle, sweepAngle, false)
          ..close();

        // If we are drawing the "body" (depth) layers, darken the color slightly
        // We can also apply a pseudo-gradient by darkening the color more on the left/right edges
        // But simply drawing the base color with a shadow multiplier works great for stacking.
        Color sliceColor = slice.color;
        
        if (layer > 0) {
          // It's a wall layer. Darken it based on its angle to simulate directional light!
          // We can calculate the middle angle of this slice to determine how much light it gets.
          final midAngle = startAngle + (sweepAngle / 2);
          // Normalize midAngle to 0..2pi
          final normalizedAngle = (midAngle % (2 * math.pi) + (2 * math.pi)) % (2 * math.pi);
          
          // Let's assume light comes from the top-left (-pi/4)
          // We use cosine to find how much the slice faces the light
          final lightIntensity = math.cos(normalizedAngle + math.pi / 4);
          
          final hsl = HSLColor.fromColor(sliceColor);
          // Map lightIntensity (-1 to 1) to a lightness modifier
          final shadowAmt = 0.15 - (lightIntensity * 0.1); 
          
          sliceColor = hsl.withLightness((hsl.lightness - shadowAmt).clamp(0.0, 1.0)).toColor();
        } else {
          // Top layer (layer == 0). Keep it bright, and maybe add a top edge highlight.
          final hsl = HSLColor.fromColor(sliceColor);
          sliceColor = hsl.withLightness((hsl.lightness + 0.05).clamp(0.0, 1.0)).toColor();
        }

        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = sliceColor;

        canvas.drawPath(path, paint);

        // Draw a subtle border on the top layer to make the rim pop
        if (layer == 0) {
          final topHighlight = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = Colors.white.withValues(alpha: 0.3);
          canvas.drawPath(path, topHighlight);
        } else if (layer == layers) {
          // Draw a dark border on the absolute bottom layer to ground it
          final bottomShadow = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = Colors.black.withValues(alpha: 0.5);
          canvas.drawPath(path, bottomShadow);
        } else if (layer % 5 == 0) {
           // draw subtle separation lines on the walls so they look physical
           final wallLine = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5
            ..color = Colors.black.withValues(alpha: 0.05);
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
