import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Фирменный аниме-логотип SyncPai:
/// Стильный аниме-маскот (Neko-Senpai в стриминговых наушниках)
/// с правым глазом-плейлистом ▶, левым подмигивающим аниме-глазом / звездочкой ✦,
/// деликатным румянцем и индикатором синхронизации.
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
    final effectiveAccent = accentColor ?? Theme.of(context).primaryColor;

    final emblem = CustomPaint(
      size: Size(size, size),
      painter: SyncPaiAnimeLogoPainter(effectiveAccent),
    );

    if (!showBadge) {
      return emblem;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: AppColors.strokeMedium,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveAccent.withValues(alpha: 0.22),
            blurRadius: size * 0.35,
            spreadRadius: 0,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.78,
          height: size * 0.78,
          child: emblem,
        ),
      ),
    );
  }
}

class SyncPaiAnimeLogoPainter extends CustomPainter {
  final Color accentColor;

  SyncPaiAnimeLogoPainter(this.accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Аниме-ушки (Neko ears): Левое и Правое ушко
    final earOuterPaint = Paint()
      ..color = AppColors.surfaceElevated
      ..style = PaintingStyle.fill;

    final earStrokePaint = Paint()
      ..color = AppColors.strokeHigh
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final earInnerPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    // Левое ушко
    final leftEar = Path()
      ..moveTo(w * 0.18, h * 0.36)
      ..lineTo(w * 0.12, h * 0.08)
      ..lineTo(w * 0.40, h * 0.22)
      ..close();
    canvas.drawPath(leftEar, earOuterPaint);
    canvas.drawPath(leftEar, earStrokePaint);

    final leftInnerEar = Path()
      ..moveTo(w * 0.21, h * 0.32)
      ..lineTo(w * 0.17, h * 0.14)
      ..lineTo(w * 0.36, h * 0.24)
      ..close();
    canvas.drawPath(leftInnerEar, earInnerPaint);

    // Правое ушко
    final rightEar = Path()
      ..moveTo(w * 0.82, h * 0.36)
      ..lineTo(w * 0.88, h * 0.08)
      ..lineTo(w * 0.60, h * 0.22)
      ..close();
    canvas.drawPath(rightEar, earOuterPaint);
    canvas.drawPath(rightEar, earStrokePaint);

    final rightInnerEar = Path()
      ..moveTo(w * 0.79, h * 0.32)
      ..lineTo(w * 0.83, h * 0.14)
      ..lineTo(w * 0.64, h * 0.24)
      ..close();
    canvas.drawPath(rightInnerEar, earInnerPaint);

    // 2. Оголовье наушников (Headphone Band)
    final bandPaint = Paint()
      ..color = AppColors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.06;

    final bandPath = Path()
      ..moveTo(w * 0.16, h * 0.46)
      ..cubicTo(w * 0.16, h * 0.14, w * 0.84, h * 0.14, w * 0.84, h * 0.46);
    canvas.drawPath(bandPath, bandPaint);

    // 3. Лицо маскота (Мягкий суперэллипс)
    final facePaint = Paint()
      ..color = AppColors.surfaceHighlight
      ..style = PaintingStyle.fill;

    final faceBorder = Paint()
      ..color = AppColors.strokeMedium
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final faceRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.58),
        width: w * 0.66,
        height: h * 0.52,
      ),
      Radius.circular(w * 0.22),
    );
    canvas.drawRRect(faceRect, facePaint);
    canvas.drawRRect(faceRect, faceBorder);

    // 4. Чаши наушников по бокам (Ear cups)
    final cupPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.14, h * 0.58), width: w * 0.12, height: h * 0.26),
        Radius.circular(w * 0.05),
      ),
      cupPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.86, h * 0.58), width: w * 0.12, height: h * 0.26),
        Radius.circular(w * 0.05),
      ),
      cupPaint,
    );

    // 5. Глаза:
    // Левый глаз: аниме-искорка / подмигивающая дуга
    final eyeLeftPaint = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.06;

    final winkPath = Path()
      ..moveTo(w * 0.32, h * 0.58)
      ..quadraticBezierTo(w * 0.38, h * 0.51, w * 0.44, h * 0.58);
    canvas.drawPath(winkPath, eyeLeftPaint);

    // Правый глаз: Символ воспроизведения ▶
    final eyeRightPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final playEye = Path()
      ..moveTo(w * 0.57, h * 0.48)
      ..lineTo(w * 0.71, h * 0.56)
      ..lineTo(w * 0.57, h * 0.64)
      ..close();
    canvas.drawPath(playEye, eyeRightPaint);

    // 6. Милый аниме-ротик (Cat smile `3` / `ω`)
    final mouthPaint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.038;

    final mouthPath = Path()
      ..moveTo(w * 0.44, h * 0.68)
      ..quadraticBezierTo(w * 0.47, h * 0.72, w * 0.50, h * 0.68)
      ..quadraticBezierTo(w * 0.53, h * 0.72, w * 0.56, h * 0.68);
    canvas.drawPath(mouthPath, mouthPaint);

    // 7. Деликатный аниме-румянец (Cheek blush)
    final blushPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.32)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.30, h * 0.66), width: w * 0.10, height: h * 0.05),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.70, h * 0.66), width: w * 0.10, height: h * 0.05),
      blushPaint,
    );

    // 8. Искорка синхронизации (Sync sparkle ✦) в верхнем правом углу
    final starPaint = Paint()
      ..color = AppColors.syncActive
      ..style = PaintingStyle.fill;

    final starPath = Path()
      ..moveTo(w * 0.88, h * 0.22)
      ..quadraticBezierTo(w * 0.88, h * 0.27, w * 0.93, h * 0.27)
      ..quadraticBezierTo(w * 0.88, h * 0.27, w * 0.88, h * 0.32)
      ..quadraticBezierTo(w * 0.88, h * 0.27, w * 0.83, h * 0.27)
      ..quadraticBezierTo(w * 0.88, h * 0.27, w * 0.88, h * 0.22);
    canvas.drawPath(starPath, starPaint);
  }

  @override
  bool shouldRepaint(covariant SyncPaiAnimeLogoPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}
