import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 1. SOLO LEVELING: Теневой Монарх (Shadow Monarch)
/// Восходящие языки теневого тумана, темно-синее инфернальное пламя и рунические искры маны.
class SoloLevelingShadowPainter extends CustomPainter {
  final double animationValue;

  SoloLevelingShadowPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, 0.6),
        radius: 1.2,
        colors: [
          Color(0xFF160638),
          Color(0xFF090A1A),
          Color(0xFF04040A),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Восходящие теневые щупальца / волны дыма
    final tendrilPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 9; i++) {
      final seed = i * 0.13;
      final prog = (animationValue + seed) % 1.0;
      final xBase = size.width * ((i + 1) / 10.0);
      final sway = math.sin((prog * math.pi * 2) + i) * 28.0;

      final path = Path();
      final startY = size.height;
      final endY = size.height * (1.0 - (prog * 0.85));

      path.moveTo(xBase, startY);
      path.cubicTo(
        xBase + sway,
        startY - (startY - endY) * 0.35,
        xBase - sway * 1.2,
        startY - (startY - endY) * 0.7,
        xBase + sway * 0.8,
        endY,
      );

      final alpha = ((1.0 - prog) * 0.55).clamp(0.05, 0.7);
      tendrilPaint
        ..color = (i.isEven ? const Color(0xFF7C4DFF) : const Color(0xFF00E5FF)).withValues(alpha: alpha)
        ..strokeWidth = 3.5 + (1.0 - prog) * 6.0;

      canvas.drawPath(path, tendrilPaint);
    }

    // Искры темной маны, поднимающиеся вверх
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 28; i++) {
      final prog = (animationValue * 1.5 + (i * 0.04)) % 1.0;
      final px = (math.sin(i * 99.0 + prog * math.pi) * 0.45 + 0.5) * size.width;
      final py = (1.0 - prog) * size.height;
      final alpha = math.sin(prog * math.pi).clamp(0.0, 1.0);

      sparkPaint.color = (i % 3 == 0
              ? const Color(0xFF00F0FF)
              : (i % 3 == 1 ? const Color(0xFFB388FF) : const Color(0xFF651FFF)))
          .withValues(alpha: alpha * 0.85);

      canvas.drawCircle(Offset(px, py), 1.5 + (i % 3) * 1.0, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SoloLevelingShadowPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

/// 2. ATTACK ON TITAN: Трансформация титана (Titan Lightning Transformation)
/// Золотисто-янтарные ветвящиеся молнии, вспыхивающие сверху вниз сквозь грозовое небо.
class TitanLightningPainter extends CustomPainter {
  final double animationValue;

  TitanLightningPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Темно-бордовое грозовое небо
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF240E07),
          Color(0xFF140704),
          Color(0xFF0A0302),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, skyPaint);

    final pulse = (math.sin(animationValue * math.pi * 6) + 1.0) / 2.0;

    // Вспышка в эпицентре удара
    final glowCenter = Offset(size.width * 0.5, size.height * 0.15);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD54F).withValues(alpha: 0.25 + pulse * 0.2),
          const Color(0xFFFF6F00).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: size.width * 0.7));
    canvas.drawCircle(glowCenter, size.width * 0.7, glowPaint);

    // Ветвящиеся молнии трансформации
    final boltPaint = Paint()
      ..color = const Color(0xFFFFE082).withValues(alpha: 0.85)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final outerBoltPaint = Paint()
      ..color = const Color(0xFFFF8F00).withValues(alpha: 0.45)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int b = 0; b < 3; b++) {
      final shift = (b - 1) * (size.width * 0.22);
      final path = Path();
      double curX = (size.width * 0.5) + shift;
      double curY = 0;
      path.moveTo(curX, curY);

      final steps = 14;
      final stepY = size.height / steps;
      for (int s = 1; s <= steps; s++) {
        final jitter = math.sin((animationValue * 15.0) + (s * 3.7) + (b * 12.0)) * 22.0;
        curX += jitter;
        curY += stepY;
        path.lineTo(curX, curY);
      }

      canvas.drawPath(path, outerBoltPaint);
      canvas.drawPath(path, boltPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TitanLightningPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

/// 3. JUJUTSU KAISEN: Черная молния (Black Flash / Кокусэн)
/// Искривление пространства, черные разрывы с багровыми и алыми электрическими ореолами.
class BlackFlashPainter extends CustomPainter {
  final double animationValue;

  BlackFlashPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Color(0xFF1F0307),
          Color(0xFF0F0103),
          Color(0xFF050001),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final center = Offset(size.width * 0.5, size.height * 0.45);

    // Черные разломы пространства с красным неоновым ореолом
    final auraPaint = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.6)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final coreBlackPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int ray = 0; ray < 8; ray++) {
      final angle = (ray * (math.pi / 4.0)) + math.sin(animationValue * math.pi * 4 + ray) * 0.15;
      final path = Path();
      path.moveTo(center.dx, center.dy);

      double dist = 0;
      final maxDist = size.width * 0.65;
      while (dist < maxDist) {
        dist += 18.0;
        final perpJitter = math.sin(dist * 0.15 + animationValue * 18.0 + ray) * 12.0;
        final px = center.dx + dist * math.cos(angle) - perpJitter * math.sin(angle);
        final py = center.dy + dist * math.sin(angle) + perpJitter * math.cos(angle);
        path.lineTo(px, py);
      }

      canvas.drawPath(path, auraPaint);
      canvas.drawPath(path, coreBlackPaint);
    }

    // Центральная сфера деформации
    final pulse = (math.sin(animationValue * math.pi * 8) + 1.0) / 2.0;
    final centerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.black,
          const Color(0xFFFF1744).withValues(alpha: 0.8),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 45.0 + pulse * 15.0));
    canvas.drawCircle(center, 45.0 + pulse * 15.0, centerPaint);
  }

  @override
  bool shouldRepaint(covariant BlackFlashPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

/// 4. BLEACH: Банкай Гэцуга Тэнсё / Рэйацу (Bankai Reiatsu Waves)
/// Восходящие багровые и антрацитовые волны духовной энергии Ичиго Куросаки.
class BleachReiatsuPainter extends CustomPainter {
  final double animationValue;

  BleachReiatsuPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Color(0xFF26050C),
          Color(0xFF140206),
          Color(0xFF0A0103),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final wavePaint = Paint()..style = PaintingStyle.stroke;

    for (int i = 0; i < 7; i++) {
      final prog = (animationValue + (i * 0.15)) % 1.0;
      final y = size.height * (1.0 - prog);
      final alpha = math.sin(prog * math.pi).clamp(0.0, 1.0);

      wavePaint
        ..color = Color.lerp(
          const Color(0xFFFF1744),
          const Color(0xFFD50000),
          prog,
        )!.withValues(alpha: alpha * 0.65)
        ..strokeWidth = 2.0 + prog * 4.0;

      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += 16.0) {
        final waveY = y + math.sin((x / size.width * math.pi * 4) + (animationValue * math.pi * 4) + i) * 16.0;
        path.lineTo(x, waveY);
      }
      canvas.drawPath(path, wavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant BleachReiatsuPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

/// 5. EVANGELION: Абсолютное Террористическое Поле (A.T. Field / Eva-01)
/// Концентрические светящиеся янтарно-оранжевые восьмиугольники, пульсирующие из центра.
class EvangelionAtFieldPainter extends CustomPainter {
  final double animationValue;

  EvangelionAtFieldPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 1.1,
        colors: [
          Color(0xFF2B1204),
          Color(0xFF140801),
          Color(0xFF080300),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final center = Offset(size.width * 0.5, size.height * 0.45);
    final fieldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 6; i++) {
      final prog = (animationValue + (i / 6.0)) % 1.0;
      final r = (size.width * 0.08) + (prog * size.width * 0.65);
      final alpha = math.sin(prog * math.pi).clamp(0.0, 1.0);

      fieldPaint
        ..color = const Color(0xFFFF9100).withValues(alpha: alpha * 0.7)
        ..strokeWidth = 2.0 + (1.0 - prog) * 2.5;

      // Рисуем правильный восьмиугольник (Octagon)
      final octPath = Path();
      const sides = 8;
      for (int s = 0; s < sides; s++) {
        final a = (s * (2 * math.pi / sides)) + (math.pi / 8.0);
        final px = center.dx + r * math.cos(a);
        final py = center.dy + r * math.sin(a);
        if (s == 0) {
          octPath.moveTo(px, py);
        } else {
          octPath.lineTo(px, py);
        }
      }
      octPath.close();
      canvas.drawPath(octPath, fieldPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EvangelionAtFieldPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}
