import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/sync_room/domain/repositories/sync_room_repository.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'package:sync_pai/features/player/services/pip_service.dart';
import '../widgets/auto_next_episode_banner.dart';
import '../widgets/double_tap_seek_overlay.dart';
import '../widgets/floating_reactions_layer.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/quick_phrase_toast_widget.dart';
import '../widgets/twitch_chat_overlay.dart';
import '../widgets/danmaku_overlay_layer.dart';
import '../widgets/pulsing_radar_waiting_widget.dart';
import '../widgets/watch_party_stats_sheet.dart';

class PlayerScreen extends StatefulWidget {
  final AnimeTitle title;
  final EpisodeItem initialEpisode;
  final PlayerQuality initialQuality;
  final String? roomCode;
  final bool isHost;
  final Duration? initialPosition;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.initialEpisode,
    this.initialQuality = PlayerQuality.fhd,
    this.roomCode,
    this.isHost = false,
    this.initialPosition,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final PlayerCubit _cubit;
  late final VideoController _videoController;
  StreamSubscription<bool>? _pipSubscription;
  bool _isInPip = false;
  bool _isMiniPlayer = false;
  Offset? _miniPlayerOffset;
  double _miniPlayerScale = 1.0;
  double _baseScale = 1.0;

  void _minimizePlayer() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() {
      _isMiniPlayer = true;
    });
  }

  void _restorePlayer() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      _isMiniPlayer = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Полноэкранный режим без системных панелей
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!kIsWeb) {
      try {
        WakelockPlus.enable();
      } catch (_) {}
    }

    // Включаем авто-переход в PiP при сворачивании приложения
    PipService.instance.setAutoPip(true);
    _pipSubscription = PipService.instance.pipModeStream.listen((inPip) {
      if (mounted) {
        setState(() {
          _isInPip = inPip;
        });
      }
    });

    final syncRepo = getIt.isRegistered<SyncRoomRepository>()
        ? getIt<SyncRoomRepository>()
        : null;

    _cubit = PlayerCubit(
      title: widget.title,
      episode: widget.initialEpisode,
      initialQuality: widget.initialQuality,
      roomCode: widget.roomCode,
      isHost: widget.isHost,
      syncRepository: syncRepo,
      initialPosition: widget.initialPosition,
    );

    _videoController = VideoController(
      _cubit.player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );

    // Фиксируем воспроизведение в списках и статистике профиля
    _recordPlaybackInAnimeList();

    if (widget.initialPosition != null && widget.initialPosition! > Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final totalSec = widget.initialPosition!.inSeconds;
          final m = (totalSec ~/ 60).toString().padLeft(2, '0');
          final s = (totalSec % 60).toString().padLeft(2, '0');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Продолжаем просмотр с $m:$s'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.surfaceElevated,
            ),
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Мгновенно отслеживаем сворачивание приложения, входящий звонок и возврат
    final isAway = state != AppLifecycleState.resumed;
    _cubit.setAppLifecycle(isAway: isAway);

    // Сохраняем прогресс при сворачивании приложения
    if (isAway) {
      _saveWatchProgress();
    }
  }

  void _recordPlaybackInAnimeList({int? episodeNum, Duration? position}) {
    // Не сохраняем в список «Смотрю» виртуальные/свободные комнаты без реального тайтла
    if (widget.title.id <= 0 || widget.title.code == 'free_sync_room') return;
    if (!getIt.isRegistered<AnimeListCubit>()) return;
    try {
      final listCubit = getIt<AnimeListCubit>();
      final existing = listCubit.state.getEntryFor(widget.title.id);
      if (existing == null) {
        // Тайтл не в закладках — не захламляем пользовательские списки
        return;
      }
      final currentEp = episodeNum ?? widget.initialEpisode.episode;
      final currentPos = position ?? widget.initialPosition ?? Duration.zero;

      listCubit.setAnimeStatus(
        animeId: widget.title.id,
        titleRu: widget.title.displayTitle,
        posterUrl: widget.title.posterMedium.isNotEmpty
            ? widget.title.posterMedium
            : widget.title.posterSmall,
        status: existing.status,
        lastEpisode: currentEp,
        positionMs: currentPos.inMilliseconds,
        episodesTotal: widget.title.episodesTotal,
      );
    } catch (_) {}
  }

  Future<void> _toggleScreenOrientation() async {
    HapticFeedback.lightImpact();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
    }
  }

  void _handleExit() {
    _saveWatchProgress();

    // Восстанавливаем ориентацию и системные панели UI Android/iOS при выходе
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    if (context.canPop()) {
      context.pop();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  void _saveWatchProgress() {
    final pos = _cubit.state.position;
    final dur = _cubit.state.duration;
    final ep = _cubit.state.episode.episode;

    if (pos.inSeconds >= 5 && dur.inSeconds > 0) {
      if (getIt.isRegistered<SharedPreferences>()) {
        final prefs = getIt<SharedPreferences>();
        final key = '${widget.title.id}_$ep';
        if ((dur - pos).inSeconds <= 30) {
          prefs.remove(key);
        } else {
          prefs.setInt(key, pos.inMilliseconds);
        }
      }
      if (getIt.isRegistered<WatchHistoryCubit>()) {
        final hist = getIt<WatchHistoryCubit>();
        hist.saveProgress(
          titleId: widget.title.id,
          titleName: widget.title.displayTitle,
          posterUrl: widget.title.posterMedium.isNotEmpty
              ? widget.title.posterMedium
              : widget.title.posterSmall,
          episode: ep,
          episodeName: _cubit.state.episode.name,
          position: pos,
          duration: dur,
        );
        if (widget.title.shikimoriId != null &&
            widget.title.shikimoriId! > 0 &&
            widget.title.shikimoriId != widget.title.id) {
          hist.saveProgress(
            titleId: widget.title.shikimoriId!,
            titleName: widget.title.displayTitle,
            posterUrl: widget.title.posterMedium.isNotEmpty
                ? widget.title.posterMedium
                : widget.title.posterSmall,
            episode: ep,
            episodeName: _cubit.state.episode.name,
            position: pos,
            duration: dur,
          );
        }
      }
    }

    if (getIt.isRegistered<AnimeListCubit>()) {
      try {
        final listCubit = getIt<AnimeListCubit>();
        var existing = listCubit.state.getEntryFor(widget.title.id);
        if (existing == null &&
            widget.title.shikimoriId != null &&
            widget.title.shikimoriId! > 0) {
          existing = listCubit.state.getEntryFor(widget.title.shikimoriId!);
        }
        if (existing != null) {
          final isEpDone = dur.inSeconds > 0 &&
              (pos.inSeconds >= (dur.inSeconds - 60) ||
               pos.inMilliseconds / dur.inMilliseconds >= 0.90);

          final totalEps = widget.title.episodesTotal;
          final isSeriesDone = isEpDone && totalEps != null && ep >= totalEps;
          var status = existing.status;
          if (isSeriesDone) {
            status = AnimeListStatus.completed;
          }

          listCubit.setAnimeStatus(
            animeId: widget.title.id,
            titleRu: widget.title.displayTitle,
            posterUrl: widget.title.posterMedium.isNotEmpty
                ? widget.title.posterMedium
                : widget.title.posterSmall,
            status: status,
            lastEpisode: ep,
            positionMs: pos.inMilliseconds,
            episodesTotal: totalEps,
          );
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pipSubscription?.cancel();
    PipService.instance.setAutoPip(false);

    // Сохраняем прогресс просмотра перед уничтожением плеера
    _saveWatchProgress();

    // Освобождаем wakelock, восстанавливаем ориентацию и системные панели
    if (!kIsWeb) {
      try {
        WakelockPlus.disable();
      } catch (_) {}
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    _cubit.close();
    super.dispose();
  }

  KeyEventResult _handleTvKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
        case LogicalKeyboardKey.mediaRewind:
          _cubit.seekRelative(-10);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
        case LogicalKeyboardKey.mediaFastForward:
          _cubit.seekRelative(10);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.space:
        case LogicalKeyboardKey.mediaPlayPause:
          _cubit.togglePlayPause();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.mediaPlay:
          _cubit.play();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.mediaPause:
          _cubit.pause();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _cubit.toggleControls();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _cubit.toggleControls();
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // В режиме Картинка-в-картинке (PiP) отображаем только чистое видео без оверлеев
    if (_isInPip) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Video(
            controller: _videoController,
            controls: NoVideoControls,
          ),
        ),
      );
    }

    return PopScope(
      canPop: _isMiniPlayer,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveWatchProgress();
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
          );
          return;
        }
        if (!_isMiniPlayer) {
          _minimizePlayer();
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleTvKeyEvent,
        child: BlocProvider.value(
          value: _cubit,
          child: Scaffold(
            backgroundColor: _isMiniPlayer ? Colors.transparent : Colors.black,
            resizeToAvoidBottomInset: false,
            body: BlocConsumer<PlayerCubit, PlayerState>(
              listenWhen: (previous, current) =>
                  previous.errorMessage != current.errorMessage ||
                  previous.episode.episode != current.episode.episode,
              listener: (context, state) {
                if (state.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.errorMessage!),
                      backgroundColor: AppColors.syncError,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                _recordPlaybackInAnimeList(
                  episodeNum: state.episode.episode,
                  position: state.position,
                );
              },
            builder: (context, state) {
              if (_isMiniPlayer) {
                final screenSize = MediaQuery.sizeOf(context);
                final padding = MediaQuery.paddingOf(context);
                final baseW = 210.0 * _miniPlayerScale;
                final baseH = 118.0 * _miniPlayerScale;
                final defaultLeft = screenSize.width - baseW - 16;
                final defaultTop = screenSize.height - baseH - padding.bottom - 70;

                final currentLeft = (_miniPlayerOffset?.dx ?? defaultLeft)
                    .clamp(8.0, screenSize.width - baseW - 8.0);
                final currentTop = (_miniPlayerOffset?.dy ?? defaultTop)
                    .clamp(padding.top + 8.0, screenSize.height - baseH - padding.bottom - 8.0);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Фоновый жест клика вне мини-плеера закрывает плеер
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _handleExit,
                      ),
                    ),
                    // Плавающее и масштабируемое мини-окно плеера (перемещение + ресайз + пауза)
                    Positioned(
                      left: currentLeft,
                      top: currentTop,
                      child: GestureDetector(
                        onScaleStart: (_) {
                          _baseScale = _miniPlayerScale;
                        },
                        onScaleUpdate: (details) {
                          setState(() {
                            _miniPlayerScale = (_baseScale * details.scale).clamp(0.85, 1.6);
                            _miniPlayerOffset = Offset(
                              currentLeft + details.focalPointDelta.dx,
                              currentTop + details.focalPointDelta.dy,
                            );
                          });
                        },
                        child: Container(
                          width: baseW,
                          height: baseH,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10121A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.65),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Video(
                                controller: _videoController,
                                controls: NoVideoControls,
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.65),
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.82),
                                      ],
                                      stops: const [0.0, 0.40, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                              // Верхняя строка: кнопка развернуть, название тайтла, закрыть
                              Positioned(
                                top: 4,
                                left: 6,
                                right: 6,
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _restorePlayer,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.fullscreen_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        state.title.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: _handleExit,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Центр: Кнопка Play/Pause
                              Center(
                                child: GestureDetector(
                                  onTap: () => _cubit.togglePlayPause(),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.70),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.5),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              // Нижняя строка: Номер серии и индикатор ресайза
                              Positioned(
                                bottom: 4,
                                left: 8,
                                right: 6,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Серия ${state.episode.episode}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Icon(
                                      Icons.pinch_rounded,
                                      size: 11,
                                      color: Colors.white.withValues(alpha: 0.45),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return GestureDetector(
                onVerticalDragEnd: (details) {
                  if (!_isMiniPlayer && details.primaryVelocity != null && details.primaryVelocity! > 350) {
                    _minimizePlayer();
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Видео полотно libmpv без стандартных нативных контролов
                  Center(
                    child: Video(
                      controller: _videoController,
                      controls: NoVideoControls,
                    ),
                  ),

                  // Слой жестов перемотки по двойному тапу (±10 сек), 2X, свайпов яркости/громкости и покадрового скраббинга
                  DoubleTapSeekOverlay(
                    onTap: () => _cubit.toggleControls(),
                    onSeekRelative: (seconds) => _cubit.seekRelative(seconds),
                    onCenterDoubleTap: () => _cubit.togglePlayPause(),
                    onBrightnessChanged: (b) => _cubit.setBrightness(b),
                    onVolumeChanged: (v) => _cubit.setVolume(v),
                    onScrubSeek: (pos) => _cubit.seek(pos),
                    currentPosition: state.position,
                    totalDuration: state.duration,
                    currentVolume: state.volume,
                    currentBrightness: state.brightness,
                    isScreenLocked: state.isScreenLocked,
                    onScreenLockedTap: () {
                      HapticFeedback.selectionClick();
                    },
                    opening: state.episode.opening,
                    ending: state.episode.ending,
                    previewUrl: state.episode.previewUrl ??
                        (state.title.posterMedium.isNotEmpty
                            ? state.title.posterMedium
                            : state.title.posterSmall),
                    isLocked: state.isSyncRoom && !state.isHost,
                    onLockedTap: () {
                      _cubit.requestPauseFromHost();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Хост управляет просмотром. Запрос на паузу отправлен хосту'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    onLongPressStart: () => _cubit.start2xFastForward(),
                    onLongPressEnd: () => _cubit.stop2xFastForward(),
                    onFastForwardRateChanged: (rate) => _cubit.setFastForwardRate(rate),
                  ),

                  // Индикатор быстрой перемотки при зажатии экрана (без неона, с поддержкой свайпов скорости)
                  if (state.is2xFastForwarding)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF14161F).withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.65),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.fast_forward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${state.playbackRate.toStringAsFixed(state.playbackRate.truncateToDouble() == state.playbackRate ? 0 : 2)}X  Быстрая перемотка',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '↑↓ Свайп скорости',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Стрим-чат (Twitch Chat Overlay) в левом верхнем углу
                  if (state.isSyncRoom)
                    TwitchChatOverlay(
                      messages: state.chatMessages,
                      isVisible: state.isChatOverlayVisible,
                      onToggleVisibility: () => _cubit.toggleChatOverlay(),
                    ),

                  // Слой плавающих летящих реакций (Floating Reactions)
                  if (state.isSyncRoom)
                    FloatingReactionsLayer(
                      reactions: state.activeReactions,
                    ),

                  // Danmaku бегущие строки поверх экрана (Bilibili / Nico Nico стиль)
                  DanmakuOverlayLayer(
                    items: state.danmakuMessages,
                    isEnabled: state.isDanmakuEnabled,
                  ),

                  // Всплывающее стеклянное уведомление быстрой фразы (шортката)
                  if (state.isSyncRoom && state.activeQuickPhrase != null)
                    QuickPhraseToastWidget(toast: state.activeQuickPhrase!),

                  // Живой радар и неоновые волны ожидания при буферизации или паузе у друга
                  if (state.isSyncRoom && state.bufferNotice != null)
                    PulsingRadarWaitingWidget(
                      title: state.bufferNotice!,
                      pingMs: state.peerPingMs,
                      awaySeconds: state.awaySecondsCount,
                      onPokeNudge: () {
                        _cubit.sendPokeNudge();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🩴 Вы кинули тапок в друга!'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Color(0xFFFF5E3A),
                          ),
                        );
                      },
                    ),

                  // Спойлер-щит (Blur Mode при резких скачках таймлайна вперед)
                  if (state.isSpoilerShieldActive)
                    Positioned.fill(
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.65),
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.primary),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_rounded, color: AppColors.primaryLight, size: 22),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Прыжок во времени (Спойлер-щит активен)',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Всплывающее уведомление о «летящем тапке» от друга
                  if (state.pokeNudgeMessage != null)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 70,
                      left: 20,
                      right: 20,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5E3A),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF5E3A).withValues(alpha: 0.5),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: Text(
                            state.pokeNudgeMessage!,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                      ),
                    ),

                  // Карточка-статистика Watch Party Wrapped
                  if (state.showWatchPartyStats)
                    Positioned.fill(
                      child: WatchPartyStatsSheet(
                        title: state.title,
                        episode: state.episode,
                        pauseCount: state.pauseCount,
                        emojisSent: state.emojisSent,
                        peerPingMs: state.peerPingMs,
                        peerName: state.peerName ?? 'Друг',
                        onClose: () => _cubit.toggleWatchPartyStats(),
                      ),
                    ),

                  // Баннер авто-перехода на следующую серию (Auto Next Episode)
                  if (state.isSyncRoom &&
                      state.autoNextCountdown != null &&
                      state.nextEpisode != null)
                    AutoNextEpisodeBanner(
                      countdown: state.autoNextCountdown!,
                      nextEpisode: state.nextEpisode!,
                      isHost: state.isHost,
                      onPlayNow: () => _cubit.playNextEpisode(),
                      onCancel: () => _cubit.cancelAutoNextCountdown(),
                    ),

                  // Индикатор локальной буферизации
                  if (state.isBuffering && state.bufferNotice == null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.strokeMedium),
                        ),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      ),
                    ),

                  // Премиальная плавающая кнопка пропуска опенинга и эндинга (5-7 сек таймер, без неона)
                  _buildSkipOverlay(state),

                  // Кастомный оверлей управления в стиле Cinema Dark
                  PlayerControlsOverlay(
                    cubit: _cubit,
                    state: state,
                    onBack: _handleExit,
                    onToggleOrientation: _toggleScreenOrientation,
                    syncStatus: state.isSyncRoom ? state.syncStatus : null,
                    syncPeerName: state.peerName,
                  ),

                  // Ненавязчивая плавающая иконка замка при активной блокировке
                  if (state.isScreenLocked)
                    Positioned(
                      left: 20,
                      top: MediaQuery.paddingOf(context).top + 16,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.9, end: 0.4),
                        duration: const Duration(seconds: 3),
                        builder: (context, opacity, child) {
                          return Opacity(
                            opacity: opacity,
                            child: child,
                          );
                        },
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              _cubit.toggleScreenLock();
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1.2,
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Ошибка воспроизведения потока (рендерится ПОВЕРХ оверлея управления, чтобы кнопки всегда реагировали на нажатия)
                  if (state.errorMessage != null)
                    Material(
                      color: Colors.black.withValues(alpha: 0.8),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          margin: const EdgeInsets.all(24),
                          constraints: const BoxConstraints(maxWidth: 420),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.strokeMedium),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.syncError, size: 44),
                              const SizedBox(height: 12),
                              Text(
                                state.errorMessage!,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    icon: const Icon(Icons.refresh_rounded, size: 18),
                                    label: const Text('Повторить'),
                                    onPressed: () {
                                      _cubit.switchEpisode(state.episode);
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textPrimary,
                                      side: const BorderSide(color: AppColors.strokeMedium),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                                    label: const Text('Выйти'),
                                    onPressed: _handleExit,
                                  ),
                                  IconButton(
                                    tooltip: 'Повернуть экран',
                                    icon: const Icon(Icons.screen_rotation_rounded, color: AppColors.textSecondary, size: 22),
                                    onPressed: _toggleScreenOrientation,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  ),
);
}

  Widget _buildSkipOverlay(PlayerState state) {
    if (state.isScreenLocked) return const SizedBox.shrink();

    final op = state.episode.opening;
    final ed = state.episode.ending;
    final curSec = state.position.inSeconds;

    final isOpening = op != null && curSec >= op.start && curSec < op.stop;
    final isEnding = ed != null && curSec >= ed.start && curSec < ed.stop;

    if (!isOpening && !isEnding) return const SizedBox.shrink();

    // Показываем кнопку в первые 7 секунд после начала опенинга/эндинга, либо если меню открыто
    final startSec = isOpening ? op.start : ed!.start;
    final elapsedSec = curSec - startSec;
    if (elapsedSec > 7 && !state.areControlsVisible) {
      return const SizedBox.shrink();
    }

    final label = isOpening ? 'Пропустить опенинг' : 'Пропустить эндинг';
    final targetDuration = isOpening ? op.stopDuration : ed!.stopDuration;

    return Positioned(
      bottom: MediaQuery.paddingOf(context).bottom + 76,
      right: 20,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          _cubit.seek(targetDuration);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF14161F).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.60),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 17),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
