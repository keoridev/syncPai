import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../sync_room/domain/entities/sync_protocol.dart';

/// Горизонтальная панель из 6 круговых стикер-реакций Пай-чан
/// (заменяет стандартные плоские Unicode-эмодзи в чате комнаты и мобильном плеере).
class PaiChanStickerReactionBar extends StatelessWidget {
  final ValueChanged<PaiChanSticker> onStickerSelected;
  final bool compact;
  final double? stickerSize;
  final EdgeInsetsGeometry? padding;
  final MainAxisAlignment mainAxisAlignment;

  const PaiChanStickerReactionBar({
    super.key,
    required this.onStickerSelected,
    this.compact = false,
    this.stickerSize,
    this.padding,
    this.mainAxisAlignment = MainAxisAlignment.spaceAround,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSize = stickerSize ?? (compact ? 26.0 : 44.0);
    final effectivePadding =
        padding ?? (compact ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2) : const EdgeInsets.symmetric(horizontal: 8, vertical: 6));

    return Padding(
      key: const ValueKey('pai_chan_sticker_reaction_bar'),
      padding: effectivePadding,
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: PaiChanSticker.values.map((sticker) {
          return Flexible(
            fit: FlexFit.loose,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 1.5 : 2.5),
              child: _PaiChanStickerButton(
                key: ValueKey('pai_sticker_btn_${sticker.id}'),
                sticker: sticker,
                size: effectiveSize,
                onTap: () => onStickerSelected(sticker),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PaiChanStickerButton extends StatefulWidget {
  final PaiChanSticker sticker;
  final double size;
  final VoidCallback onTap;

  const _PaiChanStickerButton({
    super.key,
    required this.sticker,
    required this.size,
    required this.onTap,
  });

  @override
  State<_PaiChanStickerButton> createState() => _PaiChanStickerButtonState();
}

class _PaiChanStickerButtonState extends State<_PaiChanStickerButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.88 : (_isHovered ? 1.15 : 1.0);

    return Tooltip(
      message: widget.sticker.tooltip,
      waitDuration: const Duration(milliseconds: 250),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapCancel: () => setState(() => _isPressed = false),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            try {
              HapticFeedback.lightImpact();
            } catch (_) {}
            widget.onTap();
          },
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: widget.size,
              height: widget.size,
              padding: EdgeInsets.all(widget.size >= 40 ? 4.0 : 2.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isHovered
                    ? widget.sticker.glowColor.withValues(alpha: 0.24)
                    : widget.sticker.glowColor.withValues(alpha: 0.08),
                border: Border.all(
                  color: _isHovered
                      ? widget.sticker.glowColor.withValues(alpha: 0.85)
                      : widget.sticker.glowColor.withValues(alpha: 0.35),
                  width: _isHovered ? 1.6 : 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.sticker.glowColor.withValues(alpha: _isHovered ? 0.42 : 0.16),
                    blurRadius: _isHovered ? 12 : 6,
                    spreadRadius: _isHovered ? 1.0 : 0.0,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  widget.sticker.assetPath,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      widget.sticker.fallbackEmoji,
                      style: TextStyle(fontSize: widget.size * 0.52),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Оверлей летящих стикер-реакций Пай-чан поверх видеополотна (`76x76px` + бейдж с ником).
/// Обернут в `IgnorePointer`, чтобы никогда не блокировать клики и горячие клавиши плеера.
class FloatingPaiChanReactionsOverlay extends StatelessWidget {
  final List<FloatingReaction> reactions;

  const FloatingPaiChanReactionsOverlay({
    super.key,
    required this.reactions,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      key: const ValueKey('floating_pai_chan_reactions_overlay'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final height = constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;

          return Stack(
            fit: StackFit.expand,
            children: reactions
                .map(
                  (r) => _FloatingPaiChanBubble(
                    key: ValueKey('floating_pai_sticker_${r.id}'),
                    reaction: r,
                    areaWidth: width,
                    areaHeight: height,
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _FloatingPaiChanBubble extends StatefulWidget {
  final FloatingReaction reaction;
  final double areaWidth;
  final double areaHeight;

  const _FloatingPaiChanBubble({
    super.key,
    required this.reaction,
    required this.areaWidth,
    required this.areaHeight,
  });

  @override
  State<_FloatingPaiChanBubble> createState() => _FloatingPaiChanBubbleState();
}

class _FloatingPaiChanBubbleState extends State<_FloatingPaiChanBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final double _driftPhase;

  @override
  void initState() {
    super.initState();
    _driftPhase = (widget.reaction.id.hashCode % 628) / 100.0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sticker = widget.reaction.sticker;
    final senderName = widget.reaction.sender.trim().isNotEmpty
        ? widget.reaction.sender.trim()
        : 'Гость';

    final stickerBadge = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Круглый стикер Пай-чан 76x76px
        Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                sticker.glowColor.withValues(alpha: 0.55),
                const Color(0xFF141824).withValues(alpha: 0.90),
              ],
            ),
            border: Border.all(
              color: sticker.glowColor.withValues(alpha: 0.72),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: sticker.glowColor.withValues(alpha: 0.42),
                blurRadius: 16,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              sticker.assetPath,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  sticker.fallbackEmoji,
                  style: const TextStyle(fontSize: 34),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Стеклянный бейдж с ником отправителя под стикером
        Container(
          constraints: const BoxConstraints(maxWidth: 110),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFF10131C).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sticker.glowColor.withValues(alpha: 0.35),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final baseX = widget.areaWidth * widget.reaction.startXOffset.clamp(0.18, 0.84);

        double top;
        double left;
        double scale = 1.0;
        double rotation = 0.0;

        switch (sticker) {
          case PaiChanSticker.excited:
            // Hype: double spring bounce + 360° spin + starburst particles
            final rise = Curves.easeOutCubic.transform(t);
            final bounceOffset = t < 0.55
                ? -sin((t / 0.55) * 2 * pi).abs() * 22.0 * (1.0 - t)
                : 0.0;
            top = widget.areaHeight * (0.80 - rise * 0.62) + bounceOffset;
            left = baseX + sin(t * 2.4 * pi + _driftPhase) * 14.0 - 38.0;
            if (t < 0.24) {
              scale = 0.35 + Curves.elasticOut.transform((t / 0.24).clamp(0.0, 1.0)) * 0.72;
            } else if (t < 0.48) {
              final b2 = ((t - 0.24) / 0.24).clamp(0.0, 1.0);
              scale = 1.0 + sin(b2 * pi) * 0.18;
            } else if (t > 0.75) {
              scale = 1.0 - ((t - 0.75) / 0.25) * 0.16;
            }
            if (t >= 0.06 && t <= 0.44) {
              final spinT = Curves.easeOutBack.transform(((t - 0.06) / 0.38).clamp(0.0, 1.0));
              rotation = spinT * 2 * pi;
            }
            break;

          case PaiChanSticker.happy:
            // Laugh: ±14° high-frequency wobble + playful hopping + "ха-ха" / "w" particles
            final rise = Curves.easeOutCubic.transform(t);
            final hop = -sin(t * 9.0 * pi).abs() * 14.0;
            top = widget.areaHeight * (0.78 - rise * 0.56) + hop;
            left = baseX + sin(t * 3.0 * pi + _driftPhase) * 16.0 - 38.0;
            rotation = sin(t * 20.0 * pi) * 0.244 * (1.0 - t * 0.35);
            scale = t < 0.16
                ? 0.45 + Curves.easeOutBack.transform(t / 0.16) * 0.55
                : (t > 0.74 ? 1.0 - ((t - 0.74) / 0.26) * 0.14 : 1.0);
            break;

          case PaiChanSticker.surprised:
            // Shock: dramatic zoom-pop (0.4x -> 1.35x -> 1.0x) + micro-shake + brief freeze
            final rise = t < 0.28
                ? Curves.easeOutCubic.transform(t / 0.28) * 0.55
                : (t < 0.65 ? 0.55 : 0.55 + ((t - 0.65) / 0.35) * 0.22);
            final shakeX = (t >= 0.14 && t <= 0.56)
                ? sin(t * 38.0 * pi) * 7.5 * (1.0 - (t - 0.14) / 0.42)
                : 0.0;
            top = widget.areaHeight * (0.74 - rise * 0.52);
            left = baseX + shakeX - 38.0;
            if (t < 0.14) {
              scale = 0.40 + Curves.easeOutCubic.transform(t / 0.14) * 0.95;
            } else if (t < 0.28) {
              scale = 1.35 - Curves.easeInOut.transform((t - 0.14) / 0.14) * 0.35;
            } else if (t > 0.76) {
              scale = 1.0 - ((t - 0.76) / 0.24) * 0.15;
            }
            rotation = (t >= 0.14 && t <= 0.52) ? sin(t * 30.0 * pi) * 0.08 : 0.0;
            break;

          case PaiChanSticker.sad:
            // Cry: gentle slump downward/sideways + falling blue teardrops
            final slump = Curves.easeInOutCubic.transform(t);
            top = widget.areaHeight * 0.42 + slump * 38.0;
            left = baseX - slump * 16.0 - 38.0;
            rotation = -0.08 * slump + sin(t * 4.0 * pi) * 0.03;
            scale = t < 0.18
                ? 0.5 + Curves.easeOutBack.transform(t / 0.18) * 0.5
                : 1.0 - slump * 0.10;
            break;

          case PaiChanSticker.love:
            // Love: graceful S-curve levitation + heartbeat pulse (1.0 -> 1.18 -> 1.0)
            final rise = Curves.easeOutSine.transform(t);
            final sCurve = sin(t * 3.0 * pi + _driftPhase) * 28.0;
            top = widget.areaHeight * (0.80 - rise * 0.64);
            left = baseX + sCurve - 38.0;
            final beatPhase = (t * 3.2) % 1.0;
            final pulse = beatPhase < 0.25
                ? sin((beatPhase / 0.25) * pi) * 0.18
                : (beatPhase < 0.45 ? sin(((beatPhase - 0.25) / 0.20) * pi) * 0.10 : 0.0);
            scale = t < 0.15
                ? 0.4 + Curves.easeOutBack.transform(t / 0.15) * 0.6
                : (1.0 + pulse) * (t > 0.78 ? 1.0 - ((t - 0.78) / 0.22) * 0.14 : 1.0);
            rotation = cos(t * 3.0 * pi + _driftPhase) * 0.06;
            break;

          case PaiChanSticker.sleepy:
            // Sleepy: slow dreamy pendulum sway + rising Zzz...
            final rise = Curves.linear.transform(t);
            top = widget.areaHeight * (0.72 - rise * 0.46);
            left = baseX + sin(t * 2.2 * pi + _driftPhase) * 20.0 - 38.0;
            rotation = sin(t * 2.5 * pi) * 0.14;
            scale = t < 0.20
                ? 0.6 + Curves.easeOut.transform(t / 0.20) * 0.4
                : (t > 0.72 ? 1.0 - ((t - 0.72) / 0.28) * 0.12 : 1.0);
            break;
        }

        final clampedTop = top.clamp(12.0, max(16.0, widget.areaHeight - 110.0));
        final clampedLeft = left.clamp(12.0, max(16.0, widget.areaWidth - 96.0));

        final double opacity;
        if (t < 0.10) {
          opacity = (t / 0.10).clamp(0.0, 1.0);
        } else if (t > 0.72) {
          opacity = (1.0 - (t - 0.72) / 0.28).clamp(0.0, 1.0);
        } else {
          opacity = 1.0;
        }

        return Positioned(
          top: clampedTop.toDouble(),
          left: clampedLeft.toDouble(),
          child: Opacity(
            opacity: opacity,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -36,
                  left: -37,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size(150, 150),
                      painter: _PaiChanStickerParticlesPainter(
                        sticker: sticker,
                        progress: t,
                      ),
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: rotation,
                  child: Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: stickerBadge,
    );
  }
}

class _PaiChanStickerParticlesPainter extends CustomPainter {
  final PaiChanSticker sticker;
  final double progress;

  const _PaiChanStickerParticlesPainter({
    required this.sticker,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final fade = progress > 0.75 ? (1.0 - (progress - 0.75) / 0.25).clamp(0.0, 1.0) : 1.0;

    switch (sticker) {
      case PaiChanSticker.excited:
        // Gold starburst particles radiating outward
        final paint = Paint()..style = PaintingStyle.fill;
        for (var i = 0; i < 8; i++) {
          final angle = (i / 8.0) * 2 * pi + 0.2;
          final dist = 36.0 + progress * 38.0 + (i % 2) * 8.0;
          final pos = center + Offset(cos(angle) * dist, sin(angle) * dist);
          final r = (4.5 - progress * 2.5).clamp(1.2, 4.5);
          paint.color = (i.isEven ? Colors.amberAccent : Colors.white)
              .withValues(alpha: (0.9 * fade).clamp(0.0, 1.0));
          canvas.drawCircle(pos, r, paint);
        }
        break;

      case PaiChanSticker.happy:
        // Rising "ха-ха" and "w" text particles
        const labels = ['ха-ха', 'w', 'ха!'];
        for (var i = 0; i < labels.length; i++) {
          final p = ((progress * 1.4 - i * 0.22)).clamp(0.0, 1.0);
          if (p <= 0.0 || p >= 1.0) continue;
          final xOff = (i - 1) * 32.0 + sin(p * pi) * 8.0;
          final yOff = -28.0 - p * 42.0;
          _drawText(
            canvas,
            labels[i],
            center + Offset(xOff, yOff),
            Colors.cyanAccent.withValues(alpha: ((1.0 - p) * fade).clamp(0.0, 1.0)),
            12.0,
          );
        }
        break;

      case PaiChanSticker.surprised:
        // Pulsing "!?" / "!?" badge near top-right
        if (progress > 0.08 && progress < 0.78) {
          final pulse = 1.0 + sin(progress * 18.0) * 0.18;
          canvas.save();
          canvas.translate(center.dx + 34, center.dy - 36);
          canvas.scale(pulse, pulse);
          _drawText(
            canvas,
            '!?!',
            Offset.zero,
            Colors.purpleAccent.withValues(alpha: fade),
            16.0,
          );
          canvas.restore();
        }
        break;

      case PaiChanSticker.sad:
        // Falling blue teardrops splashing off left & right sides
        final dropPaint = Paint()
          ..color = Colors.lightBlueAccent.withValues(alpha: (0.85 * fade).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;
        for (var i = 0; i < 4; i++) {
          final cycle = ((progress * 2.2 + i * 0.25) % 1.0);
          final side = i.isEven ? -1.0 : 1.0;
          final x = center.dx + side * (32.0 + cycle * 16.0);
          final y = center.dy - 6.0 + cycle * 44.0;
          canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 5.5, height: 8.5), dropPaint);
        }
        break;

      case PaiChanSticker.love:
        // Floating mini-hearts
        for (var i = 0; i < 4; i++) {
          final p = ((progress * 1.5 - i * 0.18) % 1.0);
          final xOff = (i.isEven ? -1 : 1) * (24.0 + i * 7.0) + sin(p * 2 * pi) * 6.0;
          final yOff = -22.0 - p * 46.0;
          _drawText(
            canvas,
            '♥',
            center + Offset(xOff, yOff),
            Colors.pinkAccent.withValues(alpha: ((1.0 - p) * fade).clamp(0.0, 1.0)),
            14.0,
          );
        }
        break;

      case PaiChanSticker.sleepy:
        // Rising fading Zzz...
        const zzz = ['Z', 'z', 'z'];
        for (var i = 0; i < zzz.length; i++) {
          final p = ((progress * 1.3 - i * 0.22) % 1.0);
          final xOff = 24.0 + i * 10.0 + p * 12.0;
          final yOff = -24.0 - p * 40.0;
          _drawText(
            canvas,
            zzz[i],
            center + Offset(xOff, yOff),
            Colors.indigoAccent.withValues(alpha: ((1.0 - p) * fade).clamp(0.0, 1.0)),
            15.0 - i * 2.0,
          );
        }
        break;
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PaiChanStickerParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.sticker != sticker;
}
