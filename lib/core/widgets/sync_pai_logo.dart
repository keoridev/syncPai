import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Фирменный современный логотип SyncPai в стиле Steam & Discord:
/// Монолитная матовая эмблема с чистой геометрией без едких неонов.
/// Символизирует два синхронизированных потока (Watch Together / Dual Node),
/// объединенных в единый аэродинамический треугольник воспроизведения (Playhead).
class SyncPaiLogo extends StatelessWidget {
  final double size;
  final bool showBadge;
  final bool animate;
  final Color? accentColor;

  const SyncPaiLogo({
    super.key,
    this.size = 64.0,
    this.showBadge = true,
    this.animate = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = accentColor ?? theme.colorScheme.primary;

    final emblem = CustomPaint(
      size: Size(size, size),
      painter: SyncPaiModernEmblemPainter(primary),
    );

    if (!showBadge) {
      return emblem;
    }

    // Современный матовый бейдж-сквиркл (Dark Graphite Slate в стиле Steam Deck / Discord)
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF14171F),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B1E28),
            Color(0xFF0F1117),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: size * 0.24,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.72,
          height: size * 0.72,
          child: emblem,
        ),
      ),
    );
  }
}

/// Чистый векторный отрисовщик эмблемы SyncPai
/// Строгие линии, плавные сопряжения, читаемость от 20px до 512px.
class SyncPaiModernEmblemPainter extends CustomPainter {
  final Color accentColor;

  SyncPaiModernEmblemPainter(this.accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.5);

    // 1. Тонкое фоновое кольцо синхронизации (Dual Track Ring)
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055;
    canvas.drawCircle(center, w * 0.40, ringPaint);

    // 2. Верхняя дуга связи (Host Node Arc)
    final arcRect = Rect.fromCircle(center: center, radius: w * 0.40);
    final arcPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.90),
          accentColor,
        ],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.080;

    // Дуга охвата совместного просмотра (180 градусов с поворотом)
    canvas.drawArc(arcRect, -math.pi * 0.85, math.pi * 0.95, false, arcPaint);

    // 3. Акцентный узел синхронизации (Node Point)
    final nodeOffset = Offset(
      center.dx + w * 0.40 * math.cos(-math.pi * 0.85),
      center.dy + h * 0.40 * math.sin(-math.pi * 0.85),
    );
    final nodeGlow = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(nodeOffset, w * 0.055, nodeGlow);

    // 4. Центральный монолитный треугольник Play (Геометричный Playhead)
    // Со скругленными углами в стиле Steam / YouTube
    final playPath = Path();
    final leftX = w * 0.38;
    final rightX = w * 0.72;
    final topY = h * 0.30;
    final midY = h * 0.50;
    final botY = h * 0.70;
    final cornerRadius = w * 0.055;

    playPath.moveTo(leftX + cornerRadius, topY);
    playPath.lineTo(rightX - cornerRadius * 1.5, midY - cornerRadius * 0.8);
    playPath.quadraticBezierTo(rightX, midY, rightX - cornerRadius * 1.5, midY + cornerRadius * 0.8);
    playPath.lineTo(leftX + cornerRadius, botY);
    playPath.quadraticBezierTo(leftX, botY, leftX, botY - cornerRadius);
    playPath.lineTo(leftX, topY + cornerRadius);
    playPath.quadraticBezierTo(leftX, topY, leftX + cornerRadius, topY);
    playPath.close();

    // Заливка треугольника: чистый белый / легкий стальной градиент
    final playFillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFE2E7EE),
          Color(0xFFC7CFDC),
        ],
      ).createShader(Rect.fromLTWH(leftX, topY, rightX - leftX, botY - topY))
      ..style = PaintingStyle.fill;

    canvas.drawPath(playPath, playFillPaint);

    // Тонкий скос / фаска для ощущения физического премиального значка
    final bevelPath = Path()
      ..moveTo(leftX, topY + cornerRadius)
      ..lineTo(rightX - cornerRadius * 1.5, midY)
      ..lineTo(leftX, midY)
      ..close();

    final bevelPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    canvas.drawPath(bevelPath, bevelPaint);
  }

  @override
  bool shouldRepaint(covariant SyncPaiModernEmblemPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

typedef SyncPaiAnimeLogoPainter = SyncPaiModernEmblemPainter;
typedef SyncPaiCyberPrismPainter = SyncPaiModernEmblemPainter;
