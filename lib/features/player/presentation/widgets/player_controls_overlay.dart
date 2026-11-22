import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sync_badge.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import '../../../sync_room/presentation/widgets/in_room_anime_picker_sheet.dart';
import 'floating_pai_chan_reactions_overlay.dart';
import 'player_episodes_sheet.dart';
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = state.title;
    final ep = state.episode;
    final allEpisodes = title.episodes;
    final currentIndex = allEpisodes.indexWhere((e) => e.episode == ep.episode);
    final hasNextEpisode = currentIndex >= 0 && currentIndex < allEpisodes.length - 1;
    final hasPrevEpisode = currentIndex > 0;
    final isGuestInSync = state.isSyncRoom && !state.isHost;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isShort = MediaQuery.of(context).size.height < 520;
    if (state.isScreenLocked) return const SizedBox.shrink();

    final settingsCubit =
        getIt.isRegistered<SettingsCubit>() ? getIt<SettingsCubit>() : null;

    Widget buildWithSettings(SettingsState settingsState) {
      final showSeek10s = settingsState.isHudButtonVisible('seek_10s');

      return IgnorePointer(
      ignoring: !state.areControlsVisible,
      child: AnimatedOpacity(
        opacity: state.areControlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => cubit.toggleControls(),
          onDoubleTapDown: (details) {
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
          onDoubleTap: () {},
          onVerticalDragUpdate: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isLeft = details.globalPosition.dx < (screenWidth / 2);
            final screenHeight = MediaQuery.of(context).size.height;
            final delta = -details.primaryDelta! / (screenHeight * 0.65);
            if (isLeft) {
              final newB = (state.brightness + delta).clamp(0.05, 1.0);
              cubit.setBrightness(newB);
            } else {
              final newV = (state.volume + (delta * 100.0)).clamp(0.0, 100.0);
              cubit.setVolume(newV);
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                if (state.isHudEditMode)
                  _buildHudEditTopBanner(context, settingsCubit, settingsState),
                // ВЕРХНИЙ БАР
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscape ? 16 : AppDimensions.spacingLg,
                    vertical: isLandscape ? 2 : AppDimensions.spacingSm,
                  ),
                  child: Row(
                    children: [
                      // Кнопка назад
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
                        iconSize: isLandscape ? 18 : 22,
                        visualDensity: isLandscape ? VisualDensity.compact : VisualDensity.standard,
                        onPressed: onBack,
                      ),
                      const SizedBox(width: AppDimensions.spacingSm),
                      // Название тайтла и номер серии
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: isLandscape
                                  ? AppTypography.titleSmall.copyWith(color: AppColors.textPrimary, fontSize: 13)
                                  : AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
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

                      // ТРЕЙЛИНГ-БЛОК ДЕЙСТВИЙ И СТАТУСОВ (Защищен от переполнения Flexible + SingleChildScrollView)
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Онлайн-радар присутствия (Presence) или классический SyncBadge
                              if (state.isSyncRoom) ...[
                                // Явный бейдж роли текущей сессии (строго по state.isHost)
                                Container(
                                  key: const ValueKey('player_overlay_role_pill'),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                                // Телеметрия пинга / десинхрона
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                                        state.isPeerBuffering ? Icons.hourglass_top_rounded : Icons.wifi_rounded,
                                        size: 11,
                                        color: state.isPeerBuffering ? AppColors.warning : AppColors.syncActive,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        state.isPeerBuffering ? 'Буфер' : '${state.peerPingMs}ms',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: state.isPeerBuffering ? AppColors.warning : AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ] else if (syncStatus != null) ...[
                                SyncBadge(status: syncStatus!, peerName: syncPeerName),
                                const SizedBox(width: 4),
                              ],

                              // Кнопка блокировки экрана (Screen Lock)
                              IconButton(
                                tooltip: 'Заблокировать экран',
                                icon: const Icon(Icons.lock_outline_rounded, color: AppColors.textPrimary),
                                iconSize: isLandscape ? 18 : 20,
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  cubit.toggleScreenLock();
                                },
                              ),

                              // Кнопка смены аниме внутри активной комнаты (без выхода из комнаты)
                              if (state.isSyncRoom)
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

                              // Динамические кнопки HUD строго в порядке SettingsState.playerButtonOrder
                              ..._buildOrderedTopActions(
                                context,
                                settingsState: settingsState,
                                isLandscape: isLandscape,
                              ),

                                // Кнопка Watch Party Wrapped Сторис (в режиме совместного просмотра)
                                if (state.isSyncRoom)
                                  IconButton(
                                    tooltip: 'Итоги просмотра (Сторис)',
                                    icon: Icon(Icons.auto_awesome_rounded, color: AppColors.primaryLight, size: 20),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => cubit.toggleWatchPartyStats(),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ЦЕНТР: ПЕРЕМОТКА И PLAY/PAUSE (или кнопка запроса паузы для ведомого гостя)
                if (isGuestInSync)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.9),
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.syncActive),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        icon: Icon(
                          state.isPlaying ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
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
                      ),
                    ],
                  )
                else if (state.errorMessage != null)
                  // Если есть ошибка воспроизведения — скрываем центральные кнопки управления, чтобы не перекрывать экран ошибки
                  const SizedBox.shrink()
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showSeek10s || state.isHudEditMode) ...[
                        // Перемотка на 10 сек назад
                        _wrapEditableHudSlot(
                          'seek_10s',
                          IconButton(
                            key: const ValueKey('hud_center_seek_back'),
                            iconSize: isLandscape ? 32 : 40,
                            icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                            onPressed: () => cubit.seekRelative(-10),
                          ),
                          settingsCubit,
                          settingsState,
                        ),
                        SizedBox(width: isLandscape ? 64 : 48),
                      ],

                      // Единая центральная кнопка (синхронизированы 3 состояния: Загрузка / Пауза / Плей)
                      Material(
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
                                        state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        size: isLandscape ? 32 : 44,
                                        color: AppColors.textPrimary,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (showSeek10s) ...[
                        SizedBox(width: isLandscape ? 64 : 48),
                        // Перемотка на 10 сек вперед
                        IconButton(
                          iconSize: isLandscape ? 32 : 40,
                          icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                          onPressed: () => cubit.seekRelative(10),
                        ),
                      ],
                    ],
                  ),

                // НИЖНИЙ БАР: ТАЙМЛАЙН, ШОРТКАТЫ ФРАЗ, СОЦИАЛЬНЫЙ БАР И СЕРИИ
                if (state.errorMessage != null && !state.isPlaying)
                  const SizedBox.shrink()
                else if (isLandscape || isShort)
                  _buildLandscapeBottomBar(
                    context,
                    title: title,
                    ep: ep,
                    allEpisodes: allEpisodes,
                    currentIndex: currentIndex,
                    hasNextEpisode: hasNextEpisode,
                    hasPrevEpisode: hasPrevEpisode,
                    isGuestInSync: isGuestInSync,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spacingXl,
                      vertical: AppDimensions.spacingMd,
                    ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Кнопка кооперативного пропуска опенинга (Cooperative Skip в режиме Демократия)
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
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: state.coopSkipVotes > 0 ? 6 : 2,
                                shadowColor: AppColors.primary.withValues(alpha: 0.6),
                              ),
                              icon: const Icon(Icons.fast_forward_rounded, size: 16),
                              label: Text(
                                state.coopSkipVotes > 0
                                    ? 'Друг хочет скипнуть! (${state.coopSkipVotes}/2)'
                                    : 'Пропустить опенинг (0/2)',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                              onPressed: () => cubit.voteCoopSkip(),
                            ),
                          ),
                        ),

                      // Выдвижная горизонтальная панель быстрых шорткат-фраз (без вызова клавиатуры)
                      if (state.isSyncRoom)
                        QuickPhrasesBar(cubit: cubit),

                      // Панель быстрых реакций и чата для совместного просмотра
                      if (state.isSyncRoom)
                        Container(
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
                              for (final emoji in ['🔥', '😂', '😱', '😭', '❤️']) ...[
                                InkWell(
                                  onTap: () => cubit.sendReaction(emoji),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    child: Text(emoji, style: const TextStyle(fontSize: 19)),
                                  ),
                                ),
                              ],
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
                                      const Icon(Icons.forum_outlined, size: 15, color: AppColors.textPrimary),
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
                              // Кнопка «Голосовой шёпот» (Push-to-Talk / WebRTC Voice)
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
                                        state.isVoiceMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                        size: 14,
                                        color: state.isVoiceMuted ? AppColors.textMuted : AppColors.syncActive,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        state.isVoiceMuted ? 'Шёпот' : 'В эфире',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: state.isVoiceMuted ? AppColors.textMuted : AppColors.syncActive,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Индикатор говорящего собеседника (Audio Ducking активен)
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
                              Icon(Icons.graphic_eq_rounded, color: AppColors.syncActive, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Друг говорит (громкость фильма -35%)',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),

                      // Прогресс-бар с буферизацией, таймингами и SoundCloud-тепловой картой
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
                      const SizedBox(height: AppDimensions.spacingSm),

                      // Кнопки перехода по сериям и поворот экрана
                      if (isGuestInSync)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Переключением серий управляет хост',
                              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                            ),
                            if (onToggleOrientation != null)
                              IconButton(
                                tooltip: 'Повернуть экран',
                                icon: const Icon(Icons.screen_rotation_rounded, color: AppColors.textPrimary, size: 24),
                                onPressed: onToggleOrientation,
                              ),
                          ],
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            key: const ValueKey('hud_bottom_actions_row'),
                            mainAxisSize: MainAxisSize.min,
                            children: _buildOrderedBottomActions(
                              context,
                              settingsState: settingsState,
                              allEpisodes: allEpisodes,
                              currentIndex: currentIndex,
                              hasPrevEpisode: hasPrevEpisode,
                              hasNextEpisode: hasNextEpisode,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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

  Widget _buildHudEditTopBanner(
    BuildContext context,
    SettingsCubit? settingsCubit,
    SettingsState settingsState,
  ) {
    return Container(
      key: const ValueKey('hud_edit_mode_banner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12161F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF35D9D5).withValues(alpha: 0.45),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(
                Icons.drag_indicator_rounded,
                color: Color(0xFF35D9D5),
                size: 16,
              ),
              const Text(
                'Режим настройки HUD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final p in const [
                PlayerHudPreset.standard,
                PlayerHudPreset.minimal,
                PlayerHudPreset.advanced,
              ])
                InkWell(
                  key: ValueKey('wysiwyg_preset_${p.name}'),
                  onTap: () => settingsCubit?.setPlayerHudPreset(p),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: settingsState.playerHudPreset == p
                          ? const Color(0xFF35D9D5).withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: settingsState.playerHudPreset == p
                            ? const Color(0xFF35D9D5)
                            : Colors.white12,
                      ),
                    ),
                    child: Text(
                      p.label,
                      style: TextStyle(
                        color: settingsState.playerHudPreset == p
                            ? const Color(0xFF35D9D5)
                            : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              TextButton(
                key: const ValueKey('wysiwyg_reset_btn'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => settingsCubit?.resetPlayerHudToDefault(),
                child: const Text(
                  'Сбросить',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
            ],
          ),
          ElevatedButton(
            key: const ValueKey('wysiwyg_done_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF35D9D5),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              setState(() => _selectedEditButtonId = null);
              cubit.setHudEditMode(false);
            },
            child: const Text(
              'Готово',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          if (_selectedEditButtonId != null)
            Builder(
              builder: (context) {
                final selectedId = _selectedEditButtonId!;
                final order = settingsState.playerButtonOrder;
                final idx = order.indexOf(selectedId);
                final isSelectedVisible = settingsState.isHudButtonVisible(selectedId);
                final canMoveLeft = idx > 0;
                final canMoveRight = idx >= 0 && idx < order.length - 1;
                final selectedTitle = kDefaultPlayerHudButtons
                    .where((b) => b.id == selectedId)
                    .map((b) => b.label)
                    .firstOrNull ?? selectedId;
                return Container(
                  key: const ValueKey('hud_selected_quick_bar'),
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF35D9D5).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF35D9D5).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        selectedTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('hud_move_left_btn'),
                        style: TextButton.styleFrom(
                          foregroundColor: canMoveLeft ? Colors.white : Colors.white30,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: canMoveLeft && settingsCubit != null
                            ? () {
                                HapticFeedback.selectionClick();
                                settingsCubit.reorderPlayerButtons(
                                  idx,
                                  idx - 1,
                                  adjustNewIndex: false,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 16),
                        label: const Text(
                          'Влево',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('hud_toggle_vis_btn'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF35D9D5),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: settingsCubit != null
                            ? () {
                                HapticFeedback.lightImpact();
                                settingsCubit.togglePlayerButton(
                                  selectedId,
                                  !isSelectedVisible,
                                );
                              }
                            : null,
                        icon: Icon(
                          isSelectedVisible
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 15,
                        ),
                        label: Text(
                          isSelectedVisible ? 'Скрыть' : 'Показать',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('hud_move_right_btn'),
                        style: TextButton.styleFrom(
                          foregroundColor: canMoveRight ? Colors.white : Colors.white30,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: canMoveRight && settingsCubit != null
                            ? () {
                                HapticFeedback.selectionClick();
                                settingsCubit.reorderPlayerButtons(
                                  idx,
                                  idx + 1,
                                  adjustNewIndex: false,
                                );
                              }
                            : null,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Вправо',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _wrapEditableHudSlot(
    String id,
    Widget child,
    SettingsCubit? settingsCubit,
    SettingsState settingsState,
  ) {
    if (!state.isHudEditMode) return child;
    final isVisible = settingsState.isHudButtonVisible(id);
    final isSelected = _selectedEditButtonId == id;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != id,
      onAcceptWithDetails: (details) {
        final order = settingsState.playerButtonOrder;
        final oldIdx = order.indexOf(details.data);
        final newIdx = order.indexOf(id);
        if (oldIdx >= 0 && newIdx >= 0) {
          settingsCubit?.reorderPlayerButtons(
            oldIdx,
            newIdx,
            adjustNewIndex: false,
          );
        }
      },
      builder: (context, candidateData, _) {
        final isDropTarget = candidateData.isNotEmpty;
        return Draggable<String>(
          data: id,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF12161F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF35D9D5), width: 1.5),
              ),
              child: child,
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.2, child: child),
          child: GestureDetector(
            key: ValueKey('wysiwyg_hud_slot_$id'),
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedEditButtonId = id);
            },
            child: Opacity(
              opacity: isVisible ? 1.0 : 0.35,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isDropTarget
                      ? const Color(0xFF35D9D5).withValues(alpha: 0.24)
                      : (isSelected
                          ? const Color(0xFF35D9D5).withValues(alpha: 0.16)
                          : Colors.black.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isDropTarget || isSelected)
                        ? const Color(0xFF35D9D5)
                        : const Color(0xFF35D9D5).withValues(alpha: 0.55),
                    width: isSelected ? 2.2 : 1,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IgnorePointer(child: child),
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isVisible
                              ? const Color(0xFF35D9D5)
                              : const Color(0xFF242A38),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isVisible ? Icons.check : Icons.add,
                          size: 9,
                          color: isVisible ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildOrderedBottomActions(
    BuildContext context, {
    required SettingsState settingsState,
    required List<EpisodeItem> allEpisodes,
    required int currentIndex,
    required bool hasPrevEpisode,
    required bool hasNextEpisode,
  }) {
    final settingsCubit =
        getIt.isRegistered<SettingsCubit>() ? getIt<SettingsCubit>() : null;
    final editMode = state.isHudEditMode;
    final actions = <Widget>[];
    for (final id in settingsState.playerButtonOrder) {
      final isVisible = settingsState.isHudButtonVisible(id);
      if (!editMode && !isVisible) continue;
      switch (id) {
        case 'next_episode':
          actions.add(
            _wrapEditableHudSlot(
              id,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    key: const ValueKey('hud_bottom_prev_episode'),
                    style: TextButton.styleFrom(
                      foregroundColor: hasPrevEpisode ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                    icon: const Icon(Icons.skip_previous_rounded, size: 20),
                    label: const Text('Пред. серия'),
                    onPressed: hasPrevEpisode
                        ? () => cubit.switchEpisode(allEpisodes[currentIndex - 1])
                        : null,
                  ),
                  TextButton.icon(
                    key: const ValueKey('hud_bottom_next_episode'),
                    style: TextButton.styleFrom(
                      foregroundColor: hasNextEpisode ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                    icon: const Icon(Icons.skip_next_rounded, size: 20),
                    label: const Text('След. серия'),
                    onPressed: hasNextEpisode
                        ? () => cubit.switchEpisode(allEpisodes[currentIndex + 1])
                        : null,
                  ),
                ],
              ),
              settingsCubit,
              settingsState,
            ),
          );
          break;
        case 'quality':
          actions.add(
            _wrapEditableHudSlot(
              id,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: InkWell(
                  key: const ValueKey('hud_bottom_quality'),
                  onTap: () => _showQuickQualitySheet(context),
                  borderRadius: AppDimensions.borderRadiusSmall,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: AppDimensions.borderRadiusSmall,
                      border: Border.all(color: AppColors.strokeMedium),
                    ),
                    child: Text(
                      state.selectedQuality == PlayerQuality.fhd
                          ? '1080p'
                          : state.selectedQuality == PlayerQuality.hd
                              ? '720p'
                              : '480p',
                      style: AppTypography.badge.copyWith(color: AppColors.textPrimary, fontSize: 11),
                    ),
                  ),
                ),
              ),
              settingsCubit,
              settingsState,
            ),
          );
          break;
        case 'fullscreen':
          if (onToggleOrientation != null || editMode) {
            actions.add(
              _wrapEditableHudSlot(
                id,
                IconButton(
                  key: const ValueKey('hud_bottom_fullscreen'),
                  tooltip: 'Повернуть экран (на весь экран)',
                  icon: const Icon(Icons.screen_rotation_rounded, color: AppColors.textPrimary, size: 24),
                  onPressed: onToggleOrientation,
                ),
                settingsCubit,
                settingsState,
              ),
            );
          }
          break;
      }
    }
    return actions;
  }

  List<Widget> _buildOrderedTopActions(
    BuildContext context, {
    required SettingsState settingsState,
    required bool isLandscape,
  }) {
    final settingsCubit =
        getIt.isRegistered<SettingsCubit>() ? getIt<SettingsCubit>() : null;
    final editMode = state.isHudEditMode;
    final actions = <Widget>[];

    Widget wrapEditable(String id, Widget child, bool isVisible) {
      return _wrapEditableHudSlot(id, child, settingsCubit, settingsState);
    }

    for (final id in settingsState.playerButtonOrder) {
      final isVisible = settingsState.isHudButtonVisible(id);
      if (!editMode && !isVisible) continue;

      switch (id) {
        case 'pip':
          if (onMinimize != null || widget.onEnterPip != null || editMode) {
            actions.add(
              wrapEditable(
                id,
                IconButton(
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
                isVisible,
              ),
            );
          }
          break;
        case 'speed':
          if (isLandscape || editMode) {
            actions.add(
              wrapEditable(
                id,
                InkWell(
                  key: const ValueKey('hud_action_speed'),
                  onTap: () => _showQuickSpeedSheet(context),
                  borderRadius: AppDimensions.borderRadiusSmall,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: AppDimensions.borderRadiusSmall,
                      border: Border.all(color: AppColors.strokeMedium),
                    ),
                    child: Text(
                      '${state.playbackRate}x',
                      style: AppTypography.badge.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                isVisible,
              ),
            );
          }
          break;
        case 'next_episode':
          actions.add(
            wrapEditable(
              id,
              IconButton(
                key: const ValueKey('hud_action_episodes'),
                tooltip: 'Список серий',
                icon: Icon(
                  Icons.video_library_rounded,
                  color: AppColors.textPrimary,
                  size: isLandscape ? 19 : 20,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    PlayerEpisodesSheet.show(context, cubit: cubit, state: state),
              ),
              isVisible,
            ),
          );
          break;
        case 'aspect_ratio':
          actions.add(
            wrapEditable(
              id,
              IconButton(
                key: const ValueKey('hud_action_aspect_ratio'),
                tooltip: 'Соотношение сторон',
                icon: Icon(
                  Icons.aspect_ratio_rounded,
                  color: AppColors.textPrimary,
                  size: isLandscape ? 19 : 20,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final nextFit = state.videoFit == BoxFit.contain
                      ? BoxFit.cover
                      : (state.videoFit == BoxFit.cover
                          ? BoxFit.fill
                          : BoxFit.contain);
                  cubit.setVideoFit(nextFit);
                  widget.onAspectRatioChanged?.call(nextFit);
                },
              ),
              isVisible,
            ),
          );
          break;
        case 'screenshot':
          actions.add(
            wrapEditable(
              id,
              IconButton(
                key: const ValueKey('hud_action_screenshot'),
                tooltip: 'Скриншот кадра',
                icon: Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.textPrimary,
                  size: isLandscape ? 19 : 20,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onTakeScreenshot ??
                    () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Скриншот сохранён'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
              ),
              isVisible,
            ),
          );
          break;
        case 'sleep_timer':
          actions.add(
            wrapEditable(
              id,
              IconButton(
                key: const ValueKey('hud_action_sleep_timer'),
                tooltip: 'Таймер сна',
                icon: Icon(
                  Icons.bedtime_outlined,
                  color: AppColors.textPrimary,
                  size: isLandscape ? 19 : 20,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onOpenSleepTimer ??
                    () => PlayerSettingsSheet.show(
                          context,
                          cubit: cubit,
                          state: state,
                        ),
              ),
              isVisible,
            ),
          );
          break;
        case 'settings_gear':
          actions.add(
            wrapEditable(
              id,
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
              isVisible,
            ),
          );
          break;
        case 'fullscreen':
          if (onToggleOrientation != null || editMode) {
            actions.add(
              wrapEditable(
                id,
                IconButton(
                  key: const ValueKey('hud_action_fullscreen'),
                  tooltip: isLandscape ? 'Портретный режим' : 'Альбомный режим',
                  icon: Icon(
                    isLandscape
                        ? Icons.screen_lock_portrait_rounded
                        : Icons.screen_rotation_rounded,
                    color: isLandscape
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    size: isLandscape ? 19 : 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleOrientation ?? () {},
                ),
                isVisible,
              ),
            );
          }
          break;
      }
    }
    return actions;
  }

  Widget _buildLandscapeBottomBar(
    BuildContext context, {
    required AnimeTitle title,
    required EpisodeItem ep,
    required List<EpisodeItem> allEpisodes,
    required int currentIndex,
    required bool hasNextEpisode,
    required bool hasPrevEpisode,
    required bool isGuestInSync,
  }) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Прогресс-бар с тепловой картой
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
          const SizedBox(height: 2),

          // 2. Компактная единая строка (Серии, Реакции, Шёпот, Пропуск)
          Row(
            children: [
              // Кнопки перехода по сериям
              if (!isGuestInSync) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: hasPrevEpisode ? AppColors.textPrimary : AppColors.textMuted,
                    size: 20,
                  ),
                  tooltip: 'Пред. серия',
                  onPressed: hasPrevEpisode
                      ? () => cubit.switchEpisode(allEpisodes[currentIndex - 1])
                      : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: hasNextEpisode ? AppColors.textPrimary : AppColors.textMuted,
                    size: 20,
                  ),
                  tooltip: 'След. серия',
                  onPressed: hasNextEpisode
                      ? () => cubit.switchEpisode(allEpisodes[currentIndex + 1])
                      : null,
                ),
                const SizedBox(width: 8),
              ],

              // Быстрый выбор качества потока (1080p, 720p, 480p)
              InkWell(
                onTap: () => _showQuickQualitySheet(context),
                borderRadius: AppDimensions.borderRadiusSmall,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: AppDimensions.borderRadiusSmall,
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Text(
                    state.selectedQuality == PlayerQuality.fhd
                        ? '1080p'
                        : state.selectedQuality == PlayerQuality.hd
                            ? '720p'
                            : '480p',
                    style: AppTypography.badge.copyWith(color: AppColors.textPrimary, fontSize: 11),
                  ),
                ),
              ),

              const Spacer(),

              // Стикер-реакции Пай-чан и чат в комнате
              if (state.isSyncRoom)
                Container(
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
                      // Микрофон
                      InkWell(
                        onTap: () => cubit.toggleVoiceMute(),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Icon(
                            state.isVoiceMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            size: 15,
                            color: state.isVoiceMuted ? AppColors.textMuted : AppColors.syncActive,
                          ),
                        ),
                      ),
                      // Чат
                      InkWell(
                        onTap: () => SyncChatInputSheet.show(context, cubit: cubit),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Icon(Icons.forum_outlined, size: 15, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              if (onToggleOrientation != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: isLandscape ? 'Вернуть в портретный режим' : 'Альбомный режим (на весь экран)',
                  icon: Icon(
                    isLandscape ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: AppColors.textPrimary,
                    size: 24,
                  ),
                  onPressed: onToggleOrientation,
                ),
              ],
            ],
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: const [
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
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check_rounded, color: primary, size: 20) : null,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: const [
                    Icon(Icons.high_quality_rounded, size: 20, color: Colors.white),
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
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check_rounded, color: primary, size: 20) : null,
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
