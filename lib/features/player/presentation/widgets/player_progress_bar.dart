import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/domain/entities/reaction_heatmap.dart';

/// Интерактивный таймлайн плеера в стиле YouTube / SoundCloud:
/// - Поддерживает тепловую карту реакций зрителей
/// - Светящиеся маркеры и точки таймкодов (Опенинг, Эндинг, Главы) на прогресс-баре
/// - При перетаскивании ползунка отображает парящее окно с точным таймкодом, названием фрагмента и дельтой времени (Scrubber Preview)
class PlayerProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final ValueChanged<Duration> onSeek;
  final bool isLocked;
  final VoidCallback? onLockedTap;
  final ReactionHeatmap? heatmap;
  final TimecodeRange? opening;
  final TimecodeRange? ending;
  final bool isBuffering;
  final bool showTimestamps;

  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.onSeek,
    this.isLocked = false,
    this.onLockedTap,
    this.heatmap,
    this.opening,
    this.ending,
    this.isBuffering = false,
    this.showTimestamps = true,
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

  bool _isInsideOpening(Duration pos) {
    final op = widget.opening;
    if (op == null) return false;
    final sec = pos.inSeconds;
    return sec >= op.start && sec <= op.stop;
  }

  bool _isInsideEnding(Duration pos) {
    final ed = widget.ending;
    if (ed == null) return false;
    final sec = pos.inSeconds;
    return sec >= ed.start && sec <= ed.stop;
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final posMs = widget.position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);
    final bufMs = widget.buffer.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    final actualRatio = maxMs > 0 ? (posMs / maxMs) : 0.0;
    final progressRatio = _isDragging ? _dragRatio : actualRatio;
    final bufferRatio = maxMs > 0 ? (bufMs / maxMs) : 0.0;
    final totalSec = widget.duration.inSeconds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;

            // Расчет позиций опенинга и эндинга
            double? opStartRatio;
            double? opStopRatio;
            if (totalSec > 0 && widget.opening != null) {
              opStartRatio = (widget.opening!.start / totalSec).clamp(0.0, 1.0);
              opStopRatio = (widget.opening!.stop / totalSec).clamp(0.0, 1.0);
            }

            double? edStartRatio;
            double? edStopRatio;
            if (totalSec > 0 && widget.ending != null) {
              edStartRatio = (widget.ending!.start / totalSec).clamp(0.0, 1.0);
              edStopRatio = (widget.ending!.stop / totalSec).clamp(0.0, 1.0);
            }

            final currentDragTime = Duration(milliseconds: (_dragRatio * maxMs).round());
            final inOpening = _isInsideOpening(currentDragTime);
            final inEnding = _isInsideEnding(currentDragTime);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: widget.isLocked
                      ? (_) => widget.onLockedTap?.call()
                      : (widget.isBuffering
                          ? null
                          : (details) {
                              setState(() {
                                _isDragging = true;
                                _dragRatio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                              });
                            }),
                  onHorizontalDragUpdate: widget.isLocked
                      ? (_) => widget.onLockedTap?.call()
                      : (widget.isBuffering
                          ? null
                          : (details) {
                              setState(() {
                                _dragRatio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                              });
                            }),
                  onHorizontalDragEnd: (widget.isBuffering || widget.isLocked)
                      ? null
                      : (_) {
                          if (_isDragging) {
                            widget.onSeek(Duration(milliseconds: (_dragRatio * maxMs).round()));
                          }
                          setState(() => _isDragging = false);
                        },
                  onHorizontalDragCancel: () {
                    setState(() => _isDragging = false);
                  },
                  onTapDown: widget.isLocked
                      ? (_) => widget.onLockedTap?.call()
                      : (widget.isBuffering
                          ? null
                          : (details) {
                              final ratio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                              widget.onSeek(Duration(milliseconds: (ratio * maxMs).round()));
                            }),
                  child: SizedBox(
                    height: 34,
                    child: Center(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // 1. Фоновая дорожка (чистая сплошная линия без точек)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: _isDragging ? 6.0 : 3.5,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(_isDragging ? 3.0 : 1.75),
                            ),
                          ),

                          // 2. Буфер воспроизведения
                          FractionallySizedBox(
                            widthFactor: bufferRatio,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: _isDragging ? 6.0 : 3.5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.32),
                                borderRadius: BorderRadius.circular(_isDragging ? 3.0 : 1.75),
                              ),
                            ),
                          ),

                          // 3. Цветные отрезки таймкодов (Опенинг - янтарный, Эндинг - фиолетовый/акцентный)
                          if (opStartRatio != null && opStopRatio != null && opStopRatio > opStartRatio)
                            Positioned(
                              left: barWidth * opStartRatio,
                              width: barWidth * (opStopRatio - opStartRatio),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: _isDragging ? 6.0 : 3.5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB300).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(_isDragging ? 3.0 : 1.75),
                                ),
                              ),
                            ),

                          if (edStartRatio != null && edStopRatio != null && edStopRatio > edStartRatio)
                            Positioned(
                              left: barWidth * edStartRatio,
                              width: barWidth * (edStopRatio - edStartRatio),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: _isDragging ? 6.0 : 3.5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFBA68C8).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(_isDragging ? 3.0 : 1.75),
                                ),
                              ),
                            ),

                          // 4. Линия текущего прогресса воспроизведения (чистая сплошная линия)
                          FractionallySizedBox(
                            widthFactor: progressRatio,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: _isDragging ? 6.0 : 3.5,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(_isDragging ? 3.0 : 1.75),
                              ),
                            ),
                          ),

                          // 5. Ползунок (Thumb) в чистом стиле
                          Positioned(
                            left: (barWidth * progressRatio - (_isDragging ? 8 : 5))
                                .clamp(0.0, barWidth - (_isDragging ? 16 : 10)),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: _isDragging ? 16.0 : 10.0,
                              height: _isDragging ? 16.0 : 10.0,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
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

                // 7. Всплывающее YouTube-окно предпросмотра при перемотке (Scrubber Preview) с чипом таймкода
                if (_isDragging) ...[
                  Positioned(
                    bottom: 38,
                    left: (barWidth * _dragRatio - 70).clamp(0.0, barWidth - 140),
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (inOpening
                                  ? const Color(0xFFFFB300)
                                  : inEnding
                                      ? const Color(0xFF00E5FF)
                                      : Theme.of(context).colorScheme.primary)
                              .withValues(alpha: 0.7),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.65),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Метка Опенинга / Эндинга при перемотке по точкам
                          if (inOpening || inEnding)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (inOpening ? const Color(0xFFFFB300) : const Color(0xFF00E5FF))
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    inOpening ? Icons.music_note_rounded : Icons.queue_music_rounded,
                                    size: 11,
                                    color: inOpening ? const Color(0xFFFFB300) : const Color(0xFF00E5FF),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    inOpening ? 'Опенинг' : 'Эндинг',
                                    style: TextStyle(
                                      color: inOpening ? const Color(0xFFFFB300) : const Color(0xFF00E5FF),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),

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
                                _formatDuration(currentDragTime),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
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
                                fontSize: 10.5,
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
        if (widget.showTimestamps)
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
