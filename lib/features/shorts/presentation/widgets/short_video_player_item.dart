import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/anime_clip.dart';

/// Видеоплеер для шортсов на базе media_kit
/// с поддержкой ускорения 2X при удержании экрана,
/// всплывающим управлением звуком/паузой и адаптивным размером текстуры.
class ShortVideoPlayerItem extends StatefulWidget {
  final AnimeClip clip;
  final bool isActive;
  final bool isMuted;
  final VoidCallback? onDoubleTapLike;
  final VoidCallback? onToggleMute;

  const ShortVideoPlayerItem({
    super.key,
    required this.clip,
    required this.isActive,
    this.isMuted = false,
    this.onDoubleTapLike,
    this.onToggleMute,
  });

  @override
  State<ShortVideoPlayerItem> createState() => _ShortVideoPlayerItemState();
}

class _ShortVideoPlayerItemState extends State<ShortVideoPlayerItem>
    with SingleTickerProviderStateMixin {
  Player? _player;
  VideoController? _controller;
  bool _isPlaying = true;
  bool _isBuffering = true;
  bool _hasError = false;
  double _progress = 0.0;
  bool _is2xFastForwarding = false;

  StreamSubscription? _posSub;
  StreamSubscription? _bufSub;
  StreamSubscription? _playSub;
  StreamSubscription? _errSub;

  // Анимация двойного тапа (сердце)
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

    if (widget.isActive) {
      _initPlayer();
    }
  }

  @override
  void didUpdateWidget(covariant ShortVideoPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _initPlayer();
      } else {
        _disposePlayer();
      }
    }

    if (widget.isMuted != oldWidget.isMuted && _player != null) {
      _player?.setVolume(widget.isMuted ? 0 : 100);
    }
  }

  void _initPlayer() {
    if (_player != null) return;

    try {
      final player = Player();
      // Стандартный контроллер без принудительного флага аппаратного ускорения,
      // что исключает падение декодера ImageReader/HWUI на Mali/Vivo
      final controller = VideoController(player);

      player.setPlaylistMode(PlaylistMode.loop);
      player.setVolume(widget.isMuted ? 0 : 100);

      _posSub = player.stream.position.listen((pos) {
        final dur = player.state.duration;
        if (dur.inMilliseconds > 0 && mounted) {
          setState(() {
            _progress = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
          });
        }
      });

      _bufSub = player.stream.buffering.listen((buffering) {
        if (mounted) {
          setState(() {
            _isBuffering = buffering;
          });
        }
      });

      _playSub = player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
          });
        }
      });

      _errSub = player.stream.error.listen((error) {
        if (mounted && error.isNotEmpty) {
          setState(() {
            _hasError = true;
          });
        }
      });

      // Открываем поток с явным флагом play: true, исключая битые фиктивные ссылки
      String targetUrl = widget.clip.videoUrl;
      if (targetUrl.contains('_ep1_720')) {
        targetUrl = 'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8';
      }
      player.open(Media(targetUrl), play: true);
      player.play();

      setState(() {
        _player = player;
        _controller = controller;
        _hasError = false;
        _isBuffering = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _disposePlayer() {
    _posSub?.cancel();
    _bufSub?.cancel();
    _playSub?.cancel();
    _errSub?.cancel();
    _posSub = null;
    _bufSub = null;
    _playSub = null;
    _errSub = null;

    _player?.pause();
    _player?.dispose();
    _player = null;
    _controller = null;
    _progress = 0.0;
    _is2xFastForwarding = false;
  }

  void _togglePlayPause() {
    if (_player == null) return;
    HapticFeedback.selectionClick();

    if (_isPlaying) {
      _player?.pause();
    } else {
      _player?.play();
    }
  }

  /// Удержание экрана: ускорение 2X
  void _handleLongPressStart() {
    if (_player == null) return;
    HapticFeedback.mediumImpact();
    _player?.setRate(2.0);
    setState(() {
      _is2xFastForwarding = true;
    });
  }

  void _handleLongPressEnd() {
    if (_player == null) return;
    _player?.setRate(1.0);
    if (_is2xFastForwarding) {
      HapticFeedback.lightImpact();
      setState(() {
        _is2xFastForwarding = false;
      });
    }
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

  @override
  void dispose() {
    _heartAnimController.dispose();
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTap: _handleDoubleTap,
      onLongPressStart: (_) => _handleLongPressStart(),
      onLongPressEnd: (_) => _handleLongPressEnd(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Постер под видео (без сбоев HWUI: стандартный JPG + браузерный User-Agent)
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

          // 2. Прямой видеопоток media_kit на весь экран (Positioned.fill передаёт нативному рендеру реальный размер)
          if (_player != null && _controller != null && !_hasError)
            Positioned.fill(
              child: Video(
                controller: _controller!,
                fit: BoxFit.cover,
                controls: NoVideoControls,
              ),
            ),

          // 3. Мягкий полупрозрачный градиент для контрастности текста
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

          // 4. Индикатор буферизации
          if (_isBuffering && widget.isActive && !_hasError)
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

          // 4b. Ошибка воспроизведения потока
          if (_hasError && widget.isActive)
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
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5252), size: 36),
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
                        _disposePlayer();
                        _initPlayer();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

          // 5. Индикатор удержания 2X скорости
          if (_is2xFastForwarding)
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fast_forward_rounded, color: AppColors.primary, size: 18),
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

          // 6. Оверлей Паузы + Кнопка Звука (появляется при приостановке видео)
          if (!_isPlaying && !_isBuffering && widget.isActive && !_hasError)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Иконка Возобновить
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
                    // Иконка Звука (Mute / Unmute)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onToggleMute?.call();
                      },
                      child: Icon(
                        widget.isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: widget.isMuted ? Colors.white54 : AppColors.primary,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 7. Сердечко при двойном тапе
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

          // 8. Минималистичная линия прогресса внизу
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 2.5,
              child: LinearProgressIndicator(
                value: _progress,
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
