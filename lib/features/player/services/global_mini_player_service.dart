import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../app/router/app_router.dart';
import '../presentation/cubit/player_cubit.dart';
import '../presentation/cubit/player_state.dart';

/// Глобальный сервис плавающего мини-плеера (In-App Picture-in-Picture),
/// работающий поверх всех экранов приложения (Каталог, Детали, Списки, Комнаты, Профиль).
class GlobalMiniPlayerService extends ChangeNotifier {
  GlobalMiniPlayerService._();
  static final GlobalMiniPlayerService instance = GlobalMiniPlayerService._();

  PlayerCubit? _cubit;
  VideoController? _videoController;
  VoidCallback? _onSaveProgress;
  bool _isMinimized = false;
  bool _isExpanding = false;

  Offset? _offset;
  double _scale = 1.0;

  PlayerCubit? get cubit => _cubit;
  VideoController? get videoController => _videoController;
  bool get isMinimized => _isMinimized && _cubit != null && _videoController != null;
  bool get isExpanding => _isExpanding;
  Offset? get offset => _offset;
  double get scale => _scale;

  void _notifySafely() {
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      binding.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void updateTransform({Offset? offset, double? scale}) {
    if (offset != null) _offset = offset;
    if (scale != null) _scale = scale.clamp(0.75, 1.85);
    _notifySafely();
  }

  void increaseScale() {
    HapticFeedback.lightImpact();
    _scale = (_scale + 0.18).clamp(0.75, 1.85);
    _notifySafely();
  }

  void decreaseScale() {
    HapticFeedback.lightImpact();
    _scale = (_scale - 0.18).clamp(0.75, 1.85);
    _notifySafely();
  }

  void cycleScale() {
    HapticFeedback.lightImpact();
    if (_scale < 1.15) {
      _scale = 1.32;
    } else if (_scale < 1.45) {
      _scale = 1.58;
    } else {
      _scale = 0.85;
    }
    _notifySafely();
  }

  /// Сворачивает активный плеер в глобальное плавающее окно
  void minimize({
    required PlayerCubit cubit,
    required VideoController videoController,
    VoidCallback? onSaveProgress,
  }) {
    if (_cubit != null && _cubit != cubit) {
      _cubit?.close();
    }
    _cubit = cubit;
    _videoController = videoController;
    _onSaveProgress = onSaveProgress;
    _isMinimized = true;
    _isExpanding = false;
    _notifySafely();
  }

  /// Проверяет, соответствует ли активная сессия мини-плеера запрашиваемому тайтлу
  bool hasSessionFor(int titleId, int episodeNum) {
    if (_cubit == null || _videoController == null) return false;
    final activeTitle = _cubit!.state.title;
    final matchesTitle = activeTitle.id == titleId ||
        (activeTitle.shikimoriId != null && activeTitle.shikimoriId == titleId);
    return matchesTitle && _cubit!.state.episode.episode == episodeNum;
  }

  /// Временно ставит на паузу и скрывает плавающий мини-плеер (например, при переходе в лобби)
  void pauseAndHide() {
    if (_cubit == null) return;
    try {
      _cubit?.player.pause();
    } catch (_) {}
    _isMinimized = false;
    _notifySafely();
  }

  /// Забирает существующую сессию обратно в полноэкранный PlayerScreen без перезагрузки потока
  (PlayerCubit, VideoController)? claimSession() {
    if (_cubit == null || _videoController == null) return null;
    final result = (_cubit!, _videoController!);
    _isMinimized = false;
    _isExpanding = false;
    _cubit = null;
    _videoController = null;
    _onSaveProgress = null;
    _notifySafely();
    return result;
  }

  /// Разворачивает мини-плеер обратно на полный экран
  void expandToFullscreen() {
    if (_cubit == null || _videoController == null) return;
    HapticFeedback.mediumImpact();
    final state = _cubit!.state;
    _isMinimized = false;
    _isExpanding = true;
    _notifySafely();

    appRouter.pushNamed(
      'player',
      extra: {
        'title': state.title,
        'episode': state.episode,
        'quality': state.selectedQuality,
        'roomCode': state.roomCode,
        'isHost': state.isHost,
        'reuseMiniPlayer': true,
      },
    );
  }

  /// Полностью закрывает и освобождает ресурсы мини-плеера
  Future<void> close() async {
    if (_cubit == null) return;
    _onSaveProgress?.call();
    final oldCubit = _cubit;
    _cubit = null;
    _videoController = null;
    _onSaveProgress = null;
    _isMinimized = false;
    _isExpanding = false;
    _notifySafely();
    await oldCubit?.close();
  }
}

/// Глобальный виджет-оверлей плавающего мини-плеера,
/// монтируемый в корневой Stack приложения (MaterialApp.router builder).
class GlobalMiniPlayerOverlay extends StatefulWidget {
  const GlobalMiniPlayerOverlay({super.key});

