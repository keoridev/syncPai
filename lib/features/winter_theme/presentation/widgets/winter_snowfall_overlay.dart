import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/services/winter_theme_service.dart';

/// Высокопроизводительный оверлей плотного падающего снега (110 частиц на Desktop, 75 на Mobile).
class WinterSnowfallOverlay extends StatefulWidget {
  final int? flakeCount;
  final double opacity;

  const WinterSnowfallOverlay({
    super.key,
    this.flakeCount,
    this.opacity = 1.0,
  });

  static int defaultFlakeCount() {
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    return isDesktop ? 110 : 75;
  }

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
    final count =
        (widget.flakeCount ?? WinterSnowfallOverlay.defaultFlakeCount())
            .clamp(1, 150);
    _flakes = List.generate(
      count,
      (_) {
        // Глубина (0.0 - далеко, 1.0 - близко) для естественного параллакса
        final depth = rng.nextDouble();
        return _Flake(
          x: rng.nextDouble(),
          yOffset: rng.nextDouble(),
          speed: 0.45 + depth * 0.85 + rng.nextDouble() * 0.25,
          radius: 1.2 + depth * 2.4,
          alpha: 0.25 + depth * 0.60,
          drift: 0.012 + rng.nextDouble() * 0.025,
          phase: rng.nextDouble() * math.pi * 2,
          windFreq: 1.0 + rng.nextDouble() * 1.5,
        );
      },
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _syncAnimation();
    _winterService.addListener(_syncAnimation);
  }

  void _syncAnimation() {
    if (!mounted) return;
    final active = _winterService.shouldRenderSnowfall;
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
        final active =
            !disableAnimations && _winterService.shouldRenderSnowfall;
        if (!active) return const SizedBox.shrink();

        return IgnorePointer(
          ignoring: true,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _SnowPainter(
                  progress: _controller.value,
                  flakes: _flakes,
                  opacityMultiplier: widget.opacity,
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
  final double alpha;
  final double drift;
  final double phase;
  final double windFreq;

  const _Flake({
    required this.x,
    required this.yOffset,
    required this.speed,
    required this.radius,
    required this.alpha,
    required this.drift,
    required this.phase,
    required this.windFreq,
  });
}

class _SnowPainter extends CustomPainter {
  final double progress;
  final List<_Flake> flakes;
  final double opacityMultiplier;

  const _SnowPainter({
    required this.progress,
    required this.flakes,
    required this.opacityMultiplier,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final time = progress * math.pi * 2;
    for (final f in flakes) {
      final yNorm = (f.yOffset + progress * f.speed) % 1.0;
      final xNorm =
          (f.x + math.sin(time * f.windFreq + f.phase) * f.drift) % 1.0;
      paint.color = Colors.white.withValues(
        alpha: (f.alpha * opacityMultiplier).clamp(0.0, 1.0),
      );
      canvas.drawCircle(
        Offset(xNorm * size.width, yNorm * size.height),
        f.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.opacityMultiplier != opacityMultiplier;
}
