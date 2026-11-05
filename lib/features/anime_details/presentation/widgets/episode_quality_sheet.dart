import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../player/domain/entities/player_quality.dart';

/// Шторка выбора качества видео перед переходом к просмотру серии.
/// Позволяет выбрать 1080p, 720p или 480p с информацией о доступности потока.
class EpisodeQualitySheet extends StatefulWidget {
  final AnimeTitle title;
  final EpisodeItem episode;
  final PlayerQuality initialQuality;
  final ValueChanged<PlayerQuality> onQualitySelected;

  const EpisodeQualitySheet({
    super.key,
    required this.title,
    required this.episode,
    this.initialQuality = PlayerQuality.fhd,
    required this.onQualitySelected,
  });

  static Future<PlayerQuality?> show(
    BuildContext context, {
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality initialQuality = PlayerQuality.fhd,
  }) {
    return showModalBottomSheet<PlayerQuality>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => EpisodeQualitySheet(
        title: title,
        episode: episode,
        initialQuality: initialQuality,
        onQualitySelected: (quality) {
          Navigator.of(ctx).pop(quality);
        },
      ),
    );
  }

  @override
  State<EpisodeQualitySheet> createState() => _EpisodeQualitySheetState();
}

class _EpisodeQualitySheetState extends State<EpisodeQualitySheet> {
  late PlayerQuality _selectedQuality;

  @override
  void initState() {
    super.initState();
    _selectedQuality = _resolveInitialQuality(widget.initialQuality);
  }

  /// Если изначально выбранное качество недоступно, выбираем наилучшее доступное
  PlayerQuality _resolveInitialQuality(PlayerQuality desired) {
    if (_isQualityAvailable(desired)) {
      return desired;
    }
    for (final q in PlayerQuality.values) {
      if (_isQualityAvailable(q)) return q;
    }
    return PlayerQuality.fhd;
  }

  bool _isQualityAvailable(PlayerQuality quality) {
    final ep = widget.episode;
    switch (quality) {
      case PlayerQuality.fhd:
        return ep.fhdUrl != null || (ep.hdUrl == null && ep.sdUrl == null);
      case PlayerQuality.hd:
        return ep.hdUrl != null || ep.fhdUrl != null || ep.sdUrl == null;
      case PlayerQuality.sd:
        return ep.sdUrl != null || ep.hdUrl != null || ep.fhdUrl != null;
    }
  }

  String _getQualityDescription(PlayerQuality quality) {
    switch (quality) {
      case PlayerQuality.fhd:
        return 'Максимальная четкость и детализация для большого экрана';
      case PlayerQuality.hd:
        return 'Оптимальный баланс качества видео и скорости загрузки';
      case PlayerQuality.sd:
        return 'Экономия мобильного трафика и плавная работа при слабой сети';
    }
  }

  IconData _getQualityIcon(PlayerQuality quality) {
    switch (quality) {
      case PlayerQuality.fhd:
        return Icons.hd_rounded;
      case PlayerQuality.hd:
        return Icons.high_quality_rounded;
      case PlayerQuality.sd:
        return Icons.sd_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final previewUrl = ep.previewUrl ??
        (widget.title.posterOriginal.isNotEmpty
            ? widget.title.posterOriginal
            : widget.title.posterMedium);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spacingXl,
                AppDimensions.spacingMd,
                AppDimensions.spacingXl,
                AppDimensions.spacingLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Индикатор перетаскивания (Handle bar)
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppDimensions.spacingLg),

                  // Заголовок шторки и кнопка закрытия
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Выбор качества видео',
                        style: AppTypography.titleLarge.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppDimensions.spacingMd),

                  // Карточка серии с 16:9 превью
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Превью серии
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 100,
                            height: 56,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (previewUrl.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: previewUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        const ShimmerPlaceholder.card(),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(
                                        Icons.movie_creation_outlined,
                                        color: AppColors.textMuted,
                                        size: 20,
                                      ),
                                    ),
                                  )
                                else
                                  Container(color: AppColors.surfaceElevated),
                                Container(
                                  color: Colors.black.withValues(alpha: 0.25),
                                ),
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withValues(alpha: 0.6),
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 16,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: AppDimensions.spacingMd),

                        // Инфо серии
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Серия ${ep.episode}',
                                style: AppTypography.titleSmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (ep.name != null && ep.name!.isNotEmpty)
                                    ? ep.name!
                                    : widget.title.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              if (ep.opening != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  'Опенинг: ${ep.opening!.formattedRange}',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textMuted,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppDimensions.spacingLg),

                  // Список вариантов качества видео (1080p, 720p, 480p)
                  ...PlayerQuality.values.map((quality) {
                    final isAvailable = _isQualityAvailable(quality);
                    final isSelected = quality == _selectedQuality;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isAvailable
                              ? () {
                                  setState(() => _selectedQuality = quality);
                                }
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spacingLg,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.14)
                                  : (isAvailable
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : Colors.white.withValues(alpha: 0.01)),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : (isAvailable
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.03)),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Иконка качества
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _getQualityIcon(quality),
                                    color: isSelected
                                        ? AppColors.primaryLight
                                        : (isAvailable
                                            ? AppColors.textSecondary
                                            : AppColors.textMuted),
                                    size: 22,
                                  ),
                                ),

                                const SizedBox(width: AppDimensions.spacingMd),

                                // Название и описание
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            quality.label,
                                            style: AppTypography.titleSmall.copyWith(
                                              color: isSelected
                                                  ? AppColors.textPrimary
                                                  : (isAvailable
                                                      ? AppColors.textPrimary
                                                      : AppColors.textMuted),
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (!isAvailable) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              '(недоступно)',
                                              style: AppTypography.caption.copyWith(
                                                color: AppColors.textMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _getQualityDescription(quality),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.bodySmall.copyWith(
                                          color: isAvailable
                                              ? AppColors.textSecondary
                                              : AppColors.textMuted.withValues(alpha: 0.6),
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // Радио-индикатор выбора
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white.withValues(alpha: 0.25),
                                      width: 2.0,
                                    ),
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.transparent,
                                  ),
                                  child: isSelected
                                      ? const Center(
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: AppColors.textPrimary,
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: AppDimensions.spacingMd),

                  // Кнопка подтверждения и перехода к просмотру
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        widget.onQualitySelected(_selectedQuality);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            size: 24,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Смотреть в ${_selectedQuality.label}',
                            style: AppTypography.labelLarge.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
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
      ),
    );
  }
}

