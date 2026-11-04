import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_dimensions.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/app_button.dart';
import 'package:sync_pai/core/widgets/app_chip.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';

class AnimeDetailsScreen extends StatefulWidget {
  final AnimeTitle title;
  final void Function(AnimeTitle title, EpisodeItem episode)? onPlayEpisode;
  final void Function(AnimeTitle title, EpisodeItem episode)? onStartSyncRoom;

  const AnimeDetailsScreen({
    super.key,
    required this.title,
    this.onPlayEpisode,
    this.onStartSyncRoom,
  });

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> {
  int _selectedEpisodeIndex = 0;
  bool _isDescriptionExpanded = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final backdropUrl = title.posterOriginal.isNotEmpty
        ? title.posterOriginal
        : title.posterMedium;

    final episodes = title.episodes;
    final currentEpisode = episodes.isNotEmpty && _selectedEpisodeIndex < episodes.length
        ? episodes[_selectedEpisodeIndex]
        : (episodes.isNotEmpty ? episodes.first : null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          if (backdropUrl.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 380,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      color: AppColors.background.withValues(alpha: 0.65),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.5, 1.0],
                          colors: [
                            Colors.transparent,
                            AppColors.background.withValues(alpha: 0.7),
                            AppColors.background,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Основной скроллируемый контент
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Верхний AppBar с кнопкой "Назад"
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: Padding(
                  padding: const EdgeInsets.only(left: AppDimensions.spacingLg),
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.8),
                      side: BorderSide(color: AppColors.strokeMedium, width: 1.0),
                    ),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.textPrimary,
                      size: 18,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),

              // Постер, Названия, Жанры и Кнопки действий
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppDimensions.spacingMd),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Аккуратный постер
                          Container(
                            width: 110,
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius: AppDimensions.borderRadiusCard,
                              border: Border.all(color: AppColors.strokeMedium, width: 1.0),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CachedNetworkImage(
                              imageUrl: title.posterMedium,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: AppDimensions.spacingLg),
                          // Названия и статус
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title.displayTitle,
                                  style: AppTypography.displayMedium.copyWith(
                                    fontSize: 20,
                                    height: 1.25,
                                  ),
                                ),
                                if (title.englishTitle.isNotEmpty &&
                                    title.englishTitle != title.displayTitle) ...[
                                  const SizedBox(height: AppDimensions.spacingXs),
                                  Text(
                                    title.englishTitle,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: AppDimensions.spacingMd),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppDimensions.spacingSm,
                                        vertical: AppDimensions.spacing2xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceElevated,
                                        borderRadius: AppDimensions.borderRadiusSmall,
                                        border: Border.all(color: AppColors.stroke, width: 1.0),
                                      ),
                                      child: Text(
                                        title.episodesBadgeText,
                                        style: AppTypography.badge.copyWith(
                                          color: AppColors.textPrimary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    if (title.year != null) ...[
                                      const SizedBox(width: AppDimensions.spacingSm),
                                      Text(
                                        '${title.year}',
                                        style: AppTypography.labelMedium.copyWith(
                                          color: AppColors.textSecondary,
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

                      // Жанры
                      if (title.genres.isNotEmpty) ...[
                        const SizedBox(height: AppDimensions.spacingLg),
                        Wrap(
                          spacing: AppDimensions.spacingSm,
                          runSpacing: AppDimensions.spacingSm,
                          children: title.genres
                              .map((g) => AppChip(label: g, onTap: null))
                              .toList(),
                        ),
                      ],

                      // Кнопки действий: "Смотреть" и "Смотреть с другом"
                      const SizedBox(height: AppDimensions.spacingXl),
                      Row(
                        children: [
                          // Основная («Смотреть»): акцентный моно-цвет
                          Expanded(
                            flex: 5,
                            child: AppButton(
                              label: 'Смотреть',
                              icon: Icons.play_arrow_rounded,
                              onPressed: currentEpisode != null
                                  ? () => widget.onPlayEpisode?.call(title, currentEpisode)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: AppDimensions.spacingMd),
                          // Вторичная («Смотреть с другом»): полупрозрачная матовая заливка
                          Expanded(
                            flex: 6,
                            child: AppButton.frosted(
                              label: 'Смотреть с другом',
                              icon: Icons.group_outlined,
                              onPressed: currentEpisode != null
                                  ? () => widget.onStartSyncRoom?.call(title, currentEpisode)
                                  : null,
                            ),
                          ),
                        ],
                      ),

                      // Описание (с возможностью раскрытия)
                      if (title.description.isNotEmpty) ...[
                        const SizedBox(height: AppDimensions.spacing2xl),
                        Text('Описание', style: AppTypography.titleMedium),
                        const SizedBox(height: AppDimensions.spacingSm),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isDescriptionExpanded = !_isDescriptionExpanded;
                            });
                          },
                          child: Text(
                            title.description,
                            maxLines: _isDescriptionExpanded ? null : 4,
                            overflow: _isDescriptionExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: AppTypography.bodyMedium.copyWith(
                              height: 1.55,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],

                      // Список серий
                      const SizedBox(height: AppDimensions.spacing2xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Список серий', style: AppTypography.titleMedium),
                          if (episodes.isNotEmpty)
                            Text(
                              '${episodes.length} эп.',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.spacingMd),
                    ],
                  ),
                ),
              ),

              // Список эпизодов (лаконичные плашки "Серия 1", "Серия 2")
              if (episodes.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final ep = episodes[index];
                        final isSelected = index == _selectedEpisodeIndex;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedEpisodeIndex = index;
                                });
                                widget.onPlayEpisode?.call(title, ep);
                              },
                              borderRadius: AppDimensions.borderRadiusMedium,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppDimensions.spacingLg,
                                  vertical: AppDimensions.spacingMd,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.surfaceElevated
                                      : AppColors.surface,
                                  borderRadius: AppDimensions.borderRadiusMedium,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.stroke,
                                    width: 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.play_circle_fill_rounded
                                          : Icons.play_circle_outline_rounded,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                      size: 24,
                                    ),
                                    const SizedBox(width: AppDimensions.spacingMd),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Серия ${ep.episode}',
                                            style: AppTypography.titleSmall.copyWith(
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                          if (ep.name != null && ep.name!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              ep.name!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTypography.bodySmall,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    // Значок качества
                                    if (ep.fhdUrl != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceElevated,
                                          borderRadius: AppDimensions.borderRadiusSmall,
                                          border: Border.all(
                                            color: AppColors.stroke,
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Text(
                                          '1080p',
                                          style: AppTypography.badge.copyWith(
                                            fontSize: 10,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: episodes.length,
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.spacingXl),
                    child: Center(
                      child: Text(
                        'Список серий пока недоступен',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(
                child: SizedBox(height: AppDimensions.spacing3xl),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
