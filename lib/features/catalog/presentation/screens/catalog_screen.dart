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
import '../widgets/catalog_filter_sheet.dart';
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

  void _showQuickSortSheet(BuildContext context, CatalogLoaded state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final primary = Theme.of(context).colorScheme.primary;
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppColors.strokeMedium, width: 1.0),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.sort_rounded, size: 20, color: AppColors.textPrimary),
                      const SizedBox(width: 10),
                      Text(
                        'Сортировка каталога',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.strokeMedium),
                ...CatalogSort.values.map((sort) {
                  final isSelected = sort == state.sortBy;
                  return ListTile(
                    leading: Icon(
                      sort.icon,
                      color: isSelected ? primary : AppColors.textSecondary,
                    ),
                    title: Text(
                      sort.label,
                      style: TextStyle(
                        color: isSelected ? primary : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: primary)
                        : null,
                    onTap: () {
                      context.read<CatalogCubit>().setSortBy(sort);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth <= 360;
    final horizontalPad = isNarrow ? 12.0 : AppDimensions.spacingXl;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            // Заголовок приложения, бренд и кнопки настроек отображения
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPad,
                  AppDimensions.spacingLg,
                  horizontalPad,
                  AppDimensions.spacingSm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Логотип и брендовый заголовок
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SyncPaiLogo(size: isNarrow ? 32 : 40),
                          SizedBox(width: isNarrow ? 8 : AppDimensions.spacingMd),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Sync',
                                        style: AppTypography.displayMedium.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: isNarrow ? 20 : 24,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Pai',
                                        style: AppTypography.displayMedium.copyWith(
                                          color: themePrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: isNarrow ? 20 : 24,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppDimensions.spacing2xs),
                                Text(
                                  'Каталог аниме AniLibria',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: isNarrow ? 11 : 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                      padding: EdgeInsets.fromLTRB(
                        AppDimensions.spacingXl,
                        AppDimensions.spacingMd,
                        AppDimensions.spacingXl,
                        AppDimensions.spacingSm,
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
                                color: themePrimary.withValues(alpha: 0.35),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: themePrimary.withValues(alpha: 0.16),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.history_rounded,
                                    color: themePrimaryLight,
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
                                          valueColor: AlwaysStoppedAnimation<Color>(themePrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: themePrimaryLight,
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

            // Липкая шапка с поиском (сворачивается при скролле вниз, мгновенно выплывает при свайпе вверх)
            // и зафиксированной панелью быстрых фильтров и жанров (всегда остаётся на экране)
            SliverAppBar(
              pinned: true,
              floating: true,
              snap: true,
              forceElevated: innerBoxIsScrolled,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 56,
              titleSpacing: 0,
              title: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPad),
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
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(88),
                child: Container(
                  color: AppColors.background,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Панель фильтров и быстрой сортировки
                      BlocBuilder<CatalogCubit, CatalogState>(
                        builder: (context, state) {
                          if (state is! CatalogLoaded) return const SizedBox.shrink();

                          final hasFilters = state.selectedGenres.isNotEmpty ||
                              state.sortBy != CatalogSort.updates ||
                              state.statusFilter != null;
                          final filterCount = state.selectedGenres.length +
                              (state.sortBy != CatalogSort.updates ? 1 : 0) +
                              (state.statusFilter != null ? 1 : 0);

                          return Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPad,
                              vertical: 3,
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  // Кнопка открытия полной шторки фильтров
                                  InkWell(
                                    onTap: () => CatalogFilterSheet.show(context, state),
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: hasFilters
                                            ? themePrimary.withValues(alpha: 0.22)
                                            : AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: hasFilters ? themePrimary : AppColors.strokeMedium,
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.tune_rounded,
                                            size: 16,
                                            color: hasFilters ? themePrimaryLight : AppColors.textPrimary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Фильтры',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: hasFilters ? FontWeight.w700 : FontWeight.w600,
                                              color: hasFilters ? themePrimaryLight : AppColors.textPrimary,
                                            ),
                                          ),
                                          if (filterCount > 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: themePrimary,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                '$filterCount',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  // Быстрый переключатель сортировки
                                  InkWell(
                                    onTap: () => _showQuickSortSheet(context, state),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: state.sortBy != CatalogSort.updates
                                            ? themePrimary.withValues(alpha: 0.18)
                                            : AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: state.sortBy != CatalogSort.updates
                                              ? themePrimary.withValues(alpha: 0.6)
                                              : AppColors.strokeMedium,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            state.sortBy.icon,
                                            size: 15,
                                            color: state.sortBy != CatalogSort.updates
                                                ? themePrimaryLight
                                                : AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            state.sortBy.label,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: state.sortBy != CatalogSort.updates
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: state.sortBy != CatalogSort.updates
                                                  ? themePrimaryLight
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          const Icon(Icons.arrow_drop_down_rounded, size: 16, color: AppColors.textMuted),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  // Быстрый переключатель статуса (Онгоинги / Завершенные / Все)
                                  InkWell(
                                    onTap: () {
                                      if (state.statusFilter == null) {
                                        context.read<CatalogCubit>().setStatusFilter('ongoing');
                                      } else if (state.statusFilter == 'ongoing') {
                                        context.read<CatalogCubit>().setStatusFilter('released');
                                      } else {
                                        context.read<CatalogCubit>().setStatusFilter(null);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: state.statusFilter != null
                                            ? themePrimary.withValues(alpha: 0.18)
                                            : AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: state.statusFilter != null
                                              ? themePrimary.withValues(alpha: 0.6)
                                              : AppColors.strokeMedium,
                                        ),
                                      ),
                                      child: Text(
                                        state.statusFilter == 'ongoing'
                                            ? '🎬 Онгоинги'
                                            : (state.statusFilter == 'released' ? '✓ Завершенные' : '🎬 Статус: Все'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: state.statusFilter != null ? FontWeight.w700 : FontWeight.w500,
                                          color: state.statusFilter != null ? themePrimaryLight : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 5),

                      // Горизонтальный список популярных жанров
                      BlocBuilder<CatalogCubit, CatalogState>(
                        buildWhen: (prev, curr) =>
                            curr is CatalogLoaded || curr is CatalogLoading,
                        builder: (context, state) {
                          final selectedGenres = state is CatalogLoaded
                              ? state.selectedGenres
                              : const <String>{};

                          return SizedBox(
                            height: 36,
                            child: ListView.separated(
                              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: _popularGenres.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: AppDimensions.spacingSm),
                              itemBuilder: (context, index) {
                                final genre = _popularGenres[index];
                                final isAll = genre == 'Все';
                                final isSelected = isAll
                                    ? selectedGenres.isEmpty
                                    : selectedGenres.contains(genre);

                                return InkWell(
                                  onTap: () {
                                    if (isAll) {
                                      context.read<CatalogCubit>().clearGenres();
                                    } else {
                                      context.read<CatalogCubit>().toggleGenre(genre);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? themePrimary.withValues(alpha: 0.22)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? themePrimary.withValues(alpha: 0.7)
                                            : Colors.white.withValues(alpha: 0.08),
                                        width: 1.0,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSelected && !isAll) ...[
                                          Icon(Icons.check_rounded, size: 14, color: themePrimaryLight),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
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
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: BlocBuilder<CatalogCubit, CatalogState>(
            buildWhen: (prev, curr) {
              if (prev.runtimeType != curr.runtimeType) return true;
              if (prev is CatalogLoaded && curr is CatalogLoaded) {
                return prev.filteredTitles != curr.filteredTitles ||
                    prev.viewMode != curr.viewMode ||
                    prev.gridDensity != curr.gridDensity ||
                    prev.isLoadingMore != curr.isLoadingMore;
              }
              return true;
            },
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
                        notification.scrollDelta != null &&
                        notification.scrollDelta! > 0 &&
                        notification.metrics.extentAfter < 500) {
                      context.read<CatalogCubit>().loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    color: themePrimary,
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

  // РЕЖИМ 1: Сетка (оптимизированная под 60-120 FPS с cacheExtent и RepaintBoundary)
  Widget _buildTitlesGrid(
      List<AnimeTitle> titles, CatalogGridDensity density, [bool isLoadingMore = false]) {
    final historyState = getIt.isRegistered<WatchHistoryCubit>()
        ? getIt<WatchHistoryCubit>().state
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmallPhone = width <= 360;

        final crossAxisCount = width > 900
            ? 5
            : width > 600
                ? 4
                : isSmallPhone
                    ? 2
                    : density.mobileColumns;

        final childAspectRatio = isSmallPhone
            ? 0.49
            : (crossAxisCount >= 3 ? 0.49 : 0.53);

        final gridPadding = isSmallPhone
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
            : const EdgeInsets.all(AppDimensions.spacingXl);

        final spacing = isSmallPhone ? 8.0 : AppDimensions.spacingMd;
        final extraItems = isLoadingMore ? crossAxisCount : 0;

        return GridView.builder(
          padding: gridPadding,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          // ignore: deprecated_member_use
          // ignore: deprecated_member_use
      cacheExtent: 350.0,
          addRepaintBoundaries: true,
          findChildIndexCallback: (Key key) {
            if (key is ValueKey<String>) {
              final idStr = key.value.replaceFirst('anime_grid_', '');
              final id = int.tryParse(idStr);
              if (id != null) {
                final idx = titles.indexWhere((t) => t.id == id);
                return idx >= 0 ? idx : null;
              }
            }
            return null;
          },
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: titles.length + extraItems,
          itemBuilder: (context, index) {
            if (index >= titles.length) {
              return const ShimmerPlaceholder.card();
            }
            final title = titles[index];
            final historyItem = historyState?.getForTitle(title.id);
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

  // РЕЖИМ 2: Список (оптимизированный под 60-120 FPS)
  Widget _buildTitlesList(List<AnimeTitle> titles, [bool isLoadingMore = false]) {
    final historyState = getIt.isRegistered<WatchHistoryCubit>()
        ? getIt<WatchHistoryCubit>().state
        : null;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final listPadding = screenWidth <= 360
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
        : const EdgeInsets.all(AppDimensions.spacingXl);
    final spacing = screenWidth <= 360 ? 8.0 : AppDimensions.spacingMd;

    return ListView.separated(
      padding: listPadding,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      // ignore: deprecated_member_use
      cacheExtent: 350.0,
      addRepaintBoundaries: true,
      itemCount: titles.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: spacing),
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
        final historyItem = historyState?.getForTitle(title.id);
        return AnimeListTileCard(
          title: title,
          watchProgress: historyItem?.progress,
          onTap: () => widget.onTitleSelected?.call(title),
        );
      },
    );
  }

  Widget _buildLoadingGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmall = width <= 360;
        final crossAxisCount = width > 900 ? 5 : width > 600 ? 4 : (isSmall ? 2 : 2);
        final spacing = isSmall ? 8.0 : AppDimensions.spacingMd;

        return GridView.builder(
          padding: isSmall
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
              : const EdgeInsets.all(AppDimensions.spacingXl),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: isSmall ? 0.49 : 0.53,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: crossAxisCount * 3,
          itemBuilder: (context, index) => const ShimmerPlaceholder.card(),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacing2xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            Text(
              'Ничего не найдено',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              'Попробуйте изменить поисковый запрос или сбросить фильтры жанров',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            AppButton.frosted(
              label: 'Сбросить фильтры',
              icon: Icons.refresh_rounded,
              onPressed: () {
                _searchController.clear();
                context.read<CatalogCubit>().onSearchQueryChanged('');
                context.read<CatalogCubit>().clearGenres();
                context.read<CatalogCubit>().setStatusFilter(null);
                context.read<CatalogCubit>().setSortBy(CatalogSort.updates);
              },
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 56,
              color: AppColors.syncError,
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            Text(
              'Ошибка загрузки',
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
            const SizedBox(height: AppDimensions.spacingLg),
            AppButton(
              label: 'Повторить попытку',
              icon: Icons.refresh_rounded,
              onPressed: () =>
                  context.read<CatalogCubit>().loadUpdates(refresh: true),
            ),
          ],
        ),
      ),
    );
  }
}
