import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ImportProgressData {
  final int current;
  final int total;
  final String currentTitle;
  final bool isCompleted;

  const ImportProgressData({
    required this.current,
    required this.total,
    required this.currentTitle,
    this.isCompleted = false,
  });
}

/// Анимированный модальный индикатор прогресса умного импорта аниме
class ImportProgressDialog extends StatelessWidget {
  final ValueNotifier<ImportProgressData> progressNotifier;

  const ImportProgressDialog({
    super.key,
    required this.progressNotifier,
  });

  static Future<void> show(
    BuildContext context, {
    required ValueNotifier<ImportProgressData> progressNotifier,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: ImportProgressDialog(progressNotifier: progressNotifier),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: const Color(0xFF16181F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: ValueListenableBuilder<ImportProgressData>(
          valueListenable: progressNotifier,
          builder: (context, data, _) {
            final progress = data.total > 0 ? (data.current / data.total).clamp(0.0, 1.0) : 0.0;
            final percentage = (progress * 100).toInt();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Иконка и статус
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: primary.withValues(alpha: 0.5)),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(primary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Импорт коллекции',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Импорт аниме: ${data.current} / ${data.total} (Находим Shikimori ID...)',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Прогресс бар
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(primary),
                  ),
                ),
                const SizedBox(height: 12),

                // Процент и текущий тайтл
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        data.currentTitle.isNotEmpty
                            ? 'Тайтл: ${data.currentTitle}'
                            : 'Связывание с каталогом...',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