  @override
  State<GlobalMiniPlayerOverlay> createState() => _GlobalMiniPlayerOverlayState();
}

class _GlobalMiniPlayerOverlayState extends State<GlobalMiniPlayerOverlay> {
  double _baseScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlobalMiniPlayerService.instance,
      builder: (context, _) {
        final service = GlobalMiniPlayerService.instance;
        if (!service.isMinimized || service.cubit == null || service.videoController == null) {
          return const SizedBox.shrink();
        }

        final cubit = service.cubit!;
        final controller = service.videoController!;
        final screenSize = MediaQuery.sizeOf(context);
        final padding = MediaQuery.paddingOf(context);

        final scale = service.scale;
        final isDesktopScreen = screenSize.width >= 900;
        final defaultWidth = isDesktopScreen ? 280.0 : 204.0;
        final baseW = (defaultWidth * scale).clamp(156.0, screenSize.width - 20.0);
        final baseH = baseW * 9.0 / 16.0;

        final defaultLeft = screenSize.width - baseW - 14.0;
        final defaultTop = screenSize.height - baseH - padding.bottom - 88.0;

        final maxLeft = (screenSize.width - baseW - 8.0).clamp(8.0, double.infinity);
        final maxTop = (screenSize.height - baseH - padding.bottom - 8.0)
            .clamp(padding.top + 8.0, double.infinity);

        final currentLeft = (service.offset?.dx ?? defaultLeft).clamp(8.0, maxLeft);
        final currentTop = (service.offset?.dy ?? defaultTop).clamp(padding.top + 8.0, maxTop);

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: currentLeft,
              top: currentTop,
                    width: baseW,
                    height: baseH,
                    child: Material(
                      type: MaterialType.transparency,
                      child: BlocProvider.value(
                        value: cubit,
                        child: BlocBuilder<PlayerCubit, PlayerState>(
                          builder: (context, state) {
                            final progress = state.duration.inMilliseconds > 0
                                ? (state.position.inMilliseconds / state.duration.inMilliseconds)
                                    .clamp(0.0, 1.0)
                                : 0.0;

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (_) {
                                _baseScale = service.scale;
                              },
                              onScaleUpdate: (details) {
                                final nextScale = details.pointerCount > 1
                                    ? (_baseScale * details.scale).clamp(0.75, 1.85)
                                    : service.scale;
                                final nextOffset = Offset(
                                  currentLeft + details.focalPointDelta.dx,
                                  currentTop + details.focalPointDelta.dy,
                                );
                                service.updateTransform(
                                  offset: nextOffset,
                                  scale: nextScale,
                                );
                              },
                              onDoubleTap: () => service.expandToFullscreen(),
                              child: Container(
                                width: baseW,
                                height: baseH,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E1017),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.24),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Видеопоток
                                    Video(
                                      controller: controller,
                                      controls: NoVideoControls,
                                      fit: state.videoFit,
                                    ),

                                    // Мягкое затемнение сверху и снизу для читаемости кнопок
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.black.withValues(alpha: 0.72),
                                                Colors.transparent,
                                                Colors.transparent,
                                                Colors.black.withValues(alpha: 0.82),
                                              ],
                                              stops: const [0.0, 0.34, 0.66, 1.0],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Верхняя панель: Развернуть, Название, [Уменьшить/Увеличить на ПК], Закрыть
                                    Positioned(
                                      top: 5,
                                      left: 6,
                                      right: 6,
                                      child: Row(
                                        children: [
                                          _MiniIconButton(
                                            icon: Icons.open_in_full_rounded,
                                            tooltip: 'Развернуть на весь экран',
                                            onTap: () => service.expandToFullscreen(),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () => service.expandToFullscreen(),
                                              child: Text(
                                                state.title.displayTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10.0,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          if (isDesktopScreen) ...[
                                            _MiniIconButton(
                                              icon: Icons.remove_rounded,
                                              tooltip: 'Уменьшить окно',
                                              onTap: () => service.decreaseScale(),
                                            ),
                                            const SizedBox(width: 3),
                                            _MiniIconButton(
                                              icon: Icons.add_rounded,
                                              tooltip: 'Увеличить окно',
                                              onTap: () => service.increaseScale(),
                                            ),
                                            const SizedBox(width: 3),
                                          ],
                                          _MiniIconButton(
                                            icon: Icons.close_rounded,
                                            tooltip: 'Закрыть плеер',
                                            onTap: () => service.close(),
                                          ),
                                        ],
                                      ),
                                    ),

                              // Центральные кнопки: -10с, Play/Pause (или загрузка), +10с
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        cubit.seekRelative(-10);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.replay_10_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        cubit.togglePlayPause();
                                      },
                                      child: Container(
                                        width: 34,
                                        height: 34,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.72),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.35),
                                            width: 1.1,
                                          ),
                                        ),
                                        child: state.isBuffering
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.0,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : Icon(
                                                state.isPlaying
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        cubit.seekRelative(10);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.forward_10_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Нижняя строка: Серия + ручка изменения размера в правом нижнем углу
                              Positioned(
                                bottom: 5,
                                left: 8,
                                right: 24,
                                child: Text(
                                  'Серия ${state.episode.episode}${state.episode.name != null && state.episode.name!.isNotEmpty ? ' — ${state.episode.name}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                              // Ручка изменения размера перетаскиванием за правый нижний угол
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (details) {
                                    final delta = details.delta.dx;
                                    final nextW = (baseW + delta).clamp(156.0, screenSize.width - 20.0);
                                    final nextScale = (nextW / defaultWidth).clamp(0.75, 1.85);
                                    service.updateTransform(scale: nextScale);
                                  },
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.bottomRight,
                                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                                    child: Icon(
                                      Icons.south_east_rounded,
                                      size: 12,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ),

                              // Линия прогресса в самом низу мини-окна
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 2.5,
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4.5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 0.8,
            ),
          ),
          child: Icon(
            icon,
            size: 13,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

