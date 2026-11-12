import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Премиальный фирменный логотип SyncPai в стиле Cyber-Glass / Liquid Prism:
/// Двойные синхронизированные орбитальные дуги (символ совместного просмотра)
/// вокруг граненой неоновой призмы воспроизведения ▶ с кристальным бликом.
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
    final effectiveAccent = accentColor ?? Theme.of(context).colorScheme.primary;

    final emblem = CustomPaint(
      size: Size(size, size),
      painter: SyncPaiCyberPrismPainter(effectiveAccent),
    );

    if (!showBadge) {
      return emblem;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF151929),
            Color(0xFF0B0D16),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: effectiveAccent.withValues(alpha: 0.45),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveAccent.withValues(alpha: 0.25),
            blurRadius: size * 0.32,
            spreadRadius: 0,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.80,
          height: size * 0.80,
          child: emblem,
        ),
      ),
    );
  }
}

class SyncPaiCyberPrismPainter extends CustomPainter {
  final Color accentColor;

  SyncPaiCyberPrismPainter(this.accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.50, h * 0.50);
    const cyan = Color(0xFF00E5FF);

    // 1. Внешнее свечение центральной призмы
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withValues(alpha: 0.32),
          cyan.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: w * 0.46));
    canvas.drawCircle(center, w * 0.46, glowPaint);

    // 2. Две синхронизированные кибер-дуги (символ Sync / Watch Party)
    final arcRect = Rect.fromCircle(center: center, radius: w * 0.40);

    final topArcPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cyan, accentColor],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.068;

    final bottomArcPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [accentColor, const Color(0xFFFF2A85)],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.068;

    // Верхняя левая синхро-дуга
    canvas.drawArc(arcRect, -2.55, 2.15, false, topArcPaint);
    // Нижняя правая синхро-дуга
    canvas.drawArc(arcRect, 0.59, 2.15, false, bottomArcPaint);

    // 3. Точки-импульсы синхронизации на концах орбит
    final dotPaintCyan = Paint()
      ..color = cyan
      ..style = PaintingStyle.fill;
    final dotPaintAccent = Paint()
      ..color = AppColors.syncActive
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(w * 0.82, h * 0.25), w * 0.042, dotPaintCyan);
    canvas.drawCircle(Offset(w * 0.18, h * 0.75), w * 0.042, dotPaintAccent);

    // 4. Граненая центральная призма воспроизведения (Play Crystal ▶)
    final playPath = Path();
    final p1 = Offset(w * 0.37, h * 0.27);
    final p2 = Offset(w * 0.73, h * 0.50);
    final p3 = Offset(w * 0.37, h * 0.73);

    playPath
      ..moveTo(p1.dx, p1.dy + h * 0.04)
      ..quadraticBezierTo(p1.dx, p1.dy, p1.dx + w * 0.04, p1.dy + h * 0.022)
      ..lineTo(p2.dx - w * 0.03, p2.dy - h * 0.02)
      ..quadraticBezierTo(p2.dx + w * 0.01, p2.dy, p2.dx - w * 0.03, p2.dy + h * 0.02)
      ..lineTo(p3.dx + w * 0.04, p3.dy - h * 0.022)
      ..quadraticBezierTo(p3.dx, p3.dy, p3.dx, p3.dy - h * 0.04)
      ..close();

    final playGradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white,
          cyan,
          accentColor,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(w * 0.32, h * 0.25, w * 0.44, h * 0.50))
      ..style = PaintingStyle.fill;

    canvas.drawPath(playPath, playGradientPaint);

    // Верхняя стеклянная грань призмы для объема (Liquid Glass Highlight)
    final upperFacet = Path()
      ..moveTo(p1.dx + w * 0.02, p1.dy + h * 0.03)
      ..lineTo(p2.dx - w * 0.02, p2.dy)
      ..lineTo(w * 0.46, h * 0.50)
      ..close();

    final facetPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..style = PaintingStyle.fill;
    canvas.drawPath(upperFacet, facetPaint);

    // Тонкий контур призмы
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawPath(playPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant SyncPaiCyberPrismPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

typedef SyncPaiAnimeLogoPainter = SyncPaiCyberPrismPainter;
