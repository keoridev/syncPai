import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Виджет фирменных художественных витрин Пай-тян (Pai-chan Mascot Artwork Showcases)
/// для профиля Steam Showcase (`pai_chill`, `pai_winter`, `pai_celebrate`, `pai_hacker_art`).
class PaiChanArtworkBanner extends StatefulWidget {
  final String artworkId;
  final double width;
  final double height;
  final bool isSelected;

  const PaiChanArtworkBanner({
    super.key,
    required this.artworkId,
    required this.width,
    required this.height,
    this.isSelected = false,
  });

  @override
  State<PaiChanArtworkBanner> createState() => _PaiChanArtworkBannerState();
}

class _PaiChanArtworkBannerState extends State<PaiChanArtworkBanner>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late final AnimationController _panController;

  bool get _isHackerScene => widget.artworkId.trim() == 'pai_hacker_art';

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
    _controller = AnimationController(
      vsync: this,
      duration: _isHackerScene
          ? const Duration(milliseconds: 2500)
          : const Duration(milliseconds: 3200),
    );
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant PaiChanArtworkBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkId != widget.artworkId) {
      _controller.stop();
      _controller.duration = _isHackerScene
          ? const Duration(milliseconds: 2500)
          : const Duration(milliseconds: 3200);
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    if (_isHackerScene) {
      _panController.repeat(reverse: true);
      _controller.repeat(reverse: true);
    } else {
      _panController.stop();
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _panController.dispose();
    _controller.dispose();
    super.dispose();
  }

  _PaiShowcaseSpec _resolveSpec() {
    switch (widget.artworkId) {
      case 'pai_winter':
        return const _PaiShowcaseSpec(
          gradient: [Color(0xFF07182B), Color(0xFF0F3256), Color(0xFF1A4E74)],
          primaryGlow: Color(0xFF38BDF8),
          secondaryGlow: Color(0xFF818CF8),
          mascotAsset: 'assets/mascot/winter/mascot_winter_idle.png',
          fallbackAsset: 'assets/mascot/winter/mascot_winter_happy.png',
          fallbackIcon: Icons.ac_unit_rounded,
          isWinter: true,
        );
      case 'pai_celebrate':
        return const _PaiShowcaseSpec(
          gradient: [Color(0xFF14182E), Color(0xFF18334D), Color(0xFF42213D)],
          primaryGlow: Color(0xFF22D3EE),
          secondaryGlow: Color(0xFFFF6B4A),
          mascotAsset: 'assets/mascot/general/mascot_happy.png',
          fallbackAsset: 'assets/stickers/pai_hype.png',
          fallbackIcon: Icons.auto_awesome_rounded,
        );
      case 'pai_hacker_art':
        return const _PaiShowcaseSpec(
          gradient: [Color(0xFF050A14), Color(0xFF0B1829), Color(0xFF0F2A3F)],
          primaryGlow: Color(0xFF22D3EE),
          secondaryGlow: Color(0xFF10B981),
          mascotAsset: 'assets/banners/pai_hacker_bg.png',
          fallbackAsset: 'assets/mascot/general/mascot_idle.png',
          fallbackIcon: Icons.terminal_rounded,
        );
      case 'pai_chill':
      default:
        return const _PaiShowcaseSpec(
          gradient: [Color(0xFF070B18), Color(0xFF121A35), Color(0xFF241547)],
          primaryGlow: Color(0xFF22D3EE),
          secondaryGlow: Color(0xFFA855F7),
          mascotAsset: 'assets/mascot/general/mascot_idle.png',
          fallbackAsset: 'assets/mascot/general/mascot_sleeping.png',
          fallbackIcon: Icons.nightlight_round,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isHackerScene) {
      return _buildHackerPanorama(context);
    }

    final spec = _resolveSpec();
    final w = widget.width;
    final h = widget.height;
    final isCompact = h < 120 || w < 220;
    final mascotHeight = isCompact
        ? math.min(h * 0.90, 120.0)
        : (h >= 300 ? 175.0 : 150.0);
    final mascotWidth = math.min(w * 0.56, mascotHeight);

    return RepaintBoundary(
      child: ClipRect(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: spec.gradient,
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final floatY = math.sin(t * math.pi * 2) * (isCompact ? 3.0 : 6.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (spec.isWinter)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BannerSnowPainter(progress: t),
                      ),
                    ),
                  // Мягкий радиальный свет за персонажем
                  Align(
                    alignment: isCompact ? Alignment.centerRight : Alignment.center,
                    child: Container(
                      width: mascotHeight * 1.25,
                      height: mascotHeight * 1.25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            spec.primaryGlow.withValues(alpha: 0.30),
                            spec.secondaryGlow.withValues(alpha: 0.14),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.52, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Выразительный маскот Пай-тян с плавной вертикальной левитацией
                  Align(
                    alignment: isCompact ? Alignment.bottomRight : Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: isCompact ? 6 : 0,
                        bottom: isCompact ? 2 : 24,
                      ),
                      child: Transform.translate(
                        offset: Offset(0, floatY),
                        child: SizedBox(
                          width: mascotWidth,
                          height: mascotHeight,
                          child: Image.asset(
                            spec.mascotAsset,
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomCenter,
                            errorBuilder: (_, __, ___) => Image.asset(
                              spec.fallbackAsset,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomCenter,
                              errorBuilder: (_, __, ___) => Icon(
                                spec.fallbackIcon,
                                color: spec.primaryGlow,
                                size: isCompact ? 34 : 54,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Панорамная киберпанк-витрина «Пай-тян • Кодинг-хакер» с медленным панорамированием,
  /// изолированными частицами и дыханием неонового свечения наушников/куртки.
  Widget _buildHackerPanorama(BuildContext context) {
    final w = widget.width;
    final h = widget.height;
    final isCompact = h < 120 || w < 220;
    final effectiveHeight = isCompact ? h : (h > 195.0 ? 195.0 : h);

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: SizedBox(
        width: w,
        height: effectiveHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Фоновый слой: панорама ночного кибер-мегаполиса с плавным ±4px панорамированием
            AnimatedBuilder(
              animation: _panController,
              builder: (context, child) {
                final horizontalOffset =
                    (_panController.value * 2.0 - 1.0) * (isCompact ? 2.0 : 4.0);
                return Transform.translate(
                  offset: Offset(horizontalOffset, 0),
                  child: Transform.scale(
                    scale: 1.04,
                    child: child,
                  ),
                );
              },
              child: Image.asset(
                'assets/banners/pai_hacker_bg.png',
                width: w,
                height: effectiveHeight,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF050A14), Color(0xFF0B1829), Color(0xFF0F2A3F)],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.terminal_rounded,
                      color: const Color(0xFF22D3EE).withValues(alpha: 0.7),
                      size: isCompact ? 28 : 44,
                    ),
                  ),
                ),
              ),
            ),

            // 2. Слой эмбиент-анимации (изолирован в RepaintBoundary):
            // звёзды/боке, дыхание цианового свечения гарнитуры/куртки и микро-левитация
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final rawT = _controller.value;
                  final easedT = Curves.easeInOut.transform(rawT);
                  final glowOpacity = 0.4 + 0.6 * easedT;
                  final floatY = math.sin(rawT * math.pi) * (isCompact ? 0.8 : 1.5);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _CyberCityParticlesPainter(progress: rawT),
                      ),
                      // Мягкое циановое дыхание на гарнитуре и контуре куртки справа
                      Align(
                        alignment: const Alignment(0.56, -0.18),
                        child: Transform.translate(
                          offset: Offset(0, floatY),
                          child: Opacity(
                            opacity: glowOpacity,
                            child: Container(
                              width: effectiveHeight * 0.62,
                              height: effectiveHeight * 0.62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFF22D3EE).withValues(alpha: 0.28),
                                    const Color(0xFF06B6D4).withValues(alpha: 0.10),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.48, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // 3. Передний интерфейсный слой: полупрозрачная матовая лента внизу (32px)
            if (!isCompact)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 32,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            const Color(0xFF0C1018).withValues(alpha: 0.90),
                            const Color(0xFF0C1018).withValues(alpha: 0.45),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Пай-тян • Кодинг-хакер',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFF8E9AA8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 13,
                            color: Color(0xFF8E9AA8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaiShowcaseSpec {
  final List<Color> gradient;
  final Color primaryGlow;
  final Color secondaryGlow;
  final String mascotAsset;
  final String fallbackAsset;
  final IconData fallbackIcon;
  final bool isWinter;

  const _PaiShowcaseSpec({
    required this.gradient,
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.mascotAsset,
    required this.fallbackAsset,
    required this.fallbackIcon,
    this.isWinter = false,
  });
}

class _BannerSnowPainter extends CustomPainter {
  final double progress;

  const _BannerSnowPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.32);
    for (int i = 0; i < 16; i++) {
      final seedX = ((i * 67) % 100) / 100.0;
      final seedY = ((i * 43) % 100) / 100.0;
      final x = ((seedX * size.width) + math.sin(progress * math.pi * 2 + i) * 5) %
          size.width;
      final y = ((seedY + progress) % 1.0) * size.height;
      final r = 1.1 + (i % 3) * 0.55;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BannerSnowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Мягкое мерцание далёкого цифрового боке и звёзд для ночного кибер-города.
class _CyberCityParticlesPainter extends CustomPainter {
  final double progress;

  const _CyberCityParticlesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint();
    for (int i = 0; i < 18; i++) {
      final seedX = ((i * 53 + 11) % 97) / 100.0;
      final seedY = ((i * 37 + 7) % 72) / 100.0;
      final phase = (progress + (i * 0.17)) * math.pi * 2;
      final pulse = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(phase));
      final isBokeh = i % 4 == 0;
      starPaint.color = (isBokeh
              ? const Color(0xFF22D3EE)
              : Colors.white)
          .withValues(alpha: isBokeh ? pulse * 0.26 : pulse * 0.48);
      final radius = isBokeh ? (2.0 + (i % 2) * 1.1) : (0.8 + (i % 3) * 0.35);
      canvas.drawCircle(
        Offset(seedX * size.width, seedY * size.height),
        radius,
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CyberCityParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
