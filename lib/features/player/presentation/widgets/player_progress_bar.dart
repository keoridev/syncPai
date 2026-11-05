import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'package:sync_pai/features/player/domain/entities/reaction_heatmap.dart';

/// Интерактивный таймлайн плеера в стиле YouTube / SoundCloud:
/// - Поддерживает тепловую карту реакций зрителей
/// - При перетаскивании ползунка отображает парящее окно с точным таймкодом и дельтой времени (Scrubber Preview)
class PlayerProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final ValueChanged<Duration> onSeek;
  final bool isLocked;
  final VoidCallback? onLockedTap;
  final ReactionHeatmap? heatmap;

  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.onSeek,
    this.isLocked = false,
    this.onLockedTap,
    this.heatmap,
  });

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  bool _isDragging = false;
  double _dragRatio = 0.0;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final posMs = widget.position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);
    final bufMs = widget.buffer.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    final actualRatio = maxMs > 0 ? (posMs / maxMs) : 0.0;
    final progressRatio = _isDragging ? _dragRatio : actualRatio;
    final bufferRatio = maxMs > 0 ? (bufMs / maxMs) : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: widget.isLocked
                      ? (_) => widget.onLockedTap?.call()
                      : (details) {
                          setState(() {
                            _isDragging = true;
                            _dragRatio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                          });
                          widget.onSeek(Duration(milliseconds: (_dragRatio * maxMs).round()));
                        },
                  onHorizontalDragUpdate: widget.isLocked
                      ? (_) => widget.onLockedTap?.call()
                      : (details) {
                          setState(() {
                            _dragRatio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                          });
                          widget.onSeek(Duration(milliseconds: (_dragRatio * maxMs).round()));
                        },
                  onHorizontalDragEnd: (_) {
                    setState(() => _isDragging = false);
                  },
                  onHorizontalDragCancel: () {
                    setState(() => _isDragging = false);
                  },
                  onTapDown: widget.isLocked
                      ? (_) => widget.onLockedTap?.call()
                      : (details) {
                          final ratio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                          widget.onSeek(Duration(milliseconds: (ratio * maxMs).round()));
                        },
                  child: SizedBox(
                    height: 34,
                    child: Center(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // SoundCloud-style Тепловая карта эмоций на таймлайне
                          if (widget.heatmap != null && widget.heatmap!.normalizedHeights.isNotEmpty)
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.center,
                                child: SizedBox(
                                  height: 22,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: widget.heatmap!.normalizedHeights.asMap().entries.map((entry) {
                                      final idx = entry.key;
                                      final heightFactor = entry.value;
                                      final barProgress = idx / widget.heatmap!.normalizedHeights.length;
                                      final isPlayed = barProgress <= progressRatio;
                                      final isPeak = heightFactor > 0.65;

                                      return Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 0.6),
                                          child: Container(
                                            height: (22.0 * heightFactor),
                                            decoration: BoxDecoration(
                                              color: isPeak
                                                  ? (isPlayed
                                                      ? const Color(0xFFFF5E3A)
                                                      : const Color(0xFFFF5E3A).withValues(alpha: 0.38))
                                                  : (isPlayed
                                                      ? AppColors.primary.withValues(alpha: 0.65)
                                                      : Colors.white.withValues(alpha: 0.12)),
                                              borderRadius: BorderRadius.circular(1.5),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),

                          // Фоновая дорожка
                          Container(
                            height: 4.0,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.strokeMedium,
                              borderRadius: BorderRadius.circular(2.0),
                            ),
                          ),
                          // Буфер
                          FractionallySizedBox(
                            widthFactor: bufferRatio,
                            child: Container(
                              height: 4.0,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2.0),
                              ),
                            ),
                          ),
                          // Воспроизведение
                          FractionallySizedBox(
                            widthFactor: progressRatio,
                            child: Container(
                              height: _isDragging ? 6.0 : 4.0,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(3.0),
                              ),
                            ),
                          ),
                          // Ползунок (Thumb)
                          Positioned(
                            left: (barWidth * progressRatio - (_isDragging ? 8 : 6))
                                .clamp(0.0, barWidth - (_isDragging ? 16 : 12)),
                            child: Container(
                              width: _isDragging ? 16.0 : 12.0,
                              height: _isDragging ? 16.0 : 12.0,
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.6),
                                    blurRadius: _isDragging ? 10 : 6,
                                    spreadRadius: _isDragging ? 2 : 0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Всплывающее YouTube-окно предпросмотра при перемотке (Scrubber Preview)
                if (_isDragging) ...[
                  Positioned(
                    bottom: 38,
                    left: (barWidth * _dragRatio - 50).clamp(0.0, barWidth - 100),
                    child: Container(
                      width: 100,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 14,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(Duration(milliseconds: (_dragRatio * maxMs).round())),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          // Дельта времени (например: +02:15 или -01:30)
                          Builder(builder: (_) {
                            final seekMs = (_dragRatio * maxMs).round();
                            final currentMs = widget.position.inMilliseconds;
                            final diffMs = seekMs - currentMs;
                            if (diffMs == 0) return const SizedBox.shrink();
                            final isForward = diffMs > 0;
                            final absDiff = Duration(milliseconds: diffMs.abs());
                            return Text(
                              '${isForward ? '+' : '-'}${_formatDuration(absDiff)}',
                              style: TextStyle(
                                color: isForward ? const Color(0xFF00E676) : const Color(0xFFFFB74D),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDuration(widget.position),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.isLocked) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Хост управляет',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
            Text(
              _formatDuration(widget.duration),
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
