import 'dart:math' as math;
import 'package:flutter/material.dart';

class _Star {
  final double xRatio;
  final double yRatio;
  final double radius;
  final double twinkleSpeed;
  final double twinkleOffset;
  final Color color;

  const _Star({
    required this.xRatio,
    required this.yRatio,
    required this.radius,
    required this.twinkleSpeed,
    required this.twinkleOffset,
    required this.color,
  });
}

/// Процедурный холст звездного неба и космического войда (Deep Starfield)
/// с мерцающими звездами и туманностями.
class StarfieldPainter extends CustomPainter {
  final double animationValue;
  final int starCount;

  late final List<_Star> _stars;

  static const List<Color> _palette = [
    Color(0xFFFFFFFF),
    Color(0xFF80D8FF),
    Color(0xFFB388FF),
    Color(0xFFFF80AB),
    Color(0xFF00E5FF),
  ];

  StarfieldPainter({
    required this.animationValue,
    this.starCount = 55,
  }) {
    _stars = List.generate(starCount, (i) {
      final seed = (i * 43 + 67) % 1000;
      return _Star(
        xRatio: (seed % 100) / 100.0,
        yRatio: ((seed ~/ 10) % 100) / 100.0,
        radius: 0.8 + ((seed % 5) * 0.4),
        twinkleSpeed: 1.5 + ((seed % 7) * 0.4),
        twinkleOffset: ((seed % 360) * math.pi) / 180.0,
        color: _palette[seed % _palette.length],
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Мягкая фиолетово-синяя космическая туманность
    final nebulaPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.4, -0.3),
        radius: 0.9,
        colors: [
          const Color(0xFF651FFF).withValues(alpha: 0.22),
          const Color(0xFF00D2FF).withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), nebulaPaint);

    final starPaint = Paint()..style = PaintingStyle.fill;

    for (final star in _stars) {
      // Медленный космический дрейф
      final x = (star.xRatio * size.width + (animationValue * 6.0)) % size.width;
      final y = star.yRatio * size.height;

      // Мерцание яркости
      final twinkle = (math.sin((animationValue * math.pi * 2 * star.twinkleSpeed) + star.twinkleOffset) + 1.0) / 2.0;
      final alpha = (0.25 + twinkle * 0.75).clamp(0.1, 1.0);

      starPaint.color = star.color.withValues(alpha: alpha);

      canvas.drawCircle(Offset(x, y), star.radius, starPaint);

      // Легкий ореол для ярких звезд
      if (star.radius > 1.8 && twinkle > 0.6) {
        final glowPaint = Paint()
          ..color = star.color.withValues(alpha: alpha * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(Offset(x, y), star.radius * 2.2, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

