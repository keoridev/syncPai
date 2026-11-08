import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Процедурный холст неоновой киберпанк 3D-сетки (Cyberpunk Synthwave Grid)
/// с перспективой, точкой схода на горизонте и бегущими световыми импульсами.
class CyberpunkGridPainter extends CustomPainter {
  final double animationValue;
  final Color gridColor;
  final Color horizonColor;

  CyberpunkGridPainter({
    required this.animationValue,
    this.gridColor = const Color(0xFF00F0FF),
    this.horizonColor = const Color(0xFFFF007F),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final horizonY = size.height * 0.42;
    final vanishingPoint = Offset(size.width / 2, horizonY);

    // 1. Свечение горизонта (Неоновый закат/горизонт)
    final horizonPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(0.0, -0.16),
        radius: 0.85,
        colors: [
          horizonColor.withValues(alpha: 0.45),
          gridColor.withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), horizonPaint);

    // Линия горизонта
    final linePaint = Paint()
      ..color = horizonColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, horizonY), Offset(size.width, horizonY), linePaint);

    // 2. Перспективные вертикальные лучи (исходящие из центра горизонта)
    final rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const numRays = 18;
    for (int i = 0; i <= numRays; i++) {
      final t = i / numRays;
      // Нелинейное распределение к краям
      final bottomX = (t - 0.5) * 2.8 * size.width + (size.width / 2);

      final rayAlpha = (1.0 - (t - 0.5).abs() * 0.8).clamp(0.2, 0.75);
      rayPaint.color = gridColor.withValues(alpha: rayAlpha);

      canvas.drawLine(vanishingPoint, Offset(bottomX, size.height), rayPaint);
    }

    // 3. Бегущие горизонтальные линии сетки (перспективное сжатие)
    const numHorizontalLines = 12;
    final speed = animationValue % 1.0;

    for (int i = 0; i < numHorizontalLines; i++) {
      // Степенная функция для создания иллюзии 3D глубины
      final lineProgress = ((i + speed) / numHorizontalLines);
      final depth = math.pow(lineProgress, 2.5).toDouble();

      final y = horizonY + depth * (size.height - horizonY);
      if (y > size.height) continue;

      final alpha = (depth * 0.85).clamp(0.05, 0.9);
      final hPaint = Paint()
        ..color = Color.lerp(horizonColor, gridColor, depth)!.withValues(alpha: alpha)
        ..strokeWidth = 1.0 + (depth * 1.8);

      canvas.drawLine(Offset(0, y), Offset(size.width, y), hPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CyberpunkGridPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.horizonColor != horizonColor;
  }
}

