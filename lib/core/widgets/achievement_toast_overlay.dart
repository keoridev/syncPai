import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/profile/domain/services/achievement_service.dart';

/// Ненавязчивый Steam-тост в правом нижнем углу при разблокировке достижения.
class AchievementToastOverlay extends StatefulWidget {
  const AchievementToastOverlay({super.key});

  @override
  State<AchievementToastOverlay> createState() =>
      _AchievementToastOverlayState();
}

class _AchievementToastOverlayState extends State<AchievementToastOverlay> {
  StreamSubscription<AchievementBadge>? _sub;
  AchievementBadge? _current;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _sub = AchievementService.instance.onUnlocked.listen((badge) {
      if (!mounted) return;
      _hideTimer?.cancel();
      setState(() => _current = badge);
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _current = null);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = _current;
    if (badge == null) return const SizedBox.shrink();

    return Positioned(
      right: 20,
      bottom: 24,
      child: IgnorePointer(
        ignoring: true,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF12161F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: badge.color.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badge.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(badge.icon, color: badge.color, size: 22),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🏆 Достижение разблокировано: ${badge.title}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        badge.hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
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

