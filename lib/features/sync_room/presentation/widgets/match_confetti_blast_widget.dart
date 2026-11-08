import 'dart:math';
import 'package:flutter/material.dart';

/// Виджет праздничного конфетти-салюта (Match Confetti Blast) для празднования взаимного «Мэтча».
class MatchConfettiBlastWidget extends StatefulWidget {
  final VoidCallback? onFinished;

  const MatchConfettiBlastWidget({super.key, this.onFinished});

  @override
  State<MatchConfettiBlastWidget> createState() => _MatchConfettiBlastWidgetState();
}

class _MatchConfettiBlastWidgetState extends State<MatchConfettiBlastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final Random _random = Random();

  static const List<Color> _colors = [
    Color(0xFFFF2A68),
    Color(0xFFFF5E3A),
    Color(0xFFFFD700),
    Color(0xFF00E676),
    Color(0xFF00E5FF),
    Color(0xFF7C83FD),
    Color(0xFFFF7675),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // Генерируем 75 ярких частиц с физикой взрыва
    for (int i = 0; i < 75; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 120.0 + _random.nextDouble() * 320.0;
      _particles.add(
        _ConfettiParticle(
          color: _colors[_random.nextInt(_colors.length)],
          vx: cos(angle) * speed,
          vy: sin(angle) * speed - 150.0,
          rotationSpeed: (_random.nextDouble() - 0.5) * 12.0,
          size: 6.0 + _random.nextDouble() * 6.0,
        ),
      );
    }

    _controller.forward().then((_) => widget.onFinished?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(
              progress: _controller.value,
              particles: _particles,
            ),
          );
        },
      ),
    );
  }
}

class _ConfettiParticle {
  final Color color;
  final double vx;
  final double vy;
  final double rotationSpeed;
  final double size;

  _ConfettiParticle({
    required this.color,
    required this.vx,
    required this.vy,
    required this.rotationSpeed,
    required this.size,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height * 0.42);
    final gravity = 480.0 * progress * progress;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final x = center.dx + p.vx * progress;
      final y = center.dy + p.vy * progress + gravity;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotationSpeed * progress);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
