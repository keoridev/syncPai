import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/desktop_title_bar.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../anime_lists/presentation/cubit/anime_list_state.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../kodik/presentation/cubit/kodik_cubit.dart';
import '../../../kodik/presentation/widgets/voiceover_selector_sheet.dart';
import '../../../sync_room/presentation/widgets/sync_room_lobby_sheet.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'player_progress_bar.dart';
import 'player_settings_sheet.dart';

/// Десктопный интерфейс видеоплеера в стиле YouTube / Crunchyroll Web:
/// - Авто-скрытие контролов и курсора мыши при бездействии (3 секунды)
/// - Горячие клавиши (Space, Стрелки, F, M, Escape) с оверлеями обратной связи
/// - Двухколоночный театральный режим (74% видео 16:9 + 26% сайдбар эпизодов)
/// - Нижняя панель управления с толстым интерактивным таймлайном, слайдером громкости,
///   выбором качества, скорости, кнопками «Кинотеатр» и «На весь экран»
class DesktopPlayerLayout extends StatefulWidget {
  final PlayerCubit cubit;
  final PlayerState state;
  final VideoController videoController;
  final VoidCallback onBack;
  final VoidCallback onSaveProgress;
  final Widget? skipOverlay;

  const DesktopPlayerLayout({
    super.key,
    required this.cubit,
    required this.state,
    required this.videoController,
    required this.onBack,
    required this.onSaveProgress,
    this.skipOverlay,
  });

  @override
  State<DesktopPlayerLayout> createState() => _DesktopPlayerLayoutState();
}

class _DesktopPlayerLayoutState extends State<DesktopPlayerLayout> {
  final FocusNode _focusNode = FocusNode();
  Timer? _hideControlsTimer;
  bool _areControlsVisible = true;
  bool _isCursorVisible = true;
  bool _isVolumeSliderHovered = false;
  bool _isHoveringControls = false;
  bool _isDisposed = false;

  // Режимы экрана
  bool _isFullScreen = false;
  bool _isTheaterMode = false; // Скрывает сайдбар серий, расширяя видео

  // Оверлеи визуальной обратной связи клавиатурных шорткатов
  IconData? _flashIcon;
  String? _flashLabel;
  Timer? _flashTimer;

