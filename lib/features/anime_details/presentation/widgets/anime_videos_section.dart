import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/anime_video_item.dart';

/// Секция «Видео & Трейлеры» (PV, тизеры и промо-материалы тайтла).
/// Точно соответствует официальному экрану видео Anixart (карусель PV + вертикальный список).
class AnimeVideosSection extends StatelessWidget {
  final List<AnimeVideoItem> videos;
  final String animeTitle;
  final ValueChanged<AnimeVideoItem>? onVideoTap;
  final VoidCallback? onOpenAllVideos;

  const AnimeVideosSection({
    super.key,
    required this.videos,
    required this.animeTitle,
    this.onVideoTap,
    this.onOpenAllVideos,
  });

  Future<void> _handlePlayVideo(BuildContext context, AnimeVideoItem video) async {
    if (onVideoTap != null) {
      onVideoTap!(video);
      return;
    }

    final uri = Uri.tryParse(video.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Открытие видео: ${video.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return const SizedBox.shrink();
    }

    // Первые 4 видео для горизонтальной карусели «Трейлеры»
    final pvs = videos.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок раздела
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Видео',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  animeTitle,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
            if (onOpenAllVideos != null)
              GestureDetector(
                onTap: onOpenAllVideos,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Все (${videos.length})',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.primaryLight),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.strokeMedium),
                ),
                child: Text(
                  '${videos.length} видео',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 16),

        // 1. Горизонтальная карусель: «Трейлеры»
        Text(
          'Трейлеры',
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: pvs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final video = pvs[index];
              return _buildCarouselCard(context, video);
            },
          ),
        ),

        const SizedBox(height: 20),

        // 2. Вертикальный список: «Последние видео»
        Text(
          'Последние видео',
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: videos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final video = videos[index];
            return _buildVideoRow(context, video);
          },
        ),
      ],
    );
  }

  Widget _buildCarouselCard(BuildContext context, AnimeVideoItem video) {
    return Container(
      width: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: AppColors.surfaceElevated,
          child: InkWell(
            onTap: () => _handlePlayVideo(context, video),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Превью видео
                if (video.imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: video.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ShimmerPlaceholder.card(),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.surfaceElevated,
                    ),
                  )
                else
                  Container(color: AppColors.surfaceElevated),

                // Затемнение для читаемости текста и акцента кнопки
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                ),

                // Красный значок YouTube Play в верхнем левом углу
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),

                // Метка видео снизу слева (PV1, PV2, Трейлер)
                Positioned(
                  bottom: 8,
                  left: 10,
                  right: 10,
                  child: Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoRow(BuildContext context, AnimeVideoItem video) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _handlePlayVideo(context, video),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // 16:9 Превью с красной кнопкой Play
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 110,
                    height: 64,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (video.imageUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: video.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const ShimmerPlaceholder.card(),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceElevated,
                            ),
                          )
                        else
                          Container(color: AppColors.surfaceElevated),

                        Container(color: Colors.black.withValues(alpha: 0.3)),

                        // Красный Play
                        Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914).withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Описание видео
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${video.source} • ${video.publishedAt ?? "Официальный релиз"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$animeTitle • Трейлеры',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  onPressed: () => _handlePlayVideo(context, video),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
