import 'dart:math';
import 'package:flutter/material.dart';
import '../../../sync_room/domain/entities/sync_protocol.dart';

/// Слой плавающих летящих реакций (Floating Reactions)
/// Анимирует эмодзи снизу вверх по правой кромке экрана с плавным угасанием.
class FloatingReactionsLayer extends StatelessWidget {
  final List<FloatingReaction> reactions;

  const FloatingReactionsLayer({
    super.key,
    required this.reactions,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: reactions.map((r) => _FloatingReactionItem(reaction: r)).toList(),
      ),
    );
  }
}

class _FloatingReactionItem extends StatefulWidget {
  final FloatingReaction reaction;

  const _FloatingReactionItem({required this.reaction});

  @override
  State<_FloatingReactionItem> createState() => _FloatingReactionItemState();
}

class _FloatingReactionItemState extends State<_FloatingReactionItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late double _randomWobblePhase;

  @override
  void initState() {
    super.initState();
    _randomWobblePhase = Random().nextDouble() * 2 * pi;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;

        // Y: от 85% высоты экрана до 15%
        final top = size.height * (0.85 - progress * 0.70);

        // X: базовая позиция справа + гармоническое покачивание (волна)
        final baseX = size.width * widget.reaction.startXOffset;
        final wobble = sin(progress * 3 * pi + _randomWobblePhase) * 22;
        final left = (baseX + wobble).clamp(size.width * 0.55, size.width - 50);

        // Прозрачность: первые 60% времени 1.0, затем плавное угасание в 0.0
        final opacity = progress > 0.60
            ? (1.0 - (progress - 0.60) / 0.40).clamp(0.0, 1.0)
            : (progress * 3).clamp(0.0, 1.0);

        // Масштаб: всплытие с эффектом упругого выстрела (0.6 -> 1.3 -> 1.0)
        final scale = progress < 0.2
            ? 0.6 + (progress / 0.2) * 0.7
            : (1.3 - (progress - 0.2) * 0.35).clamp(0.8, 1.3);

        return Positioned(
          top: top,
          left: left,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Text(
                widget.reaction.emoji,
                style: const TextStyle(
                  fontSize: 34,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

