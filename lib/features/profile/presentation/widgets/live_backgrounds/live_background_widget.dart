import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../../../core/network/image_cors_helper.dart';
import 'anime_procedural_painters.dart';
import 'cyberpunk_grid_painter.dart';
import 'matrix_rain_painter.dart';
import 'sakura_petals_painter.dart';
import 'snowfall_painter.dart';
import 'starfield_painter.dart';

/// Универсальный виджет анимированных фонов профиля (Live Backgrounds & Video):
/// 1. Процедурные шейдерные холсты (Matrix Rain, Sakura Petals, Cyberpunk Grid, Starfield)
/// 2. Зацикленные фоновые видео без звука (MP4 / WebM через media_kit)
/// 3. Локальные и удаленные GIF / высококачественные арты
/// 4. Все анимации строго изолированы через [RepaintBoundary] для 60-120 FPS.
class LiveBackgroundWidget extends StatefulWidget {
  final String? backgroundId;
  final String? assetOrUrl;
  final String? fallbackImageUrl;
  final List<Color>? fallbackGradient;
  final BoxFit fit;
  final bool isPaused;

  const LiveBackgroundWidget({
    super.key,
    this.backgroundId,
    this.assetOrUrl,
    this.fallbackImageUrl,
    this.fallbackGradient,
    this.fit = BoxFit.cover,
    this.isPaused = false,
  });

  @override
  State<LiveBackgroundWidget> createState() => _LiveBackgroundWidgetState();
}

