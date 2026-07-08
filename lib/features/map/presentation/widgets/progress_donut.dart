import 'dart:math';

import 'package:flutter/material.dart';

/// Donut progres sederhana (tanpa dependensi eksternal). Menampilkan cincin
/// terisi sebesar [sudah]/[total] dengan persentase di tengah.
class ProgressDonut extends StatelessWidget {
  final int sudah;
  final int total;
  final double size;
  final double stroke;
  final Color trackColor;
  final Color progressColor;
  final Color textColor;
  final bool showCount;

  const ProgressDonut({
    super.key,
    required this.sudah,
    required this.total,
    this.size = 72,
    this.stroke = 9,
    this.trackColor = const Color(0x33FFFFFF),
    this.progressColor = Colors.white,
    this.textColor = Colors.white,
    this.showCount = false,
  });

  @override
  Widget build(BuildContext context) {
    final persen = total == 0 ? 0.0 : (sudah / total).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(persen, stroke, trackColor, progressColor),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(persen * 100).round()}%',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.24,
                  height: 1.05,
                ),
              ),
              if (showCount)
                Text(
                  '$sudah/$total',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.8),
                    fontSize: size * 0.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double persen;
  final double stroke;
  final Color track;
  final Color progress;

  _DonutPainter(this.persen, this.stroke, this.track, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = progress
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, 2 * pi, false, trackPaint);
    if (persen > 0) {
      canvas.drawArc(rect, -pi / 2, 2 * pi * persen, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.persen != persen ||
      old.stroke != stroke ||
      old.track != track ||
      old.progress != progress;
}
