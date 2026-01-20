import 'package:flutter/material.dart';
import 'dart:math' as math;

class CompassWidget extends StatefulWidget {
  final double rotation;
  final VoidCallback onTap;

  const CompassWidget({super.key, required this.rotation, required this.onTap});

  @override
  State<CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<CompassWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(CompassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotation != widget.rotation) {
      _rotationAnimation =
          Tween<double>(
            begin: _rotationAnimation.value,
            end:
                -widget.rotation *
                (math.pi / 180), // Convert to radians and invert
          ).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeInOut,
            ),
          );
      _animationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _rotationAnimation,
          builder: (context, child) {
            return Transform.rotate(
              angle: _rotationAnimation.value,
              child: const Icon(Icons.navigation, color: Colors.red, size: 28),
            );
          },
        ),
      ),
    );
  }
}
