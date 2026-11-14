import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'mascot_preview_dialog.dart';
import 'mascot_state.dart';

/// Интерактивная галерея маскота SyncPai для экрана настроек и справочника
class MascotGalleryWidget extends StatefulWidget {
  final bool isStandalone;

  const MascotGalleryWidget({
    super.key,
    this.isStandalone = false,
  });

  @override
  State<MascotGalleryWidget> createState() => _MascotGalleryWidgetState();
}

class _MascotGalleryWidgetState extends State<MascotGalleryWidget> {
  MascotCategory? _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MascotState> get _filteredStates {
    return MascotState.values.where((s) {
      if (_selectedCategory != null && s.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesTitle = s.title.toLowerCase().contains(q);
        final matchesId = s.id.toLowerCase().contains(q);
        final matchesDesc = s.description.toLowerCase().contains(q);
        return matchesTitle || matchesId || matchesDesc;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.of(context).size.width;

    // Адаптивное число колонок в сетке
    final int crossAxisCount;
    if (screenWidth >= 1400) {
      crossAxisCount = 5;
    } else if (screenWidth >= 1050) {
      crossAxisCount = 4;
    } else if (screenWidth >= 650) {
      crossAxisCount = 3;
    } else {
      crossAxisCount = 2;
    }

    final states = _filteredStates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок и подзаголовок секции
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themePrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.face_retouching_natural_rounded, color: themePrimary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SyncPai Mascot',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Meet your anime companion and explore all her expressions.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Поиск по состояниям
        TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Поиск по эмоциям и состояниям...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.35)),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textSecondary),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: themePrimary.withValues(alpha: 0.5)),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Фильтр категорий (Chips)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildFilterChip(
                label: 'Все (${MascotState.values.length})',
                isSelected: _selectedCategory == null,
                onTap: () => setState(() => _selectedCategory = null),
                primaryColor: themePrimary,
              ),
              const SizedBox(width: 8),
              ...MascotCategory.values.map((cat) {
                final count = MascotState.values.where((s) => s.category == cat).length;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildFilterChip(
                    label: '${cat.labelRu} ($count)',
                    isSelected: _selectedCategory == cat,
                    onTap: () => setState(() => _selectedCategory = cat),
                    primaryColor: themePrimary,
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Сетка карточек состояний маскота
        if (states.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Text(
              'Ничего не найдено по запросу «$_searchQuery»',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: states.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, index) {
              final state = states[index];
              return _buildMascotCard(context, state, themePrimary);
            },
          ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color primaryColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? primaryColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMascotCard(BuildContext context, MascotState state, Color primaryColor) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => MascotPreviewDialog.show(context, state),
        borderRadius: BorderRadius.circular(16),
        hoverColor: primaryColor.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Мини-бейдж категории
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    state.category.labelEn,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // Изображение маскота
              Expanded(
                child: Center(
                  child: Hero(
                    tag: 'mascot_gallery_${state.id}',
                    child: Image.asset(
                      state.assetPath,
                      fit: BoxFit.contain,
                      semanticLabel: state.title,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.face_rounded,
                        color: AppColors.primary,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Название состояния
              Text(
                state.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),

              // Идентификатор состояния
              Text(
                state.id,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primaryColor.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),

              // Краткое описание
              Text(
                state.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
