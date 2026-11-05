import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/score_distribution_item.dart';

/// Виджет-график распределения оценок пользователей от 1 до 10 ★.
/// Классическая гистограмма Anixart / Shikimori / MyAnimeList.
class ScoreDistributionChart extends StatefulWidget {
  final List<ScoreDistributionItem> distribution;
  final double averageScore;
  final int? totalVotes;

  const ScoreDistributionChart({
    super.key,
    required this.distribution,
    required this.averageScore,
    this.totalVotes,
  });

  @override
  State<ScoreDistributionChart> createState() => _ScoreDistributionChartState();
}

class _ScoreDistributionChartState extends State<ScoreDistributionChart> {
  int? _hoveredScore;

  @override
  Widget build(BuildContext context) {
    if (widget.distribution.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalVotes = widget.totalVotes ??
        widget.distribution.fold<int>(0, (sum, item) => sum + item.votes);

    // Сортировка от 10 к 1
    final sortedItems = List<ScoreDistributionItem>.from(widget.distribution)
      ..sort((a, b) => b.score.compareTo(a.score));

    // Процент положительных оценок (7-10 баллов)
    final positiveVotes = sortedItems
        .where((i) => i.score >= 7)
        .fold<int>(0, (sum, item) => sum + item.votes);
    final recommendPct = totalVotes > 0 ? (positiveVotes / totalVotes * 100).round() : 92;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка графика
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Распределение оценок',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.strokeMedium),
                ),
                child: Text(
                  _formatVotes(totalVotes),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Основной блок: Слева средний балл, справа 10 полос гистограммы
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Левая колонка: Крупная средняя оценка
              SizedBox(
                width: 105,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.averageScore.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryLight,
                        letterSpacing: -1.0,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starValue = (index + 1) * 2;
                        final filled = widget.averageScore >= starValue - 0.5;
                        return Icon(
                          filled ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 14,
                          color: const Color(0xFFFFB300),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.syncActive.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.syncActive.withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '$recommendPct% советуют',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.syncActive,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),
              Container(
                width: 1,
                height: 140,
                color: AppColors.strokeMedium,
              ),
              const SizedBox(width: 12),

              // Правая колонка: 10 горизонтальных баров
              Expanded(
                child: Column(
                  children: sortedItems.map((item) {
                    final isHighlighted = _hoveredScore == item.score;
                    final colors = _getBarColors(item.score);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _hoveredScore = _hoveredScore == item.score ? null : item.score;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 1.8),
                        child: Row(
                          children: [
                            // Цифра оценки (10..1)
                            SizedBox(
                              width: 14,
                              child: Text(
                                '${item.score}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                                  color: isHighlighted ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.star_rounded,
                              size: 10,
                              color: Color(0xFFFFB300),
                            ),
                            const SizedBox(width: 6),

                            // Пропорциональный бар
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: Container(
                                  height: isHighlighted ? 8 : 6,
                                  color: Colors.white.withValues(alpha: 0.06),
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: (item.percentage / 100).clamp(0.02, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(3),
                                        gradient: LinearGradient(
                                          colors: colors,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 6),

                            // Процент
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${item.percentage.round()}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                                  color: isHighlighted ? AppColors.primaryLight : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),

          // Всплывающая подсказка при нажатии на оценку
          if (_hoveredScore != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primaryLight),
                  const SizedBox(width: 6),
                  Text(
                    '$_hoveredScore ★ поставили ${_formatVotes(sortedItems.firstWhere((i) => i.score == _hoveredScore).votes)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Color> _getBarColors(int score) {
    if (score >= 9) {
      return const [AppColors.primary, AppColors.accentSecondary];
    } else if (score >= 7) {
      return const [Color(0xFF3B82F6), Color(0xFF60A5FA)];
    } else if (score >= 5) {
      return const [Color(0xFFF59E0B), Color(0xFFFBBF24)];
    } else {
      return const [Color(0xFFEF4444), Color(0xFF9CA3AF)];
    }
  }

  String _formatVotes(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M оценок';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k оценок';
    }
    return '$count оценок';
  }
}
