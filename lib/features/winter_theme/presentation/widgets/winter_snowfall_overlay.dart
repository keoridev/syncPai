import 'package:flutter/material.dart';
import '../../../profile/presentation/widgets/live_backgrounds/snowfall_painter.dart';
import '../../domain/services/winter_theme_service.dart';

/// Легковесный оверлей процедурного снегопада для зимней темы SyncPai 2026.
///
/// Особенности:
/// 1. Абсолютно не перехватывает клики и жесты (IgnorePointer).
/// 2. Учитывает настройки доступности (prefers-reduced-motion).
/// 3. Реагирует на динамические переключатели WinterThemeService.
/// 4. Использует кэшированную геометрию LiveSnowfallPainter.
/// 5. Полностью отключает отрисовку и анимационный таймер, если снегопад выключен.
class WinterSnowfallOverlay extends StatefulWidget {
  final int flakeCount;
  final double opacity;

  const WinterSnowfallOverlay({
    super.key,
    this.flakeCount = 75,
    this.opacity = 0.85,
  });

  @override
  State<WinterSnowfallOverlay> createState() => _WinterSnowfallOverlayState();
}

class _WinterSnowfallOverlayState extends State<WinterSnowfallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final WinterThemeService _winterService = WinterThemeService.instance;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    if (_shouldAnimate()) {
      _controller.repeat();
    }

    _winterService.addListener(_handleServiceChange);
  }

  bool _shouldAnimate() {
    return _winterService.isWinterActive && _winterService.isSnowfallEnabled;
  }

  void _handleServiceChange() {
    if (!mounted) return;
    if (_shouldAnimate()) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _winterService.removeListener(_handleServiceChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion || !_shouldAnimate()) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            opacity: widget.opacity,
            child: CustomPaint(
              size: Size.infinite,
              painter: LiveSnowfallPainter(
                animationValue: _controller.value,
                snowColor: Colors.white,
                flakeCount: widget.flakeCount,
              ),
            ),
          );
        },
      ),
    );
  }
}
