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
                                                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.65)
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

                          // 1. Фоновая дорожка (с динамическим увеличением толщины при зажатии)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: _isDragging ? 7.0 : 4.0,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.strokeMedium,
                              borderRadius: BorderRadius.circular(_isDragging ? 3.5 : 2.0),
                            ),
                          ),

                          // 2. Буфер воспроизведения
                          FractionallySizedBox(
                            widthFactor: bufferRatio,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: _isDragging ? 7.0 : 4.0,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(_isDragging ? 3.5 : 2.0),
                              ),
                            ),
                          ),

                          // 3. Цветные отрезки таймкодов (Опенинг - золото/янтарь, Эндинг - циан/неон)
                          if (opStartRatio != null && opStopRatio != null && opStopRatio > opStartRatio)
                            Positioned(
                              left: barWidth * opStartRatio,
                              width: barWidth * (opStopRatio - opStartRatio),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: _isDragging ? 7.0 : 4.0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB300).withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(_isDragging ? 3.5 : 2.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFB300).withValues(alpha: 0.5),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          if (edStartRatio != null && edStopRatio != null && edStopRatio > edStartRatio)
                            Positioned(
                              left: barWidth * edStartRatio,
                              width: barWidth * (edStopRatio - edStartRatio),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: _isDragging ? 7.0 : 4.0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(_isDragging ? 3.5 : 2.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 4. Линия текущего прогресса воспроизведения (сочная iOS / Netflix анимация)
                          FractionallySizedBox(
                            widthFactor: progressRatio,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: _isDragging ? 7.0 : 4.0,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(_isDragging ? 3.5 : 2.0),
                                boxShadow: [
                                  if (_isDragging)
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // 5. Светящиеся разделительные точки-маркеры ключевых таймкодов
                          if (opStartRatio != null)
                            Positioned(
                              left: (barWidth * opStartRatio - 2.5).clamp(0.0, barWidth - 5),
                              child: Container(
                                width: 5.0,
                                height: 8.0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD54F),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0xFFFFB300), blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          if (opStopRatio != null)
                            Positioned(
                              left: (barWidth * opStopRatio - 2.5).clamp(0.0, barWidth - 5),
                              child: Container(
                                width: 5.0,
                                height: 8.0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD54F),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0xFFFFB300), blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          if (edStartRatio != null)
                            Positioned(
                              left: (barWidth * edStartRatio - 2.5).clamp(0.0, barWidth - 5),
                              child: Container(
                                width: 5.0,
                                height: 8.0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF80D8FF),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0xFF00E5FF), blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          if (edStopRatio != null)
                            Positioned(
                              left: (barWidth * edStopRatio - 2.5).clamp(0.0, barWidth - 5),
                              child: Container(
                                width: 5.0,
                                height: 8.0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF80D8FF),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0xFF00E5FF), blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),

                          // 6. Ползунок (Thumb) с плавной трансформацией размера
                          Positioned(
                            left: (barWidth * progressRatio - (_isDragging ? 10 : 6))
                                .clamp(0.0, barWidth - (_isDragging ? 20 : 12)),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: _isDragging ? 20.0 : 12.0,
                              height: _isDragging ? 20.0 : 12.0,
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: _isDragging ? 2.5 : 0.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: _isDragging ? 0.85 : 0.4),
                                    blurRadius: _isDragging ? 14 : 6,
                                    spreadRadius: _isDragging ? 3 : 0,
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
