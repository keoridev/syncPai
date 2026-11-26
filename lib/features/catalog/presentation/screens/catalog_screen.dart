import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/network/network_status_helper.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
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
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_state.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_state.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/catalog_settings.dart';
import 'package:sync_pai/features/catalog/domain/services/recommendation_engine.dart';
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
import '../../../manga/presentation/widgets/manga_catalog_view.dart';

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
  bool _isForYouTabSelected = false;

  bool get _isMangaMode => context.select<CatalogCubit, bool>(
        (c) => c.state is CatalogLoaded
            ? (c.state as CatalogLoaded).isMangaMode
            : c.isMangaMode,
      );

  static const List<({String id, String label})> _quickTabs = [
    (id: 'all', label: 'Все'),
    (id: 'ongoing', label: 'Онгоинги'),
    (id: 'popular', label: 'Популярное'),
    (id: 'released', label: 'Завершённые'),
    (id: 'movies', label: 'Фильмы'),
    (id: 'anons', label: 'Анонсы'),
    (id: 'schedule', label: 'Расписание'),
    (id: 'for_you', label: 'Для тебя'),
  ];

  String? _activeQuickTabId(CatalogState state) {
    if (_isForYouTabSelected && (state is! CatalogLoaded || state.searchQuery.isEmpty)) {
      return 'for_you';
    }
    if (state is! CatalogLoaded) return 'all';
    if (state.activeFilterKey.startsWith('announced|')) return 'anons';
    if (state.activeFilterKey.startsWith('schedule|')) return 'schedule';
    if (state.selectedGenres.isNotEmpty) return null;
    if (state.typeFilter == 'MOVIE' && state.statusFilter == null) {
      return 'movies';
    }
    if (state.typeFilter != null) return null;
    if (state.statusFilter == 'ongoing') return 'ongoing';
    if (state.statusFilter == 'released') return 'released';
    if (state.statusFilter == 'anons') return 'anons';
    if (state.statusFilter == null && state.sortBy == CatalogSort.rating) {
      return 'popular';
    }
    if (state.statusFilter == null && state.sortBy == CatalogSort.updates) {
      return 'all';
    }
    return null;
  }

  void _openForYouTab() {
    if (!mounted) return;
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      context.read<CatalogCubit>().onSearchQueryChanged('');
    }
    setState(() {
      _isForYouTabSelected = true;
      _isSearchOpen = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _launchRandomChoice(List<AnimeTitle> pool) {
    if (pool.isEmpty) return;
    HapticFeedback.mediumImpact();
    final pick = pool[math.Random().nextInt(pool.length)];
    _openAnimeDetails(pick);
  }

  void _openAnimeDetails(AnimeTitle title) {
    if (widget.onTitleSelected != null) {
      widget.onTitleSelected!(title);
    } else {
      context.pushNamed('details', extra: title);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    context.read<CatalogCubit>().loadUpdates();
    MascotCompanionService.instance.startCatalogBrowsingTimer(
      onOpenForYou: _openForYouTab,
    );
  }

  @override
  void dispose() {
    MascotCompanionService.instance.stopCatalogBrowsingTimer();
    _scrollDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      context.read<CatalogCubit>().setUserScrollOffset(
            _scrollController.position.pixels,
          );
    }
    MascotCompanionService.instance.reportCatalogInteraction(
      onOpenForYou: _openForYouTab,
    );
    _maybeTriggerLoadNextPage();
  }

  void _maybeTriggerLoadNextPage() {
    if (!mounted || !_scrollController.hasClients) return;
    final cubit = context.read<CatalogCubit>();
    final cubitState = cubit.state;
    if (cubitState is! CatalogLoaded) return;

    final pos = _scrollController.position;
    if (pos.pixels <= 200 || pos.extentAfter >= 400) return;

    if (cubit.isMangaMode) {
      if (cubitState.isMangaLoadingMore ||
          !cubitState.hasMoreManga ||
          cubitState.mangaSearchQuery.isNotEmpty) {
        return;
      }
      if (_scrollDebounceTimer?.isActive ?? false) return;
      _scrollDebounceTimer = Timer(const Duration(milliseconds: 80), () {
        if (mounted) {
          context.read<CatalogCubit>().loadNextMangaPage();
        }
      });
      return;
    }

    if (_isForYouTabSelected ||
        cubitState.isLoadingMore ||
        !cubitState.hasMore ||
        cubitState.searchQuery.isNotEmpty) {
      return;
    }
    if (_scrollDebounceTimer?.isActive ?? false) return;
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) {
        context.read<CatalogCubit>().loadNextPage();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bool isTestEnv = Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');
    final bool isDesktopOS = !isTestEnv && !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool isDesktop = isDesktopOS || screenWidth >= 900;
    final horizontalPad = isDesktop ? 20.0 : 16.0;

    return BlocListener<CatalogCubit, CatalogState>(
      listenWhen: (prev, curr) {
        if (curr is CatalogLoaded) {
          if (prev is! CatalogLoaded) return true;
          return prev.searchQuery != curr.searchQuery ||
              prev.isLoadingMore != curr.isLoadingMore ||
              prev.filteredTitles.length != curr.filteredTitles.length;
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
          if (!state.isLoadingMore && state.hasMore && state.searchQuery.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _maybeTriggerLoadNextPage();
            });
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                                    if (_isForYouTabSelected && query.trim().isNotEmpty) {
                                      setState(() => _isForYouTabSelected = false);
                                    }
                                    final cubit = context.read<CatalogCubit>();
                                    if (cubit.isMangaMode) {
                                      cubit.onMangaSearchChanged(query);
                                    } else {
                                      cubit.onSearchQueryChanged(query);
                                    }
                                  },
                                  onClear: () {
                                    final cubit = context.read<CatalogCubit>();
                                    if (cubit.isMangaMode) {
                                      cubit.onMangaSearchChanged('');
                                    } else {
                                      cubit.onSearchQueryChanged('');
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : (screenWidth >= 768
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SyncPaiLogo(size: 28),
                                const SizedBox(width: 10),
                                Text(
                                  _isMangaMode ? 'Манга и Манхва' : 'Каталог аниме',
                                  style: AppTypography.displayMedium.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                _buildModeSegmentedToggle(themePrimary),
                              ],
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SyncPaiLogo(size: 26),
                                const SizedBox(width: 6),
                                _buildModeSegmentedToggle(themePrimary),
                              ],
                            ),
                          )),
                actions: [
                  // Кнопка открытия / свертывания поиска
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      key: const ValueKey('catalog_search_toggle_btn'),
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        if (_isSearchOpen) {
                          setState(() => _isSearchOpen = false);
                          _searchController.clear();
                          final cubit = context.read<CatalogCubit>();
                          if (cubit.isMangaMode) {
                            cubit.onMangaSearchChanged('');
                          } else {
                            cubit.onSearchQueryChanged('');
                          }
                        } else {
                          setState(() => _isSearchOpen = true);
                        }
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _isSearchOpen
                              ? themePrimary.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isSearchOpen
                                ? themePrimary.withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Icon(
                          _isSearchOpen ? Icons.search_off_rounded : Icons.search_rounded,
                          color: _isSearchOpen ? themePrimary : AppColors.textPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),

                  // Переключатель числа колонок (2 к. / 3 к.) на мобильных и переключатель вида на широких экранах
                  BlocBuilder<CatalogCubit, CatalogState>(
                    buildWhen: (prev, curr) => curr is CatalogLoaded || curr is CatalogInitial,
                    builder: (context, state) {
                      final cubit = context.read<CatalogCubit>();
                      final isList = state is CatalogLoaded && state.viewMode == CatalogViewMode.list;
                      final cols = state is CatalogLoaded
                          ? state.gridDensity.mobileColumns
                          : 2;
                      final showColsToggle = !isDesktop && !isList;
                      final showViewToggle = screenWidth >= 600;
                      if (!showColsToggle && !showViewToggle) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showColsToggle) ...[
                              InkWell(
                                key: const ValueKey('catalog_grid_columns_toggle'),
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
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(horizontal: 9),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.grid_view_rounded, size: 15, color: themePrimary),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$cols к.',
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (showViewToggle) const SizedBox(width: 6),
                            ],
                            if (showViewToggle)
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
                          padding: EdgeInsets.only(right: horizontalPad),
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

              // 2. Полоса "Продолжить просмотр" или браузер манги/манхвы
              if (_isMangaMode)
                const MangaCatalogView()
              else ...[
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
                                      flex: 2,
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
                                    if (isSingleHeroDesktop &&
                                        MediaQuery.sizeOf(context).width >= 760) ...[
                                      const SizedBox(width: 12),
                                      Flexible(
                                        flex: 1,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 140),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'Просмотрено $pct%',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                                      ),
                                    ],
                                    const SizedBox(width: 8),
                                    if (isDesktop)
                                      Flexible(
                                        flex: 0,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Container(
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
                                        ),
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

              // 2.1 Баннер годовых итогов SyncPai Wrapped 2026 (на мобильном вынесен в Профиль -> Статистика)
              if (screenWidth >= 600)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 8),
                    child: const WrappedPromoBanner(),
                  ),
                ),

              // 3. Современные borderless-вкладки с анимированным подчёркиванием + кнопка фильтров
              SliverToBoxAdapter(
                child: BlocBuilder<CatalogCubit, CatalogState>(
                  builder: (context, state) {
                    final activeTabId = _activeQuickTabId(state);
                    final hasFilters = !_isForYouTabSelected &&
                        state is CatalogLoaded &&
                        (state.selectedGenres.isNotEmpty ||
                            state.sortBy != CatalogSort.updates ||
                            state.statusFilter != null ||
                            state.typeFilter != null);

                    return SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(
                          left: horizontalPad,
                          right: horizontalPad + 16,
                        ),
                        children: [
                          // Borderless-кнопка расширенных фильтров слева
                          InkWell(
                            key: const ValueKey('catalog_filter_button'),
                            onTap: () {
                              if (_isForYouTabSelected) {
                                setState(() => _isForYouTabSelected = false);
                              }
                              final currentState = state is CatalogLoaded
                                  ? state
                                  : (context.read<CatalogCubit>().state is CatalogLoaded
                                      ? context.read<CatalogCubit>().state as CatalogLoaded
                                      : null);
                              if (currentState != null) {
                                CatalogFilterSheet.show(context, currentState);
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                    color: hasFilters
                                        ? const Color(0xFFFF6B4A)
                                        : const Color(0xFF7E8A9A),
                                  ),
                                  if (hasFilters)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFFF6B4A),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Чистые borderless текстовые вкладки с анимированным подчёркиванием
                          ..._quickTabs.map((tab) {
                            final isSelected = activeTabId == tab.id;

                            return Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: InkWell(
                                key: ValueKey('catalog_quick_tab_${tab.id}'),
                                onTap: () {
                                  MascotCompanionService.instance.reportCatalogInteraction(
                                    onOpenForYou: _openForYouTab,
                                  );
                                  if (_searchController.text.isNotEmpty) {
                                    _searchController.clear();
                                    context.read<CatalogCubit>().onSearchQueryChanged('');
                                  }
                                  if (_isSearchOpen) {
                                    setState(() => _isSearchOpen = false);
                                  }
                                  if (tab.id == 'for_you') {
                                    setState(() => _isForYouTabSelected = true);
                                  } else {
                                    if (_isForYouTabSelected) {
                                      setState(() => _isForYouTabSelected = false);
                                    }
                                    context.read<CatalogCubit>().selectQuickTab(tab.id);
                                  }
                                },
                                borderRadius: BorderRadius.circular(6),
                                splashColor: Colors.white.withValues(alpha: 0.06),
                                highlightColor: Colors.transparent,
                                child: IntrinsicWidth(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Text(
                                          tab.label,
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(0xFFFFFFFF)
                                                : const Color(0xFF7E8A9A),
                                            fontSize: 14.0,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                            letterSpacing: -0.1,
                                          ),
                                        ),
                                      ),
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 220),
                                        curve: Curves.easeOutCubic,
                                        height: 2.5,
                                        width: isSelected ? 26 : 0,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6B4A),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ],
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

              // 4. Открытая секция «Для тебя» ЛИБО сетка/список каталога и поиска со статус-пиллами
              BlocBuilder<CatalogCubit, CatalogState>(
                builder: (context, state) {
                  Widget buildMainSliver(List<UserAnimeEntry> entries) {
                    final userListsMap = <int, AnimeListStatus>{
                      for (final e in entries) e.animeId: e.status,
                    };

                    if (_isForYouTabSelected && state is CatalogLoaded && state.searchQuery.isEmpty) {
                      return _buildOpenForYouSectionSliver(
                        context,
                        state: state,
                        entries: entries,
                        userListsMap: userListsMap,
                        screenWidth: screenWidth,
                        isDesktop: isDesktop,
                        horizontalPad: horizontalPad,
                      );
                    }

                    final isListMode = (state is CatalogLoaded && state.viewMode == CatalogViewMode.list);
                    if (state is CatalogLoading ||
                        (state is CatalogLoaded &&
                            state.filteredTitles.isEmpty &&
                            (state.isSearching || state.isLoadingMore))) {
                      return _buildSliverLoadingGrid(
                        horizontalPad,
                        isListMode: isListMode,
                        screenWidth: screenWidth,
                      );
                    }

                    if (state is CatalogError) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 40,
                          ),
                          child: Center(
                            child: _buildErrorState(context, state.message),
                          ),
                        ),
                      );
                    }

                    if (state is CatalogLoaded) {
                      final titles = state.filteredTitles;
                      if (titles.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 40,
                            ),
                            child: Center(
                              child: _buildEmptyState(context, state),
                            ),
                          ),
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
                                    userListStatus: userListsMap[title.id],
                                    onTap: () => _openAnimeDetails(title),
                                  ),
                                );
                              },
                              childCount: titles.length,
                            ),
                          ),
                        );
                      }

                      final mobileCols = screenWidth < 390 ? 2 : state.gridDensity.mobileColumns;
                      final gridHorizontalPad = screenWidth < 390
                          ? 12.0
                          : (screenWidth < 600 ? 14.0 : horizontalPad);
                      final gridDelegate = _resolveCatalogGridDelegate(
                        screenWidth: screenWidth,
                        mobileCols: mobileCols,
                      );

                      return SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: gridHorizontalPad),
                        sliver: SliverGrid(
                          gridDelegate: gridDelegate,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final title = titles[index];
                              return AnimePosterCard(
                                key: ValueKey(title.id),
                                title: title,
                                isCompact: !isDesktop && screenWidth < 600 && mobileCols == 3,
                                userListStatus: userListsMap[title.id],
                                onTap: () => _openAnimeDetails(title),
                              );
                            },
                            childCount: titles.length,
                          ),
                        ),
                      );
                    }

                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }

                  if (getIt.isRegistered<AnimeListCubit>()) {
                    return BlocBuilder<AnimeListCubit, AnimeListState>(
                      bloc: getIt<AnimeListCubit>(),
                      builder: (context, listState) =>
                          buildMainSliver(listState.allEntries),
                    );
                  }
                  return buildMainSliver(const <UserAnimeEntry>[]);
                },
              ),

              // 5. Индикатор бесконечного скролла (только при активной догрузке следующей страницы и непустом списке)
              BlocBuilder<CatalogCubit, CatalogState>(
                builder: (context, state) {
                  if (!_isForYouTabSelected &&
                      state is CatalogLoaded &&
                      state.isLoadingMore &&
                      state.hasMore &&
                      state.filteredTitles.isNotEmpty) {
                    return const SliverToBoxAdapter(
                      key: ValueKey('catalog_bottom_pagination_spinner'),
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
              ],

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

  Widget _buildModeSegmentedToggle(Color themePrimary) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF151923),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeSegmentButton(
            key: const ValueKey('catalog_mode_anime'),
            label: 'Аниме',
            isSelected: !_isMangaMode,
            themePrimary: themePrimary,
            onTap: () => context.read<CatalogCubit>().setMangaMode(false),
          ),
          _buildModeSegmentButton(
            key: const ValueKey('catalog_mode_manga'),
            label: 'Манга и манхва',
            isSelected: _isMangaMode,
            themePrimary: themePrimary,
            onTap: () => context.read<CatalogCubit>().setMangaMode(true),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSegmentButton({
    required Key key,
    required String label,
    required bool isSelected,
    required Color themePrimary,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: isSelected ? themePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  SliverGridDelegate _resolveCatalogGridDelegate({
    required double screenWidth,
    required int mobileCols,
  }) {
    if (screenWidth >= 900) {
      return const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 215,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.62,
      );
    }
    if (screenWidth >= 600) {
      return const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      );
    }
    final effectiveMobileCols = screenWidth < 390 ? 2 : mobileCols;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: effectiveMobileCols,
      childAspectRatio: effectiveMobileCols == 3 ? 0.52 : 0.58,
      crossAxisSpacing: effectiveMobileCols == 3 ? 8.0 : 12.0,
      mainAxisSpacing: effectiveMobileCols == 3 ? 12.0 : 14.0,
    );
  }

  Widget _buildOpenForYouSectionSliver(
    BuildContext context, {
    required CatalogLoaded state,
    required List<UserAnimeEntry> entries,
    required Map<int, AnimeListStatus> userListsMap,
    required double screenWidth,
    required bool isDesktop,
    required double horizontalPad,
  }) {
    final history = getIt.isRegistered<WatchHistoryCubit>()
        ? context.watch<WatchHistoryCubit>().state.history
        : const <WatchHistoryItem>[];
    final picks = RecommendationEngine.instance.generateForYouFeed(
      catalogPool: state.titles,
      userEntries: entries,
      watchHistory: history,
      limit: 24,
    );

    final gridHorizontalPad = screenWidth < 390
        ? 12.0
        : (screenWidth < 600 ? 14.0 : horizontalPad);
    final mobileCols = screenWidth < 390 ? 2 : state.gridDensity.mobileColumns;
    final gridDelegate = _resolveCatalogGridDelegate(
      screenWidth: screenWidth,
      mobileCols: mobileCols,
    );

    // Если персональная подборка готова — группируем в открытую витрину с тегами причин
    if (picks.isNotEmpty) {
      const hookOrder = [
        (hook: RecommendationHook.zeigarnik, title: 'Продолжить просмотр'),
        (hook: RecommendationHook.postFinaleEcho, title: 'После просмотренного'),
        (hook: RecommendationHook.plannedResurface, title: 'Из вашего «В планах»'),
        (hook: RecommendationHook.coreTaste, title: 'Точное совпадение по вкусу'),
        (hook: RecommendationHook.circadianDiscovery, title: 'Настроение момента'),
      ];

      final sections = <Widget>[];
      for (final section in hookOrder) {
        final sectionPicks = picks.where((p) => p.hook == section.hook).toList();
        if (sectionPicks.isEmpty) continue;
        sections.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 8),
            child: Row(
              children: [
                Text(
                  section.title,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${sectionPicks.length}',
                  style: AppTypography.caption.copyWith(
                    color: const Color(0xFF7E8A9A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
        sections.add(
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: gridDelegate,
            itemCount: sectionPicks.length,
            itemBuilder: (context, index) {
              final pick = sectionPicks[index];
              return AnimePosterCard(
                key: ValueKey('for_you_open_${pick.anime.id}'),
                title: pick.anime,
                isCompact: !isDesktop && screenWidth < 600 && mobileCols == 3,
                statusBadgeText: pick.reasonTag,
                userListStatus: userListsMap[pick.anime.id],
                onTap: () => _openAnimeDetails(pick.anime),
              );
            },
          ),
        );
        sections.add(const SizedBox(height: 12));
      }

      return SliverPadding(
        key: const ValueKey('catalog_open_for_you_view'),
        padding: EdgeInsets.symmetric(horizontal: gridHorizontalPad),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Персональная подборка',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _launchRandomChoice(
                      picks.map((e) => e.anime).toList(),
                    ),
                    icon: const Icon(Icons.shuffle_rounded, size: 16, color: Color(0xFFFF6B4A)),
                    label: const Text(
                      'Случайный выбор',
                      style: TextStyle(
                        color: Color(0xFFFF6B4A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...sections,
          ]),
        ),
      );
    }

    // Холодный старт: показываем открытую подборку из доступного каталога + кнопку случайного выбора
    final fallbackPool = state.titles.take(16).toList();
    return SliverPadding(
      key: const ValueKey('catalog_open_for_you_view'),
      padding: EdgeInsets.symmetric(horizontal: gridHorizontalPad),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF131720),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF6B4A), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Добавьте пару аниме в списки — здесь соберётся личная витрина под ваш вкус.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _launchRandomChoice(fallbackPool),
                  child: const Text(
                    'Случайное',
                    style: TextStyle(
                      color: Color(0xFFFF6B4A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: gridDelegate,
            itemCount: fallbackPool.length,
            itemBuilder: (context, index) {
              final title = fallbackPool[index];
              return AnimePosterCard(
                key: ValueKey('for_you_starter_${title.id}'),
                title: title,
                isCompact: !isDesktop && screenWidth < 600 && mobileCols == 3,
                userListStatus: userListsMap[title.id],
                onTap: () => _openAnimeDetails(title),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildSliverLoadingGrid(
    double horizontalPad, {
    required bool isListMode,
    required double screenWidth,
  }) {
    final bool isTestEnv = Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');
    final bool isDesktopOS = !isTestEnv && !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
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

    final gridHorizontalPad = screenWidth < 600 ? 14.0 : horizontalPad;
    final SliverGridDelegate gridDelegate = isDesktop
        ? const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 215,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.62,
          )
        : SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: screenWidth >= 600 ? 3 : 2,
            childAspectRatio: screenWidth >= 600 ? 0.64 : 0.56,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
          );

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: gridHorizontalPad),
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
        action: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
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

  Widget _buildEmptyState(BuildContext context, [CatalogLoaded? loadedState]) {
    final isSearch = loadedState != null && loadedState.searchQuery.trim().isNotEmpty;
    return Center(
      child: SyncPaiMascot(
        state: MascotState.emptySearch,
        message: isSearch ? 'По запросу ничего не найдено' : 'Ничего не найдено',
        description: isSearch
            ? 'Попробуйте другое название или проверьте раскладку'
            : 'Попробуйте изменить поисковый запрос или сбросить фильтры',
        action: OutlinedButton.icon(
          key: const ValueKey('catalog_empty_reset_btn'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Theme.of(context).colorScheme.primary),
            foregroundColor: AppColors.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            if (_searchController.text.isNotEmpty) {
              _searchController.clear();
            }
            if (_isSearchOpen) {
              setState(() => _isSearchOpen = false);
            }
            if (isSearch) {
              context.read<CatalogCubit>().onSearchQueryChanged('');
            } else {
              context.read<CatalogCubit>().resetAllFilters();
            }
          },
          icon: Icon(
            isSearch ? Icons.search_off_rounded : Icons.filter_alt_off_rounded,
            size: 16,
          ),
          label: Text(
            isSearch ? 'Сбросить поиск' : 'Сбросить фильтры',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
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
