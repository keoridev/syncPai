import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/anime_clip.dart';

/// Плавающий стеклянный оверлей с информацией о моменте, таймкодом
/// и киллер-фичей «Смотреть с этого момента (▶ ММ:СС)».
/// Чистый дизайн без визуальной перегрузки.
class ClipBottomOverlay extends StatefulWidget {
  final AnimeClip clip;
  final VoidCallback onWatchFromMoment;
  final VoidCallback onOpenDetails;

  const ClipBottomOverlay({
    super.key,
    required this.clip,
    required this.onWatchFromMoment,
    required this.onOpenDetails,
  });

  @override
  State<ClipBottomOverlay> createState() => _ClipBottomOverlayState();
}

class _ClipBottomOverlayState extends State<ClipBottomOverlay> {
  bool _isDescriptionExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Название тайтла и бейдж эпизода
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onOpenDetails();
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.clip.animeTitle,
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Text(
                    'Эп. ${widget.clip.episodeNumber}',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (widget.clip.englishTitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              widget.clip.englishTitle,
              style: AppTypography.caption.copyWith(
                color: Colors.white60,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 6),

          // 2. Описание момента (аккуратный 1-2 строки текст)
          GestureDetector(
            onTap: () {
              setState(() {
                _isDescriptionExpanded = !_isDescriptionExpanded;
              });
            },
            child: Text(
              widget.clip.caption,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.3,
                fontSize: 12.5,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
              maxLines: _isDescriptionExpanded ? 5 : 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 10),

          // 3. Главная кнопка: «Смотреть с этого момента»
          Container(
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF9800),
                  Color(0xFFF57C00),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onWatchFromMoment();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Смотреть с этого момента (${widget.clip.formattedTimestamp})',
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
