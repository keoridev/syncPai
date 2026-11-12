import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sync_badge.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'player_episodes_sheet.dart';
import 'player_progress_bar.dart';
import 'player_settings_sheet.dart';
import 'presence_radar_badge.dart';
import 'quick_phrases_bar.dart';
import 'sync_chat_input_bar.dart';
import 'package:sync_pai/features/player/services/pip_service.dart';

class PlayerControlsOverlay extends StatelessWidget {
  final PlayerCubit cubit;
  final PlayerState state;
  final VoidCallback onBack;
  final VoidCallback? onToggleOrientation;
  final SyncStatus? syncStatus;
  final String? syncPeerName;

  const PlayerControlsOverlay({
    super.key,
    required this.cubit,
    required this.state,
    required this.onBack,
    this.onToggleOrientation,
    this.syncStatus,
    this.syncPeerName,
  });

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

                              // В ЛАНДШАФТНОМ РЕЖИМЕ: расширенный набор
                              if (isLandscape) ...[
                                // Danmaku переключатель (бегущие строки)
                                IconButton(
                                  tooltip: state.isDanmakuEnabled ? 'Danmaku: ВКЛ' : 'Danmaku: ВЫКЛ',
                                  icon: Icon(
                                    state.isDanmakuEnabled ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
                                    color: state.isDanmakuEnabled ? AppColors.primary : AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => cubit.toggleDanmaku(),
                                ),

                                // Переключатель оверлея чата (в режиме синхро-комнаты)
                                if (state.isSyncRoom) ...[
                                  IconButton(
                                    tooltip: state.isChatOverlayVisible ? 'Скрыть чат' : 'Показать чат',
                                    icon: Icon(
                                      state.isChatOverlayVisible ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                      color: state.isChatOverlayVisible ? AppColors.primary : AppColors.textSecondary,
                                      size: 18,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => cubit.toggleChatOverlay(),
                                  ),
                                ],

                                // Переключатель автопропуска опенингов
                                IconButton(
                                  tooltip: cubit.isAutoSkipOpening ? 'Автопропуск опенингов: ВКЛ' : 'Автопропуск опенингов: ВЫКЛ',
                                  icon: Icon(
                                    cubit.isAutoSkipOpening ? Icons.motion_photos_paused_rounded : Icons.motion_photos_off_rounded,
                                    color: cubit.isAutoSkipOpening ? AppColors.primary : AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    cubit.toggleAutoSkipOpening();
                                  },
                                ),

                                // Список серий
                                IconButton(
                                  tooltip: 'Список серий',
                                  icon: const Icon(Icons.video_library_rounded, color: AppColors.textPrimary, size: 19),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => PlayerEpisodesSheet.show(context, cubit: cubit, state: state),
                                ),

                                // Кнопка Скорости воспроизведения (быстрый выбор)
                                InkWell(
                                  onTap: () => _showQuickSpeedSheet(context),
                                  borderRadius: AppDimensions.borderRadiusSmall,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceElevated,
                                      borderRadius: AppDimensions.borderRadiusSmall,
                                      border: Border.all(color: AppColors.strokeMedium),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${state.playbackRate}x',
                                          style: AppTypography.badge.copyWith(color: AppColors.textPrimary, fontSize: 11),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.speed_rounded, color: AppColors.textSecondary, size: 13),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

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
                                const SizedBox(width: 4),

                                // Кнопка перехода в режим Картинка-в-картинке (PiP)
                                IconButton(
                                  tooltip: 'Картинка в картинке (PiP)',
                                  icon: const Icon(
                                    Icons.picture_in_picture_alt_rounded,
                                    color: AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () async {
                                    final success = await PipService.instance.enterPip();
                                    if (!success && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Режим PiP поддерживается на устройствах Android 8.0+'),
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                ),

                                if (onToggleOrientation != null)
                                  IconButton(
                                    tooltip: 'Портретный режим',
                                    icon: const Icon(
                                      Icons.screen_lock_portrait_rounded,
                                      color: AppColors.textSecondary,
                                      size: 19,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onToggleOrientation,
                                  ),
                              ] else ...[
                                // В ПОРТРЕТНОМ РЕЖИМЕ: компактный чистый набор
                                // Список серий
                                IconButton(
                                  tooltip: 'Серии',
                                  icon: const Icon(Icons.video_library_rounded, color: AppColors.textPrimary, size: 20),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => PlayerEpisodesSheet.show(context, cubit: cubit, state: state),
                                ),

                                // Кнопка всех настроек (Liquid Glass шторка)
                                IconButton(
                                  tooltip: 'Настройки',
                                  icon: const Icon(Icons.tune_rounded, color: AppColors.textPrimary, size: 20),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => PlayerSettingsSheet.show(context, cubit: cubit, state: state),
                                ),

                                if (onToggleOrientation != null)
                                  IconButton(
                                    tooltip: 'Альбомный режим',
                                    icon: const Icon(
                                      Icons.screen_rotation_rounded,
                                      color: AppColors.textPrimary,
                                      size: 20,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onToggleOrientation,
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
                      // Перемотка на 10 сек назад
                      IconButton(
                        iconSize: isLandscape ? 30 : 40,
                        icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                        onPressed: () => cubit.seekRelative(-10),
                      ),
                      SizedBox(width: isLandscape ? 20 : AppDimensions.spacingXl),

                      // Кнопка воспроизведения/паузы
                      Material(
                        color: Theme.of(context).colorScheme.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => cubit.playOrPause(),
                          child: Padding(
                            padding: EdgeInsets.all(isLandscape ? 10 : AppDimensions.spacingLg),
                            child: Icon(
                              state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: isLandscape ? 32 : 44,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isLandscape ? 20 : AppDimensions.spacingXl),

                      // Перемотка на 10 сек вперед
                      IconButton(
                        iconSize: isLandscape ? 30 : 40,
                        icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                        onPressed: () => cubit.seekRelative(10),
                      ),
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
                        opening: ep.opening,
                        ending: ep.ending,
                        isBuffering: state.isBuffering,
                        onSeek: (pos) => cubit.seek(pos),
                        isLocked: isGuestInSync,
                        onLockedTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Таймлайном управляет хост комнаты'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: hasPrevEpisode ? AppColors.textPrimary : AppColors.textMuted,
                              ),
                              icon: const Icon(Icons.skip_previous_rounded, size: 20),
                              label: const Text('Пред. серия'),
                              onPressed: hasPrevEpisode
                                  ? () => cubit.switchEpisode(allEpisodes[currentIndex - 1])
                                  : null,
                            ),
                            if (onToggleOrientation != null)
                              IconButton(
                                tooltip: 'Повернуть экран (на весь экран)',
                                icon: const Icon(Icons.screen_rotation_rounded, color: AppColors.textPrimary, size: 24),
                                onPressed: onToggleOrientation,
                              ),
                            TextButton.icon(
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
            opening: ep.opening,
            ending: ep.ending,
            isBuffering: state.isBuffering,
            onSeek: (pos) => cubit.seek(pos),
            isLocked: isGuestInSync,
            onLockedTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Таймлайном управляет хост комнаты'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
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
              ],

              const Spacer(),

              // Реакции и чат в комнате
              if (state.isSyncRoom)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final emoji in ['🔥', '😂', '😱', '😭', '❤️']) ...[
                        InkWell(
                          onTap: () => cubit.sendReaction(emoji),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            child: Text(emoji, style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
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
