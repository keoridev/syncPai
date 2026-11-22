import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Уровень редкости коллекционного значка в стиле Steam.
enum AchievementRarityTier {
  common,
  rare,
  epic,
  legendary,
}

/// Метаданные стиля редкости и маппинг ассетов для [AchievementBadgeArtwork].
class AchievementBadgeStyle {
  final AchievementRarityTier tier;
  final String label;
  final List<Color> rimColors;
  final Color glowColor;
  final String assetKey;

  const AchievementBadgeStyle({
    required this.tier,
    required this.label,
    required this.rimColors,
    required this.glowColor,
    required this.assetKey,
  });

  static String resolveAssetKey(String badgeId) {
    switch (badgeId) {
      case 'first_episode':
      case 'first_step':
        return 'first_step';
      case 'watch_hour':
        return 'watch_hour';
      case 'op_skipper':
      case 'skip_legend':
        return 'op_skipper';
      case 'night_owl':
      case 'night_otaku':
        return 'night_owl';
      case 'marathon_runner':
      case 'marathoner':
      case 'marathon_100':
        return 'marathoner';
      case 'party_soul':
      case 'sync_master':
      case 'match_swiper':
        return 'party_soul';
      case 'collector':
      case 'anixart_collector':
        return 'collector';
      case 'bug_hunter':
        return 'bug_hunter';
      case 'founder':
      case 'pioneer':
      case 'critic':
        return 'founder';
      default:
        return badgeId;
    }
  }

  static AchievementRarityTier resolveTier(String badgeId, String? rarityLabel) {
    final key = resolveAssetKey(badgeId);
    if (key == 'bug_hunter' || key == 'founder') {
      return AchievementRarityTier.legendary;
    }
    if (key == 'marathoner' || key == 'party_soul' || key == 'collector') {
      return AchievementRarityTier.epic;
    }
    if (key == 'op_skipper' || key == 'night_owl') {
      return AchievementRarityTier.rare;
    }
    if (key == 'first_step' || key == 'watch_hour') {
      return AchievementRarityTier.common;
    }

    final normalized = (rarityLabel ?? '').trim().toLowerCase();
    if (normalized.contains('легенд') || normalized.contains('эксклюзив')) {
      return AchievementRarityTier.legendary;
    }
    if (normalized.contains('эпич')) {
      return AchievementRarityTier.epic;
    }
    if (normalized.contains('редк')) {
      return AchievementRarityTier.rare;
    }
    return AchievementRarityTier.common;
  }

  static AchievementBadgeStyle resolve(
    String badgeId, {
    String? rarityLabel,
    Color? accentOverride,
  }) {
    final assetKey = resolveAssetKey(badgeId);
    final tier = resolveTier(badgeId, rarityLabel);

    switch (tier) {
      case AchievementRarityTier.common:
        return AchievementBadgeStyle(
          tier: tier,
          label: 'Обычный',
          rimColors: const [Color(0xFF475569), Color(0xFF64748B)],
          glowColor: accentOverride ??
              (assetKey == 'watch_hour'
                  ? const Color(0xFF22D3EE)
                  : const Color(0xFF38BDF8)),
          assetKey: assetKey,
        );
      case AchievementRarityTier.rare:
        final glow = accentOverride ??
            (assetKey == 'night_owl'
                ? const Color(0xFF818CF8)
                : const Color(0xFF38BDF8));
        return AchievementBadgeStyle(
          tier: tier,
          label: 'Редкий',
          rimColors: assetKey == 'night_owl'
              ? const [Color(0xFF6366F1), Color(0xFFA855F7)]
              : const [Color(0xFF38BDF8), Color(0xFF6366F1)],
          glowColor: glow,
          assetKey: assetKey,
        );
      case AchievementRarityTier.epic:
        final epicGlow = accentOverride ??
            (assetKey == 'collector'
                ? const Color(0xFF10B981)
                : assetKey == 'marathoner'
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFFF6B4A));
        return AchievementBadgeStyle(
          tier: tier,
          label: 'Эпический',
          rimColors: const [Color(0xFFA855F7), Color(0xFFFF6B4A)],
          glowColor: epicGlow,
          assetKey: assetKey,
        );
      case AchievementRarityTier.legendary:
        final isHacker = assetKey == 'bug_hunter';
        final primary = isHacker
            ? const Color(0xFF10B981)
            : const Color(0xFFF59E0B);
        final secondary = isHacker
            ? const Color(0xFF34D399)
            : const Color(0xFFFDE047);
        return AchievementBadgeStyle(
          tier: tier,
          label: 'Легендарный',
          rimColors: [primary, secondary, primary],
          glowColor: accentOverride ?? primary,
          assetKey: assetKey,
        );
    }
  }
}

/// Переиспользуемый Steam-медальон достижения с PNG-ассетом, геометрическим
/// CustomPainter + ShaderMask фоллбэком, рамкой редкости и анимацией блика
/// для легендарных значков.
class AchievementBadgeArtwork extends StatefulWidget {
  final String badgeId;
  final bool isUnlocked;
  final double size;
  final String? rarity;
  final Color? accentColor;

