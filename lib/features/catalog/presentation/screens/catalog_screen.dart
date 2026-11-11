import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_dimensions.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/app_avatar.dart';
import 'package:sync_pai/core/widgets/app_search_bar.dart';
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
import '../widgets/catalog_filter_sheet.dart';

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
  late final ScrollController _scrollController;
  bool _isSearchOpen = false;

  static const List<String> _popularGenres = [
    'Все',
    'Сёнэн',
    'Экшен',
    'Комедия',
    'Романтика',
    'Фэнтези',
    'Детектив',
    'Драма',
    'Приключения',
    'Повседневность',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    context.read<CatalogCubit>().loadUpdates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Pre-fetch следующей страницы за 800px до конца списка
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 800) {
      context.read<CatalogCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth <= 360;
    final horizontalPad = isNarrow ? 12.0 : 16.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: themePrimary,
          backgroundColor: AppColors.surfaceElevated,
          onRefresh: () => context.read<CatalogCubit>().loadUpdates(refresh: true),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // 1. Плавающий SliverAppBar (Логотип слева, профиль и кнопка поиска справа)
              SliverAppBar(
                floating: true,
                snap: true,
                pinned: false,
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                toolbarHeight: 56,
                titleSpacing: horizontalPad,
                automaticallyImplyLeading: false,
                title: _isSearchOpen
                    ? AppSearchBar(
                        controller: _searchController,
                        onChanged: (query) {
                          context.read<CatalogCubit>().onSearchQueryChanged(query);
                        },
                        onClear: () {
                          context.read<CatalogCubit>().onSearchQueryChanged('');
                        },
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SyncPaiLogo(size: 32),
                          const SizedBox(width: 10),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Sync',
                                  style: AppTypography.displayMedium.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Pai',
                                  style: AppTypography.displayMedium.copyWith(
                                    color: themePrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                actions: [
                  if (_isSearchOpen) ...[
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                      tooltip: 'Закрыть поиск',
                      onPressed: () {
                        setState(() => _isSearchOpen = false);
                        _searchController.clear();
                        context.read<CatalogCubit>().onSearchQueryChanged('');
                      },
                    ),
                    const SizedBox(width: 4),
                  ] else ...[
                    // Кнопка открытия поиска
                    IconButton(
                      icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary, size: 22),
                      tooltip: 'Поиск аниме',
                      onPressed: () => setState(() => _isSearchOpen = true),
                    ),

                    // Переключатель Сетка / Список
                    BlocBuilder<CatalogCubit, CatalogState>(
                      buildWhen: (prev, curr) => curr is CatalogLoaded,
                      builder: (context, state) {
                        final isGrid = state is CatalogLoaded
                            ? state.viewMode == CatalogViewMode.grid
                            : true;
                        return IconButton(
                          icon: Icon(
                            isGrid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
                            color: AppColors.textPrimary,
                            size: 21,
                          ),
                          tooltip: isGrid ? 'Список' : 'Сетка',
                          onPressed: () => context.read<CatalogCubit>().toggleViewMode(),
                        );
                      },
                    ),

                    // Аватарка профиля
                    if (getIt.isRegistered<AuthCubit>())
                      BlocBuilder<AuthCubit, AuthState>(
                        bloc: getIt<AuthCubit>(),
                        builder: (context, authState) {
                          final profile = authState is Authenticated ? authState.profile : null;
                          return Padding(
                            padding: const EdgeInsets.only(left: 4, right: 12),
                            child: GestureDetector(
                              onTap: () => context.pushNamed('profile'),
                              child: AppAvatar(
                                avatarUrl: profile?.avatarUrl,
                                username: profile?.username ?? 'Гость',
                                size: 34,
                                borderWidth: 1.2,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ],
              ),

              // 2. Компактная плашка "Продолжить просмотр" (Высота 52-54 dp)
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
                        padding: EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 8),
                        child: InkWell(
                          onTap: handleResume,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: themePrimary.withValues(alpha: 0.3),
                                width: 1.0,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: themePrimary.withValues(alpha: 0.16),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.play_arrow_rounded,
                                          color: themePrimaryLight,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              recent.titleName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTypography.titleSmall.copyWith(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              'Серия ${recent.episode} • ${recent.formattedPosition} / ${recent.formattedDuration}',
                                              style: AppTypography.caption.copyWith(
                                                color: AppColors.textSecondary,
                                                fontSize: 10.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 12,
                                        color: themePrimaryLight,
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: LinearProgressIndicator(
                                    value: recent.progress,
                                    minHeight: 2.5,
                                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                                    valueColor: AlwaysStoppedAnimation<Color>(themePrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // 3. Единая строка фильтров (Один горизонтальный скролл чипов + компактная кнопка фильтра слева)
              SliverToBoxAdapter(
                child: BlocBuilder<CatalogCubit, CatalogState>(
                  builder: (context, state) {
                    final selectedGenres = state is CatalogLoaded
                        ? state.selectedGenres
                        : const <String>{};
                    final hasFilters = state is CatalogLoaded &&
                        (state.selectedGenres.isNotEmpty ||
                            state.sortBy != CatalogSort.updates ||
                            state.statusFilter != null);

                    return SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(
                          left: horizontalPad,
                          right: horizontalPad + 18,
                        ),
                        children: [
                          // Компактная кнопка расширенных фильтров
                          InkWell(
                            onTap: () {
                              if (state is CatalogLoaded) {
                                CatalogFilterSheet.show(context, state);
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: hasFilters
                                    ? themePrimary.withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: hasFilters ? themePrimary : Colors.white.withValues(alpha: 0.10),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 15,
                                    color: hasFilters ? themePrimaryLight : AppColors.textSecondary,
                                  ),
                                  if (hasFilters) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: themePrimary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Горизонтальный скролл чипов жанров
                          ..._popularGenres.map((genre) {
                            final isAll = genre == 'Все';
                            final isSelected = isAll
                                ? selectedGenres.isEmpty
                                : selectedGenres.contains(genre);

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () {
                                  if (isAll) {
                                    context.read<CatalogCubit>().clearGenres();
                                  } else {
                                    context.read<CatalogCubit>().onCategoryChanged(genre);
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? themePrimary
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? themePrimary
                                          : Colors.white.withValues(alpha: 0.08),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Text(
                                    genre,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : AppColors.textSecondary,
                                      fontSize: 12.5,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // 4. Сетка аниме (2 колонки) / Список с высокой производительностью
              BlocBuilder<CatalogCubit, CatalogState>(
                builder: (context, state) {
                  final isListMode = (state is CatalogLoaded && state.viewMode == CatalogViewMode.list);
                  if (state is CatalogLoading) {
                    return _buildSliverLoadingGrid(
                      horizontalPad,
                      isListMode: isListMode,
                      screenWidth: screenWidth,
                    );
                  }

                  if (state is CatalogError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildErrorState(context, state.message),
                    );
                  }

                  if (state is CatalogLoaded) {
                    final titles = state.filteredTitles;
                    if (titles.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(context),
                      );
                    }

                    if (state.viewMode == CatalogViewMode.list) {
                      return SliverPadding(
                        padding: EdgeInsets.only(
                          left: horizontalPad,
                          right: horizontalPad + 18,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final title = titles[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: AnimeListTileCard(
                                  title: title,
                                  onTap: () => widget.onTitleSelected?.call(title),
                                ),
                              );
                            },
                            childCount: titles.length,
                          ),
                        ),
                      );
                    }

                    // СЕТКА НА 2 КОЛОНКИ С КРУПНЫМ АСПЕКТ-РЕЙШИО 0.68
                    return SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: screenWidth > 900
                              ? 5
                              : (screenWidth > 600 ? 4 : 2), // Ровно 2 колонки на смартфонах!
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final title = titles[index];
                            return AnimePosterCard(
                              title: title,
                              onTap: () => widget.onTitleSelected?.call(title),
                            );
                          },
                          childCount: titles.length,
                        ),
                      ),
                    );
                  }

                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),

              // 5. Индикатор бесконечного скролла
              BlocBuilder<CatalogCubit, CatalogState>(
                builder: (context, state) {
                  if (state is CatalogLoaded && !state.hasReachedMax) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    );
                  }
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverLoadingGrid(
    double horizontalPad, {
    required bool isListMode,
    required double screenWidth,
  }) {
    final int columnsCount = screenWidth > 900 ? 5 : (screenWidth > 600 ? 4 : 2);
    const double aspectRatio = 0.68;

    if (isListMode) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => const AnimeListSkeletonItem(),
            childCount: 8,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnsCount,
          childAspectRatio: aspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => const AnimeCardSkeletonItem(),
          childCount: columnsCount * 4,
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.syncError),
            const SizedBox(height: AppDimensions.spacingMd),
            Text(
              'Не удалось загрузить каталог',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.read<CatalogCubit>().loadUpdates(refresh: true),
              child: const Text('Повторить попытку', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 52, color: AppColors.textMuted),
            const SizedBox(height: AppDimensions.spacingMd),
            Text(
              'Ничего не найдено',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              'Попробуйте изменить поисковый запрос или сбросить фильтры',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                context.read<CatalogCubit>().clearGenres();
                context.read<CatalogCubit>().onSearchQueryChanged('');
              },
              child: const Text('Сбросить фильтры'),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimeCardSkeletonItem extends StatelessWidget {
  const AnimeCardSkeletonItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const ShimmerPlaceholder(
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    );
  }
}

class AnimeListSkeletonItem extends StatelessWidget {
  const AnimeListSkeletonItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const ShimmerPlaceholder(
            width: 70,
            height: 100,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                ShimmerPlaceholder(
                  width: double.infinity,
                  height: 16,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                SizedBox(height: 8),
                ShimmerPlaceholder(
                  width: 120,
                  height: 12,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
