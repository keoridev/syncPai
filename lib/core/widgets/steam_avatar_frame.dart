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
    final isSnow = frame.animation == SteamFrameAnimation.snow ||
        isGlacialFrost ||
        frame.id == 'blizzard_snow' ||
        frame.id.contains('snow');
    final isMatrix = frame.animation == SteamFrameAnimation.matrix ||
        frame.id == 'terminal_matrix' ||
        frame.id == 'matrix_hacker' ||
        frame.id.contains('matrix');
    final isSakura = frame.id.contains('sakura') || frame.id.contains('blossom');
    final isFire = frame.animation == SteamFrameAnimation.fire ||
        frame.id.contains('flame') ||
        frame.id.contains('dragon') ||
        frame.id.contains('flare') ||
        frame.id.contains('oni');
    final isLightning = frame.id.contains('electric') ||
        frame.id.contains('plasma') ||
        frame.id.contains('storm');

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
              // Эффект реалистичного падающего снега (Снежная метель / Ледяной Клинок)
              if (isSnow) ...[
                ...List.generate(18, (i) {
                  final seed = (i * 0.173);
                  final speed = 0.8 + ((i % 4) * 0.25);
                  final snowY = ((t * speed + seed) % 1.0) * (frameOuterSize + 16) - (frameOuterSize / 2 + 8);
                  // Естественное покачивание на зимнем ветру
                  final wind = math.sin((t * 2 * math.pi) + (i * 1.4)) * (5.0 + (i % 3) * 2.5);
                  final snowX = ((i / 18.0) * (frameOuterSize + 8) - (frameOuterSize / 2 + 4)) + wind;
                  final flakeSize = 1.8 + (i % 4) * 0.9;
                  final opacity = (0.45 + (i % 5) * 0.12).clamp(0.2, 0.95);

                  return Transform.translate(
                    offset: Offset(snowX, snowY),
                    child: Transform.rotate(
                      angle: (t * 2.5 + i) * math.pi,
                      child: Container(
                        width: flakeSize,
                        height: flakeSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: opacity),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB3E5FC).withValues(alpha: 0.9),
                              blurRadius: 4,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],

              // Эффект реалистичного цифрового дождя Матрицы (Hacker Terminal)
              if (isMatrix) ...[
                ...List.generate(14, (i) {
                  final seed = (i * 0.21);
                  final speed = 1.2 + ((i % 3) * 0.4);
                  final dropY = ((t * speed + seed) % 1.0) * (frameOuterSize + 18) - (frameOuterSize / 2 + 9);
                  final dropX = (i / 14.0) * (frameOuterSize + 4) - (frameOuterSize / 2 + 2);
                  const glyphs = ['1', '0', 'λ', '1', '§', '0', 'ｶ', '1', '⚡', '0', '7', '1', 'X', '0'];
                  final char = glyphs[i % glyphs.length];
                  final isHead = ((t * speed + seed) % 1.0) > 0.85;

                  return Transform.translate(
                    offset: Offset(dropX, dropY),
                    child: Text(
                      char,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: isHead ? 9.5 : 8.0,
                        fontWeight: FontWeight.w900,
                        color: isHead
                            ? const Color(0xFFE0FFF4)
                            : const Color(0xFF00FF66).withValues(
                                alpha: ((dropY + frameOuterSize / 2) / frameOuterSize).clamp(0.25, 1.0),
                              ),
                        shadows: [
                          Shadow(
                            color: isHead ? const Color(0xFF00FF66) : const Color(0xFF008F39),
                            blurRadius: isHead ? 8 : 4,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              // Эффект реалистичных лепестков сакуры (Sakura Blossom)
              if (isSakura) ...[
                ...List.generate(10, (i) {
                  final seed = (i * 0.24);
                  final petalY = ((t * 0.75 + seed) % 1.0) * (frameOuterSize + 14) - (frameOuterSize / 2 + 7);
                  final flutter = math.sin((t * 2.0 + i * 0.7) * math.pi) * (frameOuterSize / 2.3);
                  final petalRot = (t * 2.4 + i * 1.1) * math.pi;

                  return Transform.translate(
                    offset: Offset(flutter, petalY),
                    child: Transform.rotate(
                      angle: petalRot,
                      child: Container(
                        width: 4.5,
                        height: 7.5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB2C9).withValues(alpha: 0.9),
                          borderRadius: const BorderRadius.all(Radius.elliptical(4, 7)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF4081).withValues(alpha: 0.7),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],

              // Эффект языков пламени и взлетающих искр (Infernal Flame / Solar Dragon)
              if (isFire) ...[
                // Языки пламени по периметру
                ...List.generate(10, (i) {
                  final flameAngle = (i * 2 * math.pi / 10) + (math.sin(t * 6 + i) * 0.16);
                  final flameHeight = 4.5 + math.sin(t * 9 + i * 2).abs() * 7.0;
                  final r = (frameOuterSize / 2) + 1.5;
                  final dx = r * math.cos(flameAngle);
                  final dy = r * math.sin(flameAngle);

                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.rotate(
                      angle: flameAngle + math.pi / 2,
                      child: Container(
                        width: 3.8,
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
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                // Взлетающие горящие искры
                ...List.generate(8, (i) {
                  final seed = (i * 0.28);
                  final sparkY = ((1.0 - ((t * 1.5 + seed) % 1.0))) * (frameOuterSize + 10) - (frameOuterSize / 2 + 5);
                  final sparkX = math.sin((t * 4 + i) * math.pi) * (frameOuterSize / 2.6);

                  return Transform.translate(
                    offset: Offset(sparkX, sparkY),
                    child: Container(
                      width: 2.5,
                      height: 2.5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFEB3B),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFFF5722),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              // Эффект электрических разрядов и молний (Electric / Plasma Storm)
              if (isLightning) ...[
                ...List.generate(6, (i) {
                  final sparkAngle = (i * 2 * math.pi / 6) + (math.sin(t * 12 + i) * 0.3);
                  final r = (frameOuterSize / 2) + 2.0;
                  final dx = r * math.cos(sparkAngle);
                  final dy = r * math.sin(sparkAngle);
                  final isFlashing = ((t * 8 + i) % 1.0) > 0.45;

                  if (!isFlashing) return const SizedBox.shrink();

                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: (i % 2 == 0) ? const Color(0xFF00E5FF) : const Color(0xFFFFEB3B),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
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