  const AchievementBadgeArtwork({
    super.key,
    required this.badgeId,
    required this.isUnlocked,
    this.size = 44,
    this.rarity,
    this.accentColor,
  });

  @override
  State<AchievementBadgeArtwork> createState() =>
      _AchievementBadgeArtworkState();
}

class _AchievementBadgeArtworkState extends State<AchievementBadgeArtwork>
    with SingleTickerProviderStateMixin {
  static const List<double> _grayscaleMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  AnimationController? _shimmerController;

  AchievementBadgeStyle get _style => AchievementBadgeStyle.resolve(
        widget.badgeId,
        rarityLabel: widget.rarity,
        accentOverride: widget.accentColor,
      );

  bool get _needsShimmer =>
      widget.isUnlocked &&
      _style.tier == AchievementRarityTier.legendary;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AchievementBadgeArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.badgeId != widget.badgeId ||
        oldWidget.isUnlocked != widget.isUnlocked ||
        oldWidget.rarity != widget.rarity) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (_needsShimmer) {
      _shimmerController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2800),
      )..repeat();
    } else {
      _shimmerController?.dispose();
      _shimmerController = null;
    }
  }

  @override
  void dispose() {
    _shimmerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final size = widget.size;
    final rimWidth = (size * 0.055).clamp(1.5, 3.0);

    final artwork = ClipOval(
      child: Image.asset(
        'assets/badges/${style.assetKey}.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _VectorMedallionFallback(
          assetKey: style.assetKey,
          style: style,
          size: size,
        ),
      ),
    );

    final Widget filteredArtwork = widget.isUnlocked
        ? artwork
        : Opacity(
            opacity: 0.28,
            child: ColorFilterWidget(
              matrix: _grayscaleMatrix,
              child: artwork,
            ),
          );

    Widget medallionCore = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isUnlocked
            ? const Color(0xFF0D1320)
            : const Color(0xFF090C14),
        boxShadow: widget.isUnlocked
            ? [
                BoxShadow(
                  color: style.glowColor.withValues(
                    alpha: style.tier == AchievementRarityTier.legendary
                        ? 0.42
                        : style.tier == AchievementRarityTier.epic
                            ? 0.30
                            : 0.22,
                  ),
                  blurRadius: size * 0.34,
                  spreadRadius: size * 0.03,
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.isUnlocked)
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    style.glowColor.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.85],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(rimWidth),
            child: filteredArtwork,
          ),
          // Металлическая рамка редкости
          IgnorePointer(
            child: _buildRimOverlay(style, rimWidth),
          ),
        ],
      ),
    );

    if (_shimmerController != null) {
      medallionCore = AnimatedBuilder(
        animation: _shimmerController!,
        builder: (context, child) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipOval(
                    child: CustomPaint(
                      painter: _SpecularSweepPainter(
                        progress: _shimmerController!.value,
                        color: style.rimColors.last,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: medallionCore,
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            medallionCore,
            if (!widget.isUnlocked)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1420),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRimOverlay(AchievementBadgeStyle style, double rimWidth) {
    if (!widget.isUnlocked) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF334155).withValues(alpha: 0.55),
            width: rimWidth,
          ),
        ),
      );
    }

    return CustomPaint(
      painter: _GradientRimPainter(
        colors: style.rimColors,
        strokeWidth: rimWidth,
      ),
    );
  }
}

/// Простой wrapper над [ColorFiltered] для читаемости матрицы оттенков серого.
class ColorFilterWidget extends StatelessWidget {
  final List<double> matrix;
  final Widget child;

  const ColorFilterWidget({
    super.key,
    required this.matrix,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: child,
    );
  }
}

/// Плашка редкости значка в стиле Steam.
class AchievementRarityPill extends StatelessWidget {
  final String badgeId;
  final String? rarity;
  final bool isUnlocked;

  const AchievementRarityPill({
    super.key,
    required this.badgeId,
    this.rarity,
    this.isUnlocked = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = AchievementBadgeStyle.resolve(
      badgeId,
      rarityLabel: rarity,
    );
    final accent = isUnlocked ? style.glowColor : const Color(0xFF94A3B8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isUnlocked ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accent.withValues(alpha: isUnlocked ? 0.45 : 0.18),
        ),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _GradientRimPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;

  const _GradientRimPainter({
    required this.colors,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: [...colors, colors.first],
      ).createShader(rect);
    canvas.drawOval(rect.deflate(strokeWidth / 2), paint);
  }

  @override
  bool shouldRepaint(covariant _GradientRimPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.strokeWidth != strokeWidth;
}

class _SpecularSweepPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _SpecularSweepPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = -size.width + (progress * size.width * 3.0);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.35),
          color.withValues(alpha: 0.28),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      ).createShader(
        Rect.fromLTWH(x, 0, size.width * 0.75, size.height),
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _SpecularSweepPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Геометрический фоллбэк на CustomPainter + ShaderMask (без системных иконок и эмодзи).
class _VectorMedallionFallback extends StatelessWidget {
  final String assetKey;
  final AchievementBadgeStyle style;
  final double size;

  const _VectorMedallionFallback({
    required this.assetKey,
    required this.style,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: [
            Color(0xFF1A2338),
            Color(0xFF0A0F1A),
          ],
        ),
      ),
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            style.glowColor,
            style.rimColors.first,
          ],
        ).createShader(bounds),
        child: CustomPaint(
          painter: _GeometricEmblemPainter(assetKey: assetKey),
        ),
      ),
    );
  }
}

