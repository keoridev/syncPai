import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/player_quality.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'package:sync_pai/features/player/services/pip_service.dart';

/// Современная полупрозрачная шторка настроек плеера (Bottom Sheet)
/// в стиле Liquid Glass вместо устаревших выпадающих списков.
class PlayerSettingsSheet extends StatelessWidget {
  final PlayerCubit cubit;
  final PlayerState state;

  const PlayerSettingsSheet({
    super.key,
    required this.cubit,
    required this.state,
  });

  static Future<void> show(BuildContext context, {
    required PlayerCubit cubit,
    required PlayerState state,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PlayerSettingsSheet(cubit: cubit, state: state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return ClipRRect(
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
                        child: Icon(Icons.tune_rounded, color: primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Настройки воспроизведения',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 1. СКОРОСТЬ ВОСПРОИЗВЕДЕНИЯ (Крупные кнопки)
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
                      final isSelected = state.playbackRate == rate;
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
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: primary.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
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
                  const SizedBox(height: 22),

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
                  const SizedBox(height: 22),

                  // 3. ДОПОЛНИТЕЛЬНЫЕ ОПЦИИ (Автопропуск опенингов, PiP, Чат)
                  Text(
                    'ОПЦИИ',
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
                        cubit.isAutoSkipOpening ? Icons.motion_photos_paused_rounded : Icons.motion_photos_off_rounded,
                        color: cubit.isAutoSkipOpening ? primary : AppColors.textMuted,
                      ),
                      title: const Text(
                        'Автопропуск опенингов',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        cubit.isAutoSkipOpening ? 'Включен (+90 секунд при начале)' : 'Выключен',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                      ),
                      trailing: Switch.adaptive(
                        value: cubit.isAutoSkipOpening,
                        activeTrackColor: primary,
                        onChanged: (val) {
                          HapticFeedback.lightImpact();
                          cubit.toggleAutoSkipOpening();
                          (context as Element).markNeedsBuild();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Режим Картинка-в-картинке (PiP)
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
                        'Картинка в картинке (PiP)',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Смотреть в плавающем окне поверх других приложений',
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
                            (context as Element).markNeedsBuild();
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primary : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.white.withValues(alpha: 0.1),
              width: 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
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
}
