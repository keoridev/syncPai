import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../domain/services/winter_theme_service.dart';

/// Лёгкий фоновый слой мягкого падающего снега (`RepaintBoundary` + `IgnorePointer`).
/// Рендерится позади карточек/контента, не перекрывая текст, аватарки и постеры.
class BackgroundSnowLayer extends StatefulWidget {
  final int? flakeCount;
  final double opacity;
  final bool forPlayer;

  const BackgroundSnowLayer({
    super.key,
    this.flakeCount,
    this.opacity = 1.0,
    this.forPlayer = false,
  });

  static int defaultFlakeCount() {
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    return isDesktop ? 85 : 45;
  }

  @override
  State<BackgroundSnowLayer> createState() => _BackgroundSnowLayerState();
}

class _BackgroundSnowLayerState extends State<BackgroundSnowLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final WinterThemeService _winterService = WinterThemeService.instance;
  late final List<_BgSnowflake> _flakes;
  late _BackgroundSnowPainter _painter;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(2026);
    final count =
        (widget.flakeCount ?? BackgroundSnowLayer.defaultFlakeCount())
            .clamp(1, 85);
    _flakes = List.generate(count, (_) {
      final depth = rng.nextDouble();
      return _BgSnowflake(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        speedY: 26.0 + depth * 36.0 + rng.nextDouble() * 10.0,
        radius: 1.2 + depth * 1.6, // 1.2px – 2.8px
        alpha: 0.14 + depth * 0.24, // 0.14 – 0.38
        driftPhase: rng.nextDouble() * math.pi * 2,
      );
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _painter = _BackgroundSnowPainter(
      repaint: _controller,
      flakes: _flakes,
      opacityMultiplier: widget.opacity,
    );
    _syncAnimation();
    _winterService.addListener(_syncAnimation);
  }

  bool get _isActive {
    if (widget.forPlayer) {
      return _winterService.isWinterThemeEnabled &&
          _winterService.isSnowfallEnabled &&
          _winterService.isSnowInPlayerEnabled;
    }
    return _winterService.isWinterThemeEnabled &&
        _winterService.isSnowfallEnabled;
  }

  void _syncAnimation() {
    if (!mounted) return;
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      binding.addPostFrameCallback((_) {
        if (mounted) _applyAnimationState();
      });
      return;
    }
    _applyAnimationState();
  }

  void _applyAnimationState() {
    final active = _isActive;
    if (active && !_controller.isAnimating) {
      _painter.resetDeltaTime();
      _controller.repeat();
    } else if (!active && _controller.isAnimating) {
      _controller.stop();
      _painter.resetDeltaTime();
    }
  }

  @override
  void didUpdateWidget(covariant BackgroundSnowLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opacity != widget.opacity ||
        oldWidget.forPlayer != widget.forPlayer) {
      _painter = _BackgroundSnowPainter(
        repaint: _controller,
        flakes: _flakes,
        opacityMultiplier: widget.opacity,
      );
      _applyAnimationState();
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
        if (disableAnimations || !_isActive) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: true,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _painter,
            ),
          ),
        );
      },
    );
  }
}

class _BgSnowflake {
  double x;
  double y;
  final double speedY;
  final double radius;
  final double alpha;
  final double driftPhase;

  _BgSnowflake({
    required this.x,
    required this.y,
    required this.speedY,
    required this.radius,
    required this.alpha,
    required this.driftPhase,
  });
}

class _BackgroundSnowPainter extends CustomPainter {
  final List<_BgSnowflake> flakes;
  final double opacityMultiplier;
  final Stopwatch _stopwatch = Stopwatch()..start();
  final math.Random _rng = math.Random(2026);

  int _lastElapsedMs = 0;
  double _totalTime = 0.0;
  bool _initialized = false;
  Size? _lastSize;

  _BackgroundSnowPainter({
    required Listenable repaint,
    required this.flakes,
    required this.opacityMultiplier,
  }) : super(repaint: repaint);

  void resetDeltaTime() {
    _lastElapsedMs = 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (!_initialized) {
      for (final f in flakes) {
        if (f.x <= 1.0 && f.y <= 1.0) {
          f.x *= size.width;
          f.y *= size.height;
        }
      }
      _initialized = true;
      _lastSize = size;
    } else if (_lastSize != null &&
        _lastSize != size &&
        _lastSize!.width > 0 &&
        _lastSize!.height > 0) {
      final sx = size.width / _lastSize!.width;
      final sy = size.height / _lastSize!.height;
      for (final f in flakes) {
        f.x *= sx;
        f.y *= sy;
      }
      _lastSize = size;
    }

    final elapsedMs = _stopwatch.elapsedMilliseconds;
    final dt = _lastElapsedMs == 0
        ? 0.016
        : ((elapsedMs - _lastElapsedMs) / 1000.0).clamp(0.0, 0.033);
    _lastElapsedMs = elapsedMs;
    _totalTime += dt;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final flake in flakes) {
      flake.y += flake.speedY * dt;
      flake.x += math.sin(_totalTime * 1.1 + flake.driftPhase) * 10.0 * dt;

      if (flake.y > size.height + 6) {
        flake.y = -6;
        flake.x = _rng.nextDouble() * size.width;
      } else if (flake.x < -6) {
        flake.x = size.width + 6;
      } else if (flake.x > size.width + 6) {
        flake.x = -6;
      }

      paint.color = Colors.white.withValues(
        alpha: (flake.alpha * opacityMultiplier).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(flake.x, flake.y), flake.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundSnowPainter oldDelegate) =>
      oldDelegate.opacityMultiplier != opacityMultiplier ||
      oldDelegate.flakes != flakes;
}

