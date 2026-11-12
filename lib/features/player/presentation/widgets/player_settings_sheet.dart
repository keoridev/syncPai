import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/desktop_title_bar.dart';
import '../../../kodik/domain/entities/kodik_translation.dart';
import '../../../kodik/presentation/cubit/kodik_cubit.dart';
import '../../../kodik/presentation/cubit/kodik_state.dart';
import '../../../sync_room/presentation/widgets/room_audio_settings_section.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'package:sync_pai/features/player/services/pip_service.dart';

/// Современная полупрозрачная шторка настроек плеера (Bottom Sheet)
/// в стиле Liquid Glass, объединяющая выбор озвучки, качества, скорости,
/// масштаба кадра и дополнительных опций.
class PlayerSettingsSheet extends StatelessWidget {
  final PlayerCubit cubit;
  final PlayerState state;
  final VoidCallback? onMinimizeToMiniPlayer;

  const PlayerSettingsSheet({
    super.key,
    required this.cubit,
    required this.state,
    this.onMinimizeToMiniPlayer,
  });

  static Future<void> show(
    BuildContext context, {
    required PlayerCubit cubit,
    required PlayerState state,
    VoidCallback? onMinimizeToMiniPlayer,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<PlayerCubit, PlayerState>(
          builder: (ctx, liveState) => PlayerSettingsSheet(
            cubit: cubit,
            state: liveState,
            onMinimizeToMiniPlayer: onMinimizeToMiniPlayer,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.94),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Полоса-хэндл для свайпа вниз
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Заголовок
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.settings_rounded, color: primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Настройки воспроизведения',
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 1. ОЗВУЧКА И СТУДИЯ (Kodik / AniLibria)
                      _buildVoiceoverSection(context, primary),
                      const SizedBox(height: 20),

                      // 2. КАЧЕСТВО ПОТОКА (1080p, 720p, 480p)
                      Text(
                        'КАЧЕСТВО ВИДЕО',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildQualityButton(
                            context,
                            label: '1080p FHD',
                            quality: PlayerQuality.fhd,
                            isSelected: state.selectedQuality == PlayerQuality.fhd,
                            primary: primary,
                          ),
                          const SizedBox(width: 8),
                          _buildQualityButton(
                            context,
                            label: '720p HD',
                            quality: PlayerQuality.hd,
                            isSelected: state.selectedQuality == PlayerQuality.hd,
                            primary: primary,
                          ),
                          const SizedBox(width: 8),
                          _buildQualityButton(
                            context,
                            label: '480p SD',
                            quality: PlayerQuality.sd,
                            isSelected: state.selectedQuality == PlayerQuality.sd,
                            primary: primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 3. СКОРОСТЬ ВОСПРОИЗВЕДЕНИЯ
                      Text(
                        'СКОРОСТЬ ВОСПРОИЗВЕДЕНИЯ',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((rate) {
                          final isSelected = (state.playbackRate - rate).abs() < 0.05;
                          return InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              cubit.setPlaybackRate(rate);
                              Navigator.pop(context);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? primary : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? primary : Colors.white.withValues(alpha: 0.1),
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                '${rate}x',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // 4. МАСШТАБ КАДРА (ASPECT RATIO / FIT)
                      Text(
                        'МАСШТАБ ЭКРАНА',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildFitButton(
                            context,
                            label: 'Вписать (16:9)',
                            icon: Icons.fit_screen_rounded,
                            fit: BoxFit.contain,
                            isSelected: state.videoFit == BoxFit.contain,
                            primary: primary,
                          ),
                          const SizedBox(width: 8),
                          _buildFitButton(
                            context,
                            label: 'Заполнить',
                            icon: Icons.crop_free_rounded,
                            fit: BoxFit.cover,
                            isSelected: state.videoFit == BoxFit.cover,
                            primary: primary,
                          ),
                          const SizedBox(width: 8),
                          _buildFitButton(
                            context,
                            label: 'Растянуть',
                            icon: Icons.settings_overscan_rounded,
                            fit: BoxFit.fill,
                            isSelected: state.videoFit == BoxFit.fill,
                            primary: primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 5. ДОПОЛНИТЕЛЬНЫЕ ОПЦИИ
                      Text(
                        'ОПЦИИ ПЛЕЕРА',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Переключатель автопропуска опенингов
                      Material(
                        color: Colors.white.withValues(alpha: 0.04),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          leading: Icon(
                            cubit.isAutoSkipOpening
                                ? Icons.fast_forward_rounded
                                : Icons.motion_photos_off_rounded,
                            color: cubit.isAutoSkipOpening ? primary : AppColors.textMuted,
                          ),
                          title: const Text(
                            'Автопропуск опенингов',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            cubit.isAutoSkipOpening ? 'Автоматический переход в начале заставки' : 'Кнопка пропуска вручную',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                          ),
                          trailing: Switch.adaptive(
                            value: cubit.isAutoSkipOpening,
                            activeTrackColor: primary,
                            onChanged: (val) {
                              HapticFeedback.lightImpact();
                              cubit.toggleAutoSkipOpening();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Danmaku комментарии на экране
                      Material(
                        color: Colors.white.withValues(alpha: 0.04),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          leading: Icon(
                            state.isDanmakuEnabled
                                ? Icons.subtitles_rounded
                                : Icons.subtitles_off_rounded,
                            color: state.isDanmakuEnabled ? primary : AppColors.textMuted,
                          ),
                          title: const Text(
                            'Бегущие комментарии (Danmaku)',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            state.isDanmakuEnabled ? 'Отображаются поверх видео' : 'Скрыты',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                          ),
                          trailing: Switch.adaptive(
                            value: state.isDanmakuEnabled,
                            activeTrackColor: primary,
                            onChanged: (val) {
                              HapticFeedback.lightImpact();
                              cubit.toggleDanmaku();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Свернуть в мини-окно внутри приложения
                      if (onMinimizeToMiniPlayer != null) ...[
                        Material(
                          color: Colors.white.withValues(alpha: 0.04),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            leading: const Icon(Icons.picture_in_picture_rounded, color: AppColors.textPrimary),
                            title: const Text(
                              'Свернуть в мини-окно (внутри приложения)',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: const Text(
                              'Продолжить просмотр и свободно листать каталог и списки',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                            onTap: () {
                              Navigator.pop(context);
                              onMinimizeToMiniPlayer?.call();
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Системный режим Картинка-в-картинке (PiP)
                      Material(
                        color: Colors.white.withValues(alpha: 0.04),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          leading: const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.textPrimary),
                          title: const Text(
                            'Системный PiP (поверх других приложений)',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: const Text(
                            'Окно поверх рабочего стола Android / iOS',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                          onTap: () async {
                            Navigator.pop(context);
                            await PipService.instance.enterPip();
                          },
                        ),
                      ),

                      // Оверлей чата (если синхро-комната)
                      if (state.isSyncRoom) ...[
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.white.withValues(alpha: 0.04),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            leading: Icon(
                              state.isChatOverlayVisible ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                              color: state.isChatOverlayVisible ? primary : AppColors.textMuted,
                            ),
                            title: const Text(
                              'Оверлей стрим-чата',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              state.isChatOverlayVisible ? 'Сообщения видны на экране' : 'Чат скрыт',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            ),
                            trailing: Switch.adaptive(
                              value: state.isChatOverlayVisible,
                              activeTrackColor: primary,
                              onChanged: (val) {
                                HapticFeedback.lightImpact();
                                cubit.toggleChatOverlay();
                              },
                            ),
                          ),
                        ),
                      ],

                      // 6. УСТРОЙСТВО ВВОДА (МИКРОФОН) И ВЫВОДА (НАУШНИКИ) В КОМНАТАХ И НА ПК
                      if (state.isSyncRoom || DesktopTitleBar.isDesktopPlatform) ...[
                        const SizedBox(height: 16),
                        RoomAudioSettingsSection(activePlayer: cubit.player),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceoverSection(BuildContext context, Color primary) {
    if (!getIt.isRegistered<KodikCubit>()) {
      return const SizedBox.shrink();
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
            : [
                KodikTranslation.anilibria(),
                const KodikTranslation(id: 610, title: 'StudioBand', type: 'voice', episodesCount: 12),
                const KodikTranslation(id: 1978, title: 'Dream Cast', type: 'voice', episodesCount: 12),
                const KodikTranslation(id: 609, title: 'AniDUB', type: 'voice', episodesCount: 12),
                const KodikTranslation(id: 923, title: 'AnimeVost', type: 'voice', episodesCount: 12),
                const KodikTranslation(id: 767, title: 'SHIZA Project', type: 'voice', episodesCount: 12),
                const KodikTranslation(id: 2148, title: 'Субтитры', type: 'subtitles', episodesCount: 12),
              ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'ОЗВУЧКА И СТУДИЯ (KODIK / ANILIBRIA)',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                if (kodikState.isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: studios.map((studio) {
                  final isSelected = kodikState.selectedTranslation.title.toLowerCase() ==
                      studio.title.toLowerCase();
                  final isSub = studio.type == 'subtitles';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () async {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(context);
                        await cubit.switchVoiceoverStudio(studio);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? primary
                                : Colors.white.withValues(alpha: 0.12),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSub ? Icons.subtitles_rounded : Icons.mic_rounded,
                              size: 14,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              studio.title,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQualityButton(
    BuildContext context, {
    required String label,
    required PlayerQuality quality,
    required bool isSelected,
    required Color primary,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          cubit.changeQuality(quality);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? primary : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.white.withValues(alpha: 0.1),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFitButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required BoxFit fit,
    required bool isSelected,
    required Color primary,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          cubit.setVideoFit(fit);
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? primary : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.white.withValues(alpha: 0.1),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
