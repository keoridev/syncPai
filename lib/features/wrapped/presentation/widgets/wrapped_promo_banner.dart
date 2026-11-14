import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';
import '../../../../core/widgets/mascot/sync_pai_mascot.dart';
import '../screens/wrapped_story_screen.dart';

/// Промо-баннер годовых итогов «SyncPai Wrapped 2026» для Главного экрана и Профиля.
class WrappedPromoBanner extends StatelessWidget {
  final VoidCallback? onOpen;

  const WrappedPromoBanner({
    super.key,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E1736),
            Color(0xFF132032),
            Color(0xFF0F1420),
          ],
        ),
        border: Border.all(
          color: AppColors.accentTurquoise.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF35D9D5).withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.mediumImpact();
            if (onOpen != null) {
              onOpen!();
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WrappedStoryScreen(),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const SizedBox(
                  width: 58,
                  height: 58,
                  child: SyncPaiMascot(
                    state: MascotState.winterHappy,
                    size: MascotSize.small,
                    animated: true,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentTurquoise.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'WRAPPED 2026',
                              style: TextStyle(
                                color: AppColors.accentTurquoise,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '✨ Новое',
                            style: TextStyle(color: Color(0xFFFFB300), fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Твоё аниме-путешествие 2026',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Один год. Десятки серий. Узнай свои личные итоги!',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentTurquoise,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Color(0xFF0F1117),
                    size: 18,
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
