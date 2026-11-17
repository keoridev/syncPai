import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';
import '../../../../core/widgets/mascot/sync_pai_mascot.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../domain/entities/anime_rating_aggregate.dart';
import '../../domain/entities/anime_review.dart';
import '../../domain/entities/score_distribution_item.dart';
import 'score_distribution_chart.dart';
import 'write_review_sheet.dart';

class AnimeReviewsSection extends StatefulWidget {
  final List<AnimeReview> reviews;
  final AnimeRatingAggregate? aggregate;
  final Map<String, double>? portalScores;
  final List<ScoreDistributionItem> scoreDistribution;
  final bool isLoading;
  final AnimeTitle? title;
  final ValueChanged<AnimeReview>? onReviewAdded;

  const AnimeReviewsSection({
    super.key,
    required this.reviews,
    this.aggregate,
    this.portalScores,
    this.scoreDistribution = const [],
    this.isLoading = false,
    this.title,
    this.onReviewAdded,
  });

  @override
  State<AnimeReviewsSection> createState() => _AnimeReviewsSectionState();
}

class _AnimeReviewsSectionState extends State<AnimeReviewsSection> {
  // Выбранный фильтр источника: null (Все), syncpai, shikimori, mal
  ReviewSource? _selectedSource;

  // Выбранный фильтр тональности: null (Все), positive (7+), negative (<7)
  ReviewSentiment? _selectedSentiment;

  // Раскрытые отзывы (Set id)
  final Set<String> _expandedReviewIds = {};

  // Раскрытые спойлеры (Set id)
  final Set<String> _revealedSpoilerIds = {};

  List<AnimeReview> get _filteredReviews {
    return widget.reviews.where((rev) {
      if (_selectedSource != null && rev.source != _selectedSource) {
        return false;
      }
      if (_selectedSentiment != null) {
        if (_selectedSentiment == ReviewSentiment.positive) {
          if (rev.sentiment != ReviewSentiment.positive) return false;
        } else if (_selectedSentiment == ReviewSentiment.negative) {
          if (rev.sentiment == ReviewSentiment.positive) return false;
        }
      }
      return true;
    }).toList();
  }