class _GeometricEmblemPainter extends CustomPainter {
  final String assetKey;

  const _GeometricEmblemPainter({required this.assetKey});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.28;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.06).clamp(1.5, 3.2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Внешний гексагон-основа
    final hex = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final pt = Offset(
        c.dx + (r * 1.32) * math.cos(angle),
        c.dy + (r * 1.32) * math.sin(angle),
      );
      if (i == 0) {
        hex.moveTo(pt.dx, pt.dy);
      } else {
        hex.lineTo(pt.dx, pt.dy);
      }
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.width * 0.035).clamp(1.0, 2.0),
    );

    switch (assetKey) {
      case 'first_step':
        final play = Path()
          ..moveTo(c.dx - r * 0.45, c.dy - r * 0.65)
          ..lineTo(c.dx + r * 0.78, c.dy)
          ..lineTo(c.dx - r * 0.45, c.dy + r * 0.65)
          ..close();
        canvas.drawPath(play, fill);
        break;
      case 'watch_hour':
        final top = Path()
          ..moveTo(c.dx - r * 0.65, c.dy - r * 0.75)
          ..lineTo(c.dx + r * 0.65, c.dy - r * 0.75)
          ..lineTo(c.dx, c.dy)
          ..close();
        final bot = Path()
          ..moveTo(c.dx - r * 0.65, c.dy + r * 0.75)
          ..lineTo(c.dx + r * 0.65, c.dy + r * 0.75)
          ..lineTo(c.dx, c.dy)
          ..close();
        canvas.drawPath(top, stroke);
        canvas.drawPath(bot, fill);
        break;
      case 'op_skipper':
        for (final dx in [-r * 0.36, r * 0.22]) {
          final chev = Path()
            ..moveTo(c.dx + dx - r * 0.28, c.dy - r * 0.55)
            ..lineTo(c.dx + dx + r * 0.30, c.dy)
            ..lineTo(c.dx + dx - r * 0.28, c.dy + r * 0.55);
          canvas.drawPath(chev, stroke);
        }
        break;
      case 'night_owl':
        final moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.78)),
          Path()
            ..addOval(
              Rect.fromCircle(
                center: Offset(c.dx + r * 0.36, c.dy - r * 0.22),
                radius: r * 0.66,
              ),
            ),
        );
        canvas.drawPath(moon, fill);
        break;
      case 'marathoner':
        final bolt = Path()
          ..moveTo(c.dx + r * 0.15, c.dy - r * 0.85)
          ..lineTo(c.dx - r * 0.52, c.dy + r * 0.08)
          ..lineTo(c.dx + r * 0.02, c.dy + r * 0.08)
          ..lineTo(c.dx - r * 0.18, c.dy + r * 0.85)
          ..lineTo(c.dx + r * 0.52, c.dy - r * 0.08)
          ..lineTo(c.dx - r * 0.02, c.dy - r * 0.08)
          ..close();
        canvas.drawPath(bolt, fill);
        break;
      case 'party_soul':
        canvas.drawCircle(Offset(c.dx - r * 0.32, c.dy), r * 0.48, stroke);
        canvas.drawCircle(Offset(c.dx + r * 0.32, c.dy), r * 0.48, stroke);
        break;
      case 'collector':
        final crown = Path()
          ..moveTo(c.dx - r * 0.72, c.dy + r * 0.45)
          ..lineTo(c.dx - r * 0.72, c.dy - r * 0.32)
          ..lineTo(c.dx - r * 0.28, c.dy + r * 0.08)
          ..lineTo(c.dx, c.dy - r * 0.58)
          ..lineTo(c.dx + r * 0.28, c.dy + r * 0.08)
          ..lineTo(c.dx + r * 0.72, c.dy - r * 0.32)
          ..lineTo(c.dx + r * 0.72, c.dy + r * 0.45)
          ..close();
        canvas.drawPath(crown, fill);
        break;
      case 'bug_hunter':
        canvas.drawRect(
          Rect.fromCenter(center: c, width: r * 1.25, height: r * 0.72),
          stroke,
        );
        canvas.drawLine(
          Offset(c.dx - r * 0.35, c.dy),
          Offset(c.dx + r * 0.35, c.dy),
          stroke,
        );
        break;
      case 'founder':
      default:
        final star = Path();
        for (int i = 0; i < 8; i++) {
          final rad = i.isEven ? r * 0.88 : r * 0.38;
          final a = (math.pi / 4) * i - math.pi / 2;
          final pt = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
          if (i == 0) {
            star.moveTo(pt.dx, pt.dy);
          } else {
            star.lineTo(pt.dx, pt.dy);
          }
        }
        star.close();
        canvas.drawPath(star, fill);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _GeometricEmblemPainter oldDelegate) =>
      oldDelegate.assetKey != assetKey;
}

