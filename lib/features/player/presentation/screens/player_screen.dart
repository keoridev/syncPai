import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
import '../widgets/sync_buffer_banner.dart';
import '../widgets/twitch_chat_overlay.dart';

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
      if (getIt.isRegistered<WatchHistoryCubit>()) {
        getIt<WatchHistoryCubit>().saveProgress(
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
      }
    }

    if (getIt.isRegistered<AnimeListCubit>()) {
      try {
        final listCubit = getIt<AnimeListCubit>();
        final existing = listCubit.state.getEntryFor(widget.title.id);
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
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveWatchProgress();
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
          );
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleTvKeyEvent,
        child: BlocProvider.value(
          value: _cubit,
          child: Scaffold(
            backgroundColor: Colors.black,
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
              return Stack(
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
                  ),

                  // Неоновый индикатор 2X при зажатии экрана
                  if (state.is2xFastForwarding)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fast_forward_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '2X  Быстрая перемотка',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
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

                  // Всплывающее стеклянное уведомление быстрой фразы (шортката)
                  if (state.isSyncRoom && state.activeQuickPhrase != null)
                    QuickPhraseToastWidget(toast: state.activeQuickPhrase!),

                  // Баннер ожидания при буферизации у друга или когда друг отошел
                  if (state.isSyncRoom && state.bufferNotice != null)
                    SyncBufferBanner(notice: state.bufferNotice!),

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

                  // Кастомный оверлей управления в стиле Cinema Dark
                  PlayerControlsOverlay(
                    cubit: _cubit,
                    state: state,
                    onBack: _handleExit,
                    onToggleOrientation: _toggleScreenOrientation,
                    syncStatus: state.isSyncRoom ? state.syncStatus : null,
                    syncPeerName: state.peerName,
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
              );
            },
          ),
        ),
      ),
    ),
  );
}
}
