import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../domain/entities/anime_clip.dart';
import '../controllers/moments_player_pool.dart';
import 'clip_bottom_overlay.dart';
import 'clip_side_actions.dart';
import 'short_video_player_item.dart';

/// Оптимизированный вертикальный PageView ленты «Моменты»
/// с 3-Player Pool Buffering и отслеживанием видимости [VisibilityDetector].
class MomentsPageView extends StatelessWidget {
  final List<AnimeClip> clips;
  final MomentsPlayerPool pool;
  final PageController pageController;
  final ValueChanged<int>? onPageChanged;
  final void Function(AnimeClip)? onToggleLike;
  final void Function(AnimeClip)? onToggleBookmark;
  final void Function(AnimeClip)? onWatchFromMoment;
  final void Function(AnimeClip)? onOpenDetails;
  final void Function(AnimeClip)? onOpenYouTube;

  const MomentsPageView({
    super.key,
    required this.clips,
    required this.pool,
    required this.pageController,
    this.onPageChanged,
    this.onToggleLike,
    this.onToggleBookmark,
    this.onWatchFromMoment,
    this.onOpenDetails,
    this.onOpenYouTube,
  });

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      scrollDirection: Axis.vertical,
      itemCount: clips.length,
      onPageChanged: (index) {
        pool.updateActiveIndex(index, clips);
        onPageChanged?.call(index);
      },
      itemBuilder: (context, index) {
        final clip = clips[index];

        return VisibilityDetector(
          key: ValueKey('moment_detector_${clip.id}_$index'),
          onVisibilityChanged: (info) {
            pool.handleVisibilityChanged(index, info.visibleFraction);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Полноэкранный плеер из пула с 2X ускорением и фолбеком на нативный YouTube
              ShortVideoPlayerItem(
                clip: clip,
                index: index,
                pool: pool,
                isActive: index == pool.currentIndex,
                onDoubleTapLike: () => onToggleLike?.call(clip),
                onOpenYouTube: () => onOpenYouTube?.call(clip),
              ),

              // Правая колонка действий: Лайк, Сохраненка, О тайтле, YouTube
              Positioned(
                right: 12,
                bottom: 125,
                child: ClipSideActions(
                  clip: clip,
                  onToggleLike: () => onToggleLike?.call(clip),
                  onToggleBookmark: () => onToggleBookmark?.call(clip),
                  onOpenDetails: () => onOpenDetails?.call(clip),
                  onOpenYouTube: () => onOpenYouTube?.call(clip),
                ),
              ),

              // Нижний оверлей: Инфо + кнопка «Смотреть с этого момента»
              Positioned(
                left: 0,
                right: 70,
                bottom: 92, // Отступ под парящий LiquidGlassNavBar
                child: ClipBottomOverlay(
                  clip: clip,
                  onWatchFromMoment: () => onWatchFromMoment?.call(clip),
                  onOpenDetails: () => onOpenDetails?.call(clip),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
