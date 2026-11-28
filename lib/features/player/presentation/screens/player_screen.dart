import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/network/network_status_helper.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/pai_chan_offline_view.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/kodik/domain/entities/kodik_translation.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_cubit.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_state.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_room.dart';
import 'package:sync_pai/features/sync_room/domain/repositories/sync_room_repository.dart';
import 'package:sync_pai/features/sync_room/presentation/widgets/reaction_overlay_layer.dart';
import 'package:sync_pai/features/sync_room/services/active_room_service.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/features/winter_theme/domain/services/winter_theme_service.dart';
import 'package:sync_pai/features/winter_theme/presentation/widgets/background_snow_layer.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sync_pai/core/widgets/desktop_title_bar.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/player/services/global_mini_player_service.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_state.dart';
import '../widgets/player_onboarding_overlay.dart';
import 'package:sync_pai/features/player/services/pip_service.dart';
import '../widgets/desktop_player_layout.dart';
import '../widgets/double_tap_seek_overlay.dart';
import '../widgets/floating_pai_chan_reactions_overlay.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/quality_selection_sheet.dart';
import '../widgets/quick_phrase_toast_widget.dart';
import '../widgets/twitch_chat_overlay.dart';
import '../widgets/danmaku_overlay_layer.dart';
import '../widgets/pulsing_radar_waiting_widget.dart';
import '../widgets/season_finale_overlay.dart';
import '../widgets/watch_party_stats_sheet.dart';

class PlayerScreen extends StatefulWidget {
  static const VideoControllerConfiguration defaultVideoControllerConfig =
      VideoControllerConfiguration(
    enableHardwareAcceleration: true,
    androidAttachSurfaceAfterVideoParameters: false,
  );

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
  final GlobalKey _videoSurfaceKey =
      GlobalKey(debugLabel: 'PersistentSyncPaiVideoSurface');
  final GlobalKey _screenshotBoundaryKey =
      GlobalKey(debugLabel: 'SyncPaiVideoScreenshotBoundary');
  final GlobalKey<DoubleTapSeekOverlayState> _seekOverlayKey =
      GlobalKey<DoubleTapSeekOverlayState>();
  final GlobalKey _viewportBoxKey =
      GlobalKey(debugLabel: 'SyncPaiPlayerViewportBox');
  bool _episodesGridMode = false;
  bool? _lastLandscapeSystemUi;
  StreamSubscription<bool>? _pipSubscription;
  bool _isInPip = false;
  bool _watchReactionsEnabled = true;
  bool _showOnboarding = false;
  final GlobalKey<PlayerOnboardingOverlayState> _onboardingKey =
      GlobalKey<PlayerOnboardingOverlayState>();
  Timer? _sleepTimer;
  int? _sleepTimerMinutes;
  bool _sleepAtEndOfEpisode = false;
  String? _centerOsdMessage;
  Timer? _centerOsdTimer;
  Uint8List? _screenshotPreviewBytes;
  Timer? _screenshotToastTimer;
  bool _skipPillCollapsed = false;
  Timer? _skipPillCollapseTimer;
  String? _activeSkipSegmentKey;
  bool _lastControlsVisible = false;
  bool _handedOffToMiniPlayer = false;
  bool _isDisposed = false;
  bool _pinchHandledInGesture = false;
  final Set<int> _activePointerIds = <int>{};
  bool _isPinching = false;
  double _videoScale = 1.0;
  double _pinchStartScale = 1.0;
  String? _zoomPillText;
  Timer? _zoomPillTimer;
  bool _snappedToFill = false;
  int? _lastZoomEpisodeNumber;
  bool? _lastZoomIsLandscape;
  int? _dismissedOpeningEpisode;
  int? _dismissedEndingEpisode;
  int? _lastSkipEpisodeNum;
  final ScrollController _portraitEpisodesScrollController = ScrollController();
  int? _lastAutoScrolledEpisode;
  bool _seasonFinaleDismissed = false;

  void _minimizePlayer({bool alreadyPopping = false}) {
    if (_handedOffToMiniPlayer || _isDisposed) return;
    _handedOffToMiniPlayer = true;
    _saveWatchProgress();

    final bool isDesktopOS =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktopOS) {
      try {
        Future.microtask(() {
          DesktopTitleBar.isFullScreenNotifier.value = false;
        });
        windowManager.setFullScreen(false);
      } catch (_) {}
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Если поток упал с фатальной ошибкой, не сворачиваем в мини-плеер, а просто выходим
    if (_cubit.state.errorMessage != null && !_cubit.state.isPlaying) {
      _handleExit();
      return;
    }

    GlobalMiniPlayerService.instance.minimize(
      cubit: _cubit,
      videoController: _videoController,
      onSaveProgress: _saveWatchProgress,
    );

    if (_cubit.state.isSyncRoom && _cubit.state.roomCode != null) {
      final rootNav = Navigator.of(context, rootNavigator: true);
      final currentRoom = SyncRoom(
        code: _cubit.state.roomCode!,
        title: _cubit.state.title,
        episode: _cubit.state.episode,
        quality: _cubit.state.selectedQuality,
        hostName: _cubit.state.isHost ? 'Хост (Вы)' : 'Хост',
        peerName: _cubit.state.peerName,
        status: SyncRoomStatus.connected,
        createdAt: DateTime.now(),
      );
      ActiveRoomService.instance.minimizeRoom(
        room: currentRoom,
        isHost: _cubit.state.isHost,
        isInPlayer: true,
        onSwitchAnime: (newTitle, {episode}) =>
            _cubit.switchAnimeInRoom(newTitle, episode: episode),
        onExpandRoom: (expandedRoom, hostFlag) {
          if (GlobalMiniPlayerService.instance.cubit != null) {
            GlobalMiniPlayerService.instance.expandToFullscreen();
            return;
          }
          final navCtx = rootNav.context;
          if (navCtx.mounted) {
            GoRouter.of(navCtx).pushNamed('player', extra: {
              'title': _cubit.state.title,
              'episode': _cubit.state.episode,
              'quality': _cubit.state.selectedQuality,
              'roomCode': _cubit.state.roomCode,
              'isHost': _cubit.state.isHost,
            });
          }
        },
      );
    }

    if (!alreadyPopping && mounted) {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.idle) {
        setState(() {});
      } else {
        binding.addPostFrameCallback((_) {
          if (!alreadyPopping && mounted) {
            setState(() {});
          }
        });
      }
    }

