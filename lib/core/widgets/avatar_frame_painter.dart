import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Тематический кастомный отрисовщик сюжетных рамок аватара
/// (Сакура с ветвью и опадающими лепестками, Кибер-катаны с разрядами молний,
/// Аура Теневого Монарха с восходящим дымом, Глитч-матрица с бегущим кодом).
class ThematicAvatarFramePainter extends CustomPainter {
  final double animationValue;
  final String frameType;
  final List<Color> colors;
  final double outerSize;

  ThematicAvatarFramePainter({
    required this.animationValue,
    required this.frameType,
    required this.colors,
    required this.outerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = outerSize / 2;

    switch (frameType) {
      case 'sakura':
        _paintSakuraFrame(canvas, center, radius);
        break;
      case 'cyber_blade':
        _paintCyberBladeFrame(canvas, center, radius);
        break;
      case 'shadow_monarch':
        _paintShadowMonarchFrame(canvas, center, radius);
        break;
      case 'matrix_glitch':
        _paintMatrixGlitchFrame(canvas, center, radius);
        break;
      default:
        _paintDefaultAura(canvas, center, radius);
        break;
    }
  }

  // --- 1. ТЕМА «САКУРА» (Sakura Blossom & Lord) ---
  void _paintSakuraFrame(Canvas canvas, Offset center, double radius) {
    final branchPaint = Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Ветвь сакуры, изящно обвивающая рамку с левой и нижней стороны
    final branchPath = Path();
    branchPath.addArc(
      Rect.fromCircle(center: center, radius: radius + 2.5),
      math.pi * 0.75,
      math.pi * 0.95,
    );
    canvas.drawPath(branchPath, branchPaint);

    // Цветы на ветви
    final flowerPaint = Paint()..style = PaintingStyle.fill;
    const flowerAngles = [math.pi * 0.85, math.pi * 1.15, math.pi * 1.45];
    for (final fa in flowerAngles) {
      final fx = center.dx + (radius + 3.0) * math.cos(fa);
      final fy = center.dy + (radius + 3.0) * math.sin(fa);

      flowerPaint.color = const Color(0xFFFF85A2);
      canvas.drawCircle(Offset(fx, fy), 4.2, flowerPaint);
      flowerPaint.color = Colors.white;
      canvas.drawCircle(Offset(fx, fy), 1.6, flowerPaint);
    }

    // 8 опадающих и кружащихся на ветру лепестков с синусоидальной траекторией
    final petalPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 8; i++) {
      final seed = (i * 0.28);
      final progress = (animationValue * 0.85 + seed) % 1.0;
      final py = (progress * (radius * 2 + 16)) - (radius + 8);
      final sway = math.sin(progress * math.pi * 2 + i) * 14.0;
      final px = sway + (math.cos(i * 1.2) * (radius * 0.65));

      final petalAngle = animationValue * math.pi * 3 + i;

      canvas.save();
      canvas.translate(center.dx + px, center.dy + py);
      canvas.rotate(petalAngle);

      petalPaint.color = Color.lerp(
        const Color(0xFFFFB2C9),
        const Color(0xFFFF4081),
        progress,
      )!.withValues(alpha: (1.0 - (progress - 0.5).abs() * 1.4).clamp(0.2, 0.95));

      final path = Path();
      path.moveTo(0, -4);
      path.cubicTo(2.5, -2, 3, 2, 0, 4.5);
      path.cubicTo(-3, 2, -2.5, -2, 0, -4);
      path.close();

      canvas.drawPath(path, petalPaint);
      canvas.restore();
    }
  }

