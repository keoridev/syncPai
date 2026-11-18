import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../../core/services/device_performance_service.dart';
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
    final baseCount = isDesktop ? 110 : 75;
    final multiplier = DevicePerformanceService.instance.snowDensityMultiplier;
    return (baseCount * multiplier).round().clamp(10, 150);
  }

  @override
  State<WinterSnowfallOverlay> createState() => _WinterSnowfallOverlayState();
}

class _WinterSnowfallOverlayState extends State<WinterSnowfallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final WinterThemeService _winterService = WinterThemeService.instance;
  late final List<Snowflake> _flakes;
  late WinterSnowfallPainter _painter;

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
        return Snowflake(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          speedY: 42.0 + depth * 65.0 + rng.nextDouble() * 18.0,
          radius: 1.2 + depth * 2.4,
          alpha: 0.25 + depth * 0.60,
          driftPhase: rng.nextDouble() * math.pi * 2,
        );
      },
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _painter = WinterSnowfallPainter(
      repaint: _controller,
      flakes: _flakes,
      opacityMultiplier: widget.opacity,
    );
    _syncAnimation();
    _winterService.addListener(_syncAnimation);
  }

  void _syncAnimation() {
    if (!mounted) return;
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      binding.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyAnimationState();
      });
      return;
    }
    _applyAnimationState();
  }

  void _applyAnimationState() {
    final active = _winterService.shouldRenderSnowfall;
    if (active && !_controller.isAnimating) {
      _painter.resetDeltaTime();
      _controller.repeat();
    } else if (!active && _controller.isAnimating) {
      _controller.stop();
      _painter.resetDeltaTime();
    }
  }

  @override
  void didUpdateWidget(covariant WinterSnowfallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opacity != widget.opacity ||
        oldWidget.flakeCount != widget.flakeCount) {
      _painter = WinterSnowfallPainter(
        repaint: _controller,
        flakes: _flakes,
        opacityMultiplier: widget.opacity,
      );
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

/// Состояние отдельной снежинки с непрерывными координатами
class Snowflake {
  double x;
  double y;
  final double speedY;
  final double radius;
  final double alpha;
  final double driftPhase;

  Snowflake({
    required this.x,
    required this.y,
    required this.speedY,
    required this.radius,
    required this.alpha,
    required this.driftPhase,
  });
}

/// Высокопроизводительный CustomPainter со встроенным `repaint: Listenable`
/// и непрерывной физикой delta-time без периодических скачков цикла.
class WinterSnowfallPainter extends CustomPainter {
  final List<Snowflake> flakes;
  final double opacityMultiplier;
  final Stopwatch _stopwatch;
  final math.Random _rng = math.Random(1337);

  int _lastElapsedMs = 0;
  double _totalTime = 0.0;
  bool _initialized = false;
  Size? _lastSize;

  WinterSnowfallPainter({
    required Listenable repaint,
    required this.flakes,
    this.opacityMultiplier = 1.0,
    Stopwatch? stopwatch,
  })  : _stopwatch = stopwatch ?? Stopwatch(),
        super(repaint: repaint) {
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
  }

  void resetDeltaTime() {
    _lastElapsedMs = 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Инициализация или пропорциональный пересчет координат при изменении размера экрана
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
      final scaleX = size.width / _lastSize!.width;
      final scaleY = size.height / _lastSize!.height;
      for (final f in flakes) {
        f.x *= scaleX;
        f.y *= scaleY;
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
      flake.x += math.sin(_totalTime * 1.4 + flake.driftPhase) * 14.0 * dt;

      // Бесшовный перенос отдельной снежинки за верхнюю границу при выходе за нижнюю
      if (flake.y > size.height + 8) {
        flake.y = -8;
        flake.x = _rng.nextDouble() * size.width;
      } else if (flake.x < -8) {
        flake.x = size.width + 8;
      } else if (flake.x > size.width + 8) {
        flake.x = -8;
      }

      paint.color = Colors.white.withValues(
        alpha: (flake.alpha * opacityMultiplier).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(flake.x, flake.y), flake.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WinterSnowfallPainter oldDelegate) =>
      oldDelegate.opacityMultiplier != opacityMultiplier ||
      oldDelegate.flakes != flakes;
}
