import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../cubit/catalog_cubit.dart';
import '../cubit/catalog_state.dart';

class CatalogFilterSheet extends StatefulWidget {
  final CatalogLoaded currentState;

  const CatalogFilterSheet({
    super.key,
    required this.currentState,
  });

  static Future<void> show(BuildContext context, CatalogLoaded state) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: context.read<CatalogCubit>(),
        child: CatalogFilterSheet(currentState: state),
      ),
    );
  }

  @override
  State<CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<CatalogFilterSheet> {
  late Set<String> _selectedGenres;
  late CatalogSort _sortBy;
  late bool _matchAll;
  late String? _status;

  static const List<String> allGenres = [
    'Экшен',
    'Приключения',
    'Комедия',
    'Драма',
    'Фэнтези',
    'Романтика',
    'Сёнэн',
    'Мистика',
    'Фантастика',
    'Психология',
    'Триллер',
    'Повседневность',
    'Сверхъестественное',
    'Детектив',
    'Спорт',
    'Меха',
    'Музыка',
    'Игры',
    'Школа',
    'Сэйнэн',
    'Магия',
    'Киберпанк',
    'Ужасы',
    'Военное',
    'Исторический',
  ];

  @override
  void initState() {
    super.initState();
    _selectedGenres = Set.from(widget.currentState.selectedGenres);
    _sortBy = widget.currentState.sortBy;
    _matchAll = widget.currentState.matchAllGenres;
    _status = widget.currentState.statusFilter;
  }

  void _applyFilters() {
    final cubit = context.read<CatalogCubit>();
    if (_selectedGenres.isEmpty) {
      cubit.clearGenres();
    } else {
      for (final g in allGenres) {
        final currentlySelected = widget.currentState.selectedGenres.contains(g);
        final wantsSelected = _selectedGenres.contains(g);
        if (currentlySelected != wantsSelected) {
          cubit.toggleGenre(g);
        }
      }
    }
    cubit.setSortBy(_sortBy);
    cubit.setMatchAllGenres(_matchAll);
    cubit.setStatusFilter(_status);
    Navigator.of(context).pop();
  }

  void _resetFilters() {
    setState(() {
      _selectedGenres.clear();
      _sortBy = CatalogSort.updates;
      _matchAll = false;
      _status = null;
    });
    final cubit = context.read<CatalogCubit>();
    cubit.clearGenres();
    cubit.setSortBy(CatalogSort.updates);
    cubit.setMatchAllGenres(false);
    cubit.setStatusFilter(null);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: AppColors.strokeMedium, width: 1.0),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Полоска хэндла
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Заголовок и кнопка сброса
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: themePrimary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune_rounded, color: themePrimaryLight, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Фильтры и Сортировка',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedGenres.isNotEmpty || _sortBy != CatalogSort.updates || _status != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _resetFilters,
                      child: const Text('Сбросить', style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),

            const Divider(color: AppColors.stroke, height: 1),

            // Прокручиваемый контент фильтра
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  // 1. СОРТИРОВКА
                  Row(
                    children: [
                      const Icon(Icons.sort_rounded, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Сортировка',
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CatalogSort.values.map((sort) {
                      final isSelected = _sortBy == sort;
                      return ChoiceChip(
                        avatar: Icon(
                          sort.icon,
                          size: 16,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                        label: Text(sort.label),
                        selected: isSelected,
                        selectedColor: themePrimary,
                        backgroundColor: AppColors.surfaceElevated,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected ? themePrimary : AppColors.strokeMedium,
                          ),
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _sortBy = sort);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // 2. СТАТУС ВЫХОДА
                  Row(
                    children: [
                      const Icon(Icons.stream_rounded, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Статус тайтла',
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusChip(
                          label: 'Все',
                          isSelected: _status == null,
                          themePrimary: themePrimary,
                          onTap: () => setState(() => _status = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatusChip(
                          label: 'Онгоинги',
                          isSelected: _status == 'ongoing',
                          themePrimary: themePrimary,
                          onTap: () => setState(() => _status = 'ongoing'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatusChip(
                          label: 'Завершенные',
                          isSelected: _status == 'released',
                          themePrimary: themePrimary,
                          onTap: () => setState(() => _status = 'released'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatusChip(
                          label: 'Анонсы',
                          isSelected: _status == 'anons',
                          themePrimary: themePrimary,
                          onTap: () => setState(() => _status = 'anons'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 3. МУЛЬТИ-ВЫБОР ЖАНРОВ
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.category_rounded, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            'Жанры (${_selectedGenres.length})',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      // Переключатель «Все совпадают» / «Любой»
                      if (_selectedGenres.length > 1)
                        InkWell(
                          onTap: () => setState(() => _matchAll = !_matchAll),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  _matchAll ? 'Все совпадают' : 'Любой из них',
                                  style: TextStyle(
                                    color: themePrimaryLight,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _matchAll ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                  size: 16,
                                  color: themePrimaryLight,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Сетка жанров с удобным мульти-выбором
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allGenres.map((genre) {
                      final isSelected = _selectedGenres.contains(genre);
                      return FilterChip(
                        label: Text(genre),
                        selected: isSelected,
                        selectedColor: themePrimary.withValues(alpha: 0.25),
                        checkmarkColor: themePrimaryLight,
                        backgroundColor: AppColors.surfaceElevated,
                        labelStyle: TextStyle(
                          color: isSelected ? themePrimaryLight : AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected ? themePrimary : AppColors.strokeMedium,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedGenres.add(genre);
                            } else {
                              _selectedGenres.remove(genre);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            // Нижняя плавающая кнопка «Применить»
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                border: Border(
                  top: BorderSide(color: AppColors.strokeMedium, width: 1.0),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themePrimary,
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _applyFilters,
                    child: Text(
                      _selectedGenres.isNotEmpty
                          ? 'Применить (${_selectedGenres.length} жанр${_selectedGenres.length == 1 ? '' : 'а'})'
                          : 'Применить фильтры',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required bool isSelected,
    required Color themePrimary,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? themePrimary : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? themePrimary : AppColors.strokeMedium,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