  // --- 2. ТЕМА «КИБЕРПАНК / КАТАНЫ» (Cyber Blade) ---
  void _paintCyberBladeFrame(Canvas canvas, Offset center, double radius) {
    final bladeLength = radius * 2.5;

    // Скрещенные катаны на фоне
    final katanaPaint = Paint()
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Левая и правая катаны под 45 градусов
    const angles = [-math.pi / 4, math.pi / 4];
    for (int i = 0; i < angles.length; i++) {
      final a = angles[i];
      final p1 = Offset(center.dx - (bladeLength / 2) * math.cos(a), center.dy - (bladeLength / 2) * math.sin(a));
      final p2 = Offset(center.dx + (bladeLength / 2) * math.cos(a), center.dy + (bladeLength / 2) * math.sin(a));

      // Неоновое свечение лезвия
      glowPaint.color = (i == 0 ? const Color(0xFF00F0FF) : const Color(0xFFFF007F)).withValues(alpha: 0.6);
      canvas.drawLine(p1, p2, glowPaint);

      // Яркий стальной стержень лезвия
      katanaPaint.color = Colors.white;
      canvas.drawLine(p1, p2, katanaPaint);
    }

    // Бегущие электрические разряды (lightning arcs)
    final sparkPaint = Paint()
      ..color = const Color(0xFF00F0FF)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final sparkProgress = (animationValue * 4) % 1.0;
    final sparkAngle = animationValue * math.pi * 4;
    final sx = center.dx + (radius + 2) * math.cos(sparkAngle);
    final sy = center.dy + (radius + 2) * math.sin(sparkAngle);

    final lightningPath = Path();
    lightningPath.moveTo(sx, sy);
    lightningPath.lineTo(sx + math.sin(sparkProgress * 10) * 6, sy + math.cos(sparkProgress * 10) * 6);
    lightningPath.lineTo(sx + 3, sy - 4);
    canvas.drawPath(lightningPath, sparkPaint);

    // Периодический RGB-глитч сдвиг (хроматическая аберрация)
    final isGlitching = (animationValue * 10 % 1.0) > 0.88;
    if (isGlitching) {
      final glitchPaint = Paint()
        ..color = const Color(0xFFFF0055).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center.translate(2.5, -1.5), radius, glitchPaint);

      glitchPaint.color = const Color(0xFF00FFFF).withValues(alpha: 0.5);
      canvas.drawCircle(center.translate(-2.5, 1.5), radius, glitchPaint);
    }
  }

  // --- 3. ТЕМА «ТЕНЕВОЙ МОНАРХ / БЕЗДНА» (Shadow Aura) ---
  void _paintShadowMonarchFrame(Canvas canvas, Offset center, double radius) {
    final t = animationValue;

    // Восходящие темные языки пламени снизу вверх
    final flamePaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 14; i++) {
      final angle = (i * 2 * math.pi / 14);
      final heightFactor = 4.0 + math.sin(t * 8 + i * 2).abs() * 9.0;
      final fx = center.dx + (radius + 1.5) * math.cos(angle);
      final fy = center.dy + (radius + 1.5) * math.sin(angle);

      canvas.save();
      canvas.translate(fx, fy);
      canvas.rotate(angle + math.pi / 2);

      flamePaint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          const Color(0xFF7B1FA2),
          const Color(0xFF311B92),
          Colors.black.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(-3, -heightFactor, 6, heightFactor));

      final flamePath = Path();
      flamePath.moveTo(-2.5, 0);
      flamePath.quadraticBezierTo(0, -heightFactor * 1.1, 0, -heightFactor);
      flamePath.quadraticBezierTo(0, -heightFactor * 1.1, 2.5, 0);
      flamePath.close();

      canvas.drawPath(flamePath, flamePaint);
      canvas.restore();
    }

    // Восходящие фиолетовые частицы дыма и искры
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 9; i++) {
      final progress = (t * 1.2 + (i * 0.11)) % 1.0;
      final py = center.dy + (radius * 1.1) - (progress * (radius * 2.2));
      final px = center.dx + math.sin(progress * math.pi * 3 + i) * (radius * 0.85);

      final alpha = (math.sin(progress * math.pi)).clamp(0.1, 0.9);
      sparkPaint.color = const Color(0xFFE040FB).withValues(alpha: alpha);
      canvas.drawCircle(Offset(px, py), 1.8 + (1.0 - progress) * 1.2, sparkPaint);
    }
  }

  // --- 4. ТЕМА «МАТРИЦА» (Code Glitch) ---
  void _paintMatrixGlitchFrame(Canvas canvas, Offset center, double radius) {
    // Вращающаяся гексагональная рамка
    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 2 * math.pi / 6) + (animationValue * math.pi);
      final x = center.dx + (radius + 2.0) * math.cos(angle);
      final y = center.dy + (radius + 2.0) * math.sin(angle);
      if (i == 0) {
        hexPath.moveTo(x, y);
      } else {
        hexPath.lineTo(x, y);
      }
    }
    hexPath.close();

    final hexPaint = Paint()
      ..color = const Color(0xFF00FF66).withValues(alpha: 0.75)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawPath(hexPath, hexPaint);

    // Пиксельные неоновые блоки на углах (распад на пиксели)
    final pixelPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 12; i++) {
      final seed = (i * 0.19);
      final blockProgress = (animationValue * 2 + seed) % 1.0;
      final angle = (i * 2 * math.pi / 12);
      final dist = radius + 3.0 + (blockProgress * 8.0);
      final bx = center.dx + dist * math.cos(angle);
      final by = center.dy + dist * math.sin(angle);

      final pixelAlpha = (1.0 - blockProgress).clamp(0.1, 0.95);
      pixelPaint.color = const Color(0xFF00FF66).withValues(alpha: pixelAlpha);
      canvas.drawRect(Rect.fromLTWH(bx, by, 3.2, 3.2), pixelPaint);
    }
  }

  void _paintDefaultAura(Canvas canvas, Offset center, double radius) {
    final auraPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          ...colors,
          colors.first,
        ],
        transform: GradientRotation(animationValue * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(center, radius, auraPaint);
  }

  @override
  bool shouldRepaint(covariant ThematicAvatarFramePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.frameType != frameType ||
        oldDelegate.outerSize != outerSize;
  }
}

