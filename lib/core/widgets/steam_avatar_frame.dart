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

              // 2. СПЕЦИАЛЬНЫЕ ЭФФЕКТЫ ЧАСТИЦ:
              // Эффект падающего снега (Glacial Frost)
              if (isGlacialFrost || frame.id == 'snowy_mountain') ...[
                ...List.generate(12, (i) {
                  final seed = (i * 0.23);
                  final snowY = ((t + seed) % 1.0) * (frameOuterSize + 12) - (frameOuterSize / 2 + 6);
                  final snowX = math.sin((t * 2 + i) * math.pi) * (frameOuterSize / 2.2);
                  final flakeSize = 2.0 + (i % 3);

                  return Transform.translate(
                    offset: Offset(snowX, snowY),
                    child: Container(
                      width: flakeSize,
                      height: flakeSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF80D8FF).withValues(alpha: 0.9),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              // Эффект кода Матрицы (Hacker / Terminal Matrix)
              if (frame.id == 'terminal_matrix') ...[
                ...List.generate(8, (i) {
                  final seed = (i * 0.31);
                  final dropY = ((t * 1.5 + seed) % 1.0) * (frameOuterSize + 14) - (frameOuterSize / 2 + 7);
                  final dropX = math.cos(i * 1.2) * (frameOuterSize / 2.1);

                  return Transform.translate(
                    offset: Offset(dropX, dropY),
                    child: Text(
                      ['0', '1', 'λ', '0', '1', 'π', '0', '1'][i],
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF00FF66).withValues(
                          alpha: ((dropY + frameOuterSize / 2) / frameOuterSize).clamp(0.2, 1.0),
                        ),
                        shadows: const [
                          Shadow(color: Color(0xFF00FF66), blurRadius: 6),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              // Эффект лепестков сакуры (Sakura Blossom)
              if (frame.id == 'sakura_blossom' || frame.id == 'cherry_blossom_night') ...[
                ...List.generate(7, (i) {
                  final seed = (i * 0.28);
                  final petalY = ((t * 0.8 + seed) % 1.0) * (frameOuterSize + 10) - (frameOuterSize / 2 + 5);
                  final petalX = math.sin((t * 1.2 + i * 0.8) * math.pi) * (frameOuterSize / 2.1);
                  final petalRot = (t * 2 + i) * math.pi;

                  return Transform.translate(
                    offset: Offset(petalX, petalY),
                    child: Transform.rotate(
                      angle: petalRot,
                      child: Container(
                        width: 4,
                        height: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9EB5).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF007F).withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],

              // Эффект языков пламени (Infernal Flame / Golden Dragon)
              if (frame.id == 'infernal_flame' || frame.id == 'golden_dragon' || frame.id == 'shadow_oni') ...[
                ...List.generate(9, (i) {
                  final flameAngle = (i * 2 * math.pi / 9) + (math.sin(t * 6 + i) * 0.15);
                  final flameHeight = 4.0 + math.sin(t * 8 + i * 2).abs() * 6.0;
                  final r = (frameOuterSize / 2) + 1;
                  final dx = r * math.cos(flameAngle);
                  final dy = r * math.sin(flameAngle);

                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.rotate(
                      angle: flameAngle + math.pi / 2,
                      child: Container(
                        width: 3.5,
                        height: flameHeight,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFFFF3D00), Color(0xFFFFD600), Colors.white],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xFFFF6D00),
                              blurRadius: 5,
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
