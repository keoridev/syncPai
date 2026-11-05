import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/anime_video_item.dart';

/// Экран «Видео & Трейлеры» тайтла.
/// Точно повторяет дизайн из Screenshot 2 (Anixart / Shikimori PVs).
class AnimeVideosScreen extends StatelessWidget {
  final String animeTitle;
  final String backdropUrl;
  final List<AnimeVideoItem> videos;

  const AnimeVideosScreen({
    super.key,
    required this.animeTitle,
    this.backdropUrl = '',
    this.videos = const [],
  });

  Future<void> _playVideo(BuildContext context, AnimeVideoItem video) async {
    final uri = Uri.tryParse(video.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Воспроизведение: ${video.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showVideoOptions(BuildContext context, AnimeVideoItem video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.strokeMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$animeTitle • ${video.source}',
                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914), size: 26),
                title: const Text('Смотреть трейлер', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _playVideo(context, video);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded, color: AppColors.textSecondary, size: 24),
                title: const Text('Скопировать ссылку', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: video.url));
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ссылка скопирована в буфер')),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.share_rounded, color: AppColors.textSecondary, size: 24),
                title: const Text('Поделиться видео', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Поделиться: ${video.url}')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Выделяем первые трейлеры в горизонтальную карусель
    final trailers = videos.where((v) => v.kind == 'pv' || v.kind.isEmpty).toList();
    final carouselItems = trailers.isNotEmpty ? trailers : videos;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Верхний баннер с постером/бэкдропом (Скриншот 2)
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Фоновое изображение
                  if (backdropUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdropUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                    )
                  else
                    Container(color: AppColors.surfaceElevated),

                  // Градиентное затемнение сверху и снизу (Скриншот 2)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.4),
                          Colors.black.withValues(alpha: 0.85),
                          AppColors.background,
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      ),
                    ),
                  ),

                  // Текстовый заголовок «Видео» и подзаголовок
                  Positioned(
                    left: 20,
                    bottom: 16,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Видео',
                          style: AppTypography.displayLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          animeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Секция «Трейлеры» (горизонтальная карусель)
          if (carouselItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  'Трейлеры',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16.5,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 110,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: carouselItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = carouselItems[index];
                    return _buildCarouselCard(context, item);
                  },
                ),
              ),
            ),
          ],

          // 3. Секция «Последние видео» (вертикальный список)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Последние видео',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16.5,
                ),
              ),
            ),
          ),

          if (videos.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Видеоматериалы загружаются...',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final video = videos[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildVideoTile(context, video),
                    );
                  },
                  childCount: videos.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: AppDimensions.spacing3xl),
          ),
        ],
      ),
    );
  }

  /// Карточка горизонтальной карусели трейлеров (Скриншот 2)
  Widget _buildCarouselCard(BuildContext context, AnimeVideoItem video) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: AppColors.surfaceElevated,
        child: InkWell(
          onTap: () => _playVideo(context, video),
          child: SizedBox(
            width: 175,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Картинка превью
                if (video.imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: video.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ShimmerPlaceholder.card(),
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                  )
                else
                  Container(color: AppColors.surfaceElevated),

                // Затемнение
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

                // Красный логотип YouTube Play в верхнем левом углу
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),

                // Текст названия трейлера снизу (PV2, PV1...)
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

  /// Элемент вертикального списка «Последние видео» (Скриншот 2)
  Widget _buildVideoTile(BuildContext context, AnimeVideoItem video) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _playVideo(context, video),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Превью 16:9 с красным значком Play (110 x 64, rounded 10)
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
                          errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                        )
                      else
                        Container(color: AppColors.surfaceElevated),

                      // Затемнение
                      Container(color: Colors.black.withValues(alpha: 0.25)),

                      // Красный значок YouTube в верхнем левом углу превью (Скриншот 2)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // 2. Описание: Название (PV3), Anixart • 17 окт. в 12:00, Тайтл, Трейлеры
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${video.source} • ${video.publishedAt ?? "17 окт. в 12:00"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      animeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Трейлеры',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Меню из трех точек (Скриншот 2)
              IconButton(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _showVideoOptions(context, video),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