  void _openWriteReview(BuildContext context) {
    if (widget.title == null) return;
    WriteReviewSheet.show(
      context,
      title: widget.title!,
      onReviewSubmitted: (newReview) {
        widget.onReviewAdded?.call(newReview);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final aggregate = widget.aggregate ?? _buildFallbackAggregate();
    final filtered = _filteredReviews;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Агрегированный заголовок рейтингов со сторонних платформ и SyncPai
        _buildAggregatedRatingHeader(aggregate),

        // 2. График распределения оценок пользователей (1-10 ★)
        if (widget.scoreDistribution.isNotEmpty) ...[
          const SizedBox(height: 16),
          ScoreDistributionChart(
            distribution: widget.scoreDistribution,
            averageScore: aggregate.shikimoriScore ?? widget.portalScores?['Shikimori'] ?? 8.8,
          ),
        ],

        const SizedBox(height: 20),

        // 3. Заголовок раздела отзывов + Кнопка «Написать отзыв»
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Отзывы сообщества',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.reviews.length} отзывов со всех платформ',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
            if (widget.title != null)
              OutlinedButton.icon(
                onPressed: () => _openWriteReview(context),
                icon: const Icon(Icons.rate_review_rounded, size: 16),
                label: const Text('Оставить отзыв'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentTurquoise,
                  side: const BorderSide(color: AppColors.accentTurquoise),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
          ],
        ),

        const SizedBox(height: 14),

        // 4. Фильтры источников и тональности
        _buildFilterChips(aggregate),

        const SizedBox(height: 16),

        // 5. Список отзывов или Empty State с маскотом Пай-чан
        if (filtered.isEmpty)
          _buildEmptyState(context)
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final rev = filtered[index];
              return _buildReviewCard(rev);
            },
          ),
      ],
    );
  }

  /// Агрегированная карточка рейтингов (SyncPai, Shikimori, MyAnimeList + Распределение тональности)
  Widget _buildAggregatedRatingHeader(AnimeRatingAggregate aggregate) {
    final shikiScoreStr = aggregate.shikimoriScore != null
        ? aggregate.shikimoriScore!.toStringAsFixed(1)
        : (widget.portalScores?['Shikimori'] ?? 8.9).toStringAsFixed(1);

    final malScoreStr = aggregate.malScore != null
        ? aggregate.malScore!.toStringAsFixed(1)
        : (widget.portalScores?['MyAnimeList'] ?? 8.8).toStringAsFixed(1);

    final syncPaiScoreStr = aggregate.syncpaiScore != null && aggregate.syncpaiScore! > 0
        ? aggregate.syncpaiScore!.toStringAsFixed(1)
        : null;

    final anilibriaScoreStr = (widget.portalScores?['AniLibria'] ?? 9.4).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
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
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_graph_rounded, color: AppColors.primary, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ОЦЕНКИ НА АНИМЕ-ПОРТАЛАХ',
                    style: AppTypography.caption.copyWith(
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              if (widget.isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // Плашки рейтингов порталов
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceAround,
                children: [
                  if (syncPaiScoreStr != null)
                    _buildPortalBadge(
                      title: 'SyncPai',
                      score: syncPaiScoreStr,
                      votesCount: aggregate.syncpaiVotesCount,
                      color: AppColors.accentTurquoise,
                      icon: Icons.sync_rounded,
                    ),
                  _buildPortalBadge(
                    title: 'Shikimori',
                    score: shikiScoreStr,
                    votesCount: aggregate.shikimoriVotesCount,
                    color: const Color(0xFF4A90E2),
                    icon: Icons.star_rounded,
                  ),
                  _buildPortalBadge(
                    title: 'MyAnimeList',
                    score: malScoreStr,
                    votesCount: aggregate.malVotesCount,
                    color: const Color(0xFF2E51A2),
                    icon: Icons.public_rounded,
                  ),
                  _buildPortalBadge(
                    title: 'AniLibria',
                    score: anilibriaScoreStr,
                    votesCount: 0,
                    color: AppColors.primary,
                    icon: Icons.headset_rounded,
                  ),
                ],
              );
            },
          ),

          // Полоска распределения тональности отзывов
          if (aggregate.totalSentimentCount > 0) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.strokeMedium, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Тональность рецензий:',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${aggregate.positivePercent.toStringAsFixed(0)}% позитивных',
                  style: AppTypography.caption.copyWith(
                    color: const Color(0xFF4CAF50),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Сегментированный бар
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    if (aggregate.positivePercent > 0)
                      Expanded(
                        flex: aggregate.positiveCount,
                        child: Container(color: const Color(0xFF4CAF50)),
                      ),
                    if (aggregate.neutralPercent > 0)
                      Expanded(
                        flex: aggregate.neutralCount,
                        child: Container(color: const Color(0xFFFFB74D)),
                      ),
                    if (aggregate.negativePercent > 0)
                      Expanded(
                        flex: aggregate.negativeCount,
                        child: Container(color: const Color(0xFFEF5350)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSentimentLegend('★ 7-10', '${aggregate.positiveCount}', const Color(0xFF4CAF50)),
                _buildSentimentLegend('★ 5-6', '${aggregate.neutralCount}', const Color(0xFFFFB74D)),
                _buildSentimentLegend('★ 1-4', '${aggregate.negativeCount}', const Color(0xFFEF5350)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPortalBadge({
    required String title,
    required String score,
    required int votesCount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 70),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                score,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: AppTypography.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
          if (votesCount > 0) ...[
            const SizedBox(height: 1),
            Text(
              '${AnimeRatingAggregate.formatVotesCount(votesCount)} голосов',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSentimentLegend(String label, String count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $count',
          style: AppTypography.caption.copyWith(
            color: AppColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  /// Фильтры источников и настроения отзывов
  Widget _buildFilterChips(AnimeRatingAggregate aggregate) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Все источники
          _buildFilterChip(
            label: 'Все (${widget.reviews.length})',
            isSelected: _selectedSource == null && _selectedSentiment == null,
            onTap: () {
              setState(() {
                _selectedSource = null;
                _selectedSentiment = null;
              });
            },
          ),
          const SizedBox(width: 8),

          // SyncPai
          _buildFilterChip(
            label: 'SyncPai (${widget.reviews.where((r) => r.source == ReviewSource.syncpai).length})',
            isSelected: _selectedSource == ReviewSource.syncpai,
            badgeColor: AppColors.accentTurquoise,
            onTap: () {
              setState(() {
                _selectedSource = _selectedSource == ReviewSource.syncpai ? null : ReviewSource.syncpai;
              });
            },
          ),
          const SizedBox(width: 8),

          // Shikimori
          _buildFilterChip(
            label: 'Shikimori (${widget.reviews.where((r) => r.source == ReviewSource.shikimori).length})',
            isSelected: _selectedSource == ReviewSource.shikimori,
            badgeColor: const Color(0xFF4A90E2),
            onTap: () {
              setState(() {
                _selectedSource = _selectedSource == ReviewSource.shikimori ? null : ReviewSource.shikimori;
              });
            },
          ),
          const SizedBox(width: 8),

          // MyAnimeList
          _buildFilterChip(
            label: 'MAL (${widget.reviews.where((r) => r.source == ReviewSource.mal).length})',
            isSelected: _selectedSource == ReviewSource.mal,
            badgeColor: const Color(0xFF2E51A2),
            onTap: () {
              setState(() {
                _selectedSource = _selectedSource == ReviewSource.mal ? null : ReviewSource.mal;
              });
            },
          ),
          const SizedBox(width: 8),

          // Быстрый фильтр «Положительные»
          _buildFilterChip(
            label: '★ Положительные',
            isSelected: _selectedSentiment == ReviewSentiment.positive,
            badgeColor: const Color(0xFF4CAF50),
            onTap: () {
              setState(() {
                _selectedSentiment =
                    _selectedSentiment == ReviewSentiment.positive ? null : ReviewSentiment.positive;
              });
            },
          ),
          const SizedBox(width: 8),

          // Быстрый фильтр «Критика»
          _buildFilterChip(
            label: 'Критика (<7)',
            isSelected: _selectedSentiment == ReviewSentiment.negative,
            badgeColor: const Color(0xFFEF5350),
            onTap: () {
              setState(() {
                _selectedSentiment =
                    _selectedSentiment == ReviewSentiment.negative ? null : ReviewSentiment.negative;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    final activeColor = badgeColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.22)
              : AppColors.surfaceElevated.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.strokeMedium,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  /// Карточка отдельного отзыва
  Widget _buildReviewCard(AnimeReview rev) {
    final isExpanded = _expandedReviewIds.contains(rev.id);
    final isSpoilerRevealed = _revealedSpoilerIds.contains(rev.id);
    final hasSpoiler = rev.containsSpoiler || rev.isSpoiler;

    // Определяем цвет плашки источника
    Color sourceColor;
    switch (rev.source) {
      case ReviewSource.syncpai:
        sourceColor = AppColors.accentTurquoise;
        break;
      case ReviewSource.shikimori:
        sourceColor = const Color(0xFF4A90E2);
        break;
      case ReviewSource.mal:
        sourceColor = const Color(0xFF2E51A2);
        break;
      case ReviewSource.anilibria:
        sourceColor = AppColors.primary;
        break;
    }

    final isLongText = rev.content.length > 220;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка отзыва: Аватар, никнейм, бейдж источника, оценка и дата
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    AppAvatar(
                      avatarUrl: rev.authorAvatarUrl,
                      username: rev.authorName,
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  rev.authorName,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: sourceColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: sourceColor.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  rev.source.displayName,
                                  style: AppTypography.caption.copyWith(
                                    color: sourceColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                rev.date,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                              if (rev.originalUrl != null) ...[
                                const Text(' • ', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                InkWell(
                                  onTap: () => _openUrl(rev.originalUrl!),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Оригинал',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.primaryLight,
                                          fontSize: 10.5,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(Icons.open_in_new_rounded, size: 10, color: AppColors.primaryLight),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Плашка оценки
              if (rev.score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getScoreColor(rev.score!).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _getScoreColor(rev.score!).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 14, color: _getScoreColor(rev.score!)),
                      const SizedBox(width: 3),
                      Text(
                        '${rev.score!.toInt()}/10',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Тело отзыва (с защитной маской от спойлеров)
          if (hasSpoiler && !isSpoilerRevealed)
            InkWell(
              onTap: () {
                setState(() => _revealedSpoilerIds.add(rev.id));
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF151923),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Спойлер — нажми, чтобы открыть',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              rev.content,
              maxLines: isExpanded ? null : 4,
              overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            if (isLongText) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedReviewIds.remove(rev.id);
                    } else {
                      _expandedReviewIds.add(rev.id);
                    }
                  });
                },
                child: Text(
                  isExpanded ? 'Свернуть' : 'Читать полностью...',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],

          const SizedBox(height: 10),

          // Подвал карточки: лайки
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
  }

  /// Empty State с маскотом Пай-чан
  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Column(
        children: [
          const SyncPaiMascot(
            state: MascotState.idle,
            size: MascotSize.small,
          ),
          const SizedBox(height: 16),
          Text(
            'Отзывов пока нет',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Станьте первым, кто оценит этот тайтл и поделится впечатлениями!',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (widget.title != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openWriteReview(context),
              icon: const Icon(Icons.rate_review_rounded, size: 16),
              label: const Text('Написать первый отзыв'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 8.0) return const Color(0xFF4CAF50);
    if (score >= 6.0) return const Color(0xFFFFB74D);
    return const Color(0xFFEF5350);
  }

  AnimeRatingAggregate _buildFallbackAggregate() {
    int pos = 0;
    int neu = 0;
    int neg = 0;
    for (final r in widget.reviews) {
      if (r.sentiment == ReviewSentiment.positive) pos++;
      if (r.sentiment == ReviewSentiment.neutral) neu++;
      if (r.sentiment == ReviewSentiment.negative) neg++;
    }
    return AnimeRatingAggregate(
      shikimoriScore: widget.portalScores?['Shikimori'] ?? 8.9,
      shikimoriVotesCount: 14200,
      malScore: widget.portalScores?['MyAnimeList'] ?? 8.8,
      malVotesCount: 28500,
      positiveCount: pos,
      neutralCount: neu,
      negativeCount: neg,
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}
