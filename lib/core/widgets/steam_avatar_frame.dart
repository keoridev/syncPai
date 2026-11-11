import 'dart:math' as math;
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

  const SteamAvatarFrameWidget({
    super.key,
    required this.child,
    this.frameId,
    required this.size,
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
    if (widget.frameId != null && widget.frameId != 'none') {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SteamAvatarFrameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frameId != oldWidget.frameId) {
      if (widget.frameId != null && widget.frameId != 'none') {
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
    if (clean.contains('sakura') || clean.contains('blossom')) {
      return 'sakura';
    }
    if (clean.contains('dragon')) {
      return 'golden_dragon';
    }
    if (clean.contains('cyber') || clean.contains('blade') || clean.contains('samurai')) {
      return 'cyber_blade';
    }
    if (clean.contains('shadow') || clean.contains('monarch') || clean.contains('void') || clean.contains('cursed') || clean.contains('oni')) {
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

    final frameOuterSize = widget.size + 14;
    final primaryFrameColor = frame.colors.isNotEmpty ? frame.colors.first : AppColors.primary;
    final thematicType = _resolveThematicType(frame.id);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          final t = _animController.value;
          final pulse = (math.sin(t * 2 * math.pi) + 1.0) / 2.0;

          return SizedBox(
            width: frameOuterSize + 20,
            height: frameOuterSize + 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Внешняя пульсирующая аура (излучение)
                Container(
                  width: frameOuterSize + (pulse * 8.0),
                  height: frameOuterSize + (pulse * 8.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: primaryFrameColor.withValues(alpha: 0.12),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),

                // 2. Тематический слой сюжетной рамки (CustomPainter)
                CustomPaint(
                  size: Size(frameOuterSize + 16, frameOuterSize + 16),
                  painter: ThematicAvatarFramePainter(
                    animationValue: t,
                    frameType: thematicType,
                    colors: frame.colors,
                    outerSize: frameOuterSize,
                  ),
                ),

                // 3. Внутренняя подложка для чистого разделения рамки и аватара
                Container(
                  width: widget.size + 4,
                  height: widget.size + 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF121316),
                    shape: BoxShape.circle,
                  ),
                ),

                // 4. Сам аватар пользователя
                widget.child,
              ],
            ),
          );
        },
      ),
    );
  }
}
