import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/anime_clip.dart';

/// Минималистичная боковая колонка: только Лайк, Сохраненка и переход к аниме.
/// Без визуального шума и тяжелого неона.
class ClipSideActions extends StatefulWidget {
  final AnimeClip clip;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenDetails;
  final VoidCallback? onOpenYouTube;

  const ClipSideActions({
    super.key,
    required this.clip,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.onOpenDetails,
    this.onOpenYouTube,
  });

  @override
  State<ClipSideActions> createState() => _ClipSideActionsState();
}

class _ClipSideActionsState extends State<ClipSideActions>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      lowerBound: 0.85,
      upperBound: 1.15,
    );
    _bounceAnimation = CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOutQuad,
    );
    _bounceController.value = 1.0;
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _handleLikeTap() {
    HapticFeedback.lightImpact();
    _bounceController.forward().then((_) => _bounceController.reverse());
    widget.onToggleLike();
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. Кнопка Лайка с анимацией пульсации
        ScaleTransition(
          scale: _bounceAnimation,
          child: _CleanActionButton(
            icon: widget.clip.isLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            iconColor: widget.clip.isLiked
                ? const Color(0xFFFF2E63)
                : Colors.white,
            label: _formatCount(widget.clip.likesCount),
            onTap: _handleLikeTap,
          ),
        ),

        const SizedBox(height: 20),

        // 2. Кнопка Сохраненка (В списки)
        _CleanActionButton(
          icon: widget.clip.isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_outline_rounded,
          iconColor: widget.clip.isBookmarked
              ? AppColors.primary
              : Colors.white,
          label: widget.clip.isBookmarked ? 'В списке' : 'В список',
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onToggleBookmark();
          },
        ),

        const SizedBox(height: 20),

        // 3. Перейти на аниме (Круглый аватар тайтла с иконкой)
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onOpenDetails();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: widget.clip.posterUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 100,
                    memCacheHeight: 100,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.black54,
                      child: const Icon(Icons.movie_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'О тайтле',
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 4. Кнопка «YouTube»
        if (widget.clip.youtubeUrl != null && widget.clip.youtubeUrl!.isNotEmpty) ...[
          const SizedBox(height: 18),
          _CleanActionButton(
            icon: Icons.play_arrow_rounded,
            iconColor: const Color(0xFFFF2A2A),
            label: 'YouTube',
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onOpenYouTube?.call();
            },
          ),
        ],
      ],
    );
  }
}

class _CleanActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _CleanActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.40),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.0,
              ),
            ),
            child: Icon(
              icon,
              size: 26,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