    if (!alreadyPopping && mounted) {
      if (context.canPop()) {
        context.pop();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    CatalogCubit.pushForegroundScreen();
    final isMobilePlatform = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (isMobilePlatform &&
        getIt.isRegistered<SettingsCubit>() &&
        !getIt<SettingsCubit>().state.hasSeenPlayerOnboarding) {
      _showOnboarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showOnboarding && !_cubit.state.isSyncRoom) {
          _cubit.pause();
        }
      });
    }
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
        final binding = WidgetsBinding.instance;
        if (binding.schedulerPhase != SchedulerPhase.idle) {
          binding.addPostFrameCallback((_) {
            if (mounted) setState(() => _isInPip = inPip);
          });
        } else {
          setState(() => _isInPip = inPip);
        }
      }
    });

    final resolvedPos = widget.initialPosition ??
        PlayerCubit.loadSavedPosition(widget.title, widget.initialEpisode.episode);

    final miniService = GlobalMiniPlayerService.instance;
    if (miniService.hasSessionFor(widget.title.id, widget.initialEpisode.episode)) {
      final claimed = miniService.claimSession()!;
      _cubit = claimed.$1;
      _videoController = claimed.$2;
    } else {
      miniService.close();

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
        initialPosition: resolvedPos,
      );

      _videoController = VideoController(
        _cubit.player,
        configuration: PlayerScreen.defaultVideoControllerConfig,
      );
    }

    // Откладываем уведомления Cubit и ChangeNotifier до завершения первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WinterThemeService.instance.enterVideoPlayer();
      MascotCompanionService.instance.setPlayerActive(true);
      _recordInitialWatchHistory();
      _recordPlaybackInAnimeList();

      if (widget.roomCode != null && widget.roomCode!.isNotEmpty) {
        ActiveRoomService.instance.registerActiveRoom(
          room: SyncRoom(
            code: widget.roomCode!,
            title: widget.title,
            episode: widget.initialEpisode,
            quality: widget.initialQuality,
            hostName: widget.isHost ? 'Хост (Вы)' : 'Хост',
            status: SyncRoomStatus.connected,
            createdAt: DateTime.now(),
          ),
          isHost: widget.isHost,
          isInPlayer: true,
          onSwitchAnime: (newTitle, {episode}) =>
              _cubit.switchAnimeInRoom(newTitle, episode: episode),
        );
      }
    });

    if (resolvedPos != null && resolvedPos > const Duration(seconds: 3)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final totalSec = resolvedPos.inSeconds;
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

  void _handleSeasonFinalePrompt(SeasonFinalePrompt prompt) {
    if (_seasonFinaleDismissed && mounted) {
      setState(() => _seasonFinaleDismissed = false);
    }
  }

  Widget? _buildSeasonFinaleOverlay(PlayerState state) {
    final prompt = state.seasonFinalePrompt;
    if (prompt == null || _seasonFinaleDismissed) return null;
    final nextSeason = prompt.nextSeason;
    final bridge = prompt.mangaBridge;
    return SeasonFinaleOverlay(
      prompt: prompt,
      onDismiss: () {
        if (mounted) setState(() => _seasonFinaleDismissed = true);
      },
      onWatchSequel: nextSeason == null
          ? null
          : () => _openVerifiedSequel(nextSeason),
      onAddPlanned: nextSeason == null
          ? null
          : () => _addSequelToPlanned(nextSeason),
      onReadManga: bridge == null
          ? null
          : () => _openMangaContinuation(bridge),
      onFindSimilar: _openSimilarTitles,
    );
  }

  void _openMangaContinuation(AnimeMangaBridge bridge) {
    _markCurrentSeasonCompleted();
    final router = GoRouter.maybeOf(context);
    _handleExit();
    if (router == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.pushNamed('manga_reader', extra: {
        'bridge': bridge,
        'initialChapter': bridge.continueFromChapter,
      });
    });
  }

  void _markCurrentSeasonCompleted() {
    final title = _cubit.state.title;
    final ep = _cubit.state.episode;
    final dur = _cubit.state.duration > Duration.zero
        ? _cubit.state.duration
        : const Duration(minutes: 24);

    if (getIt.isRegistered<WatchHistoryCubit>() && title.id > 0) {
      unawaited(
        getIt<WatchHistoryCubit>().saveProgress(
          titleId: title.id,
          titleName: title.displayTitle,
          posterUrl: title.posterMedium.isNotEmpty
              ? title.posterMedium
              : title.posterSmall,
          episode: ep.episode,
          episodeName: ep.name,
          position: dur,
          duration: dur,
        ),
      );
    }

    if (getIt.isRegistered<AnimeListCubit>() && title.id > 0) {
      unawaited(
        getIt<AnimeListCubit>().setAnimeStatus(
          animeId: title.id,
          titleRu: title.displayTitle,
          posterUrl: title.posterMedium.isNotEmpty
              ? title.posterMedium
              : title.posterSmall,
          status: AnimeListStatus.completed,
          lastEpisode: ep.episode,
          positionMs: dur.inMilliseconds,
          episodesTotal: title.episodesTotal,
        ),
      );
    }
  }

  void _openVerifiedSequel(SeasonFinaleNextSeason nextSeason) {
    _markCurrentSeasonCompleted();
    final targetTitle = nextSeason.title;
    final quality = _cubit.state.selectedQuality;
    final router = GoRouter.maybeOf(context);
    _handleExit();

    if (targetTitle == null || router == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (targetTitle.episodes.isNotEmpty) {
        router.pushNamed('player', extra: {
          'title': targetTitle,
          'episode': targetTitle.episodes.first,
          'quality': quality,
        });
      } else {
        router.pushNamed('details', extra: targetTitle);
      }
    });
  }

  void _addSequelToPlanned(SeasonFinaleNextSeason nextSeason) {
    final targetId = nextSeason.title?.id ??
        int.tryParse(nextSeason.relatedRelease?.id ?? '') ??
        0;
    if (getIt.isRegistered<AnimeListCubit>() && targetId > 0) {
      unawaited(
        getIt<AnimeListCubit>().setAnimeStatus(
          animeId: targetId,
          titleRu: nextSeason.name,
          posterUrl: nextSeason.title?.posterUrl ??
              nextSeason.relatedRelease?.posterUrl,
          status: AnimeListStatus.planned,
          episodesTotal: nextSeason.title?.episodesTotal,
          isUserInitiated: true,
        ),
      );
    }
    MascotCompanionService.instance.onCollectionAdded(
      'В планах',
      nextSeason.name,
    );
  }

  void _openSimilarTitles() {
    final title = _cubit.state.title;
    final router = GoRouter.maybeOf(context);
    _handleExit();
    if (router == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.pushNamed('details', extra: {
        'title': title,
        'scrollToSimilar': true,
      });
    });
  }

  void _recordInitialWatchHistory() {
    if (widget.title.id <= 0 || widget.title.code == 'free_sync_room') return;
    if (!getIt.isRegistered<WatchHistoryCubit>()) return;
    Future.microtask(() {
      try {
        final hist = getIt<WatchHistoryCubit>();
        final existing = hist.state.historyMap[widget.title.id];
        if (existing != null &&
            existing.episode == widget.initialEpisode.episode &&
            existing.positionMs >= 10000 &&
            widget.initialPosition == null) {
          return;
        }
        final initialPos = widget.initialPosition ??
            (existing != null && existing.episode == widget.initialEpisode.episode
                ? Duration(milliseconds: existing.positionMs)
                : const Duration(seconds: 5));
        final initialDur = existing != null && existing.durationMs > 0
            ? Duration(milliseconds: existing.durationMs)
            : const Duration(minutes: 24);
        final poster = widget.title.posterMedium.isNotEmpty
            ? widget.title.posterMedium
            : widget.title.posterSmall;

        hist.saveProgress(
          titleId: widget.title.id,
          titleName: widget.title.displayTitle,
          posterUrl: poster,
          episode: widget.initialEpisode.episode,
          episodeName: widget.initialEpisode.name,
          position: initialPos,
          duration: initialDur,
        );
      } catch (_) {}
    });
  }

  void _recordPlaybackInAnimeList({int? episodeNum, Duration? position}) {
    // Не сохраняем в список «Смотрю» виртуальные/свободные комнаты без реального тайтла
    if (widget.title.id <= 0 || widget.title.code == 'free_sync_room') return;
    if (!getIt.isRegistered<AnimeListCubit>()) return;
    Future.microtask(() {
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
    });
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
    if (_isDisposed) return;
    _saveWatchProgress();

    final bool isDesktopOS =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktopOS) {
      try {
        Future.microtask(() {
          DesktopTitleBar.isFullScreenNotifier.value = false;
        });
        windowManager.setFullScreen(false);
      } catch (_) {}
    }

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
    _saveWatchProgressExplicit(
      title: widget.title,
      episodeNum: _cubit.state.episode.episode,
      episodeName: _cubit.state.episode.name,
      position: _cubit.state.position,
      duration: _cubit.state.duration,
    );
  }

  void _saveWatchProgressExplicit({
    required AnimeTitle title,
    required int episodeNum,
    String? episodeName,
    required Duration position,
    required Duration duration,
  }) {
    final pos = position;
    final dur = duration;
    final ep = episodeNum;

    if (_cubit.hasPendingInitialSeek || pos.inSeconds < 5 || dur.inSeconds <= 0) {
      return;
    }

    if (getIt.isRegistered<SharedPreferences>()) {
      final prefs = getIt<SharedPreferences>();
      final key = '${title.id}_$ep';
      if ((dur - pos).inSeconds <= 30) {
        prefs.remove(key);
      } else {
        prefs.setInt(key, pos.inMilliseconds);
      }
    }
    if (getIt.isRegistered<WatchHistoryCubit>()) {
      Future.microtask(() {
        try {
          final hist = getIt<WatchHistoryCubit>();
          hist.saveProgress(
            titleId: title.id,
            titleName: title.displayTitle,
            posterUrl: title.posterMedium.isNotEmpty
                ? title.posterMedium
                : title.posterSmall,
            episode: ep,
            episodeName: episodeName,
            position: pos,
            duration: dur,
          );
        } catch (_) {}
      });
    }

    if (getIt.isRegistered<AnimeListCubit>()) {
      Future.microtask(() {
        try {
          final listCubit = getIt<AnimeListCubit>();
          var existing = listCubit.state.getEntryFor(title.id);
          if (existing == null &&
              title.shikimoriId != null &&
              title.shikimoriId! > 0) {
            existing = listCubit.state.getEntryFor(title.shikimoriId!);
          }
          if (existing != null) {
            final isEpDone = dur.inSeconds > 0 &&
                (pos.inSeconds >= (dur.inSeconds - 60) ||
                 pos.inMilliseconds / dur.inMilliseconds >= 0.90);

            final totalEps = title.episodesTotal;
            final isSeriesDone = isEpDone && totalEps != null && ep >= totalEps;
            var status = existing.status;
            if (isSeriesDone) {
              status = AnimeListStatus.completed;
            }

            listCubit.setAnimeStatus(
              animeId: title.id,
              titleRu: title.displayTitle,
              posterUrl: title.posterMedium.isNotEmpty
                  ? title.posterMedium
                  : title.posterSmall,
              status: status,
              lastEpisode: ep,
              positionMs: pos.inMilliseconds,
              episodesTotal: totalEps,
            );
          }
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    CatalogCubit.popForegroundScreen();
    _sleepTimer?.cancel();
    _centerOsdTimer?.cancel();
    _zoomPillTimer?.cancel();
    _portraitEpisodesScrollController.dispose();
    _screenshotToastTimer?.cancel();
    _skipPillCollapseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pipSubscription?.cancel();
    PipService.instance.setAutoPip(false);

    // Сначала сбрасываем полноэкранный режим на десктопе, предотвращая гонку с Direct3D текстурой
    final bool isDesktopOS =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktopOS) {
      try {
        windowManager.setFullScreen(false);
      } catch (_) {}
    }

    // Сохраняем прогресс просмотра и сбрасываем тему в microtask,
    // чтобы BlocBuilder / ListenableBuilder не вызывали markNeedsBuild во время unmount/сборки кадра
    final posToSave = _cubit.state.position;
    final durToSave = _cubit.state.duration;
    final epToSave = _cubit.state.episode.episode;
    final epNameToSave = _cubit.state.episode.name;
    final titleToSave = widget.title;

    final handedOff = _handedOffToMiniPlayer;
    Future.microtask(() {
      WinterThemeService.instance.exitVideoPlayer();
      if (!handedOff) {
        MascotCompanionService.instance.setPlayerActive(false);
      }
      if (isDesktopOS) {
        DesktopTitleBar.isFullScreenNotifier.value = false;
      }
      _saveWatchProgressExplicit(
        title: titleToSave,
        episodeNum: epToSave,
        episodeName: epNameToSave,
        position: posToSave,
        duration: durToSave,
      );
    });

    // Освобождаем wakelock (только если не свернули в мини-плеер), восстанавливаем ориентацию и системные панели
    if (!kIsWeb && !handedOff) {
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

    if (!_handedOffToMiniPlayer) {
      _cubit.close();
    }
    super.dispose();
  }

  KeyEventResult _handleTvKeyEvent(FocusNode node, KeyEvent event) {
    final bool isDesktopOS =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktopOS) {
      // На десктопе горячие клавиши обрабатывает DesktopPlayerLayout
      return KeyEventResult.ignored;
    }
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
        case LogicalKeyboardKey.keyP:
          _minimizePlayer();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyM:
          final cur = _cubit.state.volume;
          _cubit.setVolume(cur > 0.01 ? 0.0 : 100.0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyF:
          _toggleScreenOrientation();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyN:
          final allEpisodes = _cubit.state.title.episodes;
          final curIdx = allEpisodes.indexWhere((e) => e.episode == _cubit.state.episode.episode);
          if (curIdx >= 0 && curIdx < allEpisodes.length - 1) {
            _cubit.switchEpisode(allEpisodes[curIdx + 1]);
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyS:
          _cubit.skipOpening();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _handleExit();
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_handedOffToMiniPlayer) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    // В режиме Картинка-в-картинке (PiP) отображаем только чистое видео без оверлеев
    if (_isInPip) {
      final mqSize = MediaQuery.sizeOf(context);
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: (mqSize.width <= 0 || mqSize.height <= 0)
              ? const SizedBox.shrink()
              : RepaintBoundary(
                  key: _screenshotBoundaryKey,
                  child: Video(
                    key: _videoSurfaceKey,
                    controller: _videoController,
                    controls: NoVideoControls,
                  ),
                ),
        ),
      );
    }

    final bool isDesktopOS = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      if (_lastLandscapeSystemUi != isLandscape) {
        _lastLandscapeSystemUi = isLandscape;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isDisposed || _handedOffToMiniPlayer) return;
          SystemChrome.setEnabledSystemUIMode(
            isLandscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
          );
        });
      }
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          if (!_handedOffToMiniPlayer) {
            _minimizePlayer(alreadyPopping: true);
          }
          return;
        }
      },
      child: Focus(
        autofocus: !isDesktopOS,
        onKeyEvent: _handleTvKeyEvent,
        child: BlocProvider.value(
          value: _cubit,
          child: Scaffold(
            backgroundColor: (!isDesktopOS && !isLandscape)
                ? const Color(0xFF0B0E14)
                : Colors.black,
            resizeToAvoidBottomInset: false,
            body: BlocConsumer<PlayerCubit, PlayerState>(
              buildWhen: (previous, current) =>
                  previous.isPlaying != current.isPlaying ||
                  previous.isBuffering != current.isBuffering ||
                  previous.areControlsVisible != current.areControlsVisible ||
                  previous.selectedQuality != current.selectedQuality ||
                  previous.episode.episode != current.episode.episode ||
                  previous.title.id != current.title.id ||
                  previous.currentTranslation != current.currentTranslation ||
                  previous.videoFit != current.videoFit ||
                  previous.isScreenLocked != current.isScreenLocked ||
                  previous.playbackRate != current.playbackRate ||
                  previous.is2xFastForwarding != current.is2xFastForwarding ||
                  previous.autoNextCountdown != current.autoNextCountdown ||
                  previous.volume != current.volume ||
                  previous.brightness != current.brightness ||
                  previous.isSpoilerShieldActive != current.isSpoilerShieldActive ||
                  previous.isPeerAway != current.isPeerAway ||
                  previous.isPeerBuffering != current.isPeerBuffering ||
                  previous.syncStatus != current.syncStatus ||
                  previous.bufferNotice != current.bufferNotice ||
                  previous.chatMessages != current.chatMessages ||
                  previous.activeReactions != current.activeReactions ||
                  previous.danmakuMessages != current.danmakuMessages ||
                  previous.activeQuickPhrase != current.activeQuickPhrase ||
                  previous.roomCode != current.roomCode ||
                  previous.peerPresence != current.peerPresence ||
                  previous.errorMessage != current.errorMessage ||
                  previous.isHudEditMode != current.isHudEditMode ||
                  previous.isChatOverlayVisible != current.isChatOverlayVisible ||
                  previous.isVoiceMuted != current.isVoiceMuted ||
                  previous.isTalking != current.isTalking ||
                  previous.isPeerTalking != current.isPeerTalking ||
                  previous.pokeNudgeMessage != current.pokeNudgeMessage ||
                  previous.showWatchPartyStats != current.showWatchPartyStats ||
                  previous.coopSkipVotes != current.coopSkipVotes ||
                  previous.hasVotedCoopSkip != current.hasVotedCoopSkip,
              listenWhen: (previous, current) =>
                  previous.errorMessage != current.errorMessage ||
                  previous.episode.episode != current.episode.episode ||
                  previous.isHudEditMode != current.isHudEditMode ||
                  previous.seasonFinalePrompt != current.seasonFinalePrompt,
              listener: (context, state) {
                if (state.seasonFinalePrompt != null) {
                  _handleSeasonFinalePrompt(state.seasonFinalePrompt!);
                }
                if (state.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.errorMessage!),
                      backgroundColor: AppColors.syncError,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                final isMobilePlatform =
                    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
                if (isMobilePlatform) {
                  if (state.isHudEditMode) {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]);
                  } else {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]);
                  }
                }
                _recordPlaybackInAnimeList(
                  episodeNum: state.episode.episode,
                  position: state.position,
                );
              },
              builder: (context, state) {
                if (isDesktopOS) {
                  final desktop = DesktopPlayerLayout(
                    cubit: _cubit,
                    state: state,
                    videoController: _videoController,
                    onBack: _handleExit,
                    onSaveProgress: _saveWatchProgress,
                    skipOverlay: _buildReactiveSkipOverlay(),
                    seasonFinaleOverlay: _buildSeasonFinaleOverlay(state),
                  );
                  if (!state.isSyncRoom || state.roomCode == null) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        desktop,
                        if (!state.isScreenLocked)
                          const Positioned.fill(
                            child: BackgroundSnowLayer(
                              key: ValueKey('player_snow_layer'),
                              flakeCount: 25,
                              opacity: 0.48,
                              forPlayer: true,
                            ),
                          ),
                      ],
                    );
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      desktop,
                      if (!state.isScreenLocked)
                        const Positioned.fill(
                          child: BackgroundSnowLayer(
                            key: ValueKey('player_snow_layer'),
                            flakeCount: 25,
                            opacity: 0.48,
                            forPlayer: true,
                          ),
                        ),
                      ..._buildSyncRoomReactionWidgets(state),
                    ],
                  );
                }

                if (isLandscape) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildVideoViewport(
                        context,
                        state,
                        isLandscape: true,
                      ),
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
                      if (_showOnboarding)
                        Positioned.fill(
                          child: PlayerOnboardingOverlay(
                            key: _onboardingKey,
                            onDismiss: _dismissOnboarding,
                            onStepChanged: (step) {
                              if (step == 3) {
                                _cubit.showControls();
                              }
                            },
                          ),
                        ),
                    ],
                  );
                }

                // ПОРТРЕТНЫЙ РЕЖИМ (YouTube / Crunchyroll стиль): 16:9 плеер сверху + панель серий снизу (#0B0E14)
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeArea(
                      child: Column(
                        children: [
                          GestureDetector(
                            onVerticalDragEnd: (details) {
                              if (!state.isHudEditMode &&
                                  !state.isBuffering &&
                                  details.primaryVelocity != null &&
                                  details.primaryVelocity! > 750) {
                                _minimizePlayer();
                              }
                            },
                            child: AspectRatio(
                              key: const ValueKey('player_portrait_16_9_box'),
                              aspectRatio: 16 / 9,
                              child: ClipRect(
                                child: ColoredBox(
                                  color: Colors.black,
                                  child: _buildVideoViewport(
                                    context,
                                    state,
                                    isLandscape: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _buildPortraitCompanionPanel(context, state),
                          ),
                        ],
                      ),
                    ),
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
                    if (_showOnboarding)
                      Positioned.fill(
                        child: PlayerOnboardingOverlay(
                          key: _onboardingKey,
                          onDismiss: _dismissOnboarding,
                          onStepChanged: (step) {
                            if (step == 3) {
                              _cubit.showControls();
                            }
                          },
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

  void _showZoomPill(String text, {bool autoHide = false}) {
    _zoomPillTimer?.cancel();
    if (mounted) {
      setState(() => _zoomPillText = text);
    }
    if (autoHide) {
      _zoomPillTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() => _zoomPillText = null);
        }
      });
    }
  }

  Widget _buildVideoViewport(
    BuildContext context,
    PlayerState state, {
    required bool isLandscape,
  }) {
    final mqSize = MediaQuery.sizeOf(context);
    final hasValidSurfaceSize = mqSize.width > 0 && mqSize.height > 0;
    final canVerticalSwipe = !state.isScreenLocked && !state.isHudEditMode;

    // Сброс масштаба при выходе из ландшафта или смене серии
    if ((_lastZoomIsLandscape == true && !isLandscape) ||
        (_lastZoomEpisodeNumber != null &&
            _lastZoomEpisodeNumber != state.episode.episode)) {
      if (_videoScale != 1.0 || _snappedToFill || _zoomPillText != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _videoScale = 1.0;
            _snappedToFill = false;
            _zoomPillText = null;
          });
        });
      }
    }
    _lastZoomIsLandscape = isLandscape;
    _lastZoomEpisodeNumber = state.episode.episode;

    final double screenAspect =
        (mqSize.width > 0 && mqSize.height > 0) ? (mqSize.width / mqSize.height) : (16 / 9);
    const double videoAspect = 16 / 9;
    final double fillRatio = (screenAspect / videoAspect).clamp(1.05, 1.6);

    return ClipRect(
      child: Listener(
        onPointerDown: (event) {
          _activePointerIds.add(event.pointer);
          if (_activePointerIds.length >= 2) {
            _isPinching = true;
            _seekOverlayKey.currentState?.endExternalVerticalSwipe();
          }
        },
        onPointerUp: (event) {
          _activePointerIds.remove(event.pointer);
          if (_activePointerIds.isEmpty) {
            _isPinching = false;
          }
        },
        onPointerCancel: (event) {
          _activePointerIds.remove(event.pointer);
          if (_activePointerIds.isEmpty) {
            _isPinching = false;
          }
        },
        child: GestureDetector(
          key: _viewportBoxKey,
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: canVerticalSwipe
              ? (details) {
                  if (_isPinching || _activePointerIds.length >= 2) return;
                  final box =
                      _viewportBoxKey.currentContext?.findRenderObject() as RenderBox?;
                  final width = (box != null && box.hasSize && box.size.width > 0)
                      ? box.size.width
                      : mqSize.width;
                  final localDx = box != null
                      ? box.globalToLocal(details.globalPosition).dx
                      : details.localPosition.dx;
                  final isBrightness = localDx < (width / 2);
                  _seekOverlayKey.currentState
                      ?.startExternalVerticalSwipe(isBrightness: isBrightness);
                }
              : null,
          onVerticalDragUpdate: canVerticalSwipe
              ? (details) {
                  if (_isPinching || _activePointerIds.length >= 2) {
                    _seekOverlayKey.currentState?.endExternalVerticalSwipe();
                    return;
                  }
                  final deltaPx = details.primaryDelta;
                  if (deltaPx == null) return;
                  final box =
                      _viewportBoxKey.currentContext?.findRenderObject() as RenderBox?;
                  final height = (box != null && box.hasSize && box.size.height > 0)
                      ? box.size.height
                      : mqSize.height;
                  _seekOverlayKey.currentState?.updateExternalVerticalSwipe(
                    deltaPx: deltaPx,
                    viewportHeight: height,
                  );
                }
              : null,
          onVerticalDragEnd: canVerticalSwipe
              ? (_) => _seekOverlayKey.currentState?.endExternalVerticalSwipe()
              : null,
          onVerticalDragCancel: canVerticalSwipe
              ? () => _seekOverlayKey.currentState?.endExternalVerticalSwipe()
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
            // Видео полотно libmpv с единым стабильным GlobalKey (_videoSurfaceKey)
            // Сохраняет нативный SurfaceView / Texture при смене портретной и альбомной ориентации
            Positioned.fill(
              child: !hasValidSurfaceSize
                  ? const SizedBox.shrink()
                  : RepaintBoundary(
                      key: _screenshotBoundaryKey,
                      child: Center(
                        child: Transform.scale(
                          scale: isLandscape ? _videoScale : 1.0,
                          child: Video(
                            key: _videoSurfaceKey,
                            controller: _videoController,
                            controls: NoVideoControls,
                            fit: state.videoFit,
                            fill: Colors.black,
                          ),
                        ),
                      ),
                    ),
            ),

            if (!state.isScreenLocked)
              const Positioned.fill(
                child: BackgroundSnowLayer(
                  key: ValueKey('player_snow_layer'),
                  flakeCount: 25,
                  opacity: 0.48,
                  forPlayer: true,
                ),
              ),

            IgnorePointer(
              ignoring: state.isHudEditMode || state.isScreenLocked,
              child: GestureDetector(
                key: const ValueKey('player_pinch_scale_detector'),
                behavior: HitTestBehavior.translucent,
                onScaleStart: (details) {
                  _pinchHandledInGesture = false;
                  _pinchStartScale = _videoScale;
                  if (details.pointerCount >= 2 || _activePointerIds.length >= 2) {
                    _isPinching = true;
                    _seekOverlayKey.currentState?.endExternalVerticalSwipe();
                  }
                },
                onScaleUpdate: (details) {
                  if (details.pointerCount < 2 && _activePointerIds.length < 2) {
                    return;
                  }
                  if (!_isPinching) {
                    _isPinching = true;
                    _seekOverlayKey.currentState?.endExternalVerticalSwipe();
                  }

                  if (!isLandscape) {
                    if (details.scale > 1.25 && !_pinchHandledInGesture) {
                      _pinchHandledInGesture = true;
                      HapticFeedback.lightImpact();
                      _toggleScreenOrientation();
                    }
                    return;
                  }

                  final double rawScale =
                      (_pinchStartScale * details.scale).clamp(1.0, 2.5);
                  double nextScale;
                  String pillLabel;

                  if ((rawScale - fillRatio).abs() < 0.08) {
                    nextScale = fillRatio;
                    if (!_snappedToFill) {
                      HapticFeedback.selectionClick();
                      _snappedToFill = true;
                    }
                    pillLabel = 'На весь экран';
                  } else if (rawScale <= 1.04) {
                    nextScale = 1.0;
                    _snappedToFill = false;
                    pillLabel = 'Исходный размер';
                  } else {
                    nextScale = rawScale;
                    _snappedToFill = false;
                    pillLabel = '${nextScale.toStringAsFixed(1)}x';
                  }

                  if ((nextScale - _videoScale).abs() > 0.005 ||
                      _zoomPillText != pillLabel) {
                    setState(() => _videoScale = nextScale);
                    _showZoomPill(pillLabel);
                  }
                },
                onScaleEnd: (_) {
                  _isPinching = false;
                  _pinchHandledInGesture = false;
                  if (_zoomPillText != null) {
                    _showZoomPill(_zoomPillText!, autoHide: true);
                  }
                },
            child: BlocSelector<PlayerCubit, PlayerState, ({Duration pos, Duration dur})>(
              bloc: _cubit,
              selector: (s) => (pos: s.position, dur: s.duration),
              builder: (context, timing) => DoubleTapSeekOverlay(
                key: _seekOverlayKey,
                onTap: () => _cubit.toggleControls(),
                onSeekRelative: (seconds) {
                  _cubit.seekRelative(seconds);
                  if (_showOnboarding) {
                    _onboardingKey.currentState?.notifySeekDoubleTapped();
                  }
                },
                onCenterDoubleTap: () => _cubit.togglePlayPause(),
                onBrightnessChanged: (b) {
                  _cubit.setBrightness(b);
                  if (_showOnboarding) {
                    _onboardingKey.currentState?.notifyBrightnessSwiped();
                  }
                },
                onVolumeChanged: (v) {
                  _cubit.setVolume(v);
                  if (_showOnboarding) {
                    _onboardingKey.currentState?.notifyVolumeSwiped();
                  }
                },
                onScrubSeek: (pos) => _cubit.seek(pos),
                currentPosition: timing.pos,
                totalDuration: timing.dur,
                currentVolume: state.volume,
                currentBrightness: state.brightness,
                isScreenLocked: state.isScreenLocked,
                onScreenLockedTap: () {
                  HapticFeedback.selectionClick();
                },
                opening: state.effectiveOpening,
                ending: state.effectiveEnding,
                previewUrl: state.episode.previewUrl ??
                    (state.title.posterMedium.isNotEmpty
                        ? state.title.posterMedium
                        : state.title.posterSmall),
                isLocked: false,
                onLockedTap: () {},
                seekStepSeconds: getIt.isRegistered<SettingsCubit>()
                    ? getIt<SettingsCubit>().state.seekStepSeconds
                    : 10,
                swipeSensitivity: getIt.isRegistered<SettingsCubit>()
                    ? getIt<SettingsCubit>().state.gestureSwipeSensitivity
                    : 1.0,
                onLongPressStart:
                    state.isSyncRoom ? null : () => _cubit.start2xFastForward(),
                onLongPressEnd:
                    state.isSyncRoom ? null : () => _cubit.stop2xFastForward(),
                onFastForwardRateChanged: state.isSyncRoom
                    ? null
                    : (rate) => _cubit.setFastForwardRate(rate),
              ),
            ),
          ),
        ),

        // Индикатор быстрой перемотки при зажатии экрана
        if (state.is2xFastForwarding)
          Positioned(
            top: (isLandscape ? MediaQuery.paddingOf(context).top + 16 : 8),
            left: 8,
            right: 8,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 16 : 12,
                  vertical: isLandscape ? 8 : 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161F).withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fast_forward_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${state.playbackRate.toStringAsFixed(state.playbackRate.truncateToDouble() == state.playbackRate ? 0 : 2)}X  Быстрая перемотка',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (state.isSyncRoom && isLandscape)
          TwitchChatOverlay(
            messages: state.chatMessages,
            isVisible: state.isChatOverlayVisible,
            onToggleVisibility: () => _cubit.toggleChatOverlay(),
          ),

        if (state.isSyncRoom || state.activeReactions.isNotEmpty)
          FloatingPaiChanReactionsOverlay(
            reactions: state.activeReactions,
          ),

        DanmakuOverlayLayer(
          items: state.danmakuMessages,
          isEnabled: state.isDanmakuEnabled,
        ),

        if (state.isSyncRoom && state.activeQuickPhrase != null)
          QuickPhraseToastWidget(toast: state.activeQuickPhrase!),

        if (state.isSyncRoom && state.bufferNotice != null)
          PulsingRadarWaitingWidget(
            title: state.bufferNotice!,
            pingMs: state.peerPingMs,
            awaySeconds: state.awaySecondsCount,
            onPokeNudge: () {
              _cubit.sendPokeNudge();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Вы отправили сигнал другу!'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Color(0xFFFF5E3A),
                ),
              );
            },
          ),

        if (state.isSpoilerShieldActive)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded, color: AppColors.primaryLight, size: 18),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Прыжок во времени (Спойлер-щит активен)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
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

        if (state.pokeNudgeMessage != null)
          Positioned(
            top: isLandscape ? MediaQuery.paddingOf(context).top + 70 : 12,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5E3A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  state.pokeNudgeMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),

        if (_buildSeasonFinaleOverlay(state) case final finaleOverlay?)
          finaleOverlay,

        if (state.isBuffering &&
            state.bufferNotice == null &&
            !state.areControlsVisible &&
            state.errorMessage == null)
          Center(
            child: Container(
              padding: EdgeInsets.all(isLandscape ? 16 : 12),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.65),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.strokeMedium),
              ),
              child: SizedBox(
                width: isLandscape ? 36 : 28,
                height: isLandscape ? 36 : 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
          ),

        // Кастомный оверлей управления (строго внутри 16:9 в портрете и полноэкранный в ландшафте)
        PlayerControlsOverlay(
          cubit: _cubit,
          state: state,
          onBack: _minimizePlayer,
          onMinimize: _minimizePlayer,
          onToggleOrientation: _toggleScreenOrientation,
          onTakeScreenshot: _takeScreenshot,
          onOpenSleepTimer: _openSleepTimerSheet,
          onEnterPip: _handlePipAction,
          onAspectRatioChanged: (fit) {
            final label = fit == BoxFit.contain
                ? 'По размеру'
                : (fit == BoxFit.cover ? 'На весь экран' : 'Растянуть');
            _showCenterOsd('Экран: $label');
          },
          syncStatus: state.isSyncRoom ? state.syncStatus : null,
          syncPeerName: state.peerName,
        ),

        if (_zoomPillText != null)
          Positioned(
            top: isLandscape ? MediaQuery.paddingOf(context).top + 16 : 12,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const ValueKey('player_zoom_pill'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F141E).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _zoomPillText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (_centerOsdMessage != null)
          Center(
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('player_center_osd'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F141E).withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  _centerOsdMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),

        if (_screenshotPreviewBytes != null)
          Positioned(
            top: isLandscape ? MediaQuery.paddingOf(context).top + 56 : 10,
            right: 12,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('player_screenshot_toast'),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F141E).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF35D9D5).withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        _screenshotPreviewBytes!,
                        width: 44,
                        height: 26,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Скриншот сохранён',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        _buildReactiveSkipOverlay(),

        if (state.isSyncRoom && state.roomCode != null && isLandscape)
          ..._buildSyncRoomReactionWidgets(state),

        if (state.isScreenLocked)
          Positioned(
            left: isLandscape ? 20 : 10,
            top: isLandscape ? MediaQuery.paddingOf(context).top + 16 : 10,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.9, end: 0.4),
              duration: const Duration(seconds: 3),
              builder: (context, opacity, child) => Opacity(
                opacity: opacity,
                child: child,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _cubit.toggleScreenLock();
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: EdgeInsets.all(isLandscape ? 12 : 9),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.white,
                      size: isLandscape ? 22 : 18,
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (state.errorMessage != null)
          Material(
            color: Colors.black.withValues(alpha: 0.85),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isLandscape ? 24 : 12),
                child: NetworkStatusHelper.isConnectionError(state.errorMessage)
                    ? PaiChanOfflineView(
                        title: 'Ошибка загрузки видеопотока',
                        subtitle:
                            'Нет подключения к сети для воспроизведения серии. Проверьте интернет или выберите скачанную серию.',
                        onRetry: () => _cubit.switchEpisode(state.episode),
                        onOpenSaved: () => context.push('/downloads'),
                      )
                    : Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isLandscape ? 24 : 16,
                          vertical: isLandscape ? 20 : 12,
                        ),
                        constraints: const BoxConstraints(maxWidth: 420),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.strokeMedium),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.syncError,
                              size: isLandscape ? 44 : 28,
                            ),
                            SizedBox(height: isLandscape ? 12 : 6),
                            Text(
                              state.errorMessage!,
                              maxLines: isLandscape ? 4 : 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: isLandscape ? 14 : 12,
                              ),
                            ),
                            SizedBox(height: isLandscape ? 18 : 10),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    visualDensity: isLandscape
                                        ? VisualDensity.standard
                                        : VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isLandscape ? 16 : 12,
                                      vertical: isLandscape ? 10 : 6,
                                    ),
                                  ),
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('Повторить'),
                                  onPressed: () => _cubit.switchEpisode(state.episode),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary,
                                    visualDensity: isLandscape
                                        ? VisualDensity.standard
                                        : VisualDensity.compact,
                                    side: const BorderSide(color: AppColors.strokeMedium),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isLandscape ? 16 : 12,
                                      vertical: isLandscape ? 10 : 6,
                                    ),
                                  ),
                                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                                  label: const Text('Выйти'),
                                  onPressed: _handleExit,
                                ),
                                IconButton(
                                  tooltip: 'Повернуть экран',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.screen_rotation_rounded,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  onPressed: _toggleScreenOrientation,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
      ],
      ),
      ),
      ),
    );
  }

  Widget _buildPortraitCompanionPanel(BuildContext context, PlayerState state) {
    final primary = Theme.of(context).colorScheme.primary;
    final episodes = state.title.episodes.isNotEmpty
        ? state.title.episodes
        : <EpisodeItem>[state.episode];
    final currentEpNum = state.episode.episode;
    final isGuestInSync = state.isSyncRoom && !state.isHost;
    final qualityLabel = state.selectedQuality == PlayerQuality.fhd
        ? '1080p'
        : (state.selectedQuality == PlayerQuality.hd ? '720p' : '480p');

    return ColoredBox(
      key: const ValueKey('player_portrait_companion_panel'),
      color: const Color(0xFF0B0E14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),

              // 1. ШАПКА РЕЛИЗА И ТЕКУЩЕЙ СЕРИИ
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.title.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Серия ${state.episode.episode}${state.episode.name != null && state.episode.name!.isNotEmpty ? ' — ${state.episode.name}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => QualitySelectionSheet.show(
                        context,
                        currentQuality: state.selectedQuality,
                        onSelect: (q) => _cubit.changeQuality(q),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131722),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.hd_outlined,
                              size: 15,
                              color: primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              qualityLabel,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _toggleScreenOrientation,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131722),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: const Icon(
                          Icons.fullscreen_rounded,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. СЕЛЕКТОР ОЗВУЧКИ (AniLibria / Kodik студии)
              _buildPortraitDubbingSelector(context, state, primary),

              const SizedBox(height: 8),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),

              // 3. ЗАГОЛОВОК СПИСКА СЕРИЙ + ПЕРЕКЛЮЧАТЕЛЬ СЕТКА / СПИСОК
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.video_library_rounded,
                      size: 17,
                      color: primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Список серий',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131722),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        '${episodes.length}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('player_portrait_episodes_mode_toggle'),
                      tooltip: _episodesGridMode
                          ? 'Показать списком'
                          : 'Показать сеткой',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: const EdgeInsets.all(4),
                      icon: Icon(
                        _episodesGridMode
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _episodesGridMode = !_episodesGridMode);
                      },
                    ),
                  ],
                ),
              ),

              // 4. ПРОКРУЧИВАЕМЫЙ СПИСОК / СЕТКА СЕРИЙ
              Builder(
                builder: (_) {
                  if (_lastAutoScrolledEpisode != currentEpNum &&
                      episodes.isNotEmpty) {
                    _lastAutoScrolledEpisode = currentEpNum;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted ||
                          !_portraitEpisodesScrollController.hasClients) {
                        return;
                      }
                      final idx =
                          episodes.indexWhere((e) => e.episode == currentEpNum);
                      if (idx <= 0) return;
                      final pos = _portraitEpisodesScrollController.position;
                      final rawOffset = _episodesGridMode
                          ? ((idx ~/ 5) * 66.0)
                          : (idx * 84.0);
                      final target =
                          rawOffset.clamp(0.0, pos.maxScrollExtent);
                      _portraitEpisodesScrollController.animateTo(
                        target,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                      );
                    });
                  }
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: _episodesGridMode
                    ? GridView.builder(
                        key: const ValueKey('player_portrait_episodes_grid'),
                        controller: _portraitEpisodesScrollController,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.35,
                        ),
                        itemCount: episodes.length,
                        itemBuilder: (context, index) {
                          final ep = episodes[index];
                          final isSelected = ep.episode == currentEpNum;
                          return InkWell(
                            key: ValueKey('portrait_ep_grid_${ep.episode}'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              if (isGuestInSync) {
                                _cubit.showGuestPlaybackLockedNotice();
                                return;
                              }
                              HapticFeedback.lightImpact();
                              _cubit.switchEpisode(ep);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primary.withValues(alpha: 0.20)
                                    : const Color(0xFF131722),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? primary
                                      : Colors.white.withValues(alpha: 0.08),
                                  width: isSelected ? 1.4 : 1.0,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSelected) ...[
                                    Icon(
                                      Icons.play_arrow_rounded,
                                      size: 14,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    '${ep.episode}',
                                    style: TextStyle(
                                      color: isSelected
                                          ? primary
                                          : AppColors.textPrimary,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        key: const ValueKey('player_portrait_episodes_list'),
                        controller: _portraitEpisodesScrollController,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        physics: const BouncingScrollPhysics(),
                        itemCount: episodes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ep = episodes[index];
                          final isCurrent = ep.episode == currentEpNum;
                          final thumbUrl = (ep.previewUrl != null &&
                                  ep.previewUrl!.isNotEmpty)
                              ? ep.previewUrl!
                              : (state.title.posterMedium.isNotEmpty
                                  ? state.title.posterMedium
                                  : state.title.posterSmall);

                          return InkWell(
                            key: ValueKey('portrait_ep_item_${ep.episode}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              if (isGuestInSync) {
                                _cubit.showGuestPlaybackLockedNotice();
                                return;
                              }
                              HapticFeedback.lightImpact();
                              _cubit.switchEpisode(ep);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? primary.withValues(alpha: 0.14)
                                    : const Color(0xFF131722),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isCurrent
                                      ? primary.withValues(alpha: 0.85)
                                      : Colors.white.withValues(alpha: 0.07),
                                  width: isCurrent ? 1.3 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 96,
                                      height: 54,
                                      color: const Color(0xFF0B0E14),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (thumbUrl.isNotEmpty)
                                            CachedNetworkImage(
                                              imageUrl: wrapCorsSafeUrl(thumbUrl),
                                              fit: BoxFit.cover,
                                              memCacheWidth: 220,
                                              placeholder: (_, __) => const ColoredBox(
                                                color: Color(0xFF171C28),
                                              ),
                                              errorWidget: (_, __, ___) =>
                                                  _buildPortraitThumbFallback(),
                                            )
                                          else
                                            _buildPortraitThumbFallback(),
                                          if (isCurrent)
                                            Container(
                                              color: Colors.black.withValues(alpha: 0.45),
                                              alignment: Alignment.center,
                                              child: Container(
                                                padding: const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  color: primary,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  state.isPlaying
                                                      ? Icons.equalizer_rounded
                                                      : Icons.play_arrow_rounded,
                                                  color: Colors.white,
                                                  size: 15,
                                                ),
                                              ),
                                            )
                                          else
                                            Positioned(
                                              left: 5,
                                              bottom: 4,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 1.5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.72),
                                                  borderRadius: BorderRadius.circular(5),
                                                ),
                                                child: Text(
                                                  '#${ep.episode}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Серия ${ep.episode}',
                                          style: TextStyle(
                                            color: isCurrent
                                                ? primary
                                                : AppColors.textPrimary,
                                            fontWeight: isCurrent
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (ep.name != null && ep.name!.isNotEmpty)
                                              ? ep.name!
                                              : state.title.displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primary,
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: const Text(
                                        'СЕЙЧАС',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPortraitThumbFallback() {
    return Container(
      color: const Color(0xFF171C28),
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_creation_outlined,
        color: AppColors.textMuted,
        size: 20,
      ),
    );
  }

  Widget _buildPortraitDubbingSelector(
    BuildContext context,
    PlayerState state,
    Color primary,
  ) {
    if (!getIt.isRegistered<KodikCubit>()) {
      final activeName = state.currentTranslation?.studioName ?? 'AniLibria';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: primary.withValues(alpha: 0.7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, size: 14, color: primary),
                    const SizedBox(width: 6),
                    Text(
                      activeName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final kodikCubit = getIt<KodikCubit>();
    if (kodikCubit.state.translations.length <= 1 && !kodikCubit.state.isLoading) {
      kodikCubit.loadVoiceovers(
        shikimoriId: state.title.shikimoriId,
        title: state.title.displayTitle,
      );
    }

    return BlocBuilder<KodikCubit, KodikState>(
      bloc: kodikCubit,
      builder: (context, kodikState) {
        final studios = kodikState.translations.isNotEmpty
            ? kodikState.translations
            : <KodikTranslation>[
                KodikTranslation.anilibria(),
                const KodikTranslation(
                  id: 610,
                  title: 'StudioBand',
                  type: 'voice',
                  episodesCount: 12,
                ),
                const KodikTranslation(
                  id: 1978,
                  title: 'Dream Cast',
                  type: 'voice',
                  episodesCount: 12,
                ),
                const KodikTranslation(
                  id: 609,
                  title: 'AniDUB',
                  type: 'voice',
                  episodesCount: 12,
                ),
                const KodikTranslation(
                  id: 2148,
                  title: 'Субтитры',
                  type: 'subtitles',
                  episodesCount: 12,
                ),
              ];

        return SizedBox(
          height: 34,
          child: ListView.separated(
            key: const ValueKey('player_portrait_dubbing_list'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: studios.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final studio = studios[index];
              final isSelected =
                  kodikState.selectedTranslation.title.toLowerCase() ==
                      studio.title.toLowerCase();
              final isSub = studio.type == 'subtitles';

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _cubit.switchVoiceoverStudio(studio);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primary
                        : const Color(0xFF131722),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? primary
                          : Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSub ? Icons.subtitles_rounded : Icons.mic_rounded,
                        size: 13.5,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        studio.title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showCenterOsd(String message) {
    _centerOsdTimer?.cancel();
    if (mounted) {
      setState(() => _centerOsdMessage = message);
    }
    _centerOsdTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _centerOsdMessage = null);
    });
  }

  Future<void> _takeScreenshot() async {
    try {
      final boundary = _screenshotBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _showCenterOsd('Скриншот недоступен');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      Directory? baseDir;
      try {
        baseDir = await getDownloadsDirectory();
      } catch (_) {}
      baseDir ??= await getApplicationDocumentsDirectory();

      final saveDir = Directory('${baseDir.path}/SyncPai');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      final file = File(
        '${saveDir.path}/SyncPai_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);

      _screenshotToastTimer?.cancel();
      if (mounted) {
        setState(() => _screenshotPreviewBytes = bytes);
      }
      _screenshotToastTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _screenshotPreviewBytes = null);
      });
    } catch (e) {
      debugPrint('[PlayerScreen] Screenshot error: $e');
      _showCenterOsd('Не удалось сохранить скриншот');
    }
  }

  void _setSleepTimer({int? minutes, bool endOfEpisode = false}) {
    _sleepTimer?.cancel();
    setState(() {
      _sleepTimerMinutes = minutes;
      _sleepAtEndOfEpisode = endOfEpisode;
    });

    if (minutes != null && minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        if (mounted) {
          _cubit.pause();
          setState(() => _sleepTimerMinutes = null);
          _showCenterOsd('Таймер сна: пауза');
        }
      });
      _showCenterOsd('Таймер сна: $minutes мин');
    } else if (endOfEpisode) {
      final remaining = _cubit.state.duration - _cubit.state.position;
      if (remaining > Duration.zero) {
        _sleepTimer = Timer(remaining, () {
          if (mounted) {
            _cubit.pause();
            setState(() => _sleepAtEndOfEpisode = false);
            _showCenterOsd('Конец серии: пауза');
          }
        });
      }
      _showCenterOsd('Таймер: до конца серии');
    } else {
      _showCenterOsd('Таймер сна выключен');
    }
  }

  void _openSleepTimerSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Таймер сна',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Выкл'),
                      selected: _sleepTimerMinutes == null && !_sleepAtEndOfEpisode,
                      onSelected: (_) {
                        Navigator.of(sheetCtx).pop();
                        _setSleepTimer();
                      },
                    ),
                    for (final m in const [15, 30, 45])
                      ChoiceChip(
                        label: Text('$m мин'),
                        selected: _sleepTimerMinutes == m,
                        onSelected: (_) {
                          Navigator.of(sheetCtx).pop();
                          _setSleepTimer(minutes: m);
                        },
                      ),
                    ChoiceChip(
                      label: const Text('До конца серии'),
                      selected: _sleepAtEndOfEpisode,
                      onSelected: (_) {
                        Navigator.of(sheetCtx).pop();
                        _setSleepTimer(endOfEpisode: true);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePipAction() async {
    if (!kIsWeb && Platform.isAndroid) {
      final entered = await PipService.instance.enterPip();
      if (entered) return;
    }
    _minimizePlayer();
  }

  void _dismissOnboarding() {
    if (getIt.isRegistered<SettingsCubit>()) {
      getIt<SettingsCubit>().completePlayerOnboarding();
    }
    if (mounted) {
      setState(() => _showOnboarding = false);
    }
    if (!_cubit.state.isSyncRoom || _cubit.state.isHost) {
      _cubit.play();
    }
  }

  List<Widget> _buildSyncRoomReactionWidgets(PlayerState state) {
    final roomCode = state.roomCode;
    if (roomCode == null || roomCode.isEmpty) return const [];
    final rawPeer = state.peerName?.trim() ?? '';
    final senderName = rawPeer.isNotEmpty ? rawPeer : 'Участник';
    return [
      Positioned.fill(
        child: ReactionOverlayLayer(
          roomCode: roomCode,
          enabled: _watchReactionsEnabled,
        ),
      ),
      if (state.areControlsVisible)
        Positioned(
          left: 16,
          right: 16,
          bottom: 84,
          child: Center(
            child: ReactionDockBar(
              roomCode: roomCode,
              senderName: senderName,
              reactionsEnabled: _watchReactionsEnabled,
              onToggleEnabled: () {
                setState(() => _watchReactionsEnabled = !_watchReactionsEnabled);
              },
            ),
          ),
        ),
    ];
  }

  Widget _buildReactiveSkipOverlay() {
    return BlocSelector<
        PlayerCubit,
        PlayerState,
        ({
          int posSec,
          int durSec,
          int episode,
          bool controlsVisible,
          bool screenLocked,
          bool hudEditMode,
          int? countdown,
          String? errorMessage,
        })>(
      bloc: _cubit,
      selector: (s) => (
        posSec: s.position.inSeconds,
        durSec: s.duration.inSeconds,
        episode: s.episode.episode,
        controlsVisible: s.areControlsVisible,
        screenLocked: s.isScreenLocked,
        hudEditMode: s.isHudEditMode,
        countdown: s.autoNextCountdown,
        errorMessage: s.errorMessage,
      ),
      builder: (context, _) => _buildSkipOverlay(_cubit.state),
    );
  }

  Widget _buildSkipOverlay(PlayerState state) {
    if (state.errorMessage != null || state.isHudEditMode) {
      return const SizedBox.shrink();
    }

    final op = state.effectiveOpening;
    final ed = state.effectiveEnding;
    final curSec = state.position.inSeconds;
    final totalSec = state.duration.inSeconds;
    final curEpNum = state.episode.episode;
    if (_lastSkipEpisodeNum != curEpNum) {
      _lastSkipEpisodeNum = curEpNum;
      _dismissedOpeningEpisode = null;
      _dismissedEndingEpisode = null;
    }
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final primaryAccent = Theme.of(context).colorScheme.primary;

    // 1. Минималистичная кнопка пропуска опенинга в стиле Netflix (доступна даже при блокировке экрана)
    final isOpening = op != null &&
        curSec >= op.start &&
        curSec <= op.stop &&
        _dismissedOpeningEpisode != curEpNum;

    if (isOpening) {
      final segKey = 'op_${curEpNum}_${op.start}';
      if (_activeSkipSegmentKey != segKey) {
        _activeSkipSegmentKey = segKey;
        _skipPillCollapsed = false;
        _skipPillCollapseTimer?.cancel();
        _skipPillCollapseTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _skipPillCollapsed = true);
        });
      }
      if (state.areControlsVisible && !_lastControlsVisible) {
        _skipPillCollapsed = false;
        _skipPillCollapseTimer?.cancel();
        _skipPillCollapseTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _skipPillCollapsed = true);
        });
      }
      _lastControlsVisible = state.areControlsVisible;

      final skipCfg = getIt.isRegistered<SettingsCubit>()
          ? getIt<SettingsCubit>().state.hudConfigFor('skip_intro')
          : const PlayerHudButtonConfig(id: 'skip_intro', nx: 0.85, ny: 0.72);
      if (!skipCfg.visible && !state.isScreenLocked) {
        return const SizedBox.shrink();
      }

      return SafeArea(
        top: isLandscape,
        bottom: isLandscape,
        left: isLandscape,
        right: isLandscape,
        child: Align(
          alignment: isLandscape
              ? Alignment(skipCfg.nx * 2.0 - 1.0, skipCfg.ny * 2.0 - 1.0)
              : const Alignment(0.92, 0.42),
          child: Transform.scale(
            scale: skipCfg.scale,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('player_skip_intro_pill'),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _cubit.seek(op.stopDuration);
                  MascotCompanionService.instance.onOpeningSkipped();
                },
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  height: 36,
                  padding: EdgeInsets.symmetric(
                    horizontal: _skipPillCollapsed ? 9 : 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(15, 20, 30, 0.78),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF35D9D5).withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 200),
                        crossFadeState: _skipPillCollapsed
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text(
                            'Пропустить',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        secondChild: const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    _lastControlsVisible = state.areControlsVisible;

    // 2. Умная кнопка пропуска эндинга / перехода к следующей серии (работает и в последние 90 сек, и при блокировке экрана)
    if (_dismissedEndingEpisode == curEpNum) {
      return const SizedBox.shrink();
    }

    final allEpisodes = state.title.episodes;
    final curIdx = allEpisodes.indexWhere((e) => e.episode == curEpNum);
    final hasNext = curIdx >= 0 && curIdx < allEpisodes.length - 1;
    final nextEp = hasNext ? allEpisodes[curIdx + 1] : null;

    final isPreEndingCountdown =
        ed != null && ed.start > 30 && curSec >= ed.start - 10 && curSec < ed.start;
    final isInEndingSegment = ed != null && curSec >= ed.start && curSec <= ed.stop;
    final isEndOfEpisodeCountdown =
        totalSec > 60 && (totalSec - curSec) <= 10 && (totalSec - curSec) > 0;
    final isLast90Seconds =
        hasNext && totalSec > 90 && (totalSec - curSec) <= 90 && (totalSec - curSec) > 0;

    if (!isPreEndingCountdown &&
        !isInEndingSegment &&
        !isEndOfEpisodeCountdown &&
        !isLast90Seconds) {
      return const SizedBox.shrink();
    }

    final hasPostCredits = ed != null && totalSec > 0 && (totalSec - ed.stop) > 20;

    int countdownSec;
    if (state.autoNextCountdown != null) {
      countdownSec = state.autoNextCountdown!.clamp(1, 10);
    } else if (isPreEndingCountdown) {
      countdownSec = (ed.start - curSec).clamp(1, 10);
    } else if (isEndOfEpisodeCountdown) {
      countdownSec = (totalSec - curSec).clamp(1, 10);
    } else if (isInEndingSegment) {
      final elapsedInEnding = curSec - ed.start;
      countdownSec = (10 - (elapsedInEnding % 10)).clamp(1, 10);
    } else {
      countdownSec = (totalSec - curSec).clamp(1, 90);
    }

    final countdownProgress = (!isPreEndingCountdown &&
            !isInEndingSegment &&
            !isEndOfEpisodeCountdown &&
            isLast90Seconds)
        ? ((90 - (totalSec - curSec)) / 90.0).clamp(0.0, 1.0)
        : ((10 - countdownSec) / 10.0).clamp(0.0, 1.0);

    final String buttonLabel;
    if (isPreEndingCountdown) {
      buttonLabel = 'До эндинга • $countdownSecс';
    } else if (hasPostCredits) {
      buttonLabel = 'Пропустить эндинг • $countdownSecс';
    } else if (hasNext && (isInEndingSegment || isEndOfEpisodeCountdown)) {
      buttonLabel = 'Следующая серия • $countdownSecс';
    } else if (hasNext && isLast90Seconds) {
      buttonLabel = 'След. серия • $countdownSecс';
    } else {
      buttonLabel = 'Пропустить эндинг • $countdownSecс';
    }

    // Единая пилюля завершения серии / перехода (одинаковая позиция, вид и таймер для locked и unlocked)
    return Positioned(
      right: isLandscape ? 16 : 12,
      bottom: isLandscape ? 72 : 48,
      child: _UnifiedEndingNextPill(
        key: const ValueKey('unified_ending_next_pill'),
        label: buttonLabel,
        progress: countdownProgress,
        primaryAccent: primaryAccent,
        isNextEpisodeAction:
            hasNext && !hasPostCredits && !isPreEndingCountdown,
        onAction: () {
          HapticFeedback.mediumImpact();
          if (!isPreEndingCountdown &&
              !hasPostCredits &&
              hasNext &&
              nextEp != null) {
            _cubit.playNextEpisode(nextEp);
          } else if (ed != null) {
            _cubit.seek(ed.stopDuration);
            if (hasNext && nextEp != null && !hasPostCredits) {
              _cubit.startAutoNextCountdown(nextEp);
            }
          }
        },
        onDismiss: () {
          _cubit.cancelAutoNextCountdown();
          setState(() => _dismissedEndingEpisode = curEpNum);
        },
      ),
    );
  }
}

class _UnifiedEndingNextPill extends StatelessWidget {
  final String label;
  final double progress;
  final Color primaryAccent;
  final bool isNextEpisodeAction;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  const _UnifiedEndingNextPill({
    super.key,
    required this.label,
    required this.progress,
    required this.primaryAccent,
    required this.isNextEpisodeAction,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 210),
        decoration: BoxDecoration(
          color: const Color(0xFF12151E).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primaryAccent.withValues(alpha: 0.6),
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
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onAction,
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 2.2,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.16),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(primaryAccent),
                              ),
                              Icon(
                                isNextEpisodeAction
                                    ? Icons.skip_next_rounded
                                    : Icons.fast_forward_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.0,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Остаться',
                    child: InkWell(
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 3,
              width: 220,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
