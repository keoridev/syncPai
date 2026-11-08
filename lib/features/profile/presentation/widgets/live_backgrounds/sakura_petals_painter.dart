import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Модель отдельного процедурного лепестка сакуры
class _SakuraPetal {
  final double xRatio;
  final double yOffset;
  final double speed;
  final double swayFreq;
  final double swayAmp;
  final double size;
  final double rotationSpeed;
  final double baseAngle;
  final double opacity;

  const _SakuraPetal({
    required this.xRatio,
    required this.yOffset,
    required this.speed,
    required this.swayFreq,
    required this.swayAmp,
    required this.size,
    required this.rotationSpeed,
    required this.baseAngle,
    required this.opacity,
  });
}

/// Процедурный холст падающих лепестков сакуры (Falling Sakura Petals)
/// с физикой ветра, синусоидальным покачиванием и вращением.
class SakuraPetalsPainter extends CustomPainter {
  final double animationValue;
  final Color petalColor;
  final int count;

  late final List<_SakuraPetal> _petals;

  SakuraPetalsPainter({
    required this.animationValue,
    this.petalColor = const Color(0xFFFF85A2),
    this.count = 32,
  }) {
    _petals = List.generate(count, (i) {
      final seed = (i * 37 + 19) % 1000;
      return _SakuraPetal(
        xRatio: (seed % 100) / 100.0,
        yOffset: ((seed ~/ 10) % 100) / 100.0,
        speed: 0.6 + ((seed % 7) * 0.12),
        swayFreq: 2.0 + ((seed % 5) * 0.6),
        swayAmp: 18.0 + ((seed % 8) * 4.0),
        size: 7.0 + ((seed % 6) * 1.5),
        rotationSpeed: (seed % 2 == 0 ? 1 : -1) * (1.2 + ((seed % 4) * 0.4)),
        baseAngle: ((seed % 360) * math.pi) / 180.0,
        opacity: 0.55 + ((seed % 5) * 0.09),
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final petal in _petals) {
      // Вертикальное падение с зацикливанием
      final progress = (animationValue * petal.speed + petal.yOffset) % 1.0;
      final y = progress * (size.height + 40) - 20;

      // Горизонтальное синусоидальное покачивание (ветер)
      final sway = math.sin((progress * math.pi * 2 * petal.swayFreq) + petal.baseAngle) * petal.swayAmp;
      final x = (petal.xRatio * size.width + sway) % (size.width + 30) - 15;

      // Вращение лепестка вокруг центра
      final angle = petal.baseAngle + (animationValue * math.pi * 2 * petal.rotationSpeed);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);

      // Рисуем естественную каплевидную форму лепестка сакуры
      final path = Path();
      final w = petal.size;
      final h = petal.size * 1.6;

      path.moveTo(0, -h / 2);
      path.cubicTo(w * 0.8, -h * 0.3, w * 0.9, h * 0.2, 0, h / 2);
      path.cubicTo(-w * 0.9, h * 0.2, -w * 0.8, -h * 0.3, 0, -h / 2);
      path.close();

      paint.shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: petal.opacity * 0.85),
          petalColor.withValues(alpha: petal.opacity),
          const Color(0xFFE056FD).withValues(alpha: petal.opacity * 0.6),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(-w, -h / 2, w * 2, h));

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant SakuraPetalsPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.petalColor != petalColor;
  }
}