  // Предыдущая громкость для Mute/Unmute
  double _savedVolumeBeforeMute = 100.0;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    _checkNativeFullScreen();
  }

  Future<void> _checkNativeFullScreen() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        final isFs = await windowManager.isFullScreen();
        if (mounted && !_isDisposed) {
          setState(() {
            _isFullScreen = isFs || DesktopTitleBar.isFullScreenNotifier.value;
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _hideControlsTimer?.cancel();
    _flashTimer?.cancel();
    _focusNode.dispose();
    if (_isFullScreen) {
      DesktopTitleBar.isFullScreenNotifier.value = false;
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        try {
          windowManager.setFullScreen(false).catchError((_) {});
          defaultExitNativeFullscreen().catchError((_) {});
        } catch (_) {}
      }
    }
    super.dispose();
  }

  void _triggerFlash({required IconData icon, String? label}) {
    if (_isDisposed) return;
    _flashTimer?.cancel();
    setState(() {
      _flashIcon = icon;
      _flashLabel = label;
    });
    _flashTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && !_isDisposed) {
        setState(() {
          _flashIcon = null;
          _flashLabel = null;
        });
      }
    });
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && !_isDisposed && widget.state.isPlaying && !_isVolumeSliderHovered && !_isHoveringControls) {
        setState(() {
          _areControlsVisible = false;
          _isCursorVisible = false;
        });
      }
    });
  }

  void _showControls() {
    if (_isDisposed) return;
    if (!_areControlsVisible || !_isCursorVisible) {
      setState(() {
        _areControlsVisible = true;
        _isCursorVisible = true;
      });
    }
    _startHideTimer();
  }

  void _onHover(PointerHoverEvent event) {
    _showControls();
  }

  void _onExit(PointerExitEvent event) {
    if (widget.state.isPlaying && !_isHoveringControls) {
      setState(() {
        _areControlsVisible = false;
        _isCursorVisible = true;
      });
    }
  }

  Future<void> _setFullScreen(bool next) async {
    if (_isFullScreen == next) return;
    setState(() {
      _isFullScreen = next;
    });
    DesktopTitleBar.isFullScreenNotifier.value = next;

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        await windowManager.setFullScreen(next);
      } catch (_) {}
      try {
        if (next) {
          await defaultEnterNativeFullscreen();
        } else {
          await defaultExitNativeFullscreen();
        }
      } catch (_) {}
    }

    _triggerFlash(
      icon: next ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded,
      label: next ? 'Полноэкранный режим' : 'Оконный режим',
    );
    _showControls();
  }

  Future<void> _toggleFullScreen() async {
    await _setFullScreen(!_isFullScreen);
  }

  void _toggleMute() {
    final curVol = widget.state.volume;
    if (curVol > 0.01) {
      _savedVolumeBeforeMute = curVol;
      widget.cubit.setVolume(0.0);
      _triggerFlash(icon: Icons.volume_off_rounded, label: 'Звук выключен');
    } else {
      final restore = _savedVolumeBeforeMute > 0.05 ? _savedVolumeBeforeMute : 100.0;
      widget.cubit.setVolume(restore);
      _triggerFlash(
        icon: Icons.volume_up_rounded,
        label: '${restore.toInt()}%',
      );
    }
  }

  KeyEventResult _handleDesktopKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;

      // Space: Play / Pause
      if (key == LogicalKeyboardKey.space) {
        widget.cubit.togglePlayPause();
        _triggerFlash(
          icon: widget.state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        );
        return KeyEventResult.handled;
      }

      // Стрелка вправо: +10 сек
      if (key == LogicalKeyboardKey.arrowRight) {
        widget.cubit.seekRelative(10);
        _triggerFlash(icon: Icons.forward_10_rounded, label: '+10 сек');
        return KeyEventResult.handled;
      }

      // Стрелка влево: -10 сек
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.cubit.seekRelative(-10);
        _triggerFlash(icon: Icons.replay_10_rounded, label: '-10 сек');
        return KeyEventResult.handled;
      }

      // Стрелка вверх: громкость +5%
      if (key == LogicalKeyboardKey.arrowUp) {
        final newVol = (widget.state.volume + 5.0).clamp(0.0, 100.0);
        widget.cubit.setVolume(newVol);
        _triggerFlash(
          icon: newVol > 50 ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          label: '${newVol.toInt()}%',
        );
        return KeyEventResult.handled;
      }

      // Стрелка вниз: громкость -5%
      if (key == LogicalKeyboardKey.arrowDown) {
        final newVol = (widget.state.volume - 5.0).clamp(0.0, 100.0);
        widget.cubit.setVolume(newVol);
        _triggerFlash(
          icon: newVol == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
          label: '${newVol.toInt()}%',
        );
        return KeyEventResult.handled;
      }

      // KeyF: Полноэкранный режим
      if (key == LogicalKeyboardKey.keyF) {
        _toggleFullScreen();
        return KeyEventResult.handled;
      }

      // KeyM: Mute / Unmute
      if (key == LogicalKeyboardKey.keyM) {
        _toggleMute();
        return KeyEventResult.handled;
      }

      // Escape: Выход из фуллскрина или выход из плеера
      if (key == LogicalKeyboardKey.escape) {
        if (_isFullScreen) {
          _setFullScreen(false);
        } else {
          widget.onBack();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleDesktopKeyEvent,
      child: MouseRegion(
        cursor: _isCursorVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: _onHover,
        onExit: _onExit,
        child: Container(
          color: const Color(0xFF0A0B0E),
          child: _isFullScreen
              ? _buildVideoSurface(isFullScreen: true)
              : _buildTwoColumnLayout(),
        ),
      ),
    );
  }

  /// Двухколоночный десктопный макет (Театральный режим + Сайдбар эпизодов)
  Widget _buildTwoColumnLayout() {
    final showSidebar = !_isTheaterMode;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Левая колонка: 74% ширины (или 100% в режиме Кинотеатр)
        Expanded(
          flex: showSidebar ? 74 : 100,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Шапка с кнопкой «Назад» и бейджем текущего режима
                _buildDesktopTopBar(),
                const SizedBox(height: 14),

                // Видеоконтейнер строго 16:9 со скруглением и мягкой кинематографичной тенью
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: _buildVideoSurface(isFullScreen: false),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Метаданные под плеером: название аниме, номер серии, переключатель озвучки, закладки и совместный просмотр
                _buildMetadataPanel(),
              ],
            ),
          ),
        ),

        // Тонкий вертикальный разделитель
        if (showSidebar)
          Container(
            width: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),

        // Правая колонка: 26% ширины — стеклянный сайдбар эпизодов
        if (showSidebar)
          Expanded(
            flex: 26,
            child: _buildEpisodesSidebar(),
          ),
      ],
    );
  }

  /// Верхняя плашка десктопа с кнопкой Назад и хлебными крошками
  Widget _buildDesktopTopBar() {
    final title = widget.state.title;
    final ep = widget.state.episode;

    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: widget.onBack,
          tooltip: 'Назад к тайтлу (Esc)',
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Серия ${ep.episode}${ep.name != null && ep.name!.isNotEmpty ? ' — ${ep.name}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (widget.state.isSyncRoom)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  widget.state.roomCode ?? 'Sync Room',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Полотно видеоплеера с кликами мыши, оверлеями обратной связи и нижней панелью контролов
  Widget _buildVideoSurface({required bool isFullScreen}) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Полотно libmpv видео на черном фоне
          Center(
            child: Video(
              controller: widget.videoController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.black,
            ),
          ),

          // 2. Прозрачный слой захвата мыши и жестов поверх нативного окна Video
          Positioned.fill(
            child: MouseRegion(
              opaque: true,
              cursor: _isCursorVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
              onHover: (_) => _showControls(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  widget.cubit.togglePlayPause();
                  _triggerFlash(
                    icon: widget.state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  );
                },
                onDoubleTap: _toggleFullScreen,
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // 3. Индикатор буферизации
          if (widget.state.isBuffering && widget.state.errorMessage == null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            ),

          // 4. Всплывающий оверлей шортката (Space, Громкость, Перемотка)
          if (_flashIcon != null)
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _flashIcon != null ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_flashIcon, color: Colors.white, size: 44),
                      if (_flashLabel != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _flashLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // 5. Плавающий баннер пропуска опенинга / эндинга
          if (widget.skipOverlay != null) widget.skipOverlay!,

          // 6. Нижняя панель управления (Control Bar) в стиле YouTube Web
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_areControlsVisible,
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() => _isHoveringControls = true);
                    _showControls();
                  },
                  onExit: (_) {
                    setState(() => _isHoveringControls = false);
                    _startHideTimer();
                  },
                  child: _buildDesktopControlBar(isFullScreen: isFullScreen),
                ),
              ),
            ),
          ),

          // 7. Информативный верхний бар в Fullscreen (стрелка назад + название аниме и номер серии)
          if (isFullScreen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _areControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_areControlsVisible,
                  child: MouseRegion(
                    onEnter: (_) {
                      setState(() => _isHoveringControls = true);
                      _showControls();
                    },
                    onExit: (_) {
                      setState(() => _isHoveringControls = false);
                      _startHideTimer();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.80),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 18, 24, 24),
                      child: Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: () => _setFullScreen(false),
                            tooltip: 'Выйти из полноэкранного режима (Esc / F)',
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              '${widget.state.title.displayTitle} • Серия ${widget.state.episode.episode}'
                              '${widget.state.episode.name != null && widget.state.episode.name!.isNotEmpty ? ' — ${widget.state.episode.name}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 8,
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
            ),
        ],
      ),
    );
  }

  /// Нижний десктопный Control Bar в стиле YouTube Web (единый бар без дублирования таймкодов)
  Widget _buildDesktopControlBar({required bool isFullScreen}) {
    final state = widget.state;
    final allEpisodes = state.title.episodes;
    final curIdx = allEpisodes.indexWhere((e) => e.episode == state.episode.episode);
    final hasNext = curIdx >= 0 && curIdx < allEpisodes.length - 1;

    final curStr = _formatDuration(state.position);
    final totalStr = _formatDuration(state.duration);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Первая строка: только одна полоса прогресса (SeekBar) на всю ширину без цифр под ней
          PlayerProgressBar(
            position: state.position,
            duration: state.duration,
            buffer: state.buffer,
            onSeek: (pos) => widget.cubit.seek(pos),
            opening: state.effectiveOpening,
            ending: state.effectiveEnding,
            heatmap: state.heatmap,
            isBuffering: state.isBuffering,
            showTimestamps: false,
          ),
          const SizedBox(height: 2),

          // 2. Вторая строка: единый ряд контролов (слева и справа)
          Row(
            children: [
              // Кнопка Play/Pause (36px)
              IconButton(
                iconSize: 32,
                tooltip: state.isPlaying ? 'Пауза (Space)' : 'Воспроизведение (Space)',
                icon: Icon(
                  state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  widget.cubit.togglePlayPause();
                  _triggerFlash(
                    icon: state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  );
                },
              ),

              // Кнопка Следующая серия
              IconButton(
                iconSize: 22,
                tooltip: hasNext ? 'Следующая серия' : 'Последняя серия',
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: hasNext ? Colors.white : Colors.white24,
                ),
                onPressed: hasNext
                    ? () => widget.cubit.switchEpisode(allEpisodes[curIdx + 1])
                    : null,
              ),

              const SizedBox(width: 4),

              // Иконка звука + горизонтальный Slider громкости
              MouseRegion(
                onEnter: (_) => setState(() => _isVolumeSliderHovered = true),
                onExit: (_) => setState(() => _isVolumeSliderHovered = false),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      iconSize: 22,
                      tooltip: 'Звук (M)',
                      icon: Icon(
                        state.volume <= 0.01
                            ? Icons.volume_off_rounded
                            : (state.volume > 50 ? Icons.volume_up_rounded : Icons.volume_down_rounded),
                        color: Colors.white,
                      ),
                      onPressed: _toggleMute,
                    ),
                    SizedBox(
                      width: 90,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: state.volume.clamp(0.0, 100.0),
                          min: 0.0,
                          max: 100.0,
                          onChanged: (val) => widget.cubit.setVolume(val),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Крупный таймкод 01:58 / 24:00
              Text(
                '$curStr / $totalStr',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),

              const Spacer(),

              // Выбор скорости воспроизведения (1.0x)
              PopupMenuButton<double>(
                tooltip: 'Скорость',
                initialValue: state.playbackRate,
                onSelected: (rate) => widget.cubit.setPlaybackRate(rate),
                color: AppColors.surfaceElevated,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${state.playbackRate.toStringAsFixed(state.playbackRate.truncateToDouble() == state.playbackRate ? 0 : 2)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                itemBuilder: (ctx) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                    .map(
                      (r) => PopupMenuItem(
                        value: r,
                        child: Text(
                          '${r}x',
                          style: TextStyle(
                            color: state.playbackRate == r ? AppColors.primary : Colors.white,
                            fontWeight: state.playbackRate == r ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(width: 8),

              // Выбор качества (1080p / 720p / 480p)
              PopupMenuButton<PlayerQuality>(
                tooltip: 'Качество видео',
                initialValue: state.selectedQuality,
                onSelected: (q) => widget.cubit.changeQuality(q),
                color: AppColors.surfaceElevated,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _qualityLabel(state.selectedQuality),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                itemBuilder: (ctx) => PlayerQuality.values
                    .map(
                      (q) => PopupMenuItem(
                        value: q,
                        child: Text(
                          _qualityLabel(q),
                          style: TextStyle(
                            color: state.selectedQuality == q ? AppColors.primary : Colors.white,
                            fontWeight: state.selectedQuality == q ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(width: 8),

              // Кнопка Настройки (шторка плеера)
              IconButton(
                tooltip: 'Настройки плеера',
                icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 21),
                onPressed: () => PlayerSettingsSheet.show(
                  context,
                  cubit: widget.cubit,
                  state: widget.state,
                ),
              ),

              // Кнопка «Кинотеатр» (скрывает сайдбар серий)
              if (!isFullScreen)
                IconButton(
                  tooltip: _isTheaterMode ? 'Стандартный вид' : 'Театральный режим',
                  icon: Icon(
                    _isTheaterMode ? Icons.crop_16_9_rounded : Icons.crop_landscape_rounded,
                    color: _isTheaterMode ? AppColors.primary : Colors.white,
                    size: 21,
                  ),
                  onPressed: () {
                    setState(() {
                      _isTheaterMode = !_isTheaterMode;
                    });
                  },
                ),

              // Кнопка «На весь экран» (F)
              IconButton(
                tooltip: isFullScreen ? 'Выйти из полноэкранного режима (F)' : 'На весь экран (F)',
                icon: Icon(
                  isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: _toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Метаданные и кнопки действий под плеером
  Widget _buildMetadataPanel() {
    final title = widget.state.title;
    final ep = widget.state.episode;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF13151D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.displayTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Серия ${ep.episode}${ep.name != null && ep.name!.isNotEmpty ? ' — ${ep.name}' : ''}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Панель кнопок: Озвучка, В закладки, Смотреть вместе
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  // Переключатель озвучки
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(Icons.record_voice_over_rounded, size: 16, color: AppColors.primary),
                    label: Text(
                      _currentVoiceoverTitle(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => VoiceoverSelectorSheet.show(
                      context,
                      episodeNumber: ep.episode,
                      onVoiceoverChanged: (studio) => widget.cubit.switchVoiceoverStudio(studio),
                    ),
                  ),

                  // Кнопка «В закладки»
                  _buildBookmarkButton(title),

                  // Кнопка «Смотреть вместе» с динамическим расчетом контраста текста
                  Builder(
                    builder: (context) {
                      final onAccent = AppColors.onColor(AppColors.primary);
                      return FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: onAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(Icons.group_add_rounded, size: 18, color: onAccent),
                        label: Text(
                          'Смотреть вместе',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: onAccent,
                          ),
                        ),
                        onPressed: () {
                          SyncRoomLobbySheet.show(
                            context,
                            title: title,
                            episode: ep,
                            initialQuality: widget.state.selectedQuality,
                            onStartPlayback: (room, isHost) {
                              // Если уже находимся в плеере, обновляем сессию
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          if (title.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              title.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Кнопка управления закладками тайтла
  Widget _buildBookmarkButton(AnimeTitle title) {
    if (!getIt.isRegistered<AnimeListCubit>()) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AnimeListCubit, AnimeListState>(
      bloc: getIt<AnimeListCubit>(),
      builder: (context, listState) {
        final entry = listState.getEntryFor(title.id);
        final isBookmarked = entry != null;

        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: isBookmarked ? AppColors.primary : Colors.white,
            side: BorderSide(
              color: isBookmarked ? AppColors.primary : Colors.white.withValues(alpha: 0.18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(
            isBookmarked ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
            size: 16,
            color: isBookmarked ? AppColors.primary : Colors.white,
          ),
          label: Text(
            isBookmarked ? (entry.status.labelRu) : 'В закладки',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          onPressed: () {
            final cubit = getIt<AnimeListCubit>();
            if (isBookmarked) {
              cubit.removeAnime(title.id);
            } else {
              cubit.setAnimeStatus(
                animeId: title.id,
                titleRu: title.russianTitle,
                posterUrl: title.posterMedium.isNotEmpty ? title.posterMedium : title.posterSmall,
                status: AnimeListStatus.watching,
                lastEpisode: widget.state.episode.episode,
                positionMs: widget.state.position.inMilliseconds,
                episodesTotal: title.episodesTotal,
              );
            }
          },
        );
      },
    );
  }

  /// Правая стеклянная колонка: Сайдбар со всеми сериями тайтла
  Widget _buildEpisodesSidebar() {
    final allEpisodes = widget.state.title.episodes;
    final curEp = widget.state.episode.episode;

    return Container(
      color: const Color(0xFF0F1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка сайдбара
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(
              children: [
                Icon(Icons.format_list_numbered_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Эпизоды',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${allEpisodes.length} серий',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Список серий с превью и номерами
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: allEpisodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = allEpisodes[index];
                final isCurrent = item.episode == curEp;

                return InkWell(
                  onTap: () {
                    if (!isCurrent) {
                      widget.cubit.switchEpisode(item);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.primary.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.primary.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.06),
                        width: isCurrent ? 1.4 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Превью серии
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 84,
                            height: 48,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (item.previewUrl != null && item.previewUrl!.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: wrapCorsSafeUrl(item.previewUrl!),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: const Color(0xFF1B1D26),
                                      child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 20),
                                    ),
                                  )
                                else
                                  Container(
                                    color: const Color(0xFF1B1D26),
                                    child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 20),
                                  ),
                                if (isCurrent)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: Center(
                                      child: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 24),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Номер и название серии
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Серия ${item.episode}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent ? AppColors.primary : Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'СЕЙЧАС',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (item.name != null && item.name!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.name!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                              if (item.opening != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Опенинг: ${item.opening!.formattedRange}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _qualityLabel(PlayerQuality q) {
    switch (q) {
      case PlayerQuality.fhd:
        return '1080p';
      case PlayerQuality.hd:
        return '720p';
      case PlayerQuality.sd:
        return '480p';
    }
  }

  String _currentVoiceoverTitle() {
    if (getIt.isRegistered<KodikCubit>()) {
      final kState = getIt<KodikCubit>().state;
      return kState.activeVoiceoverTitle;
    }
    if (widget.state.currentTranslation != null) {
      return widget.state.currentTranslation!.studioName;
    }
    return 'AniLibria';
  }
}
