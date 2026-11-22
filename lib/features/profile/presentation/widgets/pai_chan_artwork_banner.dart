import 'dart:math' as math;
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
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
          gradient: [Color(0xFF02120A), Color(0xFF062717), Color(0xFF0B3F26)],
          primaryGlow: Color(0xFF10B981),
          secondaryGlow: Color(0xFF22D3EE),
          mascotAsset: 'assets/mascot/general/mascot_idle.png',
          fallbackAsset: 'assets/mascot/general/mascot_thinking.png',
          fallbackIcon: Icons.terminal_rounded,
          isMatrix: true,
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
    final spec = _resolveSpec();
    final w = widget.width;
    final h = widget.height;
    final isCompact = h < 120 || w < 220;
    final mascotHeight = math.min(h * 0.92, 190.0);
    final mascotWidth = math.min(w * 0.54, mascotHeight);

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
                  if (spec.isMatrix)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MatrixGridPainter(
                          progress: t,
                          color: spec.primaryGlow,
                        ),
                      ),
                    ),
                  if (spec.isWinter)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BannerSnowPainter(progress: t),
                      ),
                    ),
                  // Мягкий радиальный свет за персонажем
                  Positioned(
                    right: isCompact ? -w * 0.06 : w * 0.04,
                    top: -h * 0.08,
                    child: Container(
                      width: mascotHeight * 1.15,
                      height: mascotHeight * 1.15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            spec.primaryGlow.withValues(alpha: 0.32),
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
                      padding: EdgeInsets.only(right: isCompact ? 6 : 0, bottom: 2),
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
}

class _PaiShowcaseSpec {
  final List<Color> gradient;
  final Color primaryGlow;
  final Color secondaryGlow;
  final String mascotAsset;
  final String fallbackAsset;
  final IconData fallbackIcon;
  final bool isWinter;
  final bool isMatrix;

  const _PaiShowcaseSpec({
    required this.gradient,
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.mascotAsset,
    required this.fallbackAsset,
    required this.fallbackIcon,
    this.isWinter = false,
    this.isMatrix = false,
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

class _MatrixGridPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _MatrixGridPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    const step = 22.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final barPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 8; i++) {
      final x = ((i * 47 + 16) % size.width.toInt()).toDouble();
      final yStart = (((i * 29) / 100.0 + progress) % 1.0) * size.height;
      canvas.drawLine(
        Offset(x, yStart),
        Offset(x, (yStart + 14).clamp(0.0, size.height)),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixGridPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
