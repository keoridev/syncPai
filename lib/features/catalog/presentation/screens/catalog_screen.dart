import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/network/network_status_helper.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/app_avatar.dart';
import 'package:sync_pai/core/widgets/app_search_bar.dart';
import 'package:sync_pai/core/widgets/pai_chan_offline_view.dart';
import 'package:sync_pai/core/widgets/shimmer_placeholder.dart';
import 'package:sync_pai/core/widgets/view_mode_toggle.dart';
import 'package:sync_pai/core/widgets/sync_pai_logo.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/sync_pai_mascot.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_state.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/catalog_settings.dart';
import 'package:sync_pai/features/catalog/services/catalog_prefetch_service.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:sync_pai/features/watch_history/domain/entities/watch_history_item.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_state.dart';
import 'package:sync_pai/features/wrapped/presentation/widgets/wrapped_promo_banner.dart';
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
  Timer? _scrollDebounceTimer;
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
    CatalogPrefetchService.instance.startPrefetchQueue();
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels <= 0 || pos.maxScrollExtent <= 0) return;
    // Pre-fetch следующей страницы за 600px до конца списка с дебаунсом
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      if (_scrollDebounceTimer?.isActive ?? false) return;
      _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          context.read<CatalogCubit>().loadMore();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bool isDesktopOS = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool isDesktop = isDesktopOS || screenWidth >= 900;
    final isNarrow = screenWidth <= 360;
    final horizontalPad = isNarrow ? 12.0 : (isDesktop ? 20.0 : 16.0);

    return BlocListener<CatalogCubit, CatalogState>(
      listenWhen: (prev, curr) {
        if (curr is CatalogLoaded) {
          if (prev is! CatalogLoaded) return true;
          return prev.searchQuery != curr.searchQuery;
        }
        return false;
      },
      listener: (context, state) {
        if (state is CatalogLoaded) {
          if (state.searchQuery.isEmpty && _searchController.text.isNotEmpty) {
            _searchController.clear();
          } else if (state.searchQuery.isNotEmpty && _searchController.text != state.searchQuery) {
            _searchController.value = TextEditingValue(
              text: state.searchQuery,
              selection: TextSelection.collapsed(offset: state.searchQuery.length),
            );
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          top: !isDesktopOS,
          bottom: !isDesktopOS,
          left: !isDesktopOS,
          right: !isDesktopOS,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 1440 : double.infinity,
              ),
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
                floating: !isDesktop,
                snap: !isDesktop,
                pinned: isDesktop,
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                toolbarHeight: 56,
                titleSpacing: horizontalPad,
                automaticallyImplyLeading: false,
                title: _isSearchOpen
                    ? Row(
                        children: [
                          if (screenWidth >= 768) ...[
                            const SyncPaiLogo(size: 28),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 720),
                                child: AppSearchBar(
                                  controller: _searchController,
                                  autofocus: true,
                                  onChanged: (query) {
                                    context.read<CatalogCubit>().onSearchQueryChanged(query);
                                  },
                                  onClear: () {
                                    context.read<CatalogCubit>().onSearchQueryChanged('');
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : (screenWidth >= 768
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SyncPaiLogo(size: 28),
                              const SizedBox(width: 10),
                              Text(
                                'Каталог аниме',
                                style: AppTypography.displayMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SyncPaiLogo(size: 32),
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
                  // Кнопка открытия / свертывания поиска
                  IconButton(
                    icon: Icon(
                      _isSearchOpen ? Icons.search_off_rounded : Icons.search_rounded,
                      color: _isSearchOpen ? themePrimary : AppColors.textPrimary,
                      size: 22,
                    ),
                    tooltip: _isSearchOpen ? 'Скрыть строку поиска' : 'Поиск аниме',
                    onPressed: () {
                      if (_isSearchOpen) {
                        setState(() => _isSearchOpen = false);
                        _searchController.clear();
                        context.read<CatalogCubit>().onSearchQueryChanged('');
                      } else {
                        setState(() => _isSearchOpen = true);
                      }
                    },
                  ),

                  // Единый переключатель вида (Сетка / Список) + переключатель колонок (2 к. / 3 к.)
                  BlocBuilder<CatalogCubit, CatalogState>(
                    buildWhen: (prev, curr) => curr is CatalogLoaded,
                    builder: (context, state) {
                      final cubit = context.read<CatalogCubit>();
                      final isList = state is CatalogLoaded && state.viewMode == CatalogViewMode.list;
                      final cols = state is CatalogLoaded
                          ? state.gridDensity.mobileColumns
                          : 2;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isDesktop && !isList) ...[
                              InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  final nextDensity = cols == 2
                                      ? CatalogGridDensity.compact
                                      : CatalogGridDensity.standard;
                                  cubit.setGridDensity(nextDensity);
                                  if (context.mounted && getIt.isRegistered<SettingsCubit>()) {
                                    getIt<SettingsCubit>().setGridColumnCount(nextDensity.mobileColumns);
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.strokeMedium),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.view_column_rounded, size: 15, color: themePrimary),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$cols к.',
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            ViewModeToggle(
                              isGrid: !isList,
                              onChanged: (grid) {
                                cubit.setViewMode(grid ? CatalogViewMode.grid : CatalogViewMode.list);
                                if (getIt.isRegistered<SettingsCubit>()) {
                                  getIt<SettingsCubit>().setIsListView(!grid);
                                }
                              },
                            ),
                          ],
                        ),
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
              ),

              // 2. Полоса "Продолжить просмотр" (сбалансированная на Desktop и Mobile)
              if (getIt.isRegistered<WatchHistoryCubit>())
                BlocBuilder<WatchHistoryCubit, WatchHistoryState>(
                  bloc: getIt<WatchHistoryCubit>(),
                  builder: (context, historyState) {
                    final bool isDesktop = (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
                        MediaQuery.sizeOf(context).width > 800;
                    final seenTitleIds = <int>{};
                    final resumableItems = historyState.history.where((item) {
                      if (item.positionMs < 15000 || item.progress >= 0.95) return false;
                      return seenTitleIds.add(item.titleId);
                    }).take(isDesktop ? 3 : 1).toList();

                    if (resumableItems.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }

                    void handleResumeItem(WatchHistoryItem item) {
                      final currentTitles = context.read<CatalogCubit>().state is CatalogLoaded
                          ? (context.read<CatalogCubit>().state as CatalogLoaded).titles
                          : <AnimeTitle>[];
                      final matched = currentTitles.firstWhere(
                        (t) => t.id == item.titleId,
                        orElse: () => AnimeTitle(
                          id: item.titleId,
                          code: '',
                          russianTitle: item.titleName,
                          englishTitle: '',
                          posterSmall: item.posterUrl,
                          posterMedium: item.posterUrl,
                          posterOriginal: item.posterUrl,
                          episodesTotal: 12,
                          genres: const [],
                          description: '',
                          status: '',
                        ),
                      );
                      widget.onTitleSelected?.call(matched);
                    }

                    Widget buildResumeCard(WatchHistoryItem item, {required bool isSingleHeroDesktop}) {
                      final pct = (item.progress * 100).round().clamp(1, 99);
                      return InkWell(
                        onTap: () => handleResumeItem(item),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: isDesktop ? 60 : 56,
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 34,
                                        height: 46,
                                        child: item.posterUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: wrapCorsSafeUrl(item.posterUrl),
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
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.titleName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.titleSmall.copyWith(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Серия ${item.episode} • ${item.formattedPosition} / ${item.formattedDuration}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.caption.copyWith(
                                              color: AppColors.textSecondary,
                                              fontSize: 10.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSingleHeroDesktop) ...[
                                      const SizedBox(width: 16),
                                      SizedBox(
                                        width: 140,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Просмотрено $pct%',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: item.progress,
                                                minHeight: 4,
                                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                                valueColor: AlwaysStoppedAnimation<Color>(themePrimary),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 12),
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
                                  value: item.progress,
                                  minHeight: 2.5,
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                  valueColor: AlwaysStoppedAnimation<Color>(themePrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 8),
                        child: isDesktop && resumableItems.length > 1
                            ? Row(
                                children: [
                                  for (int i = 0; i < resumableItems.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 12),
                                    Expanded(
                                      child: buildResumeCard(
                                        resumableItems[i],
                                        isSingleHeroDesktop: false,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : buildResumeCard(
                                resumableItems.first,
                                isSingleHeroDesktop: isDesktop,
                              ),
                      ),
                    );
                  },
                ),

              // 2.1 Баннер годовых итогов SyncPai Wrapped 2026
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 8),
                  child: const WrappedPromoBanner(),
                ),
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
                              final currentState = state is CatalogLoaded
                                  ? state
                                  : (context.read<CatalogCubit>().state is CatalogLoaded
                                      ? context.read<CatalogCubit>().state as CatalogLoaded
                                      : null);
                              if (currentState != null) {
                                CatalogFilterSheet.show(context, currentState);
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
                                ? selectedGenres.where((g) => g.toLowerCase() != 'все').isEmpty
                                : selectedGenres.any((g) => g.toLowerCase() == genre.toLowerCase());

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () {
                                  if (_searchController.text.isNotEmpty) {
                                    _searchController.clear();
                                  }
                                  if (_isSearchOpen) {
                                    setState(() => _isSearchOpen = false);
                                  }
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
                        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final title = titles[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: AnimeListTileCard(
                                  key: ValueKey(title.id),
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

                    // Единая адаптивная сетка (Catalog == My Lists):
                    // Desktop: maxCrossAxisExtent: 215, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.62
                    // Mobile: crossAxisCount: 2 (или 3 в компактном режиме), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62
                    final int mobileCols = state.gridDensity.mobileColumns;
                    final SliverGridDelegate gridDelegate = isDesktop
                        ? const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 215,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.62,
                          )
                        : (screenWidth > 600
                            ? const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 195,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.62,
                              )
                            : SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: mobileCols,
                                childAspectRatio: mobileCols >= 3 ? 0.56 : 0.62,
                                crossAxisSpacing: 12.0,
                                mainAxisSpacing: 12.0,
                              ));

                    return SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final title = titles[index];
                            return AnimePosterCard(
                              key: ValueKey(title.id),
                              title: title,
                              isCompact: !isDesktop && mobileCols >= 3,
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
    final bool isDesktopOS = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool isDesktop = isDesktopOS || screenWidth >= 900;

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

    final SliverGridDelegate gridDelegate = isDesktop
        ? const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 215,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.62,
          )
        : SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: screenWidth > 600 ? 3 : 2,
            childAspectRatio: 0.62,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          );

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      sliver: SliverGrid(
        gridDelegate: gridDelegate,
        delegate: SliverChildBuilderDelegate(
          (context, index) => const AnimeCardSkeletonItem(),
          childCount: isDesktop ? 16 : 8,
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    if (NetworkStatusHelper.isConnectionError(message)) {
      return PaiChanOfflineView(
        onRetry: () => context.read<CatalogCubit>().loadUpdates(refresh: true),
        onOpenSaved: () => context.push('/lists'),
      );
    }

    return Center(
      child: SyncPaiMascot(
        state: MascotState.serverError,
        message: 'Не удалось загрузить каталог',
        description: message,
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: const Color(0xFF0F1117),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.read<CatalogCubit>().loadUpdates(refresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.push('/downloads'),
              icon: const Icon(Icons.download_for_offline_rounded, size: 18, color: AppColors.accentTurquoise),
              label: const Text('Офлайн-загрузки', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
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
