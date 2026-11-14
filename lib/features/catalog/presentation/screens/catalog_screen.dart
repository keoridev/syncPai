import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/app_avatar.dart';
import 'package:sync_pai/core/widgets/app_search_bar.dart';
import 'package:sync_pai/core/widgets/shimmer_placeholder.dart';
import 'package:sync_pai/core/widgets/sync_pai_logo.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/sync_pai_mascot.dart';
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
                    : (screenWidth >= 768
                        ? Text(
                            'Каталог аниме',
                            style: AppTypography.displayMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              letterSpacing: -0.4,
                            ),
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
                          )),
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

                    // Переключатель вида каталога: 2 в ряд / 3 в ряд / Список
                    BlocBuilder<CatalogCubit, CatalogState>(
                      buildWhen: (prev, curr) => curr is CatalogLoaded,
                      builder: (context, state) {
                        final cubit = context.read<CatalogCubit>();
                        final isList = state is CatalogLoaded && state.viewMode == CatalogViewMode.list;
                        final is3Columns = state is CatalogLoaded &&
                            state.viewMode == CatalogViewMode.grid &&
                            state.gridDensity == CatalogGridDensity.compact;

                        final IconData icon;
                        final String tooltip;
                        if (isList) {
                          icon = Icons.view_agenda_outlined;
                          tooltip = 'Вид: Список (тап для 2 в ряд)';
                        } else if (is3Columns) {
                          icon = Icons.apps_rounded;
                          tooltip = 'Вид: 3 в ряд (тап для списка)';
                        } else {
                          icon = Icons.grid_view_rounded;
                          tooltip = 'Вид: 2 в ряд (тап для 3 в ряд)';
                        }

                        return IconButton(
                          icon: Icon(icon, color: AppColors.textPrimary, size: 21),
                          tooltip: tooltip,
                          onPressed: () => cubit.cycleDisplayMode(),
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

                    final bool isDesktop = (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
                        MediaQuery.sizeOf(context).width > 800;

                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: isDesktop ? 460 : double.infinity,
                            ),
                            child: InkWell(
                              onTap: handleResume,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                height: 56,
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
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      child: Row(
                                        children: [
                                          // Мини-постер тайтла слева
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: SizedBox(
                                              width: 32,
                                              height: 44,
                                              child: recent.posterUrl.isNotEmpty
                                                  ? CachedNetworkImage(
                                                      imageUrl: wrapCorsSafeUrl(recent.posterUrl),
                                                      fit: BoxFit.cover,
                                                      errorWidget: (_, __, ___) => Container(
                                                        color: themePrimary.withValues(alpha: 0.16),
                                                        child: Icon(Icons.play_arrow_rounded, color: themePrimaryLight, size: 16),
                                                      ),
                                                    )
                                                  : Container(
                                                      color: themePrimary.withValues(alpha: 0.16),
                                                      child: Icon(Icons.play_arrow_rounded, color: themePrimaryLight, size: 16),
                                                    ),
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
                                                const SizedBox(height: 2),
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
                                          const SizedBox(width: 8),
                                          if (isDesktop)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: themePrimary.withValues(alpha: 0.16),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: themePrimary.withValues(alpha: 0.4)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Продолжить',
                                                    style: TextStyle(
                                                      color: themePrimaryLight,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Icon(Icons.play_arrow_rounded, size: 14, color: themePrimaryLight),
                                                ],
                                              ),
                                            )
                                          else
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
                                      color: isSelected ? AppColors.onColor(themePrimary) : AppColors.textSecondary,
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
                  if (state is CatalogLoading ||
                      (state is CatalogLoaded && state.filteredTitles.isEmpty && state.isLoadingMore)) {
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

                    final columns = screenWidth > 900
                        ? 5
                        : (screenWidth > 600
                            ? 4
                            : state.gridDensity.mobileColumns);
                    // Дефолтный естественный аспект 2:3 без обрезки по вертикали
                    final ratio = columns >= 3 ? 0.50 : 0.55;
                    final spacing = columns >= 3 ? 8.0 : 12.0;

                    return SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: ratio,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing + 4,
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
      child: SyncPaiMascot(
        state: message.toLowerCase().contains('connect') || message.toLowerCase().contains('сеть')
            ? MascotState.networkError
            : MascotState.serverError,
        message: 'Не удалось загрузить каталог',
        description: message,
        action: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: const Color(0xFF0F1117),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => context.read<CatalogCubit>().loadUpdates(refresh: true),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Повторить попытку', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SyncPaiMascot(
        state: MascotState.emptySearch,
        message: 'Ничего не найдено',
        description: 'Попробуйте изменить поисковый запрос или сбросить фильтры',
        action: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Theme.of(context).colorScheme.primary),
            foregroundColor: AppColors.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            context.read<CatalogCubit>().clearGenres();
            context.read<CatalogCubit>().onSearchQueryChanged('');
          },
          icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
          label: const Text('Сбросить фильтры', style: TextStyle(fontWeight: FontWeight.w600)),
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
