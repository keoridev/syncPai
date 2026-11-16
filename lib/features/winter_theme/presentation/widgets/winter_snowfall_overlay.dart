import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/services/winter_theme_service.dart';

/// Лёгкий оверлей падающего снега (до 35 частиц), активный только при включённой настройке.
class WinterSnowfallOverlay extends StatefulWidget {
  final int flakeCount;
  final double opacity;

  const WinterSnowfallOverlay({
    super.key,
    this.flakeCount = 35,
    this.opacity = 0.65,
  });

  @override
  State<WinterSnowfallOverlay> createState() => _WinterSnowfallOverlayState();
}

class _WinterSnowfallOverlayState extends State<WinterSnowfallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final WinterThemeService _winterService = WinterThemeService.instance;
  late final List<_Flake> _flakes;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(42);
    final count = widget.flakeCount.clamp(1, 35);
    _flakes = List.generate(
      count,
      (_) => _Flake(
        x: rng.nextDouble(),
        yOffset: rng.nextDouble(),
        speed: 0.4 + rng.nextDouble() * 0.7,
        radius: 1.1 + rng.nextDouble() * 1.8,
        drift: (rng.nextDouble() - 0.5) * 0.04,
      ),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _syncAnimation();
    _winterService.addListener(_syncAnimation);
  }

  void _syncAnimation() {
    if (!mounted) return;
    final active =
        _winterService.isWinterActive && _winterService.isSnowfallEnabled;
    if (active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _winterService.removeListener(_syncAnimation);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return ListenableBuilder(
      listenable: _winterService,
      builder: (context, _) {
        final active = !disableAnimations &&
            _winterService.isWinterActive &&
            _winterService.isSnowfallEnabled;
        if (!active) return const SizedBox.shrink();

        return IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _SnowPainter(
                  progress: _controller.value,
                  flakes: _flakes,
                  opacity: widget.opacity,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Flake {
  final double x;
  final double yOffset;
  final double speed;
  final double radius;
  final double drift;

  const _Flake({
    required this.x,
    required this.yOffset,
    required this.speed,
    required this.radius,
    required this.drift,
  });
}

class _SnowPainter extends CustomPainter {
  final double progress;
  final List<_Flake> flakes;
  final double opacity;

  const _SnowPainter({
    required this.progress,
    required this.flakes,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: opacity * 0.55);
    for (final f in flakes) {
      final yNorm = (f.yOffset + progress * f.speed) % 1.0;
      final xNorm = (f.x + math.sin(progress * math.pi * 2 + f.yOffset * 6) * f.drift) % 1.0;
      canvas.drawCircle(
        Offset(xNorm * size.width, yNorm * size.height),
        f.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
