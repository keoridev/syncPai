import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class DoubleTapSeekOverlay extends StatefulWidget {
  final VoidCallback onTap;
  final ValueChanged<int> onSeekRelative;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  const DoubleTapSeekOverlay({
    super.key,
    required this.onTap,
    required this.onSeekRelative,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  State<DoubleTapSeekOverlay> createState() => _DoubleTapSeekOverlayState();
}

class _DoubleTapSeekOverlayState extends State<DoubleTapSeekOverlay> {
  int? _seekIndicatorSeconds;
  bool _isLeft = false;
  Timer? _dismissTimer;

  void _triggerSeek(int seconds, bool left) {
    widget.onSeekRelative(seconds);
    _dismissTimer?.cancel();
    setState(() {
      _seekIndicatorSeconds = (_seekIndicatorSeconds ?? 0) + seconds;
      _isLeft = left;
    });
    _dismissTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _seekIndicatorSeconds = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Детекторы касаний по левой и правой половинам экрана с поддержкой 2X при удержании
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onTap,
                onDoubleTap: () => _triggerSeek(-10, true),
                onLongPressStart: (_) => widget.onLongPressStart?.call(),
                onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                onLongPressCancel: () => widget.onLongPressEnd?.call(),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onTap,
                onDoubleTap: () => _triggerSeek(10, false),
                onLongPressStart: (_) => widget.onLongPressStart?.call(),
                onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                onLongPressCancel: () => widget.onLongPressEnd?.call(),
              ),
            ),
          ],
        ),

        // Анимированный индикатор перемотки
        if (_seekIndicatorSeconds != null)
          Positioned(
            left: _isLeft ? 40 : null,
            right: !_isLeft ? 40 : null,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.strokeMedium),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                      color: AppColors.textPrimary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_seekIndicatorSeconds! > 0 ? '+' : ''}$_seekIndicatorSeconds сек',
                      style: AppTypography.labelLarge.copyWith(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