class _LiveBackgroundWidgetState extends State<LiveBackgroundWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animController;
  Player? _videoPlayer;
  VideoController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (_isProcedural && !isTest) {
      _animController.repeat();
    }

    _setupVideoIfApplicable();
  }

  bool get _isProcedural {
    final bgId = (widget.backgroundId ?? '').toLowerCase();
    final media = (widget.assetOrUrl ?? '').toLowerCase();
    return bgId.contains('matrix') ||
        media == 'matrix' ||
        bgId.contains('sakura') ||
        media == 'sakura' ||
        bgId.contains('snow') ||
        bgId.contains('winter') ||
        bgId.contains('frost') ||
        media == 'snow' ||
        media == 'snowfall' ||
        bgId.contains('cyberpunk') ||
        media == 'cyberpunk' ||
        bgId.contains('space') ||
        bgId.contains('void') ||
        bgId.contains('star') ||
        media == 'starfield' ||
        bgId.contains('solo_leveling') ||
        media == 'solo_leveling' ||
        bgId.contains('titan') ||
        media == 'titan_lightning' ||
        bgId.contains('black_flash') ||
        bgId.contains('jujutsu') ||
        media == 'black_flash' ||
        bgId.contains('bleach') ||
        media == 'bleach_bankai' ||
        bgId.contains('evangelion') ||
        media == 'evangelion_at';
  }

  @override
  void didUpdateWidget(covariant LiveBackgroundWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

    if (widget.isPaused != oldWidget.isPaused) {
      if (widget.isPaused) {
        _videoPlayer?.pause();
        if (_animController.isAnimating) _animController.stop();
      } else {
        _videoPlayer?.play();
        if (_isProcedural && !isTest && !_animController.isAnimating) {
          _animController.repeat();
        }
      }
    }

    if (_isProcedural && !isTest) {
      if (!widget.isPaused && !_animController.isAnimating) {
        _animController.repeat();
      }
    } else {
      if (_animController.isAnimating) _animController.stop();
    }

    if (widget.assetOrUrl != oldWidget.assetOrUrl ||
        widget.backgroundId != oldWidget.backgroundId) {
      _cleanupVideo();
      _setupVideoIfApplicable();
    }
  }

  void _setupVideoIfApplicable() {
    final media = (widget.assetOrUrl ?? widget.backgroundId ?? '').trim().toLowerCase();
    final isVideo = media.endsWith('.mp4') || media.endsWith('.webm') || media.endsWith('.mov');

    if (!isVideo) return;

    try {
      _videoPlayer = Player();
      _videoController = VideoController(_videoPlayer!);
      _videoPlayer!.setVolume(0.0);
      _videoPlayer!.setPlaylistMode(PlaylistMode.loop);

      final path = (widget.assetOrUrl ?? widget.backgroundId!).trim();
      final isNetwork = path.startsWith('http://') || path.startsWith('https://');

      if (isNetwork) {
        _videoPlayer!.open(Media(path));
      } else {
        final cleanPath = path.replaceFirst('file://', '');
        _videoPlayer!.open(Media(cleanPath));
      }

      setState(() => _isVideoInitialized = true);
    } catch (_) {
      _cleanupVideo();
    }
  }

  void _cleanupVideo() {
    _videoPlayer?.stop();
    _videoPlayer?.dispose();
    _videoPlayer = null;
    _videoController = null;
    _isVideoInitialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _animController.stop();
      _videoPlayer?.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
      _videoPlayer?.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    _cleanupVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgId = (widget.backgroundId ?? '').toLowerCase();
    final media = (widget.assetOrUrl ?? '').trim();

    // 1. Если инициализировано видео — воспроизводим зацикленный mp4
    if (_isVideoInitialized && _videoController != null) {
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Статичный резервный кадр при загрузке или отсутствии сети
            if (widget.fallbackImageUrl != null && widget.fallbackImageUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: wrapCorsSafeUrl(widget.fallbackImageUrl!),
                fit: widget.fit,
                placeholder: (_, __) => _buildFallbackGradient(),
                errorWidget: (_, __, ___) => _buildFallbackGradient(),
              )
            else
              _buildFallbackGradient(),

            // Фоновый видео-луп
            SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                child: SizedBox(
                  width: _videoController!.player.state.width?.toDouble() ?? 1280,
                  height: _videoController!.player.state.height?.toDouble() ?? 720,
                  child: Video(
                    controller: _videoController!,
                    controls: NoVideoControls,
                  ),
                ),
              ),
            ),

            // Темный градиент-фильтр поверх видео для сохранения читаемости текста
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Процедурный живой фон: Эффект «Матрица»
    if (bgId.contains('matrix') || media == 'matrix') {
      return RepaintBoundary(
        child: Container(
          color: const Color(0xFF030D06),
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: MatrixRainPainter(
                animationValue: _animController.value,
                primaryColor: const Color(0xFF00FF66),
              ),
            ),
          ),
        ),
      );
    }

    // 3. Процедурный живой фон: «Падающая сакура»
    if (bgId.contains('sakura') || media == 'sakura') {
      return RepaintBoundary(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF260D1E),
                Color(0xFF160914),
                Color(0xFF0F060E),
              ],
            ),
          ),
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: SakuraPetalsPainter(
                animationValue: _animController.value,
                petalColor: const Color(0xFFFF76AC),
              ),
            ),
          ),
        ),
      );
    }

    // 3.1. Процедурный живой фон: «Падающий снег» (Live Snowfall)
    if (bgId.contains('snow') || bgId.contains('winter') || bgId.contains('frost') || media == 'snow' || media == 'snowfall') {
      return RepaintBoundary(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0B1626),
                Color(0xFF14243B),
                Color(0xFF0D1724),
              ],
            ),
          ),
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: LiveSnowfallPainter(
                animationValue: _animController.value,
                snowColor: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    // 4. Процедурный живой фон: «Киберпанк 3D-сетка»
    if (bgId.contains('cyber') || bgId.contains('synth') || media == 'cyberpunk') {
      return RepaintBoundary(
        child: Container(
          color: const Color(0xFF090614),
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: CyberpunkGridPainter(
                animationValue: _animController.value,
                gridColor: const Color(0xFF00F0FF),
                horizonColor: const Color(0xFFFF007F),
              ),
            ),
          ),
        ),
      );
    }

    // 5. Процедурный живой фон: «Звездное небо / Космос»
    if (bgId.contains('space') || bgId.contains('void') || bgId.contains('star') || media == 'starfield') {
      return RepaintBoundary(
        child: Container(
          color: const Color(0xFF06060F),
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: StarfieldPainter(
                animationValue: _animController.value,
              ),
            ),
          ),
        ),
      );
    }

    // 6. Процедурный живой фон: Solo Leveling (Теневой Монарх)
    if (bgId.contains('solo_leveling') || media == 'solo_leveling') {
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: SoloLevelingShadowPainter(
              animationValue: _animController.value,
            ),
          ),
        ),
      );
    }

    // 7. Процедурный живой фон: Атака Титанов (Золотая молния)
    if (bgId.contains('titan') || media == 'titan_lightning') {
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: TitanLightningPainter(
              animationValue: _animController.value,
            ),
          ),
        ),
      );
    }

    // 8. Процедурный живой фон: Магическая Битва (Black Flash)
    if (bgId.contains('black_flash') || bgId.contains('jujutsu') || media == 'black_flash') {
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: BlackFlashPainter(
              animationValue: _animController.value,
            ),
          ),
        ),
      );
    }

    // 9. Процедурный живой фон: Блич (Банкай / Рэйацу)
    if (bgId.contains('bleach') || media == 'bleach_bankai') {
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: BleachReiatsuPainter(
              animationValue: _animController.value,
            ),
          ),
        ),
      );
    }

    // 10. Процедурный живой фон: Евангелион (A.T. Field)
    if (bgId.contains('evangelion') || media == 'evangelion_at') {
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: EvangelionAtFieldPainter(
              animationValue: _animController.value,
            ),
          ),
        ),
      );
    }

    // 6. Локальное изображение или GIF
    final isLocal = media.isNotEmpty &&
        !media.startsWith('http') &&
        (media.startsWith('/') || media.contains(':\\') || media.startsWith('file:'));

    if (isLocal) {
      final clean = media.replaceFirst('file://', '');
      return RepaintBoundary(
        child: Image.file(
          File(clean),
          fit: widget.fit,
          errorBuilder: (_, __, ___) => _buildFallbackGradient(),
        ),
      );
    }

    // 7. Сетевое изображение или GIF
    if (media.startsWith('http')) {
      return RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: wrapCorsSafeUrl(media),
          fit: widget.fit,
          filterQuality: FilterQuality.high,
          errorWidget: (_, __, ___) => _buildFallbackGradient(),
          placeholder: (_, __) => _buildFallbackGradient(),
        ),
      );
    }

    // 8. Дефолтный градиент
    return _buildFallbackGradient();
  }

  Widget _buildFallbackGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.fallbackGradient ??
              const [
                Color(0xFF1E1F24),
                Color(0xFF121316),
              ],
        ),
      ),
    );
  }
}
