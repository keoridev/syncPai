import 'package:flutter/material.dart';
import '../../features/profile/domain/entities/steam_profile_customization.dart';
import '../theme/app_colors.dart';
import 'avatar_frame_painter.dart';

/// Анимированная тематическая рамка аватара в стиле Steam Points Shop / Discord Nitro
/// с многослойным рендерингом (Сакура с ветвью, Кибер-катаны с молниями, Аура Теневого Монарха, Матрица),
/// обернутая в [RepaintBoundary] для стабильных 60–120 FPS.
class SteamAvatarFrameWidget extends StatefulWidget {
  final Widget child;
  final String? frameId;
  final double size;
  final String shape; // 'circle' или 'square'
  final bool animate;

  const SteamAvatarFrameWidget({
    super.key,
    required this.child,
    this.frameId,
    required this.size,
    this.shape = 'circle',
    this.animate = true,
  });

  @override
  State<SteamAvatarFrameWidget> createState() => _SteamAvatarFrameWidgetState();
}

class _SteamAvatarFrameWidgetState extends State<SteamAvatarFrameWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animate && widget.frameId != null && widget.frameId != 'none') {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SteamAvatarFrameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frameId != oldWidget.frameId ||
        widget.animate != oldWidget.animate) {
      if (widget.animate &&
          widget.frameId != null &&
          widget.frameId != 'none') {
        if (!_animController.isAnimating) _animController.repeat();
      } else {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _resolveThematicType(String id) {
    final clean = id.toLowerCase();
    if (clean.contains('pai_headphones') || clean == 'headphones') {
      return 'pai_headphones';
    }
    if (clean.contains('pai_peek') || clean == 'peek') {
      return 'pai_peek';
    }
    if (clean.contains('pai_hacker') || clean == 'hacker_glitch' || clean == 'bug_hunter') {
      return 'pai_hacker';
    }
    if (clean.contains('sakura') || clean.contains('blossom')) {
      return 'sakura';
    }
    if (clean.contains('gold') || clean.contains('dragon')) {
      return 'golden_dragon';
    }
    if (clean.contains('katana') || clean.contains('samurai')) {
      return 'katana_guard';
    }
    if (clean.contains('techno') || clean.contains('bevel')) {
      return 'techno_bevel';
    }
    if (clean.contains('monolith')) {
      return 'monolith';
    }
    if (clean.contains('ice') || clean.contains('crystal') || clean.contains('frost')) {
      return 'ice_crystal';
    }
    if (clean.contains('minimal')) {
      return 'minimal';
    }
    if (clean.contains('coral')) {
      return 'coral_contour';
    }
    if (clean.contains('ember') || clean.contains('rank_ember') || clean.contains('flame')) {
      return 'rank_ember';
    }
    if (clean.contains('cyber') || clean.contains('blade')) {
      return 'cyber_blade';
    }
    if (clean.contains('shadow') || clean.contains('monarch') || clean.contains('void')) {
      return 'shadow_monarch';
    }
    if (clean.contains('matrix') || clean.contains('terminal')) {
      return 'matrix_glitch';
    }
    return 'default';
  }

  @override
  Widget build(BuildContext context) {
    final frame = SteamAvatarFrame.fromId(widget.frameId);

    if (frame.id == 'none') {
      return widget.child;
    }

    final isSquare = widget.shape == 'square';
    final frameOuterSize = widget.size + 14;
    final primaryFrameColor = frame.colors.isNotEmpty ? frame.colors.first : AppColors.primary;
    final thematicType = _resolveThematicType(frame.id);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          final t = _animController.value;

          if (isSquare) {
            return SizedBox(
              width: frameOuterSize + 16,
              height: frameOuterSize + 16,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. Сам аватар (без перекрывающей внутренней рамки)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: widget.child,
                  ),

                  // 2. Чёткий векторный слой архитектурной рамки (без glow)
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size(frameOuterSize + 16, frameOuterSize + 16),
                      painter: ThematicAvatarFramePainter(
                        animationValue: t,
                        frameType: _resolveThematicType(frame.id),
                        colors: frame.colors.isNotEmpty
                            ? frame.colors
                            : [primaryFrameColor],
                        outerSize: frameOuterSize,
                        shape: 'square',
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return SizedBox(
            width: frameOuterSize + 20,
            height: frameOuterSize + 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Сам аватар пользователя (строго круглая обрезка)
                ClipOval(
                  child: widget.child,
                ),

                // 2. Тематический слой сюжетной рамки (CustomPainter)
                IgnorePointer(
                  child: CustomPaint(
                    size: Size(frameOuterSize + 20, frameOuterSize + 20),
                    painter: ThematicAvatarFramePainter(
                      animationValue: t,
                      frameType: thematicType,
                      colors: frame.colors,
                      outerSize: frameOuterSize,
                      shape: 'circle',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
