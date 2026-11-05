import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_dimensions.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/app_avatar.dart';
import 'package:sync_pai/core/widgets/app_button.dart';
import 'package:sync_pai/core/widgets/app_search_bar.dart';
import 'package:sync_pai/core/widgets/glass_container.dart';
import 'package:sync_pai/core/widgets/shimmer_placeholder.dart';
import 'package:sync_pai/core/widgets/sync_pai_logo.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_state.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/catalog_settings.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_state.dart';
import '../cubit/catalog_cubit.dart';
import '../cubit/catalog_state.dart';
import '../widgets/anime_list_tile_card.dart';
import '../widgets/anime_poster_card.dart';
import '../widgets/catalog_settings_sheet.dart';

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
            // Заголовок приложения, бренд и кнопки настроек отображения
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
                    // Логотип и брендовый заголовок
                    Row(
                      children: [
                        const SyncPaiLogo(size: 40),
                        const SizedBox(width: AppDimensions.spacingMd),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Sync',
                                    style: AppTypography.displayMedium.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Pai',
                                    style: AppTypography.displayMedium.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppDimensions.spacing2xs),
                            Text(
                              'Каталог аниме AniLibria',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Кнопки переключения вида: Сетка / Список + Настройки + Профиль
                    BlocBuilder<CatalogCubit, CatalogState>(
                      buildWhen: (prev, curr) => curr is CatalogLoaded,
                      builder: (context, state) {
                        final isGrid = state is CatalogLoaded
                            ? state.viewMode == CatalogViewMode.grid
                            : true;
                        final gridDensity = state is CatalogLoaded
                            ? state.gridDensity
                            : CatalogGridDensity.standard;

                        return Row(
                          children: [
                            // Кнопка перехода в Профиль пользователя
                            if (getIt.isRegistered<AuthCubit>()) ...[
                              BlocBuilder<AuthCubit, AuthState>(
                                bloc: getIt<AuthCubit>(),
                                builder: (context, authState) {
                                  final profile = authState is Authenticated ? authState.profile : null;
                                  return GestureDetector(
                                    onTap: () => context.pushNamed('profile'),
                                    child: AppAvatar(
                                      avatarUrl: profile?.avatarUrl,
                                      username: profile?.username ?? 'Гость',
                                      size: 38,
                                      borderWidth: 1.2,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: AppDimensions.spacingSm),
                            ],

                            // Кнопка быстрого переключения Сетка <-> Список
                            GlassContainer(
                              width: 38,
                              height: 38,
                              borderRadius: BorderRadius.circular(10),
                              backgroundOpacity: 0.08,
                              borderOpacity: 0.12,
                              onTap: () => context
                                  .read<CatalogCubit>()
                                  .toggleViewMode(),
                              child: Center(
                                child: Icon(
                                  isGrid
                                      ? Icons.view_agenda_rounded
                                      : Icons.grid_view_rounded,
                                  color: AppColors.textPrimary,
                                  size: 19,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppDimensions.spacingSm),

                            // Кнопка подробных настроек (шторка плотности и вида)
                            GlassContainer(
                              width: 38,
                              height: 38,
                              borderRadius: BorderRadius.circular(10),
                              backgroundOpacity: 0.08,
                              borderOpacity: 0.12,
                              onTap: () {
                                CatalogSettingsSheet.show(
                                  context,
                                  cubit: context.read<CatalogCubit>(),
                                  currentViewMode: isGrid
                                      ? CatalogViewMode.grid
                                      : CatalogViewMode.list,
                                  currentGridDensity: gridDensity,
                                );
                              },
                              child: const Center(
                                child: Icon(
                                  Icons.tune_rounded,
                                  color: AppColors.textSecondary,
                                  size: 19,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
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

            // Горизонтальный список жанров в капсулах (чипах)
            SliverToBoxAdapter(
              child: BlocBuilder<CatalogCubit, CatalogState>(
                buildWhen: (prev, curr) =>
                    curr is CatalogLoaded || curr is CatalogLoading,
                builder: (context, state) {
                  final selected = state is CatalogLoaded
                      ? state.selectedGenre ?? 'Все'
                      : 'Все';

                  return SizedBox(
                    height: 38,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacingXl,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: _popularGenres.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppDimensions.spacingSm),
                      itemBuilder: (context, index) {
                        final genre = _popularGenres[index];
                        final isSelected = genre == selected;

                        return InkWell(
                          onTap: () {
                            context
                                .read<CatalogCubit>()
                                .selectGenre(genre == 'Все' ? null : genre);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.6)
                                    : Colors.white.withValues(alpha: 0.08),
                                width: 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              genre,
                              style: AppTypography.labelLarge.copyWith(
                                color: isSelected
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 13,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            // Напоминание о продолжении просмотра на главной странице
            if (getIt.isRegistered<WatchHistoryCubit>())
              BlocBuilder<WatchHistoryCubit, WatchHistoryState>(
                bloc: getIt<WatchHistoryCubit>(),
                builder: (context, historyState) {
                final recent = historyState.history.isNotEmpty ? historyState.history.first : null;
                if (recent == null || recent.positionMs < 15000 || recent.progress >= 0.95) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }

                void handleResume() {
                  final currentTitles = context.read<CatalogCubit>().state is CatalogLoaded
                      ? (context.read<CatalogCubit>().state as CatalogLoaded).titles
                      : <AnimeTitle>[];
                  final matched = currentTitles.firstWhere(
                    (t) => t.id == recent.titleId,
                    orElse: () => AnimeTitle(
                      id: recent.titleId,
                      code: '',
                      russianTitle: recent.titleName,
                      englishTitle: '',
                      posterSmall: recent.posterUrl,
                      posterMedium: recent.posterUrl,
                      posterOriginal: recent.posterUrl,
                      episodesTotal: 12,
                      genres: const [],
                      description: '',
                      status: '',
                    ),
                  );
                  widget.onTitleSelected?.call(matched);
                }

                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimensions.spacingXl,
                      AppDimensions.spacingMd,
                      AppDimensions.spacingXl,
                      0,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: handleResume,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.history_rounded,
                                  color: AppColors.primaryLight,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      recent.titleName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.titleSmall.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Серия ${recent.episode} • ${recent.formattedPosition} / ${recent.formattedDuration}',
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: recent.progress,
                                        minHeight: 3,
                                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppColors.primaryLight,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
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

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification &&
                        notification.metrics.extentAfter < 500) {
                      context.read<CatalogCubit>().loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceElevated,
                    onRefresh: () =>
                        context.read<CatalogCubit>().loadUpdates(refresh: true),
                    child: state.viewMode == CatalogViewMode.list
                        ? _buildTitlesList(state.filteredTitles, state.isLoadingMore)
                        : _buildTitlesGrid(
                            state.filteredTitles, state.gridDensity, state.isLoadingMore),
                  ),
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  // РЕЖИМ 1: Сетка (несколько в ряд)
  Widget _buildTitlesGrid(
      List<AnimeTitle> titles, CatalogGridDensity density, [bool isLoadingMore = false]) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : density.mobileColumns;

        final childAspectRatio = crossAxisCount >= 3 ? 0.53 : 0.58;
        final extraItems = isLoadingMore ? crossAxisCount : 0;

        return GridView.builder(
          padding: const EdgeInsets.all(AppDimensions.spacingXl),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: AppDimensions.spacingMd,
            mainAxisSpacing: AppDimensions.spacingMd,
          ),
          itemCount: titles.length + extraItems,
          itemBuilder: (context, index) {
            if (index >= titles.length) {
              return const ShimmerPlaceholder.card();
            }
            final title = titles[index];
            final historyItem = getIt.isRegistered<WatchHistoryCubit>()
                ? getIt<WatchHistoryCubit>().state.getForTitle(title.id)
                : null;
            return AnimePosterCard(
              title: title,
              watchProgress: historyItem?.progress,
              onTap: () => widget.onTitleSelected?.call(title),
            );
          },
        );
      },
    );
  }

  // РЕЖИМ 2: Список (подробные карточки в столбик)
  Widget _buildTitlesList(List<AnimeTitle> titles, [bool isLoadingMore = false]) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppDimensions.spacingXl),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemCount: titles.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) =>
          const SizedBox(height: AppDimensions.spacingMd),
      itemBuilder: (context, index) {
        if (index == titles.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }
        final title = titles[index];
        final historyItem = getIt.isRegistered<WatchHistoryCubit>()
            ? getIt<WatchHistoryCubit>().state.getForTitle(title.id)
            : null;
        return AnimeListTileCard(
          title: title,
          watchProgress: historyItem?.progress,
          onTap: () => widget.onTitleSelected?.call(title),
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
        crossAxisSpacing: AppDimensions.spacingMd,
        mainAxisSpacing: AppDimensions.spacingMd,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.stroke, width: 1.0),
              ),
              clipBehavior: Clip.antiAlias,
              child: const ShimmerPlaceholder.card(),
            ),
          ),
          const SizedBox(height: 10),
          const ShimmerPlaceholder.line(width: double.infinity, height: 14),
          const SizedBox(height: 5),
          const ShimmerPlaceholder.line(width: 80, height: 11),
        ],
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
