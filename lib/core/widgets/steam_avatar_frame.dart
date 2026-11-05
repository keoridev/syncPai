import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../features/profile/domain/entities/steam_profile_customization.dart';

/// Анимированная рамка аватара в стиле Steam Points Shop
/// с излучающимся неоновым свечением, пульсирующей аурой,
/// ледяными кристаллами для Ледяного Клинка и вращающимися орбитальными частицами энергии.
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
      duration: const Duration(seconds: 3),
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

  @override
  Widget build(BuildContext context) {
    final frame = SteamAvatarFrame.fromId(widget.frameId);

    if (frame.id == 'none') {
      return widget.child;
    }

    final frameOuterSize = widget.size + 14;
    final isGlacialFrost = frame.id == 'glacial_frost';

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final t = _animController.value;
        final angle = t * 2 * math.pi;
        // Пульсация излучения (дыхание ауры)
        final pulse = (math.sin(t * 2 * math.pi) + 1.0) / 2.0;
        final glowSpread = 2.0 + (pulse * 3.5);
        final glowBlur = 10.0 + (pulse * 8.0);
        final primaryFrameColor = frame.colors.isNotEmpty ? frame.colors.first : Colors.cyanAccent;
        final secondaryFrameColor = frame.colors.length > 1 ? frame.colors[1] : primaryFrameColor;

        return SizedBox(
          width: frameOuterSize + 16,
          height: frameOuterSize + 16,
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
                      color: primaryFrameColor.withValues(alpha: 0.38 + (pulse * 0.28)),
                      blurRadius: glowBlur,
                      spreadRadius: glowSpread,
                    ),
                    BoxShadow(
                      color: secondaryFrameColor.withValues(alpha: 0.28 + (pulse * 0.22)),
                      blurRadius: glowBlur * 1.4,
                      spreadRadius: glowSpread * 0.6,
                    ),
                    if (isGlacialFrost)
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.2 + (pulse * 0.2)),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                  ],
                ),
              ),

              // 2. СПЕЦЭФФЕКТ ДЛЯ «ЛЕДЯНОЙ КЛИНОК» (Glacial Frost):
              // 8 кристаллических ледяных осколков, пульсирующих ледяным светом
              if (isGlacialFrost) ...[
                ...List.generate(8, (i) {
                  final shardAngle = (i * math.pi / 4) + (t * 0.4);
                  final r = (frameOuterSize / 2) + 2 + (pulse * 2.0);
                  final dx = r * math.cos(shardAngle);
                  final dy = r * math.sin(shardAngle);

                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.rotate(
                      angle: shardAngle + (math.pi / 4),
                      child: Container(
                        width: 5,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85 + (pulse * 0.15)),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],

              // 3. Внешнее медленно вращающееся неоновое кольцо с градиентом
              Transform.rotate(
                angle: angle,
                child: Container(
                  width: frameOuterSize,
                  height: frameOuterSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        ...frame.colors,
                        frame.colors.first,
                      ],
                    ),
                  ),
                ),
              ),

              // 4. Внутреннее контр-вращающееся тонкое кольцо для эффекта глубины
              Transform.rotate(
                angle: -angle * 1.5,
                child: Container(
                  width: frameOuterSize - 4,
                  height: frameOuterSize - 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        secondaryFrameColor.withValues(alpha: 0.9),
                        Colors.transparent,
                        primaryFrameColor.withValues(alpha: 0.9),
                        Colors.transparent,
                        secondaryFrameColor.withValues(alpha: 0.9),
                      ],
                    ),
                  ),
                ),
              ),

              // 5. Орбитальные энергетические частицы-блики (излучающиеся искры)
              ...List.generate(isGlacialFrost ? 5 : 4, (i) {
                final particleCount = isGlacialFrost ? 5 : 4;
                final particleAngle = angle + (i * (2 * math.pi / particleCount));
                final radius = (frameOuterSize / 2) - 1;
                final dx = radius * math.cos(particleAngle);
                final dy = radius * math.sin(particleAngle);

                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: Container(
                    width: isGlacialFrost ? 5.5 : 5,
                    height: isGlacialFrost ? 5.5 : 5,
                    decoration: BoxDecoration(
                      shape: isGlacialFrost ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isGlacialFrost ? BorderRadius.circular(1.5) : null,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: isGlacialFrost ? const Color(0xFF00E5FF) : primaryFrameColor,
                          blurRadius: 7,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                );
              }),

              // 6. Внутренняя подложка для разделения рамки и аватара
              Container(
                width: widget.size + 4,
                height: widget.size + 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF121316),
                  shape: BoxShape.circle,
                ),
              ),

              // 7. Сам аватар пользователя
              widget.child,
            ],
          ),
        );
      },
    );
  }
}
