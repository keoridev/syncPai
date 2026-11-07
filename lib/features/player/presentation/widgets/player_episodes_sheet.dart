import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

/// Шторка быстрого выбора серии прямо из плеера (Bottom Sheet)
class PlayerEpisodesSheet extends StatelessWidget {
  final PlayerCubit cubit;
  final PlayerState state;

  const PlayerEpisodesSheet({
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
      builder: (_) => PlayerEpisodesSheet(cubit: cubit, state: state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final episodes = state.title.episodes;
    final primary = Theme.of(context).colorScheme.primary;
    final currentEp = state.episode.episode;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Хэндл
                const SizedBox(height: 12),
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
                const SizedBox(height: 14),

                // Заголовок
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.video_library_rounded, color: primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Выбор серии',
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Всего серий: ${episodes.isNotEmpty ? episodes.length : state.title.episodesTotal ?? "—"}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10, height: 1),

                // Список серий
                Expanded(
                  child: episodes.isEmpty
                      ? const Center(
                          child: Text(
                            'Список серий недоступен',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: episodes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final ep = episodes[index];
                            final isPlaying = ep.episode == currentEp;

                            return InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                                cubit.switchEpisode(ep);
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? primary.withValues(alpha: 0.18)
                                      : Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isPlaying ? primary : Colors.white.withValues(alpha: 0.08),
                                    width: isPlaying ? 1.4 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: isPlaying ? primary : Colors.white.withValues(alpha: 0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: isPlaying
                                          ? const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18)
                                          : Text(
                                              '${ep.episode}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Серия ${ep.episode}',
                                            style: TextStyle(
                                              color: isPlaying ? primary : AppColors.textPrimary,
                                              fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w600,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          if (ep.name != null && ep.name!.isNotEmpty)
                                            Text(
                                              ep.name!,
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
                                    if (isPlaying)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: primary,
                                          borderRadius: BorderRadius.circular(8),
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
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
