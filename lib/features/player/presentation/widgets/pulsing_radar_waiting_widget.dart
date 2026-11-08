import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Живая анимация ожидания хоста / буферизации (Neon Radar + Mascot)
/// Заменяет статичную плашку живым неоновым радаром, пульсирующими волнами
/// и индикатором активного вебсокета.
class PulsingRadarWaitingWidget extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int pingMs;

  const PulsingRadarWaitingWidget({
    super.key,
    this.title = 'Ожидание хоста...',
    this.subtitle = 'Сокет слушает сервер • Серия запустится синхронно',
    this.pingMs = 28,
  });

  @override
  State<PulsingRadarWaitingWidget> createState() => _PulsingRadarWaitingWidgetState();
}

class _PulsingRadarWaitingWidgetState extends State<PulsingRadarWaitingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Анимированный неоновый радар с маскотом по центру
            SizedBox(
              width: 84,
              height: 84,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _RadarWavePainter(progress: _controller.value),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceElevated,
                          border: Border.all(
                            color: AppColors.primaryLight,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.6),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '🐱',
                          style: TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // Заголовок ожидания
            Text(
              widget.title,
              style: AppTypography.titleSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),

            // Подзаголовок
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Живая телеметрия сокета (зеленая точка + пинг)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.syncActive,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Сокет активен • ${widget.pingMs}мс',
                    style: const TextStyle(
                      color: AppColors.syncActive,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarWavePainter extends CustomPainter {
  final double progress;

  _RadarWavePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 3 концентрические расходящиеся неоновые волны
    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + (i * 0.33)) % 1.0;
      final radius = 22.0 + (maxRadius - 22.0) * waveProgress;
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = const Color(0xFF6C5CE7).withValues(alpha: opacity * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;

      canvas.drawCircle(center, radius, paint);
    }

    // Вращающийся луч радара
    final angle = progress * 2 * pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: pi / 2,
        colors: [
          const Color(0xFF00CEC9).withValues(alpha: 0.35),
          Colors.transparent,
        ],
        transform: GradientRotation(angle),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarWavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
