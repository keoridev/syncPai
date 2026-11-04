import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../../../core/widgets/app_search_bar.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/anime_title.dart';
import '../cubit/catalog_cubit.dart';
import '../cubit/catalog_state.dart';
import '../widgets/anime_poster_card.dart';

class CatalogScreen extends StatefulWidget {
  final ValueChanged<AnimeTitle>? onTitleSelected;

  const CatalogScreen({
    super.key,
    this.onTitleSelected,
  });

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _popularGenres = [
    'Все',
    'Сёнэн',
    'Экшен',
    'Комедия',
    'Романтика',
    'Фэнтези',
    'Драма',
    'Детектив',
    'Приключения',
    'Повседневность',
  ];

  @override
  void initState() {
    super.initState();
    context.read<CatalogCubit>().loadUpdates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            // Заголовок приложения и статус
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spacingXl,
                  AppDimensions.spacingLg,
                  AppDimensions.spacingXl,
                  AppDimensions.spacingSm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SyncPai',
                          style: AppTypography.displayMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spacing2xs),
                        Text(
                          'Каталог релизов AniLibria',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    // Декоративная иконка комнат
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: AppDimensions.borderRadiusMedium,
                        border: Border.all(color: AppColors.stroke, width: 1.0),
                      ),
                      child: const Icon(
                        Icons.group_work_outlined,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Строка поиска
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingXl,
                  vertical: AppDimensions.spacingSm,
                ),
                child: AppSearchBar(
                  controller: _searchController,
                  onChanged: (query) {
                    context.read<CatalogCubit>().onSearchQueryChanged(query);
                  },
                  onClear: () {
                    context.read<CatalogCubit>().onSearchQueryChanged('');
                  },
                ),
              ),
            ),

            // Горизонтальный список чипсов-жанров
            SliverToBoxAdapter(
              child: BlocBuilder<CatalogCubit, CatalogState>(
                buildWhen: (prev, curr) =>
                    curr is CatalogLoaded || curr is CatalogLoading,
                builder: (context, state) {
                  final selected = state is CatalogLoaded
                      ? state.selectedGenre ?? 'Все'
                      : 'Все';

                  return SizedBox(
                    height: AppDimensions.chipHeight + 16,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacingXl,
                        vertical: AppDimensions.spacingSm,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: _popularGenres.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppDimensions.spacingSm),
                      itemBuilder: (context, index) {
                        final genre = _popularGenres[index];
                        final isSelected = genre == selected;

                        return AppChip(
                          label: genre,
                          isSelected: isSelected,
                          onTap: () {
                            context
                                .read<CatalogCubit>()
                                .selectGenre(genre == 'Все' ? null : genre);
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
          body: BlocBuilder<CatalogCubit, CatalogState>(
            builder: (context, state) {
              if (state is CatalogLoading) {
                return _buildLoadingGrid();
              }

              if (state is CatalogError) {
                return _buildErrorState(context, state.message);
              }

              if (state is CatalogLoaded) {
                if (state.filteredTitles.isEmpty) {
                  return _buildEmptyState(context);
                }

                return RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceElevated,
                  onRefresh: () =>
                      context.read<CatalogCubit>().loadUpdates(refresh: true),
                  child: _buildTitlesGrid(state.filteredTitles),
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTitlesGrid(List<AnimeTitle> titles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Адаптивная колоночная сетка
        final crossAxisCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : 2;

        return GridView.builder(
          padding: const EdgeInsets.all(AppDimensions.spacingXl),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.58,
            crossAxisSpacing: AppDimensions.spacingLg,
            mainAxisSpacing: AppDimensions.spacingLg,
          ),
          itemCount: titles.length,
          itemBuilder: (context, index) {
            final title = titles[index];
            return AnimePosterCard(
              title: title,
              onTap: () => widget.onTitleSelected?.call(title),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(AppDimensions.spacingXl),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.58,
        crossAxisSpacing: AppDimensions.spacingLg,
        mainAxisSpacing: AppDimensions.spacingLg,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.borderRadiusCard,
          border: Border.all(color: AppColors.stroke, width: 1.0),
        ),
        child: Column(
          children: const [
            Expanded(child: ShimmerPlaceholder.card()),
            Padding(
              padding: EdgeInsets.all(AppDimensions.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerPlaceholder.line(width: double.infinity, height: 14),
                  SizedBox(height: AppDimensions.spacingSm),
                  ShimmerPlaceholder.line(width: 80, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacing2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 54,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Text(
              'Ничего не найдено',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              'Попробуйте изменить поисковый запрос или фильтр жанров',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacing2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 52,
              color: AppColors.syncWaiting,
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Text(
              'Не удалось загрузить данные',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXl),
            AppButton(
              label: 'Повторить попытку',
              icon: Icons.refresh_rounded,
              onPressed: () {
                context.read<CatalogCubit>().loadUpdates(refresh: true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

