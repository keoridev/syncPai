import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/di/injection.dart';
import '../../domain/repositories/sync_room_repository.dart';

class ReactionPreset {
  final String emoji;
  final String label;

  const ReactionPreset(this.emoji, this.label);
}

const List<ReactionPreset> kWatchTogetherReactions = [
  ReactionPreset('🔥', 'Огонь'),
  ReactionPreset('😭', 'Стекло'),
  ReactionPreset('😱', 'Шок'),
  ReactionPreset('😂', 'Ор'),
  ReactionPreset('❤️', 'Имба'),
  ReactionPreset('👏', 'Абсолют'),
];

/// Парящий слой эфемерных реакций поверх видео-полотна Watch-Together (60/120 FPS, zero-DB).
class ReactionOverlayLayer extends StatefulWidget {
  final String roomCode;
  final bool enabled;
  final Stream<SyncReactionEvent>? reactionsStream;

  const ReactionOverlayLayer({
    super.key,
    required this.roomCode,
    this.enabled = true,
    this.reactionsStream,
  });

  @override
  State<ReactionOverlayLayer> createState() => _ReactionOverlayLayerState();
}

class _ActiveFloatingReaction {
  final SyncReactionEvent event;
  final double rightOffset;

  _ActiveFloatingReaction({
    required this.event,
    required this.rightOffset,
  });
}

class _ReactionOverlayLayerState extends State<ReactionOverlayLayer> {
  final List<_ActiveFloatingReaction> _active = [];
  final math.Random _rng = math.Random();
  StreamSubscription<SyncReactionEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant ReactionOverlayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomCode != widget.roomCode ||
        oldWidget.reactionsStream != widget.reactionsStream) {
      _sub?.cancel();
      _subscribe();
    }
    if (!widget.enabled && _active.isNotEmpty) {
      setState(() => _active.clear());
    }
  }

  void _subscribe() {
    final stream = widget.reactionsStream ??
        (getIt.isRegistered<SyncRoomRepository>()
            ? getIt<SyncRoomRepository>().subscribeToReactions(widget.roomCode)
            : null);
    if (stream == null) return;
    _sub = stream.listen((event) {
      if (!mounted || !widget.enabled) return;
      setState(() {
        if (_active.length >= 16) {
          _active.removeAt(0);
        }
        _active.add(
          _ActiveFloatingReaction(
            event: event,
            rightOffset: 16.0 + _rng.nextDouble() * 34.0,
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _active.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: _active
              .map(
                (item) => _FloatingReactionPill(
                  key: ValueKey(item.event.id),
                  item: item,
                  onFinished: () {
                    if (mounted) {
                      setState(() {
                        _active.removeWhere((e) => e.event.id == item.event.id);
                      });
                    }
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _FloatingReactionPill extends StatefulWidget {
  final _ActiveFloatingReaction item;
  final VoidCallback onFinished;

  const _FloatingReactionPill({
    super.key,
    required this.item,
    required this.onFinished,
  });

  @override
  State<_FloatingReactionPill> createState() => _FloatingReactionPillState();
}

class _FloatingReactionPillState extends State<_FloatingReactionPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, -4.6),
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 14),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 58),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 28),
    ]).animate(_controller);

    _controller.forward().whenComplete(widget.onFinished);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ev = widget.item.event;
    return Positioned(
      right: widget.item.rightOffset,
      bottom: 84,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF12161F).withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ev.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  ev.label.isNotEmpty
                      ? '${ev.sender}: ${ev.label}'
                      : ev.sender,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Компактная панель реакций + переключатель в HUD плеера Watch-Together (лимит 1 / 500мс).
class ReactionDockBar extends StatefulWidget {
  final String roomCode;
  final String senderName;
  final bool reactionsEnabled;
  final VoidCallback onToggleEnabled;
  final Future<void> Function(ReactionPreset preset)? onSendOverride;

  const ReactionDockBar({
    super.key,
    required this.roomCode,
    required this.senderName,
    required this.reactionsEnabled,
    required this.onToggleEnabled,
    this.onSendOverride,
  });

  @override
  State<ReactionDockBar> createState() => _ReactionDockBarState();
}

class _ReactionDockBarState extends State<ReactionDockBar> {
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _send(ReactionPreset preset) async {
    final now = DateTime.now();
    if (now.difference(_lastSentAt) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastSentAt = now;
    HapticFeedback.lightImpact();

    if (widget.onSendOverride != null) {
      await widget.onSendOverride!(preset);
      return;
    }
    if (getIt.isRegistered<SyncRoomRepository>()) {
      await getIt<SyncRoomRepository>().sendFloatingReaction(
        roomCode: widget.roomCode,
        sender: widget.senderName,
        emoji: preset.emoji,
        label: preset.label,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.reactionsEnabled)
              ...kWatchTogetherReactions.map(
                (r) => Tooltip(
                  message: r.label,
                  child: InkWell(
                    onTap: () => _send(r),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.emoji, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 4),
                          Text(
                            r.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            InkWell(
              key: const ValueKey('toggle_watch_reactions_btn'),
              onTap: widget.onToggleEnabled,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.reactionsEnabled
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.reactionsEnabled
                      ? 'Реакции: Вкл'
                      : 'Реакции: Выкл',
                  style: TextStyle(
                    color: widget.reactionsEnabled
                        ? Colors.white
                        : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

