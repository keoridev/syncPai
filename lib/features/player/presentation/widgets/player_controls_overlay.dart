import 'package:flutter/material.dart';
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

    return IgnorePointer(
      ignoring: !state.areControlsVisible,
      child: AnimatedOpacity(
        opacity: state.areControlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.25, 0.75, 1.0],
              colors: [
                Colors.black.withValues(alpha: isLandscape ? 0.65 : 0.75),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: isLandscape ? 0.75 : 0.85),
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

                      // Онлайн-радар присутствия (Presence) или классический SyncBadge
                      if (state.isSyncRoom) ...[
                        PresenceRadarBadge(
                          presence: state.peerPresence,
                          fallbackName: syncPeerName ?? 'Друг',
                        ),
                        const SizedBox(width: AppDimensions.spacingSm),
                      ] else if (syncStatus != null) ...[
                        SyncBadge(status: syncStatus!, peerName: syncPeerName),
                        const SizedBox(width: AppDimensions.spacingSm),
                      ],

                      // В ЛАНДШАФТНОМ РЕЖИМЕ: полный набор кнопок
                      if (isLandscape) ...[
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
                          const SizedBox(width: AppDimensions.spacingSm),
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
                            cubit.toggleAutoSkipOpening();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  cubit.isAutoSkipOpening
                                      ? 'Автопропуск опенингов включен'
                                      : 'Автопропуск опенингов выключен',
                                ),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: AppDimensions.spacingSm),

                        // Список серий
                        IconButton(
                          tooltip: 'Список серий',
                          icon: const Icon(Icons.video_library_rounded, color: AppColors.textPrimary, size: 19),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => PlayerEpisodesSheet.show(context, cubit: cubit, state: state),
                        ),
                        const SizedBox(width: AppDimensions.spacingSm),

                        // Кнопка Скорости и Настроек (Liquid Glass шторка)
                        InkWell(
                          onTap: () => PlayerSettingsSheet.show(context, cubit: cubit, state: state),
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
                                const Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 13),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spacingSm),

                        // Выбор качества потока (1080p, 720p, 480p)
                        InkWell(
                          onTap: () => PlayerSettingsSheet.show(context, cubit: cubit, state: state),
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
                        const SizedBox(width: AppDimensions.spacingSm),

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
                        if (onToggleOrientation != null) ...[
                          const SizedBox(width: AppDimensions.spacingSm),
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
                        ],
                      ] else ...[
                        // В ПОРТРЕТНОМ РЕЖИМЕ: ультра-компактно (Качество + Меню Дополнительно ⋮)
                        // Список серий
                        IconButton(
                          tooltip: 'Серии',
                          icon: const Icon(Icons.video_library_rounded, color: AppColors.textPrimary, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => PlayerEpisodesSheet.show(context, cubit: cubit, state: state),
                        ),
                        const SizedBox(width: 2),

                        // Качество потока
                        InkWell(
                          onTap: () => PlayerSettingsSheet.show(context, cubit: cubit, state: state),
                          borderRadius: AppDimensions.borderRadiusSmall,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                      ],
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
                else if (state.errorMessage != null && !state.isPlaying)
                  // Если есть ошибка воспроизведения — не перекрываем центральное окно ошибки кнопками плеера
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
                      // Кнопка быстрого пропуска опенинга / эндинга по таймкодам (только для хоста / соло)
                      if (!isGuestInSync &&
                          ep.opening != null &&
                          state.position.inSeconds >= ep.opening!.start &&
                          state.position.inSeconds < ep.opening!.stop)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.9),
                                side: BorderSide(color: AppColors.primary, width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: Icon(Icons.fast_forward_rounded, color: AppColors.primary, size: 16),
                              label: const Text('Пропустить опенинг', style: TextStyle(color: AppColors.textPrimary)),
                              onPressed: () => cubit.skipOpening(),
                            ),
                          ),
                        )
                      else if (!isGuestInSync &&
                          ep.opening == null &&
                          state.position.inSeconds >= 5 &&
                          state.position.inSeconds < 180)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.9),
                                side: BorderSide(color: AppColors.primary, width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: Icon(Icons.fast_forward_rounded, color: AppColors.primary, size: 16),
                              label: const Text('+90с (Опенинг)', style: TextStyle(color: AppColors.textPrimary)),
                              onPressed: () => cubit.skipOpening(),
                            ),
                          ),
                        )
                      else if (!isGuestInSync &&
                          ep.ending != null &&
                          state.position.inSeconds >= ep.ending!.start &&
                          state.position.inSeconds < ep.ending!.stop)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.9),
                                side: const BorderSide(color: AppColors.syncActive, width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.skip_next_rounded, color: AppColors.syncActive, size: 16),
                              label: const Text('Пропустить эндинг', style: TextStyle(color: AppColors.textPrimary)),
                              onPressed: () {
                                if (hasNextEpisode) {
                                  cubit.switchEpisode(allEpisodes[currentIndex + 1]);
                                } else {
                                  cubit.seek(ep.ending!.stopDuration);
                                }
                              },
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

              // Кнопка пропуска опенинга (компактная пилюля)
              if (!isGuestInSync &&
                  ep.opening != null &&
                  state.position.inSeconds >= ep.opening!.start &&
                  state.position.inSeconds < ep.opening!.stop)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.9),
                    side: BorderSide(color: AppColors.primary, width: 1.0),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.fast_forward_rounded, color: AppColors.primary, size: 14),
                  label: const Text('Опенинг', style: TextStyle(color: AppColors.textPrimary, fontSize: 11)),
                  onPressed: () => cubit.skipOpening(),
                )
              else if (!isGuestInSync &&
                  ep.opening == null &&
                  state.position.inSeconds >= 5 &&
                  state.position.inSeconds < 180)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.9),
                    side: BorderSide(color: AppColors.primary, width: 1.0),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.fast_forward_rounded, color: AppColors.primary, size: 14),
                  label: const Text('+90с', style: TextStyle(color: AppColors.textPrimary, fontSize: 11)),
                  onPressed: () => cubit.skipOpening(),
                ),
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
}
