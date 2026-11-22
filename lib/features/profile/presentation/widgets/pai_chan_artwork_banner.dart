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
      duration: const Duration(milliseconds: 3600),
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
          gradient: [Color(0xFF061627), Color(0xFF0E2F4F), Color(0xFF1A4B6E)],
          primaryGlow: Color(0xFF38BDF8),
          secondaryGlow: Color(0xFF818CF8),
          badgeText: 'ЗИМА 2026 • PAI-CHAN',
          titleText: 'Зимняя Пай-тян',
          subText: 'Снежный стрим • 1080p',
          kanji: '冬',
          mascotAsset: 'assets/mascot/winter/mascot_winter_idle.png',
          fallbackAsset: 'assets/mascot/winter/mascot_winter_happy.png',
          fallbackIcon: Icons.ac_unit_rounded,
          isWinter: true,
        );
      case 'pai_celebrate':
        return const _PaiShowcaseSpec(
          gradient: [Color(0xFF1F0633), Color(0xFF470B57), Color(0xFF8B125C)],
          primaryGlow: Color(0xFFFF4D94),
          secondaryGlow: Color(0xFFFBBF24),
          badgeText: 'PLUS SCENE • PAI-CHAN',
          titleText: 'Абсолют кино',
          subText: 'Премьера • Watch Together',
          kanji: '映',
          mascotAsset: 'assets/mascot/general/mascot_happy.png',
          fallbackAsset: 'assets/stickers/pai_hype.png',
          fallbackIcon: Icons.auto_awesome_rounded,
        );
      case 'pai_hacker_art':
        return const _PaiShowcaseSpec(
          gradient: [Color(0xFF02130B), Color(0xFF062917), Color(0xFF0B4227)],
          primaryGlow: Color(0xFF10B981),
          secondaryGlow: Color(0xFF22D3EE),
          badgeText: 'BUG HUNTER • ROOT',
          titleText: 'Кодинг-хакер',
          subText: 'Терминал • Эксклюзив',
          kanji: '電',
          mascotAsset: 'assets/mascot/loading_success/mascot_uploading.png',
          fallbackAsset: 'assets/mascot/general/mascot_thinking.png',
          fallbackIcon: Icons.terminal_rounded,
        );
      case 'pai_chill':
      default:
        return const _PaiShowcaseSpec(
          gradient: [Color(0xFF070B18), Color(0xFF121A35), Color(0xFF241547)],
          primaryGlow: Color(0xFF22D3EE),
          secondaryGlow: Color(0xFFA855F7),
          badgeText: 'НОЧНОЙ МАРАФОН • PAI-CHAN',
          titleText: 'Ночной марафон',
          subText: 'Lo-Fi Кинозал • 24/7',
          kanji: '夜',
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
    final mascotHeight = math.min(h * 0.94, 190.0);
    final mascotWidth = math.min(w * 0.48, mascotHeight);

    return RepaintBoundary(
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
          final bobOffset = math.sin(t * math.pi * 2) * (isCompact ? 2.0 : 4.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Фоновые боке-частицы или падающий снег
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ShowcaseParticlesPainter(
                      progress: t,
                      primaryColor: spec.primaryGlow,
                      secondaryColor: spec.secondaryGlow,
                      isWinter: spec.isWinter,
                    ),
                  ),
                ),
              ),

              // 2. Циан / фиолетовый радиальный свет за персонажем справа
              Positioned(
                right: -w * 0.04,
                top: -h * 0.12,
                child: Container(
                  width: mascotHeight * 1.15,
                  height: mascotHeight * 1.15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        spec.primaryGlow.withValues(alpha: 0.34),
                        spec.secondaryGlow.withValues(alpha: 0.14),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.52, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. Декоративный кандзи на заднем плане
              Positioned(
                right: mascotWidth * 0.65,
                top: isCompact ? 6 : 12,
                child: Text(
                  spec.kanji,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: math.min(h * 0.52, 68),
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.06),
                    letterSpacing: 2,
                  ),
                ),
              ),

              // 4. Правый слой: крупный маскот Пай-тян с плавным дыханием
              Positioned(
                right: isCompact ? 6 : 14,
                bottom: 0,
                child: Transform.translate(
                  offset: Offset(0, bobOffset),
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

              // 5. Левый слой: атмосферная HUD-карточка с мини-экраном и эквалайзером
              Positioned(
                left: isCompact ? 10 : 16,
                top: isCompact ? 10 : 16,
                bottom: isCompact ? 10 : 16,
                right: mascotWidth + (isCompact ? 10 : 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: EdgeInsets.all(isCompact ? 8 : 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0F1E).withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(isCompact ? 10 : 14),
                      border: Border.all(
                        color: spec.primaryGlow.withValues(alpha: 0.35),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: spec.primaryGlow.withValues(alpha: 0.12),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Статус-бейдж
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 6 : 8,
                            vertical: isCompact ? 2 : 3,
                          ),
                          decoration: BoxDecoration(
                            color: spec.primaryGlow.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: spec.primaryGlow.withValues(alpha: 0.45),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: spec.primaryGlow,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  spec.badgeText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: spec.primaryGlow,
                                    fontSize: isCompact ? 8 : 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isCompact ? 5 : 8),
                        // Мини-киноэкран и анимированный аудио-эквалайзер
                        if (!isCompact) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  spec.primaryGlow.withValues(alpha: 0.16),
                                  spec.secondaryGlow.withValues(alpha: 0.14),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_circle_filled_rounded,
                                  size: 16,
                                  color: spec.primaryGlow,
                                ),
                                const SizedBox(width: 7),
                                _EqualizerBars(
                                  progress: t,
                                  color: spec.primaryGlow,
                                  secondaryColor: spec.secondaryGlow,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    spec.subText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Заголовок сцены
                        Text(
                          spec.titleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 12 : 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

class _PaiShowcaseSpec {
  final List<Color> gradient;
  final Color primaryGlow;
  final Color secondaryGlow;
  final String badgeText;
  final String titleText;
  final String subText;
  final String kanji;
  final String mascotAsset;
  final String fallbackAsset;
  final IconData fallbackIcon;
  final bool isWinter;

  const _PaiShowcaseSpec({
    required this.gradient,
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.badgeText,
    required this.titleText,
    required this.subText,
    required this.kanji,
    required this.mascotAsset,
    required this.fallbackAsset,
    required this.fallbackIcon,
    this.isWinter = false,
  });
}

class _EqualizerBars extends StatelessWidget {
  final double progress;
  final Color color;
  final Color secondaryColor;

  const _EqualizerBars({
    required this.progress,
    required this.color,
    required this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (i) {
          final wave = 0.35 +
              0.65 *
                  ((math.sin((progress * math.pi * 4) + (i * 1.15)) + 1) / 2);
          return Container(
            width: 2.5,
            height: 14 * wave,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i.isEven ? color : secondaryColor,
            ),
          );
        }),
      ),
    );
  }
}

class _ShowcaseParticlesPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isWinter;

  const _ShowcaseParticlesPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isWinter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 14; i++) {
      final seedX = ((i * 73) % 100) / 100.0;
      final seedY = ((i * 41) % 100) / 100.0;
      final radius = isWinter ? (1.4 + (i % 3) * 0.7) : (2.2 + (i % 4) * 1.6);

      final double x;
      final double y;
      if (isWinter) {
        x = ((seedX * size.width) + math.sin(progress * math.pi * 2 + i) * 6) %
            size.width;
        y = ((seedY + progress) % 1.0) * size.height;
      } else {
        x = seedX * size.width;
        y = ((seedY - progress * 0.35 + 1.0) % 1.0) * size.height;
      }

      final paint = Paint()
        ..color = (isWinter
                ? Colors.white
                : (i.isEven ? primaryColor : secondaryColor))
            .withValues(alpha: isWinter ? 0.32 : 0.18);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShowcaseParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isWinter != isWinter ||
      oldDelegate.primaryColor != primaryColor;
}
