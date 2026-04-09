import 'package:flutter/material.dart';

/// Animated Counter Widget - Smoothly animates number changes
/// 
/// Uses TweenAnimationBuilder to create a count-up/count-down effect
/// when the value changes.
class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: value.toDouble(),
        end: value.toDouble(),
      ),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return Text(
          animatedValue.toInt().toString(),
          style: style,
        );
      },
    );
  }
}

/// Animated Counter with Scale Effect
/// 
/// Adds a subtle scale animation when the value changes
class AnimatedCounterWithScale extends StatefulWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedCounterWithScale({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<AnimatedCounterWithScale> createState() => _AnimatedCounterWithScaleState();
}

class _AnimatedCounterWithScaleState extends State<AnimatedCounterWithScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  int _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(AnimatedCounterWithScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _scaleController.forward().then((_) => _scaleController.reverse());
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: _previousValue.toDouble(),
          end: widget.value.toDouble(),
        ),
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        onEnd: () {
          setState(() {
            _previousValue = widget.value;
          });
        },
        builder: (context, animatedValue, child) {
          return Text(
            animatedValue.toInt().toString(),
            style: widget.style,
          );
        },
      ),
    );
  }
}