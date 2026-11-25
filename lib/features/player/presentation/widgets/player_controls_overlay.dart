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
  bool _isDraggingHud = false;
  late final ValueNotifier<Map<String, PlayerHudButtonConfig>> _draftLayout;
  final ValueNotifier<({bool snapX, bool snapY, double? guideNx, double? guideNy})>
      _snapGuides = ValueNotifier((
    snapX: false,
    snapY: false,
    guideNx: null,
    guideNy: null,
  ));

  PlayerCubit get cubit => widget.cubit;
  PlayerState get state => widget.state;
  VoidCallback get onBack => widget.onBack;
  VoidCallback? get onMinimize => widget.onMinimize;
  VoidCallback? get onToggleOrientation => widget.onToggleOrientation;
  SyncStatus? get syncStatus => widget.syncStatus;
  String? get syncPeerName => widget.syncPeerName;

  @override
  void initState() {
    super.initState();
    final initial = getIt.isRegistered<SettingsCubit>()
        ? getIt<SettingsCubit>().state.hudLayout
        : const SettingsState().hudLayout;
    _draftLayout = ValueNotifier(Map<String, PlayerHudButtonConfig>.from(initial));
  }

  @override
  void dispose() {
    _draftLayout.dispose();
    _snapGuides.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlayerControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isHudEditMode && !widget.state.isHudEditMode) {
      _selectedEditButtonId = null;
      _isDraggingHud = false;
      _snapGuides.value = (
        snapX: false,
        snapY: false,
        guideNx: null,
        guideNy: null,
      );
    }
  }

  static const Set<String> _topRowButtonIds = {
    'lock_screen',
    'speed',
    'quality_dub',
    'pip_mode',
    'settings',
  };

  static const Set<String> _bottomRowButtonIds = {
    'next_episode',
    'fullscreen',
  };

  bool _isDockedInTopBar(PlayerHudButtonConfig cfg) =>
      _topRowButtonIds.contains(cfg.id) && (cfg.ny - 0.08).abs() <= 0.04;

  bool _isDockedInBottomBar(PlayerHudButtonConfig cfg) =>
      _bottomRowButtonIds.contains(cfg.id) && (cfg.ny - 0.82).abs() <= 0.05;

  void _onDragStart(PlayerHudButtonConfig config) {
    if (PlayerHudButtonConfig.isLockedCenterControl(config.id)) {
      if (_selectedEditButtonId != config.id) {
        setState(() => _selectedEditButtonId = config.id);
      }
      return;
    }
    _isDraggingHud = true;
    _rawDragNx = config.nx;
    _rawDragNy = config.ny;
    _snapGuides.value = (
      snapX: (config.nx - 0.5).abs() <= 0.001,
      snapY: (config.ny - 0.5).abs() <= 0.001,
      guideNx: null,
      guideNy: null,
    );
    if (_selectedEditButtonId != config.id) {
      setState(() => _selectedEditButtonId = config.id);
    }
  }

  void _onDragUpdate(
    String id,
    DragUpdateDetails details,
    Size canvasSize,
  ) {
    if (PlayerHudButtonConfig.isLockedCenterControl(id)) return;
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

    const step = 0.02;
    const snapThreshold = 0.02;

    double effectiveNx = ((_rawDragNx / step).round() * step)
        .clamp(PlayerHudButtonConfig.minNx, PlayerHudButtonConfig.maxNx)
        .toDouble();
    double effectiveNy = ((_rawDragNy / step).round() * step)
        .clamp(PlayerHudButtonConfig.minNy, PlayerHudButtonConfig.maxNy)
        .toDouble();

    final currentMap = _draftLayout.value;
    double? guideNx;
    double? guideNy;
    final nextSnapX = (_rawDragNx - 0.5).abs() <= snapThreshold;
    final nextSnapY = (_rawDragNy - 0.5).abs() <= snapThreshold;

    if (nextSnapX) {
      effectiveNx = 0.5;
    } else {
      double bestDx = snapThreshold + 0.001;
      for (final other in currentMap.values) {
        if (other.id == id || !other.visible) continue;
        final dx = (_rawDragNx - other.nx).abs();
        if (dx <= snapThreshold && dx < bestDx) {
          bestDx = dx;
          effectiveNx = other.nx;
          guideNx = other.nx;
        }
      }
    }

    if (nextSnapY) {
      effectiveNy = 0.5;
    } else {
      double bestDy = snapThreshold + 0.001;
      for (final other in currentMap.values) {
        if (other.id == id || !other.visible) continue;
        final dy = (_rawDragNy - other.ny).abs();
        if (dy <= snapThreshold && dy < bestDy) {
          bestDy = dy;
          effectiveNy = other.ny;
          guideNy = other.ny;
        }
      }
    }

    final prevGuides = _snapGuides.value;
    if ((nextSnapX && !prevGuides.snapX) ||
        (nextSnapY && !prevGuides.snapY) ||
        (guideNx != null && prevGuides.guideNx != guideNx) ||
        (guideNy != null && prevGuides.guideNy != guideNy)) {
      HapticFeedback.selectionClick();
    }

    _snapGuides.value = (
      snapX: nextSnapX,
      snapY: nextSnapY,
      guideNx: guideNx,
      guideNy: guideNy,
    );

    final prevBtn = currentMap[id] ?? PlayerHudButtonConfig(id: id, nx: 0.5, ny: 0.5);
    final nextBtn = prevBtn.copyWith(nx: effectiveNx, ny: effectiveNy);
    if (nextBtn != prevBtn) {
      _draftLayout.value = Map<String, PlayerHudButtonConfig>.from(currentMap)
        ..[id] = nextBtn;
    }
  }

  void _onDragEnd(SettingsCubit? settingsCubit, Size canvasSize) {
    final draggedId = _selectedEditButtonId;
    if (draggedId != null && !PlayerHudButtonConfig.isLockedCenterControl(draggedId)) {
      final map = _draftLayout.value;
      final current = map[draggedId];
      if (current != null) {
        final nudged = _ensureMinSeparation(draggedId, current, map, canvasSize);
        if (nudged != current) {
          _draftLayout.value = Map<String, PlayerHudButtonConfig>.from(map)
            ..[draggedId] = nudged;
        }
      }
    }
    _isDraggingHud = false;
    _snapGuides.value = (
      snapX: false,
      snapY: false,
      guideNx: null,
      guideNy: null,
    );
    settingsCubit?.applyHudLayout(_draftLayout.value);
  }

  PlayerHudButtonConfig _ensureMinSeparation(
    String id,
    PlayerHudButtonConfig candidate,
    Map<String, PlayerHudButtonConfig> layout,
    Size canvasSize,
  ) {
    final spanW = canvasSize.width > 96 ? canvasSize.width - 48 : canvasSize.width;
    final spanH = canvasSize.height > 96 ? canvasSize.height - 48 : canvasSize.height;
    if (spanW <= 0 || spanH <= 0) return candidate;

    const minDist = 52.0;
    const minDistSq = minDist * minDist;

    bool isFree(double nx, double ny) {
      final cx = nx * spanW;
      final cy = ny * spanH;
      for (final other in layout.values) {
        if (other.id == id || !other.visible) continue;
        final dx = cx - (other.nx * spanW);
        final dy = cy - (other.ny * spanH);
        if ((dx * dx + dy * dy) < minDistSq) return false;
      }
      return true;
    }

    if (isFree(candidate.nx, candidate.ny)) return candidate;

    const step = 0.02;
    for (int ring = 1; ring <= 8; ring++) {
      for (int ix = -ring; ix <= ring; ix++) {
        for (int iy = -ring; iy <= ring; iy++) {
          if (ix.abs() != ring && iy.abs() != ring) continue;
          final testNx = (candidate.nx + ix * step)
              .clamp(PlayerHudButtonConfig.minNx, PlayerHudButtonConfig.maxNx)
              .toDouble();
          final testNy = (candidate.ny + iy * step)
              .clamp(PlayerHudButtonConfig.minNy, PlayerHudButtonConfig.maxNy)
              .toDouble();
          if (isFree(testNx, testNy)) {
            return candidate.copyWith(nx: testNx, ny: testNy);
          }
        }
      }
    }
    return candidate;
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
      if (!_isDraggingHud && _draftLayout.value != settingsState.hudLayout) {
        _draftLayout.value = Map<String, PlayerHudButtonConfig>.from(
          settingsState.hudLayout,
        );
      }
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
                    final box = context.findRenderObject() as RenderBox?;
                    final localDx = box != null
                        ? box.globalToLocal(details.globalPosition).dx
                        : details.localPosition.dx;
                    final boxWidth = (box != null && box.hasSize && box.size.width > 0)
                        ? box.size.width
                        : MediaQuery.of(context).size.width;
                    final step = settingsState.seekStepSeconds;
                    if (localDx < boxWidth * 0.38) {
                      cubit.seekRelative(-step);
                    } else if (localDx > boxWidth * 0.62) {
                      cubit.seekRelative(step);
                    } else {
                      cubit.togglePlayPause();
                    }
                  },
            onDoubleTap: state.isHudEditMode ? null : () {},
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.24, 0.62, 0.86, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: isLandscape ? 0.70 : 0.76),
                    Colors.black.withValues(alpha: 0.30),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isLandscape ? 0.72 : 0.76),
                    Colors.black.withValues(alpha: isLandscape ? 0.90 : 0.92),
                  ],
                ),
              ),
              child: SafeArea(
                top: isLandscape,
                bottom: isLandscape,
                left: isLandscape,
                right: isLandscape,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );

                    // В портретной ориентации всегда используем аккуратный док-макет
                    // и никогда не рендерим 2D-редактор на узком вертикальном экране.
                    if (!isLandscape) {
                      return _buildPortraitDockedLayout(
                        context,
                        settingsState: settingsState,
                        isShort: isShort,
                        isGuestInSync: isGuestInSync,
                        allEpisodes: allEpisodes,
                        currentIndex: currentIndex,
                        hasPrevEpisode: hasPrevEpisode,
                        hasNextEpisode: hasNextEpisode,
                      );
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. ВЕРХНИЙ БАР (назад, название, статусы Watch Together, топ-ряд кнопок и настройки)
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
                                settingsState: settingsState,
                                allEpisodes: allEpisodes,
                                currentIndex: currentIndex,
                                hasPrevEpisode: hasPrevEpisode,
                                hasNextEpisode: hasNextEpisode,
                              ),
                            ),
                          ),
                        ),

                        // 2. НИЖНИЙ БАР (таймлайн, нижний ряд кнопок, быстрые фразы, реакции комнаты — скрыт в режиме настройки HUD)
                        if (!state.isHudEditMode &&
                            (state.errorMessage == null || state.isPlaying))
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: _buildBottomBar(
                              context,
                              isLandscape: isLandscape,
                              isShort: isShort,
                              isGuestInSync: isGuestInSync,
                              settingsState: settingsState,
                              allEpisodes: allEpisodes,
                              currentIndex: currentIndex,
                              hasPrevEpisode: hasPrevEpisode,
                              hasNextEpisode: hasNextEpisode,
                            ),
                          ),

                        // 3. ВЫРАВНИВАЮЩАЯ СЕТКА И МАГНИТНЫЕ ЛИНИИ В РЕЖИМЕ НАСТРОЙКИ
                        if (state.isHudEditMode)
                          ValueListenableBuilder<
                              ({bool snapX, bool snapY, double? guideNx, double? guideNy})>(
                            valueListenable: _snapGuides,
                            builder: (context, guides, _) => PlayerHudEditGridOverlay(
                              snapXActive: guides.snapX,
                              snapYActive: guides.snapY,
                              snapGuideNx: guides.guideNx,
                              snapGuideNy: guides.guideNy,
                            ),
                          ),

                        // 4. КНОПКА ЗАПРОСА ПАУЗЫ ДЛЯ УЧАСТНИКА КОМНАТЫ (не хост)
                        if (isGuestInSync && !state.isHudEditMode)
                          Align(
                            alignment: Alignment.center,
                            child: _buildGuestPauseButton(context),
                          ),

                        // 5. СВОБОДНЫЙ 2D-ХОЛСТ КНОПОК HUD (60/120 FPS через ValueNotifier)
                        RepaintBoundary(
                          child: ValueListenableBuilder<Map<String, PlayerHudButtonConfig>>(
                            valueListenable: _draftLayout,
                            builder: (context, draftMap, _) => Stack(
                              fit: StackFit.expand,
                              children: _buildFreeFormHudButtons(
                                context,
                                hudLayout: draftMap,
                                settingsCubit: settingsCubit,
                                canvasSize: canvasSize,
                                isLandscape: isLandscape,
                                isGuestInSync: isGuestInSync,
                                allEpisodes: allEpisodes,
                                currentIndex: currentIndex,
                                hasPrevEpisode: hasPrevEpisode,
                                hasNextEpisode: hasNextEpisode,
                                seekStepSeconds: settingsState.seekStepSeconds,
                              ),
                            ),
                          ),
                        ),

                        // 6. ПЛАВАЮЩИЙ ИНСПЕКТОР ВЫБРАННОЙ КНОПКИ И ПРЕСЕТОВ (ВНИЗУ НА МЕСТЕ ТАЙМЛАЙНА)
                        if (state.isHudEditMode)
                          PlayerHudInspectorPill(
                            settingsCubit: settingsCubit,
                            settingsState: settingsState,
                            selectedButtonId: _selectedEditButtonId,
                            onSelectButton: (id) =>
                                setState(() => _selectedEditButtonId = id),
                            onDone: () {
                              settingsCubit?.applyHudLayout(_draftLayout.value);
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
    SettingsState? settingsState,
    List<EpisodeItem> allEpisodes = const [],
    int currentIndex = 0,
    bool hasPrevEpisode = false,
    bool hasNextEpisode = false,
  }) {
    final title = state.title;
    final ep = state.episode;
    final dockedTopControls = <Widget>[];
    if (isLandscape && !state.isHudEditMode && settingsState != null) {
      final topConfigs = [
        for (final id in const ['lock_screen', 'speed', 'quality_dub', 'pip_mode', 'settings'])
          settingsState.hudConfigFor(id),
      ].where((c) => c.visible && _isDockedInTopBar(c)).toList()
        ..sort((a, b) => a.nx.compareTo(b.nx));

      for (int i = 0; i < topConfigs.length; i++) {
        final cfg = topConfigs[i];
        final w = _buildSingle2DControl(
          context,
          id: cfg.id,
          isLandscape: isLandscape,
          allEpisodes: allEpisodes,
          currentIndex: currentIndex,
          hasPrevEpisode: hasPrevEpisode,
          hasNextEpisode: hasNextEpisode,
          seekStepSeconds: settingsState.seekStepSeconds,
        );
        if (w != null) {
          dockedTopControls.add(
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
              child: Transform.scale(scale: cfg.scale, child: w),
            ),
          );
        }
      }
    }

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
          if (isLandscape && !state.isSyncRoom) const Spacer(flex: 1),
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
                  ...dockedTopControls,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitDockedLayout(
    BuildContext context, {
    required SettingsState settingsState,
    required bool isShort,
    required bool isGuestInSync,
    required List<EpisodeItem> allEpisodes,
    required int currentIndex,
    required bool hasPrevEpisode,
    required bool hasNextEpisode,
  }) {
    final title = state.title;
    final ep = state.episode;

    Widget? control(String id) {
      if (!settingsState.hudConfigFor(id).visible) return null;
      return _buildSingle2DControl(
        context,
        id: id,
        isLandscape: false,
        allEpisodes: allEpisodes,
        currentIndex: currentIndex,
        hasPrevEpisode: hasPrevEpisode,
        hasNextEpisode: hasNextEpisode,
        seekStepSeconds: settingsState.seekStepSeconds,
      );
    }

    final topRightControls = <Widget>[
      for (final id in const ['lock_screen', 'speed', 'quality_dub', 'pip_mode', 'settings'])
        if (control(id) case final w?) w,
    ];
    final seekBack = control('seek_back');
    final playPause = control('play_pause');
    final seekForward = control('seek_forward');
    final fullscreenBtn = control('fullscreen');

    return Column(
      key: const ValueKey('player_portrait_docked_layout'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. КОМПАКТНЫЙ ВЕРХНИЙ РЯД ВНУТРИ 16:9: <, название, lock, 1.0x, 720p, PiP, gear
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary,
                ),
                iconSize: 17,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                onPressed: onBack,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  title.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
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
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: state.isHost
                                ? AppColors.primary.withValues(alpha: 0.22)
                                : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: state.isHost
                                  ? AppColors.primaryLight.withValues(alpha: 0.7)
                                  : Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            state.isHost ? 'Хост комнаты' : 'Участник',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: state.isHost
                                  ? AppColors.primaryLight
                                  : Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      for (int i = 0; i < topRightControls.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        topRightControls[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. ЦЕНТРАЛЬНЫЙ РЯД ТРАНСПОРТА: -10s, play/pause, +10s
        Expanded(
          child: Center(
            child: isGuestInSync
                ? _buildGuestPauseButton(context)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (seekBack != null) seekBack,
                      if (seekBack != null && playPause != null)
                        const SizedBox(width: 24),
                      if (playPause != null) playPause,
                      if (playPause != null && seekForward != null)
                        const SizedBox(width: 24),
                      if (seekForward != null) seekForward,
                    ],
                  ),
          ),
        ),

        // 3. НИЖНИЙ РЯД ВНУТРИ 16:9: прогресс-бар + кнопка полного экрана
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 6, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isSyncRoom && ep.opening != null)
                BlocSelector<PlayerCubit, PlayerState, ({int sec, int votes, bool voted})>(
                  bloc: cubit,
                  selector: (s) => (
                    sec: s.position.inSeconds,
                    votes: s.coopSkipVotes,
                    voted: s.hasVotedCoopSkip,
                  ),
                  builder: (context, coop) {
                    if (coop.sec < ep.opening!.start || coop.sec >= ep.opening!.stop) {
                      return const SizedBox.shrink();
                    }
                    return Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: coop.voted ? AppColors.syncActive : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.fast_forward_rounded, size: 14),
                          label: Text(
                            coop.votes > 0
                                ? 'Скип (${coop.votes}/2)'
                                : 'Пропустить (${coop.votes}/2)',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                          onPressed: () => cubit.voteCoopSkip(),
                        ),
                      ),
                    );
                  },
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: BlocSelector<PlayerCubit, PlayerState, ({Duration pos, Duration dur, Duration buf, bool isBuf})>(
                      bloc: cubit,
                      selector: (s) => (
                        pos: s.position,
                        dur: s.duration,
                        buf: s.buffer,
                        isBuf: s.isBuffering,
                      ),
                      builder: (context, timing) => PlayerProgressBar(
                        position: timing.pos,
                        duration: timing.dur,
                        buffer: timing.buf,
                        heatmap: cubit.state.heatmap,
                        opening: cubit.state.effectiveOpening,
                        ending: cubit.state.effectiveEnding,
                        isBuffering: timing.isBuf,
                        onSeek: (pos) => cubit.seek(pos),
                        onDragStart: () => cubit.pauseControlsAutoHide(),
                        onDragEnd: () => cubit.resetControlsAutoHideTimer(),
                        isLocked: isGuestInSync,
                        onLockedTap: () => cubit.showGuestPlaybackLockedNotice(),
                      ),
                    ),
                  ),
                  if (fullscreenBtn != null) ...[
                    const SizedBox(width: 6),
                    fullscreenBtn,
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
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
    required Map<String, PlayerHudButtonConfig> hudLayout,
    required SettingsCubit? settingsCubit,
    required Size canvasSize,
    required bool isLandscape,
    required bool isGuestInSync,
    required List<EpisodeItem> allEpisodes,
    required int currentIndex,
    required bool hasPrevEpisode,
    required bool hasNextEpisode,
    int seekStepSeconds = 10,
  }) {
    final widgets = <Widget>[];
    final hasError = state.errorMessage != null;

    for (final meta in kPlayerHud2DButtons) {
      final config = (hudLayout[meta.id] ??
              PlayerHud2DPresets.classicLayout()[meta.id] ??
              PlayerHudButtonConfig(id: meta.id, nx: 0.5, ny: 0.5))
          .clamped();
      if (!config.visible) continue;

      if (!state.isHudEditMode) {
        if (meta.id == 'skip_intro') continue;
        if (isLandscape &&
            (_isDockedInTopBar(config) || _isDockedInBottomBar(config))) {
          continue;
        }
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
        seekStepSeconds: seekStepSeconds,
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
          ),
          onDragEnd: () => _onDragEnd(settingsCubit, canvasSize),
          child: button,
        ),
      );
    }

    return widgets;
  }

  IconData _seekBackIconFor(int step) {
    switch (step) {
      case 5:
        return Icons.replay_5_rounded;
      case 30:
        return Icons.replay_30_rounded;
      case 10:
      default:
        return Icons.replay_10_rounded;
    }
  }

  IconData _seekForwardIconFor(int step) {
    switch (step) {
      case 5:
        return Icons.forward_5_rounded;
      case 30:
        return Icons.forward_30_rounded;
      case 10:
      default:
        return Icons.forward_10_rounded;
    }
  }

  Widget? _buildSingle2DControl(
    BuildContext context, {
    required String id,
    required bool isLandscape,
    required List<EpisodeItem> allEpisodes,
    required int currentIndex,
    required bool hasPrevEpisode,
    required bool hasNextEpisode,
    int seekStepSeconds = 10,
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
              padding: EdgeInsets.all(isLandscape ? 12 : 9),
              child: SizedBox(
                width: isLandscape ? 32 : 28,
                height: isLandscape ? 32 : 28,
                child: Center(
                  child: state.isBuffering
                      ? SizedBox(
                          width: isLandscape ? 24 : 20,
                          height: isLandscape ? 24 : 20,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(
                          state.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: isLandscape ? 32 : 28,
                          color: AppColors.textPrimary,
                        ),
                ),
              ),
            ),
          ),
        );

      case 'seek_back':
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const ValueKey('hud_center_seek_back'),
            tooltip: 'Назад $seekStepSeconds сек',
            iconSize: isLandscape ? 32 : 25,
            padding: EdgeInsets.all(isLandscape ? 8 : 6),
            constraints: BoxConstraints(
              minWidth: isLandscape ? 44 : 38,
              minHeight: isLandscape ? 44 : 38,
            ),
            icon: seekStepSeconds == 15
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.replay_rounded,
                        color: Colors.white,
                        size: isLandscape ? 32 : 25,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          '15',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  )
                : Icon(_seekBackIconFor(seekStepSeconds), color: Colors.white),
            onPressed: () => cubit.seekRelative(-seekStepSeconds),
          ),
        );

      case 'seek_forward':
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const ValueKey('hud_center_seek_forward'),
            tooltip: 'Вперёд $seekStepSeconds сек',
            iconSize: isLandscape ? 32 : 25,
            padding: EdgeInsets.all(isLandscape ? 8 : 6),
            constraints: BoxConstraints(
              minWidth: isLandscape ? 44 : 38,
              minHeight: isLandscape ? 44 : 38,
            ),
            icon: seekStepSeconds == 15
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.forward_5_rounded,
                        color: Colors.transparent,
                        size: isLandscape ? 32 : 25,
                      ),
                      Transform.flip(
                        flipX: true,
                        child: Icon(
                          Icons.replay_rounded,
                          color: Colors.white,
                          size: isLandscape ? 32 : 25,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          '15',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  )
                : Icon(_seekForwardIconFor(seekStepSeconds), color: Colors.white),
            onPressed: () => cubit.seekRelative(seekStepSeconds),
          ),
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
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 9 : 7,
              vertical: isLandscape ? 5 : 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.90),
              borderRadius: AppDimensions.borderRadiusSmall,
              border: Border.all(color: AppColors.strokeMedium),
            ),
            child: Text(
              '${state.playbackRate}x',
              style: AppTypography.badge.copyWith(
                color: AppColors.textPrimary,
                fontSize: isLandscape ? 11.5 : 10.5,
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
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 9 : 7,
              vertical: isLandscape ? 5 : 4,
            ),
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
                fontSize: isLandscape ? 11.5 : 10.5,
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
            iconSize: isLandscape ? 19 : 16,
            padding: EdgeInsets.all(isLandscape ? 8 : 5),
            constraints: BoxConstraints(
              minWidth: isLandscape ? 36 : 30,
              minHeight: isLandscape ? 36 : 30,
            ),
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
              size: isLandscape ? 22 : 20,
            ),
            padding: EdgeInsets.all(isLandscape ? 8 : 5),
            constraints: BoxConstraints(
              minWidth: isLandscape ? 36 : 32,
              minHeight: isLandscape ? 36 : 32,
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
            iconSize: isLandscape ? 18 : 16,
            padding: EdgeInsets.all(isLandscape ? 8 : 5),
            constraints: BoxConstraints(
              minWidth: isLandscape ? 36 : 30,
              minHeight: isLandscape ? 36 : 30,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: widget.onEnterPip ?? onMinimize ?? () {},
          ),
        );

      case 'settings':
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: const ValueKey('hud_action_settings_gear'),
            tooltip: 'Настройки плеера',
            icon: Icon(
              Icons.settings_outlined,
              color: AppColors.textPrimary,
              size: isLandscape ? 19 : 17,
            ),
            padding: EdgeInsets.all(isLandscape ? 8 : 5),
            constraints: BoxConstraints(
              minWidth: isLandscape ? 36 : 30,
              minHeight: isLandscape ? 36 : 30,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () => PlayerSettingsSheet.show(
              context,
              cubit: cubit,
              state: state,
              onMinimizeToMiniPlayer: onMinimize,
            ),
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
    SettingsState? settingsState,
    List<EpisodeItem> allEpisodes = const [],
    int currentIndex = 0,
    bool hasPrevEpisode = false,
    bool hasNextEpisode = false,
  }) {
    final ep = state.episode;
    Widget? dockedNextEp;
    Widget? dockedFullscreen;
    if (!state.isHudEditMode && settingsState != null) {
      final nextCfg = settingsState.hudConfigFor('next_episode');
      if (!isGuestInSync &&
          nextCfg.visible &&
          (!isLandscape || _isDockedInBottomBar(nextCfg))) {
        final w = _buildSingle2DControl(
          context,
          id: 'next_episode',
          isLandscape: isLandscape,
          allEpisodes: allEpisodes,
          currentIndex: currentIndex,
          hasPrevEpisode: hasPrevEpisode,
          hasNextEpisode: hasNextEpisode,
          seekStepSeconds: settingsState.seekStepSeconds,
        );
        if (w != null) {
          dockedNextEp = Transform.scale(scale: nextCfg.scale, child: w);
        }
      }
      final fsCfg = settingsState.hudConfigFor('fullscreen');
      if (fsCfg.visible && (!isLandscape || _isDockedInBottomBar(fsCfg))) {
        final w = _buildSingle2DControl(
          context,
          id: 'fullscreen',
          isLandscape: isLandscape,
          allEpisodes: allEpisodes,
          currentIndex: currentIndex,
          hasPrevEpisode: hasPrevEpisode,
          hasNextEpisode: hasNextEpisode,
          seekStepSeconds: settingsState.seekStepSeconds,
        );
        if (w != null) {
          dockedFullscreen = Transform.scale(scale: fsCfg.scale, child: w);
        }
      }
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (isLandscape || isShort) ? 16 : AppDimensions.spacingXl,
        vertical: (isLandscape || isShort) ? 4 : AppDimensions.spacingMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dockedNextEp != null || dockedFullscreen != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  dockedNextEp ?? const SizedBox.shrink(),
                  dockedFullscreen ?? const SizedBox.shrink(),
                ],
              ),
            ),
          if (state.isSyncRoom && ep.opening != null)
            BlocSelector<PlayerCubit, PlayerState, ({int sec, int votes, bool voted})>(
              bloc: cubit,
              selector: (s) => (
                sec: s.position.inSeconds,
                votes: s.coopSkipVotes,
                voted: s.hasVotedCoopSkip,
              ),
              builder: (context, coop) {
                if (coop.sec < ep.opening!.start || coop.sec >= ep.opening!.stop) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: coop.voted
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
                        elevation: coop.votes > 0 ? 6 : 2,
                        shadowColor: AppColors.primary.withValues(alpha: 0.6),
                      ),
                      icon: const Icon(Icons.fast_forward_rounded, size: 16),
                      label: Text(
                        coop.votes > 0
                            ? 'Друг хочет скипнуть! (${coop.votes}/2)'
                            : 'Пропустить опенинг (0/2)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: () => cubit.voteCoopSkip(),
                    ),
                  ),
                );
              },
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

          BlocSelector<PlayerCubit, PlayerState, ({Duration pos, Duration dur, Duration buf, bool isBuf})>(
            bloc: cubit,
            selector: (s) => (
              pos: s.position,
              dur: s.duration,
              buf: s.buffer,
              isBuf: s.isBuffering,
            ),
            builder: (context, timing) => PlayerProgressBar(
              position: timing.pos,
              duration: timing.dur,
              buffer: timing.buf,
              heatmap: cubit.state.heatmap,
              opening: cubit.state.effectiveOpening,
              ending: cubit.state.effectiveEnding,
              isBuffering: timing.isBuf,
              onSeek: (pos) => cubit.seek(pos),
              onDragStart: () => cubit.pauseControlsAutoHide(),
              onDragEnd: () => cubit.resetControlsAutoHideTimer(),
              isLocked: isGuestInSync,
              onLockedTap: () => cubit.showGuestPlaybackLockedNotice(),
            ),
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
