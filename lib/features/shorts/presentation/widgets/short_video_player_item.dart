import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/anime_clip.dart';
import '../controllers/moments_player_pool.dart';

/// Видеоплеер для шортсов/моментов, интегрированный с [MomentsPlayerPool]
/// Поддерживает:
/// - 3-Player Pool Buffering (без повторной пересборки Player с нуля на каждый свайп)
/// - Нативное аппаратное декодирование (hwdec: auto, max 1080x1920)
/// - Удержание для ускорения 2X
/// - Стилизованную карточку для YouTube Shorts без тяжелого WebView
/// - Анимацию двойного тапа (сердце)
class ShortVideoPlayerItem extends StatefulWidget {
  final AnimeClip clip;
  final int index;
  final MomentsPlayerPool? pool;
  final PooledPlayerEntry? entry;
  final bool isActive;
  final bool isMuted;
  final VoidCallback? onDoubleTapLike;
  final VoidCallback? onToggleMute;
  final VoidCallback? onOpenYouTube;

  const ShortVideoPlayerItem({
    super.key,
    required this.clip,
    this.index = 0,
    this.pool,
    this.entry,
    required this.isActive,
    this.isMuted = false,
    this.onDoubleTapLike,
    this.onToggleMute,
    this.onOpenYouTube,
  });

  @override
  State<ShortVideoPlayerItem> createState() => _ShortVideoPlayerItemState();
}

class _ShortVideoPlayerItemState extends State<ShortVideoPlayerItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnim;
  late Animation<double> _heartOpacityAnim;
  bool _showHeartOverlay = false;

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_heartAnimController);

    _heartOpacityAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartAnimController);
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    HapticFeedback.mediumImpact();
    widget.onDoubleTapLike?.call();

    setState(() {
      _showHeartOverlay = true;
    });
    _heartAnimController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _showHeartOverlay = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (widget.pool != null) {
      HapticFeedback.selectionClick();
      widget.pool!.togglePlayPause(widget.index);
    } else if (widget.entry != null) {
      HapticFeedback.selectionClick();
      if (widget.entry!.isPlaying) {
        widget.entry!.player.pause();
      } else {
        widget.entry!.player.play();
      }
    }
  }

  void _handleLongPressStart() {
    if (widget.pool != null) {
      HapticFeedback.mediumImpact();
      widget.pool!.set2xSpeed(widget.index, true);
    } else if (widget.entry != null) {
      HapticFeedback.mediumImpact();
      widget.entry!.player.setRate(2.0);
      widget.entry!.is2xFastForwarding = true;
    }
  }

  void _handleLongPressEnd() {
    if (widget.pool != null) {
      widget.pool!.set2xSpeed(widget.index, false);
      HapticFeedback.lightImpact();
    } else if (widget.entry != null) {
      widget.entry!.player.setRate(1.0);
      widget.entry!.is2xFastForwarding = false;
      HapticFeedback.lightImpact();
    }
  }

  bool get _isYouTubeOnly {
    final hasNoDirect = widget.clip.videoUrl.isEmpty;
    final hasYt = (widget.clip.youtubeId != null && widget.clip.youtubeId!.isNotEmpty) ||
        (widget.clip.youtubeUrl != null && widget.clip.youtubeUrl!.isNotEmpty);
    return hasNoDirect && hasYt;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pool != null) {
      return ListenableBuilder(
        listenable: widget.pool!,
        builder: (context, _) => _buildContent(context),
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    final entry = widget.entry ?? widget.pool?.getEntry(widget.index);
    final isActive = widget.isActive;
    final isMuted = widget.pool?.isMuted ?? widget.isMuted;
    final isPlaying = entry?.isPlaying ?? false;
    final isBuffering = entry?.isBuffering ?? true;
    final hasError = entry?.hasError ?? false;
    final progress = entry?.progress ?? 0.0;
    final is2x = entry?.is2xFastForwarding ?? false;

    return GestureDetector(
      onTap: _isYouTubeOnly ? widget.onOpenYouTube : _togglePlayPause,
      onDoubleTap: _handleDoubleTap,
      onLongPressStart: _isYouTubeOnly ? null : (_) => _handleLongPressStart(),
      onLongPressEnd: _isYouTubeOnly ? null : (_) => _handleLongPressEnd(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Стабильный постер под видео (JPG с User-Agent, без сбоев HWUI)
          CachedNetworkImage(
            imageUrl: widget.clip.posterUrl,
            fit: BoxFit.cover,
            memCacheWidth: 480,
            memCacheHeight: 854,
            httpHeaders: kIsWeb
                ? null
                : const {
                    'User-Agent':
                        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
                  },
            placeholder: (context, url) => Container(
              color: AppColors.background,
              child: const Center(
                child: ShimmerPlaceholder(width: 60, height: 60),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: AppColors.background,
              child: const Icon(Icons.movie_outlined, size: 54, color: Colors.white24),
            ),
          ),

          // 2. Прямой видеопоток media_kit из пула контроллеров
          if (!_isYouTubeOnly && entry != null && !hasError)
            Positioned.fill(
              child: Video(
                controller: entry.controller,
                fit: BoxFit.cover,
                controls: NoVideoControls,
              ),
            ),

          // 3. Мягкий градиент для читаемости элементов управления и текста
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0.0, 0.18, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 4. Плашка YouTube Shorts (если клип только на YouTube)
          if (_isYouTubeOnly) ...[
            Positioned(
              top: 70,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF0000).withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'YouTube Shorts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF0000).withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF0000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Смотреть в YouTube Shorts',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Нативный запуск без лагов WebView',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 5. Индикатор буферизации
          if (!_isYouTubeOnly && isBuffering && isActive && !hasError)
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),

          // 6. Ошибка воспроизведения
          if (!_isYouTubeOnly && hasError && isActive)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFFF5252), size: 36),
                    const SizedBox(height: 8),
                    Text(
                      'Не удалось загрузить видеопоток',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () {
                        widget.pool?.retry(widget.index, widget.clip);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Повторить попытку',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 7. Индикатор 2X скорости при удержании
          if (!_isYouTubeOnly && is2x)
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fast_forward_rounded,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '2X Скорость',
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 8. Оверлей Паузы + Кнопка Звука
          if (!_isYouTubeOnly && !isPlaying && !isBuffering && isActive && !hasError)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _togglePlayPause,
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(width: 1, height: 26, color: Colors.white24),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (widget.pool != null) {
                          widget.pool!.toggleMute();
                        } else {
                          widget.onToggleMute?.call();
                        }
                      },
                      child: Icon(
                        isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: isMuted ? Colors.white54 : AppColors.primary,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 9. Сердечко при двойном тапе
          if (_showHeartOverlay)
            Center(
              child: AnimatedBuilder(
                animation: _heartAnimController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _heartOpacityAnim.value.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: _heartScaleAnim.value,
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFFF2E63),
                        size: 96,
                      ),
                    ),
                  );
                },
              ),
            ),

          // 10. Линия прогресса внизу
          if (!_isYouTubeOnly)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 2.5,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
