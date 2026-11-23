import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sync_badge.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';
import '../../../sync_room/presentation/widgets/in_room_anime_picker_sheet.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'floating_pai_chan_reactions_overlay.dart';
import 'player_episodes_sheet.dart';
import 'player_hud_2d_canvas.dart';
import 'player_progress_bar.dart';
import 'player_settings_sheet.dart';
import 'presence_radar_badge.dart';
import 'quick_phrases_bar.dart';
import 'sync_chat_input_bar.dart';

class PlayerControlsOverlay extends StatefulWidget {
  final PlayerCubit cubit;
  final PlayerState state;
  final VoidCallback onBack;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleOrientation;
  final VoidCallback? onTakeScreenshot;
  final VoidCallback? onOpenSleepTimer;
  final VoidCallback? onEnterPip;
  final ValueChanged<BoxFit>? onAspectRatioChanged;
  final SyncStatus? syncStatus;
  final String? syncPeerName;

  const PlayerControlsOverlay({
    super.key,
    required this.cubit,
    required this.state,
    required this.onBack,
    this.onMinimize,
    this.onToggleOrientation,
    this.onTakeScreenshot,
    this.onOpenSleepTimer,
    this.onEnterPip,
    this.onAspectRatioChanged,
    this.syncStatus,
    this.syncPeerName,
  });

  @override
  State<PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

class _PlayerControlsOverlayState extends State<PlayerControlsOverlay> {
  String? _selectedEditButtonId;
  double _rawDragNx = 0.5;
  double _rawDragNy = 0.5;
  bool _snapXActive = false;
  bool _snapYActive = false;

  PlayerCubit get cubit => widget.cubit;
  PlayerState get state => widget.state;
  VoidCallback get onBack => widget.onBack;
  VoidCallback? get onMinimize => widget.onMinimize;
  VoidCallback? get onToggleOrientation => widget.onToggleOrientation;
  SyncStatus? get syncStatus => widget.syncStatus;
  String? get syncPeerName => widget.syncPeerName;

  @override
  void didUpdateWidget(covariant PlayerControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isHudEditMode && !widget.state.isHudEditMode) {
      _selectedEditButtonId = null;
      _snapXActive = false;
      _snapYActive = false;
    }
  }

  void _onDragStart(PlayerHudButtonConfig config) {
    setState(() {
      _selectedEditButtonId = config.id;
      _rawDragNx = config.nx;
      _rawDragNy = config.ny;
      _snapXActive = (config.nx - 0.5).abs() <= 0.001;
      _snapYActive = (config.ny - 0.5).abs() <= 0.001;
    });
  }

  void _onDragUpdate(
    String id,
    DragUpdateDetails details,
    Size canvasSize,
    SettingsCubit? settingsCubit,
  ) {
    final spanW = canvasSize.width > 96
        ? canvasSize.width - 48
        : canvasSize.width.clamp(1.0, double.infinity);
    final spanH = canvasSize.height > 96
        ? canvasSize.height - 48
        : canvasSize.height.clamp(1.0, double.infinity);

    _rawDragNx = (_rawDragNx + details.delta.dx / spanW)
        .clamp(PlayerHudButtonConfig.minNx, PlayerHudButtonConfig.maxNx)
        .toDouble();
    _rawDragNy = (_rawDragNy + details.delta.dy / spanH)
        .clamp(PlayerHudButtonConfig.minNy, PlayerHudButtonConfig.maxNy)
        .toDouble();

    final nextSnapX = (_rawDragNx - 0.5).abs() <= 0.02;
    final nextSnapY = (_rawDragNy - 0.5).abs() <= 0.02;
    if ((nextSnapX && !_snapXActive) || (nextSnapY && !_snapYActive)) {
      HapticFeedback.selectionClick();
    }

    final effectiveNx = nextSnapX ? 0.5 : _rawDragNx;
    final effectiveNy = nextSnapY ? 0.5 : _rawDragNy;

    setState(() {
      _snapXActive = nextSnapX;
      _snapYActive = nextSnapY;
    });

    settingsCubit?.updateHudButtonConfig(
      id,
      nx: effectiveNx,
      ny: effectiveNy,
      persist: false,
    );
  }

  void _onDragEnd(SettingsCubit? settingsCubit) {
    setState(() {
      _snapXActive = false;
      _snapYActive = false;
    });
    settingsCubit?.persistHudLayout();
  }

