import 'package:flutter/material.dart';

/// Smooth progress bar that animates between values using AnimationController.
/// Uses FractionallySizedBox for GPU-friendly width animation.
class SmoothProgressBar extends StatefulWidget {
  final double value;
  final Color fillColor;
  final Color backgroundColor;
  final double height;
  final BorderRadius borderRadius;

  const SmoothProgressBar({
    super.key,
    required this.value,
    this.fillColor = Colors.white,
    this.backgroundColor = const Color(0x33FFFFFF),
    this.height = 4,
    this.borderRadius = const BorderRadius.all(Radius.circular(2)),
  });

  @override
  State<SmoothProgressBar> createState() => _SmoothProgressBarState();
}

class _SmoothProgressBarState extends State<SmoothProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _lastValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _lastValue = widget.value;
    _animation = AlwaysStoppedAnimation(widget.value);
  }

  @override
  void didUpdateWidget(SmoothProgressBar old) {
    super.didUpdateWidget(old);
    if ((widget.value - _lastValue).abs() > 0.001) {
      _animation = Tween<double>(begin: _lastValue, end: widget.value)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
      _lastValue = widget.value;
    }
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
        builder: (context, _) {
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: widget.borderRadius,
            ),
            clipBehavior: Clip.hardEdge,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _animation.value.clamp(0.0, 1.0),
                heightFactor: 1.0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.fillColor,
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
