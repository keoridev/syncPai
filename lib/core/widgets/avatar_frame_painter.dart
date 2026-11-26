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
      case 'pai_headphones':
        _paintPaiHeadphonesFrame(canvas, center, radius);
        break;
      case 'pai_peek':
        _paintPaiPeekFrame(canvas, center, radius);
        break;
      case 'pai_hacker':
        _paintPaiHackerFrame(canvas, center, radius);
        break;
      case 'sakura':
        _paintSakuraFrame(canvas, center, radius);
        break;
      case 'katana_guard':
        _paintKatanaGuardFrame(canvas, center, radius);
        break;
      case 'techno_bevel':
        _paintTechnoBevelFrame(canvas, center, radius);
        break;
      case 'monolith':
        _paintMonolithFrame(canvas, center, radius);
        break;
      case 'ice_crystal':
        _paintIceCrystalFrame(canvas, center, radius);
        break;
      case 'minimal':
        _paintMinimalFrame(canvas, center, radius);
        break;
      case 'coral_contour':
        _paintCoralContourFrame(canvas, center, radius);
        break;
      case 'rank_ember':
        _paintRankEmberFrame(canvas, center, radius);
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
      case 'golden_dragon':
        _paintGoldenDragonFrame(canvas, center, radius);
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
      ..style = PaintingStyle.stroke;

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

  // --- 5. ТЕМА «ЗОЛОТОЙ ДРАКОН» (Golden Dragon) ---
  void _paintGoldenDragonFrame(Canvas canvas, Offset center, double radius) {
    // 1. Золотое тело дракона, обвивающее контур
    final bodyPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0xFFFFD700),
          Color(0xFFFF9100),
          Color(0xFFFF6D00),
          Color(0xFFFFE57F),
          Color(0xFFFFD700),
        ],
        transform: GradientRotation(animationValue * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;

    final bodyPath = Path();
    bodyPath.addArc(
      Rect.fromCircle(center: center, radius: radius + 2.0),
      -math.pi * 0.4,
      math.pi * 1.85,
    );
    canvas.drawPath(bodyPath, bodyPaint);

    // 2. Драконьи чешуйки вдоль обода
    final scalePaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    for (int i = 0; i < 14; i++) {
      final a = -math.pi * 0.35 + (i * (math.pi * 1.7 / 14));
      final sx = center.dx + (radius + 2.0) * math.cos(a);
      final sy = center.dy + (radius + 2.0) * math.sin(a);
      canvas.save();
      canvas.translate(sx, sy);
      canvas.rotate(a + math.pi / 2);
      final sp = Path()
        ..moveTo(-2.5, 0)
        ..quadraticBezierTo(0, -3.5, 2.5, 0);
      canvas.drawPath(sp, scalePaint);
      canvas.restore();
    }

    // 3. Голова Дракона на верхнем правом фланге (с рогами и усами)
    final headAngle = -math.pi * 0.38;
    final hx = center.dx + (radius + 3.0) * math.cos(headAngle);
    final hy = center.dy + (radius + 3.0) * math.sin(headAngle);

    canvas.save();
    canvas.translate(hx, hy);
    canvas.rotate(headAngle + math.pi * 0.65);

    // Морда дракона
    final headPaint = Paint()..color = const Color(0xFFFFD700);
    final headPath = Path()
      ..moveTo(0, -5)
      ..lineTo(5, 2)
      ..lineTo(2, 6)
      ..lineTo(-2, 6)
      ..lineTo(-5, 2)
      ..close();
    canvas.drawPath(headPath, headPaint);

    // Глаз дракона (рубиновый огонь)
    final eyePaint = Paint()..color = const Color(0xFFFF1744);
    canvas.drawCircle(const Offset(2.2, 0.5), 1.2, eyePaint);

    // Рога дракона
    final hornPaint = Paint()
      ..color = const Color(0xFFFFE57F)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-1.5, -4), const Offset(-4, -9), hornPaint);
    canvas.drawLine(const Offset(1.5, -4), const Offset(4, -9), hornPaint);

    // Усы дракона (колеблются на ветру)
    final whiskerSway = math.sin(animationValue * math.pi * 4) * 2.0;
    final whiskerPaint = Paint()
      ..color = const Color(0xFFFFF9C4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final wPath = Path()
      ..moveTo(3, 4)
      ..quadraticBezierTo(7 + whiskerSway, 8, 11, 7 + whiskerSway);
    canvas.drawPath(wPath, whiskerPaint);

    canvas.restore();

    // 4. Парящие искры и огненные жемчужины дракона
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 7; i++) {
      final prog = (animationValue + (i / 7.0)) % 1.0;
      final angle = (i * 1.1) + (prog * math.pi * 2);
      final dist = radius + 3.0 + math.sin(prog * math.pi) * 6.0;
      final px = center.dx + dist * math.cos(angle);
      final py = center.dy + dist * math.sin(angle);
      final alpha = (1.0 - (prog - 0.5).abs() * 2.0).clamp(0.2, 0.95);

      sparkPaint.color = Color.lerp(
        const Color(0xFFFFD700),
        const Color(0xFFFF3D00),
        prog,
      )!.withValues(alpha: alpha);

      canvas.drawCircle(Offset(px, py), 1.8 * (1.0 - prog * 0.4), sparkPaint);
    }
  }

  // --- 0.1 ТЕМА «НАУШНИКИ ПАЙ-ТЯН» (Pai-chan Cat-Ear Headphones — Free) ---
  void _paintPaiHeadphonesFrame(Canvas canvas, Offset center, double radius) {
    const cyan = Color(0xFF35D9D5);
    const glowCyan = Color(0xFF00E5FF);

    // 1. Неоновое свечение ободка
    final glowPaint = Paint()
      ..color = glowCyan.withValues(alpha: 0.5)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke;

    final bandPaint = Paint()
      ..color = cyan
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Дуга наушников через верх (от -0.85*pi до -0.15*pi)
    final bandRect = Rect.fromCircle(center: center, radius: radius + 3.5);
    canvas.drawArc(bandRect, -math.pi * 0.85, math.pi * 0.70, false, glowPaint);
    canvas.drawArc(bandRect, -math.pi * 0.85, math.pi * 0.70, false, bandPaint);

    // 2. Кошачьи ушки на оголовье (Cat-Ear horns)
    final earAngles = [-math.pi * 0.65, -math.pi * 0.35];
    for (int i = 0; i < earAngles.length; i++) {
      final a = earAngles[i];
      final ex = center.dx + (radius + 3.5) * math.cos(a);
      final ey = center.dy + (radius + 3.5) * math.sin(a);

      canvas.save();
      canvas.translate(ex, ey);
      canvas.rotate(a + math.pi / 2);

      // Внешнее ушко
      final earPath = Path()
        ..moveTo(-5, 0)
        ..lineTo(0, -11)
        ..lineTo(5, 0)
        ..close();

      final earFillPaint = Paint()
        ..color = cyan.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawPath(earPath, earFillPaint);
      canvas.drawPath(earPath, bandPaint);

      // Внутреннее светящееся ушко
      final innerEarPath = Path()
        ..moveTo(-2.5, 0)
        ..lineTo(0, -6.5)
        ..lineTo(2.5, 0)
        ..close();
      final innerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawPath(innerEarPath, innerPaint);

      canvas.restore();
    }

    // 3. Светящиеся чашечки наушников по бокам с пульсацией
    final pulse = 1.0 + 0.12 * math.sin(animationValue * math.pi * 2);
    final earcupPaint = Paint()
      ..color = cyan
      ..style = PaintingStyle.fill;
    final earcupGlow = Paint()
      ..color = glowCyan.withValues(alpha: 0.6);

    final cupAngles = [-math.pi * 0.88, -math.pi * 0.12];
    for (final ca in cupAngles) {
      final cx = center.dx + (radius + 2.5) * math.cos(ca);
      final cy = center.dy + (radius + 2.5) * math.sin(ca);

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(ca + math.pi / 2);
      final cupRect = Rect.fromCenter(center: Offset.zero, width: 6.0 * pulse, height: 11.0 * pulse);
      final rrect = RRect.fromRectAndRadius(cupRect, const Radius.circular(3));
      canvas.drawRRect(rrect, earcupGlow);
      canvas.drawRRect(rrect, earcupPaint);
      // Белый неоновый блик в центре чашки
      canvas.drawCircle(Offset.zero, 1.8, Paint()..color = Colors.white);
      canvas.restore();
    }

    // 4. Тонкое базовое кольцо с неоновым свечением
    final ringPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF35D9D5),
          Color(0xFF00B4D8),
          Color(0xFF90E0EF),
          Color(0xFF35D9D5),
        ],
        transform: GradientRotation(animationValue * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius, ringPaint);
  }

  // --- 0.2 ТЕМА «ПАЙ-ТЯН РЯДОМ» (Pai-chan Peek — Plus) ---
  void _paintPaiPeekFrame(Canvas canvas, Offset center, double radius) {
    // 1. Cyan/Violet градиентное внешнее кольцо
    final ringPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF35D9D5),
          Color(0xFF8B5CF6),
          Color(0xFFFF76AC),
          Color(0xFF35D9D5),
        ],
        transform: GradientRotation(animationValue * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;
    canvas.drawCircle(center, radius, ringPaint);

    // 2. Chibi Пай-тян, выглядывающая снизу справа (угол ~ 45 градусов / math.pi * 0.25)
    const peekAngle = math.pi * 0.25;
    // Легкое покачивание / дыхание маскота
    final bob = math.sin(animationValue * math.pi * 2) * 1.2;
    final px = center.dx + (radius + 2.0) * math.cos(peekAngle);
    final py = center.dy + (radius + 2.0) * math.sin(peekAngle) + bob;

    canvas.save();
    canvas.translate(px, py);

    // Личико Пай-тян (круглая форма головы)
    final facePaint = Paint()..color = const Color(0xFFFFF3E0);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4);
    canvas.drawCircle(Offset.zero, 8.5, shadowPaint);
    canvas.drawCircle(Offset.zero, 8.0, facePaint);

    // Волосы / челка Пай-тян (неоново-бирюзовый с фиолетовым)
    final hairPaint = Paint()..color = const Color(0xFF35D9D5);
    final hairPath = Path()
      ..moveTo(-7.5, -3)
      ..quadraticBezierTo(-4, -9.5, 0, -8)
      ..quadraticBezierTo(4, -9.5, 7.5, -3)
      ..quadraticBezierTo(3, -5, 0, -5)
      ..quadraticBezierTo(-3, -5, -7.5, -3)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    // Ушки маскота
    final earPaint = Paint()..color = const Color(0xFF8B5CF6);
    final leftEar = Path()
      ..moveTo(-6, -6)
      ..lineTo(-9, -12)
      ..lineTo(-3, -8)
      ..close();
    final rightEar = Path()
      ..moveTo(3, -8)
      ..lineTo(9, -12)
      ..lineTo(6, -6)
      ..close();
    canvas.drawPath(leftEar, earPaint);
    canvas.drawPath(rightEar, earPaint);

    // Kawaii глаза (темно-фиолетовые точки с белыми искорками)
    final eyePaint = Paint()..color = const Color(0xFF2E1065);
    final glintPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(-3.0, -0.5), 1.4, eyePaint);
    canvas.drawCircle(const Offset(3.0, -0.5), 1.4, eyePaint);
    canvas.drawCircle(const Offset(-3.4, -0.9), 0.5, glintPaint);
    canvas.drawCircle(const Offset(2.6, -0.9), 0.5, glintPaint);

    // Румянец на щечках
    final blushPaint = Paint()..color = const Color(0xFFFF80AB).withValues(alpha: 0.65);
    canvas.drawCircle(const Offset(-5.0, 1.8), 1.2, blushPaint);
    canvas.drawCircle(const Offset(5.0, 1.8), 1.2, blushPaint);

    // Лапки, держащиеся за обод рамки
    final pawPaint = Paint()..color = Colors.white;
    final pawStroke = Paint()
      ..color = const Color(0xFF35D9D5)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final leftPaw = RRect.fromRectAndRadius(const Rect.fromLTWH(-6.5, 3.5, 4.5, 3.5), const Radius.circular(2));
    final rightPaw = RRect.fromRectAndRadius(const Rect.fromLTWH(2.0, 3.5, 4.5, 3.5), const Radius.circular(2));
    canvas.drawRRect(leftPaw, pawPaint);
    canvas.drawRRect(leftPaw, pawStroke);
    canvas.drawRRect(rightPaw, pawPaint);
    canvas.drawRRect(rightPaw, pawStroke);

    canvas.restore();
  }

  // --- 0.3 ТЕМА «КИБЕР-ПАЙ-ТЯН / ОХОТНИК ЗА БАГАМИ» (Animated Code Rain) ---
  void _paintPaiHackerFrame(Canvas canvas, Offset center, double radius) {
    const emerald = Color(0xFF10B981);
    const brightEmerald = Color(0xFF34D399);

    // 1. Плоский матовый изумрудный контур с бегущим сегментом
    final ringPaint = Paint()
      ..color = emerald.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, ringPaint);

    final activeArcPaint = Paint()
      ..color = brightEmerald
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      animationValue * math.pi * 2,
      math.pi * 0.45,
      false,
      activeArcPaint,
    );

    // 2. Анимированный каскад кода (0, 1, {, }, ;, </>) вдоль периметра рамки
    const glyphs = ['0', '1', '{', '}', ';', '</>'];
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < 10; i++) {
      final colX = center.dx - radius - 4 + (i * (radius * 2 + 8) / 9);
      final speed = 1.0 + (i % 3) * 0.35;
      final prog = (animationValue * speed + i * 0.17) % 1.0;
      final yPos = center.dy - radius - 6 + prog * (radius * 2 + 12);
      final distFromCenter = Offset(colX - center.dx, yPos - center.dy).distance;

      // Рисуем глифы по краям/углам, не перекрывая центр лица на аватаре
      if (distFromCenter >= radius * 0.85) {
        final alpha = (1.0 - (prog - 0.5).abs() * 1.8).clamp(0.2, 0.95);
        tp.text = TextSpan(
          text: glyphs[(i + (animationValue * 6).floor()) % glyphs.length],
          style: TextStyle(
            color: (i % 2 == 0 ? brightEmerald : emerald).withValues(alpha: alpha),
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(colX - tp.width / 2, yPos - tp.height / 2));
      }
    }
  }

  // --- «ГАРДА КАТАНЫ» (Реалистичная диагональная катана: рукоять цука, гарда цуба, стальной клинок) ---
  void _paintKatanaGuardFrame(Canvas canvas, Offset center, double radius) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 4);

    final bladeStart = -radius - 8.0;
    final guardX = radius * 0.52;
    final hiltEnd = radius + 9.0;

    // 1. Стальной клинок с острой фаской (без неонового свечения)
    final bladePath = Path()
      ..moveTo(bladeStart, 0)
      ..lineTo(bladeStart + 7, -3.0)
      ..lineTo(guardX, -3.0)
      ..lineTo(guardX, 2.5)
      ..lineTo(bladeStart + 5, 2.5)
      ..close();
    canvas.drawPath(bladePath, Paint()..color = const Color(0xFFCBD5E1));

    // Блик по режущей кромке (хамон)
    canvas.drawLine(
      Offset(bladeStart + 5, 2.0),
      Offset(guardX, 2.0),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.0,
    );

    // 2. Бронзовая/стальная гарда (цуба)
    final tsubaPaint = Paint()..color = const Color(0xFFD97706);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(guardX, 0), width: 4.5, height: 15.0),
        const Radius.circular(2),
      ),
      tsubaPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(guardX, 0), width: 4.5, height: 15.0),
        const Radius.circular(2),
      ),
      Paint()
        ..color = const Color(0xFFFDE68A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 3. Обмотка рукояти (цука) с ромбовидным узором
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(guardX + 2.2, -3.0, hiltEnd, 3.0),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFF1E293B),
    );
    final wrapPaint = Paint()
      ..color = const Color(0xFFFF6B4A)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (double x = guardX + 4.5; x < hiltEnd - 2; x += 4.2) {
      canvas.drawLine(Offset(x, -2.5), Offset(x + 2.5, 2.5), wrapPaint);
      canvas.drawLine(Offset(x + 2.5, -2.5), Offset(x, 2.5), wrapPaint);
    }

    canvas.restore();
  }

  // --- «ТЕХНО-СРЕЗ 45°» (Восьмиугольный Sci-Fi HUD со срезами и засечками) ---
  void _paintTechnoBevelFrame(Canvas canvas, Offset center, double radius) {
    final r = radius + 2.0;
    final cut = r * 0.34;
    final rect = Rect.fromCircle(center: center, radius: r);
    final octPath = Path()
      ..moveTo(rect.left + cut, rect.top)
      ..lineTo(rect.right - cut, rect.top)
      ..lineTo(rect.right, rect.top + cut)
      ..lineTo(rect.right, rect.bottom - cut)
      ..lineTo(rect.right - cut, rect.bottom)
      ..lineTo(rect.left + cut, rect.bottom)
      ..lineTo(rect.left, rect.bottom - cut)
      ..lineTo(rect.left, rect.top + cut)
      ..close();

    canvas.drawPath(
      octPath,
      Paint()
        ..color = const Color(0xFF22D3EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final tickPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(center.dx - 8, rect.top - 2.5), Offset(center.dx + 8, rect.top - 2.5), tickPaint);
    canvas.drawLine(Offset(center.dx - 8, rect.bottom + 2.5), Offset(center.dx + 8, rect.bottom + 2.5), tickPaint);
  }

  // --- «МОНОЛИТ» (Массивная матовая обсидиановая рамка со стальными болтами) ---
  void _paintMonolithFrame(Canvas canvas, Offset center, double radius) {
    final r = radius + 2.5;
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromCircle(center: center, radius: r),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      outerRect,
      Paint()
        ..color = const Color(0xFF334155)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCircle(center: center, radius: r - 3),
        const Radius.circular(10),
      ),
      Paint()
        ..color = const Color(0xFF64748B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 4 стальных заклёпки по углам
    final boltPaint = Paint()..color = const Color(0xFF94A3B8);
    final offset = r - 5;
    for (final dx in [-offset, offset]) {
      for (final dy in [-offset, offset]) {
        canvas.drawCircle(Offset(center.dx + dx, center.dy + dy), 2.3, boltPaint);
      }
    }
  }

  // --- «КРИСТАЛЛ ЛЬДА» (Острые ледяные грани по углам) ---
  void _paintIceCrystalFrame(Canvas canvas, Offset center, double radius) {
    final shardPaint = Paint()..color = const Color(0xFF7DD3FC);
    final edgePaint = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2 + math.pi / 4;
      canvas.save();
      canvas.translate(
        center.dx + (radius + 2) * math.cos(angle),
        center.dy + (radius + 2) * math.sin(angle),
      );
      canvas.rotate(angle + math.pi / 2);
      final shard = Path()
        ..moveTo(0, -7)
        ..lineTo(4.5, 2)
        ..lineTo(0, 5)
        ..lineTo(-4.5, 2)
        ..close();
      canvas.drawPath(shard, shardPaint);
      canvas.drawPath(shard, edgePaint);
      canvas.restore();
    }
  }

  void _paintMinimalFrame(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius + 1,
      Paint()
        ..color = const Color(0xFF64748B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintCoralContourFrame(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius + 1,
      Paint()
        ..color = const Color(0xFFFF6B4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
  }

  void _paintRankEmberFrame(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawCircle(center, radius + 1, paint);
    final emberPaint = Paint()..color = const Color(0xFFF59E0B);
    for (int i = 0; i < 6; i++) {
      final a = i * (math.pi / 3) + animationValue * math.pi * 2;
      canvas.drawCircle(
        Offset(center.dx + (radius + 3.5) * math.cos(a), center.dy + (radius + 3.5) * math.sin(a)),
        2.0,
        emberPaint,
      );
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