  @override
  Widget build(BuildContext context) {
    final title = state.title;
    final ep = state.episode;
    final allEpisodes = title.episodes;
    final currentIndex = allEpisodes.indexWhere((e) => e.episode == ep.episode);
    final hasNextEpisode =
        currentIndex >= 0 && currentIndex < allEpisodes.length - 1;
    final hasPrevEpisode = currentIndex > 0;
    final isGuestInSync = state.isSyncRoom && !state.isHost;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isShort = MediaQuery.of(context).size.height < 520;
    if (state.isScreenLocked) return const SizedBox.shrink();

    final settingsCubit =
        getIt.isRegistered<SettingsCubit>() ? getIt<SettingsCubit>() : null;

    Widget buildWithSettings(SettingsState settingsState) {
      final isVisibleOverlay = state.areControlsVisible || state.isHudEditMode;

      return IgnorePointer(
        ignoring: !isVisibleOverlay,
        child: AnimatedOpacity(
          opacity: isVisibleOverlay ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: state.isHudEditMode
                ? () => setState(() => _selectedEditButtonId = null)
                : () => cubit.toggleControls(),
            onDoubleTapDown: state.isHudEditMode
                ? null
                : (details) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final dx = details.globalPosition.dx;
                    if (dx < screenWidth * 0.38) {
                      cubit.seekRelative(-10);
                    } else if (dx > screenWidth * 0.62) {
                      cubit.seekRelative(10);
                    } else {
                      cubit.togglePlayPause();
                    }
                  },
            onDoubleTap: state.isHudEditMode ? null : () {},
            onVerticalDragUpdate: state.isHudEditMode
                ? null
                : (details) {
                    final deltaPx = details.primaryDelta;
                    if (deltaPx == null) return;
                    final screenWidth = MediaQuery.of(context).size.width;
                    final isLeft = details.globalPosition.dx < (screenWidth / 2);
                    final screenHeight = MediaQuery.of(context).size.height;
                    final delta = -deltaPx / (screenHeight * 0.65);
                    if (isLeft) {
                      cubit.setBrightness(
                        (state.brightness + delta).clamp(0.05, 1.0),
                      );
                    } else {
                      cubit.setVolume(
                        (state.volume + (delta * 100.0)).clamp(0.0, 100.0),
                      );
                    }
                  },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.22, 0.65, 0.88, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: isLandscape ? 0.70 : 0.80),
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isLandscape ? 0.72 : 0.82),
                    Colors.black.withValues(alpha: isLandscape ? 0.90 : 0.95),
                  ],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. ВЕРХНИЙ БАР (назад, название, статусы Watch Together, настройки)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            ignoring: state.isHudEditMode,
                            child: Opacity(
                              opacity: state.isHudEditMode ? 0.32 : 1.0,
                              child: _buildTopHeaderBar(
                                context,
                                isLandscape: isLandscape,
                              ),
                            ),
                          ),
                        ),

                        // 2. НИЖНИЙ БАР (таймлайн, быстрые фразы, реакции комнаты)
                        if (state.errorMessage == null || state.isPlaying)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: state.isHudEditMode,
                              child: Opacity(
                                opacity: state.isHudEditMode ? 0.32 : 1.0,
                                child: _buildBottomBar(
                                  context,
                                  isLandscape: isLandscape,
                                  isShort: isShort,
                                  isGuestInSync: isGuestInSync,
                                ),
                              ),
                            ),
                          ),

                        // 3. ВЫРАВНИВАЮЩАЯ СЕТКА И ЦЕНТРАЛЬНЫЕ МАГНИТНЫЕ ЛИНИИ В РЕЖИМЕ НАСТРОЙКИ
                        if (state.isHudEditMode)
                          PlayerHudEditGridOverlay(
                            snapXActive: _snapXActive,
                            snapYActive: _snapYActive,
                          ),

                        // 4. КНОПКА ЗАПРОСА ПАУЗЫ ДЛЯ УЧАСТНИКА КОМНАТЫ (не хост)
                        if (isGuestInSync && !state.isHudEditMode)
                          Align(
                            alignment: Alignment.center,
                            child: _buildGuestPauseButton(context),
                          ),

                        // 5. СВОБОДНЫЙ 2D-ХОЛСТ КНОПОК HUD (позиционирование nx/ny + scale)
                        ..._buildFreeFormHudButtons(
                          context,
                          settingsState: settingsState,
                          settingsCubit: settingsCubit,
                          canvasSize: canvasSize,
                          isLandscape: isLandscape,
                          isGuestInSync: isGuestInSync,
                          allEpisodes: allEpisodes,
                          currentIndex: currentIndex,
                          hasPrevEpisode: hasPrevEpisode,
                          hasNextEpisode: hasNextEpisode,
                        ),

                        // 6. ПЛАВАЮЩИЙ ИНСПЕКТОР ВЫБРАННОЙ КНОПКИ И ПРЕСЕТОВ (TOP-CENTER)
                        if (state.isHudEditMode)
                          PlayerHudInspectorPill(
                            settingsCubit: settingsCubit,
                            settingsState: settingsState,
                            selectedButtonId: _selectedEditButtonId,
                            onSelectButton: (id) =>
                                setState(() => _selectedEditButtonId = id),
                            onDone: () {
                              setState(() => _selectedEditButtonId = null);
                              cubit.setHudEditMode(false);
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (settingsCubit == null) {
      return buildWithSettings(const SettingsState());
    }
    return BlocBuilder<SettingsCubit, SettingsState>(
      bloc: settingsCubit,
      builder: (context, settingsState) => buildWithSettings(settingsState),
    );
  }

  Widget _buildTopHeaderBar(
    BuildContext context, {
    required bool isLandscape,
  }) {
    final title = state.title;
    final ep = state.episode;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 16 : AppDimensions.spacingLg,
        vertical: isLandscape ? 2 : AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
            ),
            iconSize: isLandscape ? 18 : 22,
            visualDensity:
                isLandscape ? VisualDensity.compact : VisualDensity.standard,
            onPressed: onBack,
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isLandscape
                      ? AppTypography.titleSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        )
                      : AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                ),
                Text(
                  'Серия ${ep.episode}${ep.name != null && ep.name!.isNotEmpty ? ' — ${ep.name}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: isLandscape ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.isSyncRoom) ...[
                    Container(
                      key: const ValueKey('player_overlay_role_pill'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: state.isHost
                            ? AppColors.primary.withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: state.isHost
                              ? AppColors.primaryLight.withValues(alpha: 0.7)
                              : Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state.isHost
                                ? Icons.verified_user_rounded
                                : Icons.person_outline_rounded,
                            size: 11,
                            color: state.isHost
                                ? AppColors.primaryLight
                                : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.isHost ? 'Хост комнаты' : 'Участник',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: state.isHost
                                  ? AppColors.primaryLight
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    PresenceRadarBadge(
                      presence: state.peerPresence,
                      fallbackName: syncPeerName ?? 'Друг',
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: state.isPeerBuffering
                            ? AppColors.warning.withValues(alpha: 0.2)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: state.isPeerBuffering
                              ? AppColors.warning
                              : (state.peerPingMs > 150
                                  ? AppColors.warning
                                  : AppColors.syncActive.withValues(alpha: 0.6)),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state.isPeerBuffering
                                ? Icons.hourglass_top_rounded
                                : Icons.wifi_rounded,
                            size: 11,
                            color: state.isPeerBuffering
                                ? AppColors.warning
                                : AppColors.syncActive,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.isPeerBuffering
                                ? 'Буфер'
                                : '${state.peerPingMs}ms',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: state.isPeerBuffering
                                  ? AppColors.warning
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const ValueKey('player_switch_room_anime_btn'),
                      tooltip: 'Сменить аниме в комнате',
                      icon: Icon(
                        Icons.swap_horiz_rounded,
                        color: AppColors.primaryLight,
                      ),
                      iconSize: isLandscape ? 19 : 21,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        InRoomAnimePickerSheet.show(
                          context,
                          roomCode: state.roomCode,
                          currentTitle: state.title,
                          onAnimeSelected: (newTitle) =>
                              cubit.switchAnimeInRoom(newTitle),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Итоги просмотра (Сторис)',
                      icon: Icon(
                        Icons.auto_awesome_rounded,
                        color: AppColors.primaryLight,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => cubit.toggleWatchPartyStats(),
                    ),
                  ] else if (syncStatus != null) ...[
                    SyncBadge(status: syncStatus!, peerName: syncPeerName),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    key: const ValueKey('hud_action_settings_gear'),
                    tooltip: 'Настройки плеера',
                    icon: Icon(
                      Icons.settings_outlined,
                      color: AppColors.textPrimary,
                      size: isLandscape ? 19 : 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => PlayerSettingsSheet.show(
                      context,
                      cubit: cubit,
                      state: state,
                      onMinimizeToMiniPlayer: onMinimize,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestPauseButton(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.9),
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.syncActive),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      icon: Icon(
        state.isPlaying
            ? Icons.pause_circle_outline_rounded
            : Icons.play_circle_outline_rounded,
        color: AppColors.syncActive,
        size: 26,
      ),
      label: Text(
        state.isPlaying ? 'Попросить паузу' : 'Ожидание хоста',
        style: AppTypography.labelLarge,
      ),
      onPressed: () {
        cubit.requestPauseFromHost();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запрос на паузу отправлен хосту'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  List<Widget> _buildFreeFormHudButtons(
    BuildContext context, {
    required SettingsState settingsState,
    required SettingsCubit? settingsCubit,
    required Size canvasSize,
    required bool isLandscape,
    required bool isGuestInSync,
    required List<EpisodeItem> allEpisodes,
    required int currentIndex,
    required bool hasPrevEpisode,
    required bool hasNextEpisode,
  }) {
    final widgets = <Widget>[];
    final hasError = state.errorMessage != null;

    for (final meta in kPlayerHud2DButtons) {
      final config = settingsState.hudConfigFor(meta.id);
      if (!config.visible) continue;

      if (!state.isHudEditMode) {
        if (meta.id == 'skip_intro') continue;
        if (hasError &&
            (meta.id == 'play_pause' ||
                meta.id == 'seek_back' ||
                meta.id == 'seek_forward')) {
          continue;
        }
        if (isGuestInSync &&
            (meta.id == 'play_pause' ||
                meta.id == 'seek_back' ||
                meta.id == 'seek_forward' ||
                meta.id == 'next_episode')) {
          continue;
        }
      }

      final button = _buildSingle2DControl(
        context,
        id: meta.id,
        isLandscape: isLandscape,
        allEpisodes: allEpisodes,
        currentIndex: currentIndex,
        hasPrevEpisode: hasPrevEpisode,
        hasNextEpisode: hasNextEpisode,
      );
      if (button == null) continue;

      widgets.add(
        PlayerHudDraggableButton(
          config: config,
          isEditMode: state.isHudEditMode,
          isSelected: _selectedEditButtonId == config.id,
          onTapSelect: () => setState(() => _selectedEditButtonId = config.id),
          onDragStart: () => _onDragStart(config),
          onDragUpdate: (details) => _onDragUpdate(
            config.id,
            details,
            canvasSize,
            settingsCubit,
          ),
          onDragEnd: () => _onDragEnd(settingsCubit),
          child: button,
        ),
      );
    }

    return widgets;
  }

  Widget? _buildSingle2DControl(
    BuildContext context, {
    required String id,
    required bool isLandscape,
    required List<EpisodeItem> allEpisodes,
    required int currentIndex,
    required bool hasPrevEpisode,
    required bool hasNextEpisode,
  }) {
    switch (id) {
      case 'play_pause':
        return Material(
          key: const ValueKey('hud_center_play_pause'),
          color: Theme.of(context).colorScheme.primary,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => cubit.playOrPause(),
            child: Padding(
              padding: EdgeInsets.all(isLandscape ? 12 : AppDimensions.spacingLg),
              child: SizedBox(
                width: isLandscape ? 32 : 44,
                height: isLandscape ? 32 : 44,
                child: Center(
                  child: state.isBuffering
                      ? SizedBox(
                          width: isLandscape ? 24 : 30,
                          height: isLandscape ? 24 : 30,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(
                          state.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: isLandscape ? 32 : 44,
                          color: AppColors.textPrimary,
                        ),
                ),
              ),
            ),
          ),
        );

      case 'seek_back':
        return IconButton(
          key: const ValueKey('hud_center_seek_back'),
          iconSize: isLandscape ? 32 : 40,
          icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
          onPressed: () => cubit.seekRelative(-10),
        );

      case 'seek_forward':
        return IconButton(
          key: const ValueKey('hud_center_seek_forward'),
          iconSize: isLandscape ? 32 : 40,
          icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
          onPressed: () => cubit.seekRelative(10),
        );

      case 'skip_intro':
        return Container(
          key: const ValueKey('hud_edit_skip_intro'),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(15, 20, 30, 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF35D9D5).withValues(alpha: 0.55),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.skip_next_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'Пропустить',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );

      case 'next_episode':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('hud_action_episodes'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Список серий',
                icon: const Icon(
                  Icons.video_library_rounded,
                  color: AppColors.textPrimary,
                  size: 19,
                ),
                onPressed: () => PlayerEpisodesSheet.show(
                  context,
                  cubit: cubit,
                  state: state,
                ),
              ),
              if (hasPrevEpisode)
                IconButton(
                  key: const ValueKey('hud_bottom_prev_episode'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Пред. серия',
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: AppColors.textPrimary,
                    size: 20,
                  ),
                  onPressed: () => cubit.switchEpisode(allEpisodes[currentIndex - 1]),
                ),
              IconButton(
                key: const ValueKey('hud_bottom_next_episode'),
                visualDensity: VisualDensity.compact,
                tooltip: 'След. серия',
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: hasNextEpisode
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                  size: 20,
                ),
                onPressed: hasNextEpisode
                    ? () => cubit.switchEpisode(allEpisodes[currentIndex + 1])
                    : () => PlayerEpisodesSheet.show(
                          context,
                          cubit: cubit,
                          state: state,
                        ),
              ),
            ],
          ),
        );

      case 'speed':
        return InkWell(
          key: const ValueKey('hud_action_speed'),
          onTap: () => _showQuickSpeedSheet(context),
          borderRadius: AppDimensions.borderRadiusSmall,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.90),
              borderRadius: AppDimensions.borderRadiusSmall,
              border: Border.all(color: AppColors.strokeMedium),
            ),
            child: Text(
              '${state.playbackRate}x',
              style: AppTypography.badge.copyWith(
                color: AppColors.textPrimary,
                fontSize: 11.5,
              ),
            ),
          ),
        );

      case 'quality_dub':
        return InkWell(
          key: const ValueKey('hud_bottom_quality'),
          onTap: () => _showQuickQualitySheet(context),
          borderRadius: AppDimensions.borderRadiusSmall,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.90),
              borderRadius: AppDimensions.borderRadiusSmall,
              border: Border.all(color: AppColors.strokeMedium),
            ),
            child: Text(
              state.selectedQuality == PlayerQuality.fhd
                  ? '1080p'
                  : state.selectedQuality == PlayerQuality.hd
                      ? '720p'
                      : '480p',
              style: AppTypography.badge.copyWith(
                color: AppColors.textPrimary,
                fontSize: 11.5,
              ),
            ),
          ),
        );

      case 'lock_screen':
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const ValueKey('hud_action_lock_screen'),
            tooltip: 'Заблокировать экран',
            icon: const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.textPrimary,
            ),
            iconSize: isLandscape ? 19 : 21,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              HapticFeedback.lightImpact();
              cubit.toggleScreenLock();
            },
          ),
        );

      case 'fullscreen':
        if (onToggleOrientation == null && !state.isHudEditMode) {
          return null;
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const ValueKey('hud_bottom_fullscreen'),
            tooltip: isLandscape ? 'Портретный режим' : 'Альбомный режим',
            icon: Icon(
              isLandscape
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: onToggleOrientation ?? () {},
          ),
        );

      case 'pip_mode':
        if (onMinimize == null && widget.onEnterPip == null && !state.isHudEditMode) {
          return null;
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const ValueKey('hud_action_pip'),
            tooltip: 'Картинка в картинке (PiP)',
            icon: const Icon(
              Icons.picture_in_picture_alt_rounded,
              color: AppColors.textPrimary,
            ),
            iconSize: isLandscape ? 18 : 20,
            visualDensity: VisualDensity.compact,
            onPressed: widget.onEnterPip ?? onMinimize ?? () {},
          ),
        );

      default:
        return null;
    }
  }

  Widget _buildBottomBar(
    BuildContext context, {
    required bool isLandscape,
    required bool isShort,
    required bool isGuestInSync,
  }) {
    final ep = state.episode;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (isLandscape || isShort) ? 16 : AppDimensions.spacingXl,
        vertical: (isLandscape || isShort) ? 4 : AppDimensions.spacingMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.isSyncRoom &&
              ep.opening != null &&
              state.position.inSeconds >= ep.opening!.start &&
              state.position.inSeconds < ep.opening!.stop)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: state.hasVotedCoopSkip
                        ? AppColors.syncActive
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: state.coopSkipVotes > 0 ? 6 : 2,
                    shadowColor: AppColors.primary.withValues(alpha: 0.6),
                  ),
                  icon: const Icon(Icons.fast_forward_rounded, size: 16),
                  label: Text(
                    state.coopSkipVotes > 0
                        ? 'Друг хочет скипнуть! (${state.coopSkipVotes}/2)'
                        : 'Пропустить опенинг (0/2)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () => cubit.voteCoopSkip(),
                ),
              ),
            ),

          if (state.isSyncRoom && !(isLandscape || isShort))
            QuickPhrasesBar(cubit: cubit),

          if (state.isSyncRoom && !(isLandscape || isShort))
            _buildSyncReactionsBar(context),

          if (state.isPeerTalking)
            Container(
              margin: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.syncActive.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.syncActive),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    color: AppColors.syncActive,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Друг говорит (громкость фильма -35%)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          PlayerProgressBar(
            position: state.position,
            duration: state.duration,
            buffer: state.buffer,
            heatmap: state.heatmap,
            opening: state.effectiveOpening,
            ending: state.effectiveEnding,
            isBuffering: state.isBuffering,
            onSeek: (pos) => cubit.seek(pos),
            isLocked: isGuestInSync,
            onLockedTap: () => cubit.showGuestPlaybackLockedNotice(),
          ),

          if (isGuestInSync)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Переключением серий управляет хост',
                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
              ),
            ),

          if (state.isSyncRoom && (isLandscape || isShort))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildCompactLandscapeSyncBar(context),
            ),
        ],
      ),
    );
  }

  Widget _buildSyncReactionsBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaiChanStickerReactionBar(
            compact: true,
            onStickerSelected: (sticker) => cubit.sendReaction(sticker.id),
          ),
          Container(
            height: 18,
            width: 1,
            color: AppColors.strokeMedium,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          InkWell(
            onTap: () => SyncChatInputSheet.show(context, cubit: cubit),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.forum_outlined,
                    size: 15,
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Чат',
                    style: AppTypography.labelLarge.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 18,
            width: 1,
            color: AppColors.strokeMedium,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          GestureDetector(
            onTap: () => cubit.toggleVoiceMute(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: state.isVoiceMuted
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.syncActive.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: state.isVoiceMuted
                      ? Colors.white.withValues(alpha: 0.1)
                      : AppColors.syncActive,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    state.isVoiceMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    size: 14,
                    color: state.isVoiceMuted
                        ? AppColors.textMuted
                        : AppColors.syncActive,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    state.isVoiceMuted ? 'Шёпот' : 'В эфире',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: state.isVoiceMuted
                          ? AppColors.textMuted
                          : AppColors.syncActive,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLandscapeSyncBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaiChanStickerReactionBar(
            compact: true,
            onStickerSelected: (sticker) => cubit.sendReaction(sticker.id),
          ),
          Container(
            height: 14,
            width: 1,
            color: AppColors.strokeMedium,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          InkWell(
            onTap: () => cubit.toggleVoiceMute(),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(
                state.isVoiceMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 15,
                color: state.isVoiceMuted
                    ? AppColors.textMuted
                    : AppColors.syncActive,
              ),
            ),
          ),
          InkWell(
            onTap: () => SyncChatInputSheet.show(context, cubit: cubit),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(
                Icons.forum_outlined,
                size: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuickSpeedSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
        final primary = Theme.of(context).colorScheme.primary;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.speed_rounded, size: 20, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Скорость воспроизведения',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              ...speeds.map((rate) {
                final isSelected = (state.playbackRate - rate).abs() < 0.05;
                return ListTile(
                  dense: true,
                  title: Text(
                    '${rate}x${rate == 1.0 ? ' (Обычная)' : ''}',
                    style: TextStyle(
                      color: isSelected ? primary : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: primary, size: 20)
                      : null,
                  onTap: () {
                    cubit.setPlaybackRate(rate);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showQuickQualitySheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final primary = Theme.of(context).colorScheme.primary;
        final qualities = [
          (PlayerQuality.fhd, '1080p (Full HD)'),
          (PlayerQuality.hd, '720p (HD)'),
          (PlayerQuality.sd, '480p (SD)'),
        ];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.high_quality_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Качество видео',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              ...qualities.map((item) {
                final isSelected = state.selectedQuality == item.$1;
                return ListTile(
                  dense: true,
                  title: Text(
                    item.$2,
                    style: TextStyle(
                      color: isSelected ? primary : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: primary, size: 20)
                      : null,
                  onTap: () {
                    cubit.changeQuality(item.$1);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
