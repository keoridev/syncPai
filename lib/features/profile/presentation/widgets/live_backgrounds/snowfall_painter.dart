import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Высокопроизводительный процедурный холст эффекта «Падающий снег» (Live Snowfall).
/// Многослойные частицы снега разного размера, скорости, глубины и ракурса
/// с естественным покачиванием от ветра (sin/cos sway) и мягким мерцанием.
class LiveSnowfallPainter extends CustomPainter {
  final double animationValue;
  final Color snowColor;
  final int flakeCount;

  static final List<_SnowflakeParticle> _cachedFlakes = _generateFlakes(110);

  LiveSnowfallPainter({
    required this.animationValue,
    this.snowColor = Colors.white,
    this.flakeCount = 90,
  });

  static List<_SnowflakeParticle> _generateFlakes(int count) {
    final rand = math.Random(42); // фиксированный seed для стабильности геометрии
    return List.generate(count, (i) {
      final depth = rand.nextDouble(); // 0.0 (далеко/мелкий) .. 1.0 (близко/крупный)
      return _SnowflakeParticle(
        baseX: rand.nextDouble(),
        speedY: 0.18 + depth * 0.45,
        radius: 1.0 + depth * 2.8,
        opacity: 0.25 + depth * 0.65,
        swayAmplitude: 8.0 + depth * 18.0,
        swayFrequency: 1.2 + rand.nextDouble() * 2.0,
        swayPhase: rand.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paintSoft = Paint()
      ..color = snowColor
      ..style = PaintingStyle.fill;

    final paintGlow = Paint()
      ..color = snowColor.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0)
      ..style = PaintingStyle.fill;

    final count = math.min(flakeCount, _cachedFlakes.length);

    for (int i = 0; i < count; i++) {
      final f = _cachedFlakes[i];

      // Прогресс падения по вертикали (бесшовный цикл)
      final yProgress = (animationValue * f.speedY + (i / count)) % 1.0;
      final y = yProgress * (size.height + 30) - 15;

      // Горизонтальное покачивание (естественный бриз)
      final sway = math.sin((animationValue * math.pi * 2 * f.swayFrequency) + f.swayPhase) * f.swayAmplitude;
      final x = (f.baseX * size.width + sway) % size.width;

      final currentAlpha = f.opacity * (0.8 + 0.2 * math.cos(animationValue * math.pi * 4 + f.swayPhase));
      paintSoft.color = snowColor.withValues(alpha: currentAlpha.clamp(0.1, 0.95));

      // Крупные снежинки рисуются с неоновым мягким свечением
      if (f.radius > 2.5) {
        canvas.drawCircle(Offset(x, y), f.radius * 1.4, paintGlow);
      }
      canvas.drawCircle(Offset(x, y), f.radius, paintSoft);
    }
  }

  @override
  bool shouldRepaint(covariant LiveSnowfallPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.snowColor != snowColor;
  }
}

class _SnowflakeParticle {
  final double baseX;
  final double speedY;
  final double radius;
  final double opacity;
  final double swayAmplitude;
  final double swayFrequency;
  final double swayPhase;

  const _SnowflakeParticle({
    required this.baseX,
    required this.speedY,
    required this.radius,
    required this.opacity,
    required this.swayAmplitude,
    required this.swayFrequency,
    required this.swayPhase,
  });
}

