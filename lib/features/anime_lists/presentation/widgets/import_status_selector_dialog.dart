import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/user_anime_entry.dart';

/// Результат выбора настроек в диалоге импорта
class ImportStatusSelection {
  final bool autoDistribute;
  final AnimeListStatus defaultStatus;
  final bool useShikimoriSearch;

  const ImportStatusSelection({
    this.autoDistribute = true,
    required this.defaultStatus,
    required this.useShikimoriSearch,
  });
}

/// Диалоговое окно выбора категории по умолчанию перед импортом Anixart CSV
class ImportStatusSelectorDialog extends StatefulWidget {
  final int totalTitlesDetected;
  final String fileName;

  const ImportStatusSelectorDialog({
    super.key,
    required this.totalTitlesDetected,
    required this.fileName,
  });

  static Future<ImportStatusSelection?> show(
    BuildContext context, {
    required int totalTitlesDetected,
    required String fileName,
  }) {
    return showDialog<ImportStatusSelection>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ImportStatusSelectorDialog(
        totalTitlesDetected: totalTitlesDetected,
        fileName: fileName,
      ),
    );
  }

  @override
  State<ImportStatusSelectorDialog> createState() =>
      _ImportStatusSelectorDialogState();
}

class _ImportStatusSelectorDialogState extends State<ImportStatusSelectorDialog> {
  bool _autoDistribute = true;
  AnimeListStatus _selectedStatus = AnimeListStatus.planned;
  bool _useShikimoriSearch = true;

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
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок и иконка
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primary.withValues(alpha: 0.5)),
                  ),
                  child: Icon(Icons.file_download_outlined, color: primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Импорт закладок Anixart',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.totalTitlesDetected} тайтлов в "${widget.fileName}"',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            const Text(
              'Распределение по категориям:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),

            // 1. Автоматическое распределение по категориям из файла Anixart
            InkWell(
              onTap: () => setState(() => _autoDistribute = true),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _autoDistribute
                      ? primary.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _autoDistribute ? primary : Colors.white.withValues(alpha: 0.08),
                    width: _autoDistribute ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: _autoDistribute ? primary : AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Автоматически из файла',
                                style: TextStyle(
                                  color: _autoDistribute ? Colors.white : AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: _autoDistribute ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'ТОП',
                                  style: TextStyle(
                                    color: primary,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'Раскидает по спискам «В планах», «Просмотрено», «Смотрю», «Брошено» согласно файлу',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_autoDistribute)
                      Icon(Icons.check_circle_rounded, color: primary, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Ручной выбор единой категории
            _buildStatusTile(
              status: AnimeListStatus.planned,
              title: 'В планах',
              subtitle: 'Буду смотреть позже (все тайтлы)',
              icon: Icons.bookmark_outline_rounded,
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(height: 6),
            _buildStatusTile(
              status: AnimeListStatus.watching,
              title: 'Смотрю',
              subtitle: 'Активный просмотр (все тайтлы)',
              icon: Icons.play_circle_outline_rounded,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 6),
            _buildStatusTile(
              status: AnimeListStatus.completed,
              title: 'Просмотрено',
              subtitle: 'Полностью просмотренные (все тайтлы)',
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 6),
            _buildStatusTile(
              status: AnimeListStatus.dropped,
              title: 'Брошено',
              subtitle: 'Тайтлы, которые не понравились (все)',
              icon: Icons.delete_outline_rounded,
              color: const Color(0xFFEF4444),
            ),

            const SizedBox(height: 16),

            // Чекбокс умного поиска Shikimori
            InkWell(
              onTap: () {
                setState(() => _useShikimoriSearch = !_useShikimoriSearch);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _useShikimoriSearch,
                      activeColor: primary,
                      onChanged: (val) {
                        setState(() => _useShikimoriSearch = val ?? true);
                      },
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Умный поиск по Shikimori API',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Находит истинный ID, постеры и эпизоды',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Кнопки действий
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      Navigator.of(context).pop(null);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      Navigator.of(context).pop(
                        ImportStatusSelection(
                          autoDistribute: _autoDistribute,
                          defaultStatus: _selectedStatus,
                          useShikimoriSearch: _useShikimoriSearch,
                        ),
                      );
                    },
                    child: const Text(
                      'Начать импорт',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTile({
    required AnimeListStatus status,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = !_autoDistribute && _selectedStatus == status;
    return InkWell(
      onTap: () => setState(() {
        _autoDistribute = false;
        _selectedStatus = status;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : AppColors.textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

