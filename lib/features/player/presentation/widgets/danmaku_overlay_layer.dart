import 'dart:math';
import 'package:flutter/material.dart';

/// Элемент плавающего комментария (Danmaku / 弹幕)
class DanmakuItem {
  final String id;
  final String text;
  final String sender;
  final Color color;
  final int lane;
  final double speedFactor;

  const DanmakuItem({
    required this.id,
    required this.text,
    required this.sender,
    this.color = Colors.white,
    required this.lane,
    this.speedFactor = 1.0,
  });
}

/// Слой плавающих комментариев в стиле Bilibili / Nico Nico (Danmaku)
/// Комментарии плавно проплывают справа налево в верхней трети экрана,
/// абсолютно не перекрывая субтитры внизу.
class DanmakuOverlayLayer extends StatefulWidget {
  final List<DanmakuItem> items;
  final bool isEnabled;

  const DanmakuOverlayLayer({
    super.key,
    required this.items,
    this.isEnabled = true,
  });

  @override
  State<DanmakuOverlayLayer> createState() => _DanmakuOverlayLayerState();
}

class _DanmakuOverlayLayerState extends State<DanmakuOverlayLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final List<_ActiveDanmakuEntry> _activeEntries = [];
  final Set<String> _seenItemIds = {};
  final Random _random = Random();

  static const int _maxLanes = 4;
  static const double _laneHeight = 32.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateDanmaku);
    _animController.repeat();
    _syncNewItems();
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNewItems();
  }

  void _syncNewItems() {
    if (!widget.isEnabled) {
      _activeEntries.clear();
      return;
    }

    final now = DateTime.now();
    for (final item in widget.items) {
      if (!_seenItemIds.contains(item.id)) {
        _seenItemIds.add(item.id);
        final lane = item.lane % _maxLanes;
        _activeEntries.add(_ActiveDanmakuEntry(
          item: item,
          lane: lane,
          startTime: now,
          duration: Duration(milliseconds: (6500 / item.speedFactor).round() + _random.nextInt(600)),
        ));
      }
    }
  }

  void _updateDanmaku() {
    if (!mounted || !widget.isEnabled) return;
    final now = DateTime.now();
    setState(() {
      _activeEntries.removeWhere((entry) {
        final elapsed = now.difference(entry.startTime).inMilliseconds;
        return elapsed > entry.duration.inMilliseconds;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled || _activeEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final now = DateTime.now();

    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: _activeEntries.map((entry) {
            final elapsed = now.difference(entry.startTime).inMilliseconds;
            final progress = (elapsed / entry.duration.inMilliseconds).clamp(0.0, 1.0);

            // Движение справа налево: от screenWidth до -400
            final startX = screenWidth + 20.0;
            final endX = -450.0;
            final currentX = startX + (endX - startX) * progress;
            final topOffset = 24.0 + (entry.lane * _laneHeight);

            return Positioned(
              left: currentX,
              top: topOffset,
              child: _DanmakuTextBubble(entry: entry),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ActiveDanmakuEntry {
  final DanmakuItem item;
  final int lane;
  final DateTime startTime;
  final Duration duration;

  _ActiveDanmakuEntry({
    required this.item,
    required this.lane,
    required this.startTime,
    required this.duration,
  });
}

class _DanmakuTextBubble extends StatelessWidget {
  final _ActiveDanmakuEntry entry;

  const _DanmakuTextBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.item.color.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.item.sender.isNotEmpty) ...[
            Text(
              '${entry.item.sender}: ',
              style: TextStyle(
                color: entry.item.color.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                ],
              ),
            ),
          ],
          Text(
            entry.item.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
