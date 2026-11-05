import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/kodik_translation.dart';
import '../cubit/kodik_cubit.dart';
import '../cubit/kodik_state.dart';

/// Модальная шторка выбора студии озвучки и перевода (AniLibria / Kodik).
class VoiceoverSelectorSheet extends StatelessWidget {
  final int episodeNumber;
  final ValueChanged<KodikTranslation>? onVoiceoverChanged;

  const VoiceoverSelectorSheet({
    super.key,
    this.episodeNumber = 1,
    this.onVoiceoverChanged,
  });

  static Future<KodikTranslation?> show(
    BuildContext context, {
    int episodeNumber = 1,
    ValueChanged<KodikTranslation>? onVoiceoverChanged,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<KodikTranslation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        KodikCubit cubit;
        try {
          cubit = context.read<KodikCubit>();
        } catch (_) {
          cubit = getIt<KodikCubit>();
        }
        return BlocProvider.value(
          value: cubit,
          child: VoiceoverSelectorSheet(
            episodeNumber: episodeNumber,
            onVoiceoverChanged: onVoiceoverChanged,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KodikCubit, KodikState>(
      builder: (context, state) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.spacingXl,
              16,
              AppDimensions.spacingXl,
              20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Индикатор перетаскивания шторки
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.strokeMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Заголовок шторки
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.record_voice_over_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Озвучка и перевод',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Выберите любимую студию дубляжа или субтитры',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                if (state.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: state.translations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final tr = state.translations[index];
                        final isSelected = tr.id == state.selectedTranslation.id;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              await context.read<KodikCubit>().selectVoiceover(
                                    tr,
                                    episodeNumber: episodeNumber,
                                  );
                              onVoiceoverChanged?.call(tr);
                              if (context.mounted) {
                                Navigator.pop(context, tr);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.14)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.6)
                                      : AppColors.strokeMedium,
                                  width: isSelected ? 1.4 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    tr.displayIcon,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              tr.title,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? AppColors.primaryLight
                                                    : AppColors.textPrimary,
                                                fontWeight:
                                                    isSelected ? FontWeight.w700 : FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (tr.isAniLibria) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1.5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'Рекомендуется',
                                                  style: TextStyle(
                                                    color: AppColors.primaryLight,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          tr.isAniLibria
                                              ? 'Оригинальный релиз AniLibria • FHD 1080p • Прямой HLS поток'
                                              : (tr.isSubtitles
                                                  ? 'Оригинал с русскими субтитрами • ${tr.episodesCount} серий • Kodik'
                                                  : 'Русский дубляж • ${tr.episodesCount} серий • Kodik CDN'),
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.primaryLight,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
