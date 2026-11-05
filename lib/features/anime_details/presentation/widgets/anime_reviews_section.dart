import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../domain/entities/anime_review.dart';
import '../../domain/entities/score_distribution_item.dart';
import 'score_distribution_chart.dart';

class AnimeReviewsSection extends StatelessWidget {
  final List<AnimeReview> reviews;
  final Map<String, double>? portalScores;
  final List<ScoreDistributionItem> scoreDistribution;
  final bool isLoading;

  const AnimeReviewsSection({
    super.key,
    required this.reviews,
    this.portalScores,
    this.scoreDistribution = const [],
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final shikiScore = (portalScores?['Shikimori'] ?? 8.9).toStringAsFixed(1);
    final malScore = (portalScores?['MyAnimeList'] ?? 8.8).toStringAsFixed(1);
    final anilibriaScore = (portalScores?['AniLibria'] ?? 9.4).toStringAsFixed(1);
    final worldArtScore = (portalScores?['World Art'] ?? 8.7).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Плашки рейтингов со сторонних сервисов (Shikimori, MAL, AniLibria)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.strokeMedium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ОЦЕНКИ НА АНИМЕ-ПОРТАЛАХ',
                    style: AppTypography.caption.copyWith(
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildScoreChip('Shikimori', shikiScore, const Color(0xFF4A90E2)),
                  _buildScoreChip('MyAnimeList', malScore, const Color(0xFF2E51A2)),
                  _buildScoreChip('AniLibria', anilibriaScore, AppColors.primary),
                  _buildScoreChip('World Art', worldArtScore, const Color(0xFFE5A00D)),
                ],
              ),
            ],
          ),
        ),

        // График распределения оценок пользователей (1-10 ★)
        if (scoreDistribution.isNotEmpty) ...[
          const SizedBox(height: 16),
          ScoreDistributionChart(
            distribution: scoreDistribution,
            averageScore: portalScores?['Shikimori'] ?? 8.8,
          ),
        ],

        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Отзывы сообщества',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${reviews.length} рецензии',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Список отзывов
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reviews.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final rev = reviews[index];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.strokeMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          AppAvatar(
                            avatarUrl: rev.avatar,
                            username: rev.author,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rev.author,
                                style: AppTypography.labelLarge.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    rev.source,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.primaryLight,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const Text('  •  ', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                  Text(
                                    rev.date,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textMuted,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 3),
                            Text(
                              '${rev.score}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    rev.text,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.favorite_rounded, size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${rev.likes}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildScoreChip(String portal, String score, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: color, size: 15),
            const SizedBox(width: 3),
            Text(
              score,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          portal,
          style: AppTypography.caption.copyWith(
            color: AppColors.textMuted,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}
