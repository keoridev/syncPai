import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../cubit/player_cubit.dart';

class QuickPhraseItem {
  final String phrase;
  final String emoji;

  const QuickPhraseItem(this.phrase, this.emoji);
}

/// Выдвижная панель быстрых шорткат-фраз для просмотра аниме.
/// Избавляет от необходимости открывать громоздкую клавиатуру в ландшафтном режиме.
class QuickPhrasesBar extends StatelessWidget {
  final PlayerCubit cubit;

  const QuickPhrasesBar({
    super.key,
    required this.cubit,
  });

  static const List<QuickPhraseItem> phrases = [
    QuickPhraseItem('Останови, отойду на минуту', '⏸️'),
    QuickPhraseItem('Чекни субтитры', '💬'),
    QuickPhraseItem('Что за трек?!', '🎵'),
    QuickPhraseItem('Ахахах', '😂'),
    QuickPhraseItem('Опенинг пушка!', '🔥'),
    QuickPhraseItem('Вот это поворот!', '😱'),
    QuickPhraseItem('Перемотай назад', '⏪'),
    QuickPhraseItem('Продолжаем!', '▶'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: phrases.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = phrases[index];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                cubit.sendQuickPhrase(item.phrase, emoji: item.emoji);
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.strokeMedium,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      item.phrase,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

