import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_dimensions.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/auth_gate_sheet.dart';
import 'package:sync_pai/core/widgets/glass_container.dart';
import 'package:sync_pai/core/widgets/shimmer_placeholder.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_state.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_state.dart';
import 'package:sync_pai/features/catalog/data/services/anime_meta_enrichment_service.dart';
import 'package:sync_pai/features/catalog/domain/services/recommendation_engine.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/for_you_recommendations_shelf.dart';
import 'package:sync_pai/features/watch_history/domain/entities/watch_history_item.dart';
import 'package:sync_pai/features/anime_details/data/datasources/anime_reviews_provider.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_rating_aggregate.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_review.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_video_item.dart';
import 'package:sync_pai/features/anime_details/domain/entities/related_anime_release.dart';
import 'package:sync_pai/features/anime_details/domain/entities/score_distribution_item.dart';
import 'package:sync_pai/features/anime_details/domain/entities/user_lists_stats.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/anime_media_info_section.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/anime_reviews_section.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/episode_quality_sheet.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/related_releases_section.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/resume_progress_card.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/user_lists_distribution_widget.dart';
import 'package:sync_pai/features/sync_room/presentation/widgets/floating_room_overlay.dart';
import 'package:sync_pai/features/sync_room/presentation/widgets/sync_room_config_sheet.dart';
import 'package:sync_pai/features/sync_room/services/active_room_service.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_player_links_usecase.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/downloads/domain/repositories/download_repository.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_state.dart';
import 'package:sync_pai/core/widgets/tv_focusable.dart';
import 'package:sync_pai/features/downloads/domain/entities/download_task.dart';
import 'package:sync_pai/features/downloads/presentation/cubit/download_cubit.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/shared/widgets/compact_episode_grid.dart';
import 'package:sync_pai/features/downloads/presentation/cubit/download_state.dart';
import 'package:sync_pai/features/torrents/domain/entities/torrent_release.dart';
import 'package:sync_pai/features/torrents/domain/repositories/torrent_repository.dart';
import 'package:sync_pai/features/torrents/data/repositories/torrent_repository_impl.dart';
import 'package:sync_pai/features/torrents/presentation/widgets/torrent_releases_sheet.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_cubit.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_state.dart';
import 'package:sync_pai/features/kodik/presentation/widgets/voiceover_selector_sheet.dart';
import 'package:sync_pai/features/main/presentation/screens/main_screen.dart';
import 'package:sync_pai/features/manga/data/services/anime_manga_bridge_service.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';

/// In-Memory LRU кэш с 30-минутным TTL для мгновенного повторного открытия деталей аниме (0ms)
class CachedAnimeDetails {
  final AnimeTitle title;
  final List<AnimeReview>? reviews;
  final AnimeRatingAggregate? aggregate;
  final Map<String, double>? portalScores;
  final List<RelatedAnimeRelease>? relatedReleases;
  final List<AnimeVideoItem>? videos;
  final UserListsStats? userStats;
  final List<ScoreDistributionItem>? scoreDistribution;
  final DateTime cachedAt;

  const CachedAnimeDetails({
    required this.title,
    this.reviews,
    this.aggregate,
    this.portalScores,
    this.relatedReleases,
    this.videos,
    this.userStats,
    this.scoreDistribution,
    required this.cachedAt,
  });

  bool get isExpired => DateTime.now().difference(cachedAt).inMinutes >= 30;

  CachedAnimeDetails copyWith({
    AnimeTitle? title,
    List<AnimeReview>? reviews,
    AnimeRatingAggregate? aggregate,
    Map<String, double>? portalScores,
    List<RelatedAnimeRelease>? relatedReleases,
    List<AnimeVideoItem>? videos,
    UserListsStats? userStats,
    List<ScoreDistributionItem>? scoreDistribution,
    DateTime? cachedAt,
  }) {
    return CachedAnimeDetails(
      title: title ?? this.title,
      reviews: reviews ?? this.reviews,
      aggregate: aggregate ?? this.aggregate,
      portalScores: portalScores ?? this.portalScores,
      relatedReleases: relatedReleases ?? this.relatedReleases,
      videos: videos ?? this.videos,
      userStats: userStats ?? this.userStats,
      scoreDistribution: scoreDistribution ?? this.scoreDistribution,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }
}

class AnimeDetailsCache {
  static const int _maxEntries = 50;
  static final LinkedHashMap<int, CachedAnimeDetails> _lru = LinkedHashMap<int, CachedAnimeDetails>();

  static CachedAnimeDetails? get(int id) {
    if (id <= 0) return null;
    final entry = _lru.remove(id);
    if (entry == null) return null;
    if (entry.isExpired) return null;
    // Перемещаем в конец (MRU)
    _lru[id] = entry;
    return entry;
  }

  static void putTitle(AnimeTitle title) {
    if (title.id <= 0) return;
    final existing = _lru.remove(title.id);
    if (_lru.length >= _maxEntries) {
      _lru.remove(_lru.keys.first);
    }
    _lru[title.id] = (existing ?? CachedAnimeDetails(title: title, cachedAt: DateTime.now())).copyWith(
      title: title,
      cachedAt: DateTime.now(),
    );
  }

  static void putReviews({
    required int id,
    required AnimeTitle fallbackTitle,
    required List<AnimeReview> reviews,
    AnimeRatingAggregate? aggregate,
    Map<String, double>? portalScores,
    List<RelatedAnimeRelease>? relatedReleases,
    List<AnimeVideoItem>? videos,
    UserListsStats? userStats,
    List<ScoreDistributionItem>? scoreDistribution,
  }) {
    if (id <= 0) return;
    final existing = _lru.remove(id);
    if (_lru.length >= _maxEntries) {
      _lru.remove(_lru.keys.first);
    }
    _lru[id] = (existing ?? CachedAnimeDetails(title: fallbackTitle, cachedAt: DateTime.now())).copyWith(
      reviews: reviews,
      aggregate: aggregate,
      portalScores: portalScores,
      relatedReleases: relatedReleases,
      videos: videos,
      userStats: userStats,
      scoreDistribution: scoreDistribution,
      cachedAt: DateTime.now(),
    );
  }

  static void clear() => _lru.clear();
}

/// Детальный экран аниме в премиальном стиле Cinematic Dark / Nordic Dark.
///
/// 1. Cinematic Backdrop на 44% высоты экрана с бесшовным растворением в фон.
/// 2. Крупный заголовок, год и жанры через точку без серых плашек.
/// 3. Акцентная главная кнопка «Смотреть» + матовые круглые glass-кнопки действий.
/// 4. Карточка продолжения просмотра (ResumeProgressCard) с точным прогрессом.
/// 5. Вкладки «Серии», «Инфо & Трейлер» и «Отзывы» с оценками порталов (Shikimori/MAL/AniLibria).
class AnimeDetailsScreen extends StatefulWidget {
  final AnimeTitle title;
  final bool scrollToSimilar;
  final void Function(AnimeTitle title, EpisodeItem episode, PlayerQuality quality)? onPlayEpisode;
  final void Function(AnimeTitle title, EpisodeItem episode, PlayerQuality quality, Duration position)? onResumeEpisode;
  final void Function(AnimeTitle title, EpisodeItem episode)? onStartSyncRoom;

  const AnimeDetailsScreen({
    super.key,
    required this.title,
    this.scrollToSimilar = false,
    this.onPlayEpisode,
    this.onResumeEpisode,
    this.onStartSyncRoom,
  });

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> with SingleTickerProviderStateMixin {
  late AnimeTitle _currentTitle;
  int _selectedEpisodeIndex = 0;
  int _currentTabIndex = 0; // 0: Серии, 1: Инфо & Трейлер, 2: Отзывы
  late final TabController _tabController;
  late List<AnimeReview> _reviews;
  AnimeRatingAggregate? _aggregate;
  Map<String, double>? _portalScores;
  List<RelatedAnimeRelease> _relatedReleases = [];
  List<AnimeVideoItem> _videos = [];
  UserListsStats _userStats = const UserListsStats();
  List<ScoreDistributionItem> _scoreDistribution = [];
  bool _isLoadingReviews = false;
  bool _isDescriptionExpanded = false;
  bool _isLoadingDetails = false;
  bool _isOpeningEpisode = false;
  bool _isStartingWatchTogether = false;
  bool _isOpeningManga = false;
  bool _isAnimeOriginalConfirmed = false;
  late final ScrollController _scrollController;
  final GlobalKey _similarSectionKey = GlobalKey();
  bool _showAppBarTitle = false;
  AnimeMangaBridge? _mangaBridge;
  List<AnimeTitle> _shikimoriSimilar = const [];
  bool? _manualCompactEpisodeGrid;
  int? _selectedEpisodeRangeIndex;

  @override
  void initState() {
    super.initState();
    CatalogCubit.pushForegroundScreen();
    final cached = AnimeDetailsCache.get(widget.title.id);
    if (cached != null) {
      _currentTitle = cached.title.episodes.isNotEmpty
          ? widget.title.copyWith(
              episodes: cached.title.episodes,
              episodesTotal: cached.title.episodesTotal ?? widget.title.episodesTotal,
              description: widget.title.description.isNotEmpty
                  ? widget.title.description
                  : cached.title.description,
              genres: widget.title.genres.isNotEmpty
                  ? widget.title.genres
                  : cached.title.genres,
              year: widget.title.year ?? cached.title.year,
            )
          : widget.title;
      _reviews = cached.reviews ?? AnimeReviewsProvider.getReviewsForTitle(_currentTitle);
      _aggregate = cached.aggregate;
      _portalScores = cached.portalScores;
      final rawRelated = (cached.relatedReleases ?? [])
          .where((r) => !r.id.startsWith('rel_'))
          .toList();
      _relatedReleases = rawRelated.where((r) => !r.isCurrent).isNotEmpty
          ? rawRelated
          : [];
      _videos = cached.videos ?? [];
      _userStats = cached.userStats ?? const UserListsStats();
      _scoreDistribution = cached.scoreDistribution ?? [];
    } else {
      _currentTitle = widget.title;
      _reviews = AnimeReviewsProvider.getReviewsForTitle(widget.title);
    }

    _scrollController = ScrollController()..addListener(_handleScroll);
    if (widget.scrollToSimilar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 220), () {
          if (!mounted) return;
          final targetCtx = _similarSectionKey.currentContext;
          if (targetCtx != null && targetCtx.mounted) {
            Scrollable.ensureVisible(
              targetCtx,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
            );
          }
        });
      });
    }
    _resolveMangaBridge();
    _loadShikimoriSimilar();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index != _currentTabIndex) {
        setState(() => _currentTabIndex = _tabController.index);
      }
    });

    // Декаплинг параллельной загрузки (SWR + независимые стримы без блокирующего Future.wait)
    if (_currentTitle.episodes.length <= 1) {
      unawaited(_loadFullDetails(silent: cached != null));
    } else if (cached != null && DateTime.now().difference(cached.cachedAt).inMinutes >= 5) {
      // Тихая фоновая ревалидация кэшированных серий (SWR)
      unawaited(_loadFullDetails(silent: true));
    }

    if (cached?.reviews == null) {
      unawaited(_loadShikimoriReviews());
    } else if (DateTime.now().difference(cached!.cachedAt).inMinutes >= 5) {
      // Тихая фоновая ревалидация метаданных/отзывов (SWR)
      unawaited(_loadShikimoriReviews(silent: true));
    }

    unawaited(() async {
      final enriched = await AnimeMetaEnrichmentService.instance.enrichSingle(_currentTitle);
      if (mounted &&
          (enriched.posterOriginal != _currentTitle.posterOriginal ||
              enriched.score != _currentTitle.score)) {
        setState(() => _currentTitle = enriched);
      }
    }());

    if (getIt.isRegistered<KodikCubit>()) {
      unawaited(
        getIt<KodikCubit>().loadVoiceovers(
          shikimoriId: _currentTitle.shikimoriId,
          title: _currentTitle.displayTitle,
        ),
      );
    }
  }

  void _openCatalogWithGenre(String genre) {
    final cleanGenre = genre.trim();
    if (cleanGenre.isEmpty) return;
    HapticFeedback.selectionClick();
    CatalogCubit? cubit;
    if (getIt.isRegistered<CatalogCubit>()) {
      cubit = getIt<CatalogCubit>();
    } else {
      try {
        cubit = context.read<CatalogCubit>();
      } catch (_) {}
    }
    cubit?.applyFilterSheet(
      genres: {cleanGenre},
      sortBy: CatalogSort.updates,
      matchAll: false,
      statusFilter: null,
      typeFilter: null,
    );
    MainScreen.switchToTab(0);
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      try {
        GoRouter.of(context).go('/');
      } catch (_) {}
    }
  }

  String? _formatTitleType(String? rawKind) {
    final clean = (rawKind ?? '').trim();
    if (clean.isEmpty) return null;
    switch (clean.toLowerCase()) {
      case 'tv':
      case 'tv_series':
        return 'ТВ';
      case 'movie':
      case 'full':
        return 'Фильм';
      case 'ova':
        return 'OVA';
      case 'ona':
        return 'ONA';
      case 'special':
        return 'Спешл';
      default:
        return clean;
    }
  }

  Widget _buildMetadataRow(
    BuildContext context,
    AnimeTitle title, {
    bool compact = false,
    bool withShadows = false,
  }) {
    final typeLabel = _formatTitleType(title.kind);
    final scoreValue = (title.score != null && title.score! > 0)
        ? title.score!
        : (_aggregate?.shikimoriScore ??
            _aggregate?.syncpaiScore ??
            _aggregate?.malScore);

    final shadows = withShadows
        ? const [
            Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 1)),
          ]
        : null;

    final metaStyle = AppTypography.labelMedium.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w500,
      fontSize: compact ? 12.0 : 13.0,
      shadows: shadows,
    );

    final dot = Text(
      '•',
      style: TextStyle(color: AppColors.textMuted, shadows: shadows),
    );

    final parts = <Widget>[];
    if (title.status.isNotEmpty) {
      parts.add(
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 9,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title.status,
            style: AppTypography.badge.copyWith(
              color: AppColors.primaryLight,
              fontSize: compact ? 10.5 : 11.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final textTokens = <String>[
      if (title.year != null) '${title.year}',
      if (typeLabel != null) typeLabel,
      if (title.episodesBadgeText.isNotEmpty) title.episodesBadgeText,
    ];

    for (var i = 0; i < textTokens.length; i++) {
      if (parts.isNotEmpty) parts.add(dot);
      parts.add(Text(textTokens[i], style: metaStyle));
    }

    if (scoreValue != null) {
      if (parts.isNotEmpty) parts.add(dot);
      parts.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              color: const Color(0xFFFFC107),
              size: compact ? 14 : 15,
            ),
            const SizedBox(width: 3),
            Text(
              scoreValue.toStringAsFixed(1),
              style: metaStyle.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: parts,
    );
  }

  Widget _buildGenrePills(BuildContext context, AnimeTitle title) {
    final genres = title.genres.map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
    if (genres.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: genres.map((genre) {
        return Material(
          color: const Color(0xFF191F2B),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: ValueKey('details_genre_pill_$genre'),
            onTap: () => _openCatalogWithGenre(genre),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                genre,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary.withValues(alpha: 0.92),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExpandableSynopsis(BuildContext context, String description) {
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      height: 1.55,
      fontSize: 13.5,
      color: AppColors.textSecondary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: description, style: bodyStyle),
          maxLines: 4,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth > 0 ? constraints.maxWidth : 300);

        final needsToggle = painter.didExceedMaxLines || _isDescriptionExpanded;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: needsToggle
                  ? () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded)
                  : null,
              child: Text(
                description,
                maxLines: _isDescriptionExpanded ? null : 4,
                overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: bodyStyle,
              ),
            ),
            if (needsToggle) ...[
              const SizedBox(height: 6),
              InkWell(
                key: const ValueKey('details_synopsis_toggle'),
                onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    _isDescriptionExpanded ? 'Свернуть' : 'Развернуть описание',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _loadShikimoriReviews({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoadingReviews = true);
    }
    try {
      final shikiSource = getIt.isRegistered<ShikimoriRemoteDataSource>()
          ? getIt<ShikimoriRemoteDataSource>()
          : ShikimoriRemoteDataSourceImpl();
      final result = await shikiSource
          .getReviewsAndRatings(_currentTitle)
          .timeout(const Duration(seconds: 8));
      AnimeDetailsCache.putReviews(
        id: _currentTitle.id,
        fallbackTitle: _currentTitle,
        reviews: result.reviews,
        aggregate: result.aggregate,
        portalScores: result.portalScores,
        relatedReleases: result.relatedReleases,
        videos: result.videos,
        userStats: result.userStats,
        scoreDistribution: result.scoreDistribution,
      );
      if (mounted) {
        setState(() {
          if (_currentTitle.genres.isEmpty && result.genres.isNotEmpty) {
            _currentTitle = _currentTitle.copyWith(genres: result.genres);
            AnimeDetailsCache.putTitle(_currentTitle);
          }
          _reviews = result.reviews;
          _aggregate = result.aggregate;
          _portalScores = result.portalScores;
          _relatedReleases = result.relatedReleases
              .where((r) => !r.id.startsWith('rel_'))
              .toList();
          if (_relatedReleases.where((r) => !r.isCurrent).isEmpty) {
            _relatedReleases = const [];
          }
          _videos = result.videos;
          _userStats = result.userStats;
          _scoreDistribution = result.scoreDistribution;
          _isLoadingReviews = false;
        });
        if (getIt.isRegistered<KodikCubit>()) {
          getIt<KodikCubit>().loadVoiceovers(
            shikimoriId: result.shikimoriId ?? _currentTitle.shikimoriId,
            title: _currentTitle.displayTitle,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingReviews = false);
      }
    }
  }

  int? _extractSeasonNumber(String s) {
    final lower = s.toLowerCase();
    if (lower.contains('второй') || lower.contains('2 сезон') || lower.contains('тв-2') || lower.contains('tv-2') || lower.contains('2nd') || lower.contains('season 2') || RegExp(r'\b2\b').hasMatch(lower) || RegExp(r'\bii\b').hasMatch(lower)) return 2;
    if (lower.contains('третий') || lower.contains('3 сезон') || lower.contains('тв-3') || lower.contains('tv-3') || lower.contains('3rd') || lower.contains('season 3') || RegExp(r'\b3\b').hasMatch(lower) || RegExp(r'\biii\b').hasMatch(lower)) return 3;
    if (lower.contains('четвертый') || lower.contains('четвёртый') || lower.contains('4 сезон') || lower.contains('тв-4') || lower.contains('tv-4') || lower.contains('4th') || lower.contains('season 4') || RegExp(r'\b4\b').hasMatch(lower) || RegExp(r'\biv\b').hasMatch(lower)) return 4;
    if (lower.contains('пятый') || lower.contains('5 сезон') || lower.contains('тв-5') || lower.contains('5th') || lower.contains('season 5') || RegExp(r'\b5\b').hasMatch(lower)) return 5;
    if (lower.contains('фильм') || lower.contains('movie')) return 100;
    return null;
  }

  Future<void> _loadShikimoriSimilar() async {
    if (!getIt.isRegistered<ShikimoriRemoteDataSource>()) return;
    try {
      final ds = getIt<ShikimoriRemoteDataSource>();
      final shikiId = _currentTitle.shikimoriId ??
          await ds.resolveShikimoriId(_currentTitle);
      if (!mounted || shikiId == null || shikiId <= 0) return;
      final similar = await ds.getSimilarAnimes(shikiId);
      if (mounted && similar.isNotEmpty) {
        setState(() => _shikimoriSimilar = similar);
      }
    } catch (_) {}
  }

  Future<void> _resolveMangaBridge() async {
    final memCached = AnimeMangaBridgeService.instance.getCached(_currentTitle.id);
    if (memCached != null) {
      if (mounted) setState(() => _mangaBridge = memCached);
      return;
    }
    if (AnimeMangaBridgeService.instance.isConfirmedOriginal(_currentTitle.id)) {
      if (mounted) setState(() => _isAnimeOriginalConfirmed = true);
      return;
    }
    final prefsCached =
        await AnimeMangaBridgeService.instance.getCachedFromPrefs(_currentTitle.id);
    if (prefsCached != null && mounted) {
      setState(() => _mangaBridge = prefsCached);
    }
  }

  Future<void> _handleReadMangaTap(AnimeTitle title) async {
    if (_isOpeningManga) return;
    if (_mangaBridge != null) {
      _openMangaReader(_mangaBridge!);
      return;
    }

    setState(() => _isOpeningManga = true);
    final resolved = await AnimeMangaBridgeService.instance.resolveForAnime(
      title,
      onChapterOffsetUpdated: (updated) {
        if (mounted) setState(() => _mangaBridge = updated);
      },
    );
    if (!mounted) return;
    setState(() => _isOpeningManga = false);
    if (resolved != null) {
      setState(() => _mangaBridge = resolved);
      _openMangaReader(resolved);
      return;
    }

    if (AnimeMangaBridgeService.instance.isConfirmedOriginal(title.id)) {
      setState(() => _isAnimeOriginalConfirmed = true);
      MascotCompanionService.instance.notifyAnimeOriginalNoManga();
      return;
    }

    final ds = getIt.isRegistered<MangaDexDataSource>()
        ? getIt<MangaDexDataSource>()
        : MangaDexDataSource();
    final query = title.englishTitle.trim().isNotEmpty
        ? title.englishTitle.trim()
        : title.russianTitle.trim();
    final matches = await ds
        .searchManga(query, limit: 10)
        .timeout(const Duration(seconds: 4), onTimeout: () => const []);
    if (!mounted) return;
    if (matches.isNotEmpty) {
      context.pushNamed(
        'manga_details',
        pathParameters: {'id': matches.first.id},
        extra: matches.first,
      );
    } else {
      MascotCompanionService.instance.notifyAnimeOriginalNoManga();
    }
  }

  void _openMangaReader(AnimeMangaBridge bridge) {
    HapticFeedback.lightImpact();
    context.pushNamed('manga_reader', extra: {
      'bridge': bridge,
      'initialChapter': bridge.continueFromChapter,
    });
  }

  void _onRelatedReleaseSelected(RelatedAnimeRelease release) async {
    if (release.isCurrent) return;

    if (release.resolvedTitle != null) {
      context.pushNamed('details', extra: release.resolvedTitle);
      return;
    }

    // Попытка найти реальный тайтл на AniLibria через поиск
    try {
      final catalogRepo = getIt.isRegistered<CatalogRepository>() ? getIt<CatalogRepository>() : null;
      if (catalogRepo != null) {
        var searchResults = await catalogRepo.searchTitles(release.title, limit: 10);
        if (searchResults.isEmpty && release.originalTitle != null && release.originalTitle!.isNotEmpty) {
          searchResults = await catalogRepo.searchTitles(release.originalTitle!, limit: 10);
        }

        if (searchResults.isNotEmpty) {
          final targetSeason = _extractSeasonNumber(release.title) ??
              (release.originalTitle != null ? _extractSeasonNumber(release.originalTitle!) : null);

          // Исключаем текущий тайтл, чтобы старый сезон не открывался при клике на новый
          final candidates = searchResults.where((s) => s.id != _currentTitle.id).toList();

          AnimeTitle? matched;
          if (candidates.isNotEmpty) {
            if (targetSeason != null) {
              try {
                matched = candidates.where(
                  (s) =>
                      _extractSeasonNumber(s.russianTitle) == targetSeason ||
                      _extractSeasonNumber(s.englishTitle) == targetSeason,
                ).firstOrNull;
              } catch (_) {}
            }

            matched ??= candidates.where(
              (s) =>
                  s.russianTitle.toLowerCase().trim() == release.title.toLowerCase().trim() ||
                  (release.originalTitle != null &&
                      s.englishTitle.toLowerCase().trim() == release.originalTitle!.toLowerCase().trim()),
            ).firstOrNull;
          }

          if (matched != null && mounted) {
            final enrichedMatch = (matched.genres.isEmpty && _currentTitle.genres.isNotEmpty)
                ? matched.copyWith(genres: _currentTitle.genres)
                : matched;
            context.pushNamed('details', extra: enrichedMatch);
            return;
          }
        }
      }
    } catch (_) {}

    // Fallback: тайтл еще не вышел или отсутствует в базе — статус «Скоро» без ложных старых серий
    final yearNum = int.tryParse(release.year?.replaceAll(RegExp(r'\D'), '') ?? '');
    final fallbackTitle = AnimeTitle(
      id: int.tryParse(release.id) ?? (DateTime.now().millisecondsSinceEpoch % 100000),
      code: release.title.toLowerCase().replaceAll(' ', '-'),
      russianTitle: release.title,
      englishTitle: release.originalTitle ?? release.title,
      posterSmall: release.posterUrl,
      posterMedium: release.posterUrl,
      posterOriginal: release.posterUrl,
      genres: _currentTitle.genres,
      description: 'Продолжение франшизы ${_currentTitle.displayTitle}. Релиз ожидается.',
      status: 'Скоро',
      year: yearNum ?? _currentTitle.year,
      episodes: const [],
      episodesTotal: 0,
    );
    if (mounted) {
      context.pushNamed('details', extra: fallbackTitle);
    }
  }

  void _handleScroll() {
    final threshold = MediaQuery.sizeOf(context).height * 0.30;
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > threshold;
      if (shouldShow != _showAppBarTitle) {
        setState(() => _showAppBarTitle = shouldShow);
      }
    }
  }

  @override
  void dispose() {
    CatalogCubit.popForegroundScreen();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSecondaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color iconColor = AppColors.textPrimary,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 46,
                height: 46,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              GlassIconButton(
                icon: icon,
                size: 46,
                iconSize: 20,
                iconColor: iconColor,
                onTap: onTap,
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: 78,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color iconColor = AppColors.textPrimary,
    bool isLoading = false,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTorrentsSheet(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Поиск торрент-раздач и BDRip 1080p...'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final TorrentRepository repo = getIt.isRegistered<TorrentRepository>()
          ? getIt<TorrentRepository>()
          : TorrentRepositoryImpl();
      final releases = await repo.getTorrentsForTitle(
        titleId: _currentTitle.id,
        titleCode: _currentTitle.code,
        titleRu: _currentTitle.russianTitle,
      );

      if (context.mounted) {
        TorrentReleasesSheet.show(
          context,
          releases: releases,
          animeTitle: _currentTitle.displayTitle,
          onPlayTorrent: (TorrentRelease release, String streamUrl) {
            final dummyEpisode = EpisodeItem(
              episode: 1,
              name: release.series,
              fhdUrl: streamUrl,
              hdUrl: streamUrl,
              sdUrl: streamUrl,
            );
            widget.onPlayEpisode?.call(_currentTitle, dummyEpisode, PlayerQuality.fhd);
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Ошибка поиска торрентов: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showDeleteDownloadDialog(BuildContext context, AnimeTitle title, EpisodeItem ep) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Удалить скачанную серию?',
          style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Серия ${ep.episode} «${ep.name ?? title.displayTitle}» будет удалена из памяти устройства.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.syncError,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              final taskId = DownloadTask.generateId(title.id, ep.episode);
              if (getIt.isRegistered<DownloadCubit>()) {
                getIt<DownloadCubit>().deleteDownload(taskId);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Серия удалена из памяти устройства'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFullDetails({bool silent = false}) async {
    if (!silent && _currentTitle.episodes.length <= 1) {
      setState(() => _isLoadingDetails = true);
    }
    final releaseId = _currentTitle.id;
    final titleRu = _currentTitle.russianTitle;
    final titleEn = _currentTitle.englishTitle;
    final rawDisplayTitle = titleRu.isNotEmpty ? titleRu : titleEn;
    final displayTitle = rawDisplayTitle.startsWith('search:')
        ? rawDisplayTitle.substring('search:'.length).trim()
        : rawDisplayTitle;
    final isExternalSourceId = _currentTitle.code.startsWith('search:') ||
        _currentTitle.code.startsWith('shikimori_') ||
        (_currentTitle.shikimoriId != null &&
            _currentTitle.shikimoriId == releaseId);
    final playerReleaseId = isExternalSourceId ? 0 : releaseId;

    // 1. Независимая быстрая загрузка серий/потоков AniLibria (не ждёт метаданные)
    if (getIt.isRegistered<GetPlayerLinksUseCase>()) {
      unawaited(Future<void>(() async {
        try {
          final translations = await getIt<GetPlayerLinksUseCase>().call(
            playerReleaseId,
            title: displayTitle,
          );
          if (translations.isNotEmpty) {
            final direct = translations.where((t) => t.isDirectStream && t.episodes.isNotEmpty);
            if (direct.isNotEmpty) {
              final eps = direct.first.episodes.map((e) => e.toEpisodeItem()).toList();
              if (eps.isNotEmpty) {
                final updated = _currentTitle.copyWith(
                  episodes: eps,
                  episodesTotal: eps.length,
                );
                AnimeDetailsCache.putTitle(updated);
                if (mounted) {
                  setState(() {
                    _currentTitle = updated;
                    _isLoadingDetails = false;
                  });
                }
                return;
              }
            }
          }
        } catch (_) {}
        if (mounted && _isLoadingDetails) {
          setState(() => _isLoadingDetails = false);
        }
      }));
    }

    // 2. Независимая подгрузка метаданных/запасного списка серий (не блокирует AniLibria)
    final needsMetadata = _currentTitle.description.isEmpty ||
        _currentTitle.genres.isEmpty ||
        _currentTitle.episodes.length <= 1;
    if (needsMetadata && getIt.isRegistered<CatalogRepository>()) {
      unawaited(Future<void>(() async {
        try {
          var fetchedDetails = await getIt<CatalogRepository>().getTitleDetails(
            id: releaseId,
            code: _currentTitle.code,
          );
          if (fetchedDetails.genres.isEmpty &&
              _currentTitle.genres.isEmpty &&
              displayTitle.isNotEmpty) {
            try {
              final hits = await getIt<CatalogRepository>().searchTitles(
                displayTitle,
                limit: 3,
              );
              if (hits.isNotEmpty) {
                final best = hits.firstWhere(
                  (h) => h.genres.isNotEmpty,
                  orElse: () => hits.first,
                );
                if (best.genres.isNotEmpty) {
                  fetchedDetails = fetchedDetails.copyWith(
                    genres: best.genres,
                    description: fetchedDetails.description.isNotEmpty
                        ? fetchedDetails.description
                        : best.description,
                  );
                }
              }
            } catch (_) {}
          }
          final resolvedEpisodes = _currentTitle.episodes.length > 1
              ? _currentTitle.episodes
              : (fetchedDetails.episodes.isNotEmpty
                  ? fetchedDetails.episodes
                  : _currentTitle.episodes);
          final updatedTitle = _currentTitle.copyWith(
            episodes: resolvedEpisodes,
            episodesTotal: resolvedEpisodes.isNotEmpty
                ? resolvedEpisodes.length
                : (_currentTitle.episodesTotal ?? fetchedDetails.episodesTotal),
            description: _currentTitle.description.isNotEmpty
                ? _currentTitle.description
                : fetchedDetails.description,
            genres: _currentTitle.genres.isNotEmpty
                ? _currentTitle.genres
                : fetchedDetails.genres,
            year: _currentTitle.year ?? fetchedDetails.year,
          );
          AnimeDetailsCache.putTitle(updatedTitle);
          if (mounted) {
            setState(() {
              _isLoadingDetails = false;
              _currentTitle = updatedTitle;
            });
          }
        } catch (_) {
          if (mounted && _isLoadingDetails) {
            setState(() => _isLoadingDetails = false);
          }
        }
      }));
    } else if (!getIt.isRegistered<GetPlayerLinksUseCase>() && mounted && _isLoadingDetails) {
      setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _requestPlayEpisode(EpisodeItem episode, [Duration? initialPosition]) async {
    if (_isOpeningEpisode) return;
    _isOpeningEpisode = true;
    try {
      SharedPreferences? prefs;
    if (getIt.isRegistered<SharedPreferences>()) {
      prefs = getIt<SharedPreferences>();
    }
    final savedQuality = prefs?.getString('preferred_player_quality');
    final defaultQuality = PlayerQuality.values.firstWhere(
      (q) => q.name == savedQuality,
      orElse: () => PlayerQuality.fhd,
    );

    Duration? effectiveInitialPosition = initialPosition;
    if (effectiveInitialPosition == null) {
      if (getIt.isRegistered<WatchHistoryCubit>()) {
        final histState = getIt<WatchHistoryCubit>().state;
        var history = histState.getForTitle(_currentTitle.id);
        if (history == null &&
            _currentTitle.shikimoriId != null &&
            _currentTitle.shikimoriId! > 0) {
          history = histState.getForTitle(_currentTitle.shikimoriId!);
        }
        if (history != null && history.episode == episode.episode && history.positionMs > 2000) {
          effectiveInitialPosition = Duration(milliseconds: history.positionMs);
        }
      }
      if (effectiveInitialPosition == null && getIt.isRegistered<AnimeListCubit>()) {
        final listState = getIt<AnimeListCubit>().state;
        var entry = listState.getEntryFor(_currentTitle.id);
        if (entry == null &&
            _currentTitle.shikimoriId != null &&
            _currentTitle.shikimoriId! > 0) {
          entry = listState.getEntryFor(_currentTitle.shikimoriId!);
        }
        if (entry != null && entry.lastEpisode == episode.episode && entry.positionMs > 2000) {
          effectiveInitialPosition = Duration(milliseconds: entry.positionMs);
        }
      }
    }

    if (getIt.isRegistered<AnimeListCubit>()) {
      try {
        final listCubit = getIt<AnimeListCubit>();
        final existing = listCubit.state.getEntryFor(_currentTitle.id);
        if (existing != null) {
          listCubit.setAnimeStatus(
            animeId: _currentTitle.id,
            titleRu: _currentTitle.displayTitle,
            posterUrl: _currentTitle.posterMedium.isNotEmpty
                ? _currentTitle.posterMedium
                : _currentTitle.posterSmall,
            status: existing.status,
            lastEpisode: episode.episode,
            positionMs: effectiveInitialPosition?.inMilliseconds ?? existing.positionMs,
            episodesTotal: _currentTitle.episodesTotal,
          );
        }
      } catch (_) {}
    }

    EpisodeItem targetEpisode = episode;
    if (getIt.isRegistered<KodikCubit>()) {
      final kodikCubit = getIt<KodikCubit>();
      if (!kodikCubit.state.isAniLibriaActive) {
        final streamUrl = await kodikCubit.getStreamForEpisode(episode.episode);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          targetEpisode = EpisodeItem(
            episode: episode.episode,
            name: episode.name != null
                ? '${episode.name} • ${kodikCubit.state.activeVoiceoverTitle}'
                : 'Серия ${episode.episode} (${kodikCubit.state.activeVoiceoverTitle})',
            fhdUrl: streamUrl,
            hdUrl: streamUrl,
            sdUrl: streamUrl,
            previewUrl: episode.previewUrl,
            opening: episode.opening,
            ending: episode.ending,
          );
        } else if (targetEpisode.bestAvailableUrl == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Озвучка «${kodikCubit.state.activeVoiceoverTitle}» временно недоступна для серии ${episode.episode}. Попробуйте AniLibria или другую студию.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }
    }

    final isDownloaded = getIt.isRegistered<DownloadRepository>() &&
        getIt<DownloadRepository>().isDownloaded(_currentTitle.id, targetEpisode.episode);

    if (targetEpisode.bestAvailableUrl == null && !isDownloaded) {
      // Пытаемся получить полные серии через Supabase Edge Function get_anime_player_data (BFF)
      if (getIt.isRegistered<GetPlayerLinksUseCase>()) {
        try {
          final translations = await getIt<GetPlayerLinksUseCase>().call(
            _currentTitle.id,
            title: _currentTitle.displayTitle,
          );
          if (translations.isNotEmpty) {
            final direct = translations.where((t) => t.isDirectStream && t.episodes.isNotEmpty);
            if (direct.isNotEmpty) {
              final directEpisodes = direct.first.episodes
                  .map((e) => e.toEpisodeItem())
                  .toList();
              final updatedTitle = _currentTitle.copyWith(episodes: directEpisodes);
              _currentTitle = updatedTitle;
              targetEpisode = directEpisodes.firstWhere(
                (e) => e.episode == episode.episode,
                orElse: () => directEpisodes.first,
              );
            }
          }
        } catch (_) {}
      }
    }

    if (targetEpisode.bestAvailableUrl == null && !isDownloaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Видеопоток для этой серии пока не готов. Выберите другую серию или студию озвучки.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (effectiveInitialPosition != null && effectiveInitialPosition > Duration.zero) {
      if (widget.onResumeEpisode != null) {
        widget.onResumeEpisode!.call(_currentTitle, targetEpisode, defaultQuality, effectiveInitialPosition);
        return;
      }
    }

    if (!mounted) return;

    final chosenQuality = await EpisodeQualitySheet.show(
      context,
      title: _currentTitle,
      episode: targetEpisode,
      initialQuality: defaultQuality,
    );

    if (chosenQuality != null && mounted) {
      prefs?.setString('preferred_player_quality', chosenQuality.name);
      if (effectiveInitialPosition != null && effectiveInitialPosition > Duration.zero && widget.onResumeEpisode != null) {
        widget.onResumeEpisode!.call(_currentTitle, targetEpisode, chosenQuality, effectiveInitialPosition);
      } else {
        widget.onPlayEpisode?.call(_currentTitle, targetEpisode, chosenQuality);
      }
    }
    } finally {
      _isOpeningEpisode = false;
    }
  }

  void _showAnimeStatusSheet(BuildContext context, AnimeTitle title, UserAnimeEntry? currentEntry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: 16),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.strokeMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Добавить в список',
                style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              ...AnimeListStatus.values.map((status) {
                final isSelected = currentEntry?.status == status;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(status.icon, color: status.color, size: 18),
                  ),
                  title: Text(
                    status.labelRu,
                    style: TextStyle(
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                      : null,
                  onTap: () {
                    context.read<AnimeListCubit>().setAnimeStatus(
                          animeId: title.id,
                          titleRu: title.russianTitle,
                          posterUrl: title.posterMedium.isNotEmpty ? title.posterMedium : title.posterSmall,
                          status: status,
                          episodesTotal: title.episodesTotal,
                          isUserInitiated: true,
                        );
                    Navigator.pop(sheetContext);
                  },
                );
              }),
              if (currentEntry != null) ...[
                const Divider(color: AppColors.strokeMedium),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.syncError, size: 22),
                  title: const Text(
                    'Удалить из списков',
                    style: TextStyle(color: AppColors.syncError, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    context.read<AnimeListCubit>().removeAnime(title.id);
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ],
          ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildWatchButton(BuildContext context, EpisodeItem? currentEpisode, {double? width, double height = 48.0}) {
    final isAnons = (_currentTitle.isAnnounced && _currentTitle.episodes.isEmpty) ||
        _currentTitle.status.toLowerCase().contains('анонс') ||
        _currentTitle.status.toLowerCase().contains('скоро');

    if (isAnons) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF261D15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFFF9800).withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded, color: Color(0xFFFFB74D), size: 14),
                SizedBox(width: 6),
                Text(
                  'Ожидается выход',
                  style: TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: width,
            height: height,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF261D15),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFFF9800), width: 1.2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: const Icon(Icons.bookmark_add_rounded, color: Color(0xFFFFB74D), size: 20),
              label: const Text(
                'Добавить в «В планах»',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                if (getIt.isRegistered<AnimeListCubit>()) {
                  context.read<AnimeListCubit>().setAnimeStatus(
                    animeId: _currentTitle.id,
                    titleRu: _currentTitle.displayTitle,
                    posterUrl: _currentTitle.posterMedium.isNotEmpty
                        ? _currentTitle.posterMedium
                        : _currentTitle.posterSmall,
                    status: AnimeListStatus.planned,
                    isUserInitiated: true,
                  );
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Анонс добавлен в список «В планах»'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFFE06C53),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    final themePrimary = Theme.of(context).colorScheme.primary;
    final onThemePrimary = AppColors.onColor(themePrimary);

    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: () {
          if (currentEpisode != null) {
            _requestPlayEpisode(currentEpisode);
          } else {
            _requestPlayEpisode(const EpisodeItem(episode: 1));
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: themePrimary,
          foregroundColor: onThemePrimary,
          elevation: 3,
          shadowColor: themePrimary.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: themePrimary),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              size: 24,
              color: onThemePrimary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  currentEpisode != null && currentEpisode.episode > 1
                      ? 'Серия ${currentEpisode.episode} • Смотреть'
                      : 'Смотреть',
                  maxLines: 1,
                  style: AppTypography.labelLarge.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: onThemePrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleWatchTogetherTap(
    BuildContext context,
    AnimeTitle title,
    EpisodeItem? currentEpisode,
  ) async {
    final isUnreleased = title.episodes.isEmpty &&
        (title.status.toLowerCase().contains('анонс') ||
            (title.year != null && title.year! >= 2026));
    if (isUnreleased) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ожидается выход — совместный просмотр станет доступен после релиза'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is! Authenticated || authState.profile.isAnonymous) {
        await AuthGateSheet.show(context);
        return;
      }
    } catch (_) {}

    if (_isStartingWatchTogether) return;
    _isStartingWatchTogether = true;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _isStartingWatchTogether = false;
    });

    final ep = currentEpisode ?? const EpisodeItem(episode: 1, name: 'Серия 1');
    final roomService = ActiveRoomService.instance;

    if (roomService.hasActiveRoom) {
      await roomService.switchAnimeInActiveRoom(title, episode: ep);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '📺 В комнате ${roomService.formattedRoomCode} включено «${title.displayTitle}»!',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      roomService.expandRoom();
      return;
    }

    if (widget.onStartSyncRoom != null) {
      widget.onStartSyncRoom!(title, ep);
    } else {
      SyncRoomConfigSheet.show(
        context,
        title: title,
        episode: ep,
        onConfirm: ({
          required int maxPeers,
          required bool isHostControlOnly,
          required PlayerQuality quality,
          required String roomCode,
        }) {},
      );
    }
  }

  Widget _buildSecondaryActionsRow(
    BuildContext context,
    AnimeTitle title,
    EpisodeItem? currentEpisode,
    String backdropUrl, {
    bool isDesktop = false,
  }) {
    return ListenableBuilder(
      listenable: ActiveRoomService.instance,
      builder: (context, _) {
        final hasActiveRoom = ActiveRoomService.instance.hasActiveRoom;
        final watchTogetherLabel = hasActiveRoom
            ? 'В комнату ${ActiveRoomService.instance.formattedRoomCode}'
            : 'Вместе';
        final watchTogetherIcon = hasActiveRoom
            ? Icons.swap_horiz_rounded
            : Icons.group_outlined;

        if (isDesktop) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildDesktopActionButton(
                icon: watchTogetherIcon,
                iconColor: hasActiveRoom ? AppColors.syncActive : AppColors.textPrimary,
                label: watchTogetherLabel,
                onTap: () => _handleWatchTogetherTap(context, title, currentEpisode),
              ),
              _buildDesktopActionButton(
                icon: Icons.movie_outlined,
                label: 'Трейлеры',
                onTap: () {
                  context.pushNamed('anime-videos', extra: {
                    'title': _currentTitle.displayTitle,
                    'backdrop': backdropUrl,
                    'videos': _videos,
                  });
                },
              ),
              if (getIt.isRegistered<AnimeListCubit>())
                BlocBuilder<AnimeListCubit, AnimeListState>(
                  bloc: getIt<AnimeListCubit>(),
                  builder: (context, listState) {
                    final entry = listState.getEntryFor(title.id);
                    final isInList = entry != null;
                    return _buildDesktopActionButton(
                      icon: isInList ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      iconColor: isInList ? AppColors.primaryLight : AppColors.textPrimary,
                      label: isInList ? entry.status.labelRu : 'В закладки',
                      onTap: () => _showAnimeStatusSheet(context, title, entry),
                    );
                  },
                ),
              _buildDesktopActionButton(
                icon: Icons.cloud_download_outlined,
                label: 'Скачать',
                onTap: () => _openTorrentsSheet(context),
              ),
              if (_currentTitle.id > 0 && !_isAnimeOriginalConfirmed)
                _buildDesktopActionButton(
                  icon: Icons.menu_book_rounded,
                  iconColor: AppColors.primaryLight,
                  isLoading: _isOpeningManga,
                  label: _mangaBridge?.continueFromChapter != null
                      ? 'Читать мангу • ${_mangaBridge!.isEstimatedChapter ? '~' : ''}с ${_mangaBridge!.continueFromChapter} гл.'
                      : 'Читать мангу',
                  onTap: () => _handleReadMangaTap(title),
                ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _buildSecondaryActionButton(
                icon: watchTogetherIcon,
                iconColor: hasActiveRoom ? AppColors.syncActive : AppColors.textPrimary,
                label: hasActiveRoom ? 'В комнату' : 'Вместе',
                onTap: () => _handleWatchTogetherTap(context, title, currentEpisode),
              ),
            ),
            Expanded(
              child: _buildSecondaryActionButton(
                icon: Icons.movie_outlined,
                label: 'Трейлеры',
                onTap: () {
                  context.pushNamed('anime-videos', extra: {
                    'title': _currentTitle.displayTitle,
                    'backdrop': backdropUrl,
                    'videos': _videos,
                  });
                },
              ),
            ),
            if (_currentTitle.id > 0 && !_isAnimeOriginalConfirmed)
              Expanded(
                child: _buildSecondaryActionButton(
                  icon: Icons.menu_book_rounded,
                  iconColor: AppColors.primaryLight,
                  isLoading: _isOpeningManga,
                  label: _mangaBridge?.continueFromChapter != null
                      ? '${_mangaBridge!.isEstimatedChapter ? '~' : ''}с ${_mangaBridge!.continueFromChapter} гл.'
                      : 'Читать мангу',
                  onTap: () => _handleReadMangaTap(title),
                ),
              ),
            if (getIt.isRegistered<AnimeListCubit>())
              Expanded(
                child: BlocBuilder<AnimeListCubit, AnimeListState>(
                  bloc: getIt<AnimeListCubit>(),
                  builder: (context, listState) {
                    final entry = listState.getEntryFor(title.id);
                    final isInList = entry != null;
                    return _buildSecondaryActionButton(
                      icon: isInList ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      iconColor: isInList ? AppColors.primaryLight : AppColors.textPrimary,
                      label: isInList ? entry.status.labelRu : 'В закладки',
                      onTap: () => _showAnimeStatusSheet(context, title, entry),
                    );
                  },
                ),
              ),
            Expanded(
              child: _buildSecondaryActionButton(
                icon: Icons.cloud_download_outlined,
                label: 'Скачать',
                onTap: () => _openTorrentsSheet(context),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVoiceoverSelector(BuildContext context, List<EpisodeItem> episodes) {
    if (!getIt.isRegistered<KodikCubit>()) return const SizedBox.shrink();

    return BlocBuilder<KodikCubit, KodikState>(
      bloc: getIt<KodikCubit>(),
      builder: (context, kodikState) {
        final isAniLibria = kodikState.isAniLibriaActive;
        final activeTitle = kodikState.activeVoiceoverTitle;
        final icon = kodikState.selectedTranslation.displayIcon;

        return Align(
          alignment: Alignment.centerLeft,
          child: TvFocusable(
            borderRadius: BorderRadius.circular(12),
            onPressed: () {
              final epNum = episodes.isNotEmpty
                  ? episodes[_selectedEpisodeIndex.clamp(0, episodes.length - 1)].episode
                  : 1;
              VoiceoverSelectorSheet.show(
                context,
                episodeNumber: epNum,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAniLibria
                      ? AppColors.strokeMedium
                      : AppColors.primary.withValues(alpha: 0.5),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    'Озвучка: ',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    activeTitle,
                    style: AppTypography.labelMedium.copyWith(
                      color: isAniLibria ? AppColors.textPrimary : AppColors.primaryLight,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopHero({
    required BuildContext context,
    required AnimeTitle title,
    required String backdropUrl,
    required String initialPoster,
    required EpisodeItem? currentEpisode,
    required List<EpisodeItem> episodes,
  }) {
    final posterImage = initialPoster.isNotEmpty ? initialPoster : backdropUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingXl,
        AppDimensions.spacingMd,
        AppDimensions.spacingXl,
        AppDimensions.spacingLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Слева: четкий постер 2:3 (240x360) со скругленными углами и тенью
          Container(
            width: 240,
            height: 360,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Hero(
                tag: 'anime-poster-${title.id}',
                child: CachedNetworkImage(
                  imageUrl: wrapCorsSafeUrl(posterImage),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  placeholder: (context, url) => const ColoredBox(color: Colors.black26),
                  errorWidget: (context, primaryUrl, error) => CachedNetworkImage(
                    imageUrl: wrapCorsSafeUrl(title.effectiveFallbackPoster),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (context, url) => const ColoredBox(color: Colors.black26),
                    errorWidget: (context, fallbackUrl, error) => Container(
                      color: AppColors.surface,
                      child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 28),

          // Справа: колонка с метаданными, описанием, озвучкой и действиями
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Метаданные: Статус • Год • Тип • Серии • Рейтинг
                _buildMetadataRow(context, title),

                const SizedBox(height: 10),

                // Крупное название тайтла
                Text(
                  title.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.displayMedium.copyWith(
                    fontSize: 28,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),

                // Английское название
                if (title.englishTitle.isNotEmpty && title.englishTitle != title.displayTitle) ...[
                  const SizedBox(height: 4),
                  Text(
                    title.englishTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                ],

                // Кликабельные тональные плашки жанров
                if (title.genres.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildGenrePills(context, title),
                ],

                const SizedBox(height: 14),

                // Описание (до 4 строк с кнопкой Развернуть описание / Свернуть)
                if (title.description.isNotEmpty) ...[
                  _buildExpandableSynopsis(context, title.description),
                  const SizedBox(height: 14),
                ],

                // Выбор озвучки
                _buildVoiceoverSelector(context, episodes),

                const SizedBox(height: 16),

                // Ряд кнопок действий: компактная «Смотреть» (width: 220) + вторичные кнопки
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildWatchButton(context, currentEpisode, width: 220, height: 46),
                    _buildSecondaryActionsRow(context, title, currentEpisode, backdropUrl, isDesktop: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEpisodesSlivers({
    required BuildContext context,
    required AnimeTitle title,
    required List<EpisodeItem> episodes,
    required String backdropUrl,
    required bool isDesktop,
  }) {
    final isCompactGrid =
        _manualCompactEpisodeGrid ?? (episodes.length > kCompactEpisodeGridThreshold);

    if (!isCompactGrid) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
          sliver: isDesktop
              ? SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 4.2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildEpisodeCard(
                      context,
                      title,
                      episodes[index],
                      index,
                      backdropUrl,
                    ),
                    childCount: episodes.length,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildEpisodeCard(
                      context,
                      title,
                      episodes[index],
                      index,
                      backdropUrl,
                    ),
                    childCount: episodes.length,
                  ),
                ),
        ),
      ];
    }

    int? lastWatchedEp;
    if (getIt.isRegistered<WatchHistoryCubit>()) {
      final histState = getIt<WatchHistoryCubit>().state;
      final histItem = histState.historyMap[title.id];
      if (histItem != null) {
        lastWatchedEp = histItem.episode;
      } else {
        final normTitle = title.russianTitle.trim().toLowerCase();
        for (final h in histState.history) {
          if (h.titleName.trim().toLowerCase() == normTitle) {
            lastWatchedEp = h.episode;
            break;
          }
        }
      }
    }

    final activeEp = lastWatchedEp ??
        episodes[_selectedEpisodeIndex.clamp(0, episodes.length - 1)].episode;
    final effectiveRangeIndex = _selectedEpisodeRangeIndex ??
        computeEpisodeRangeIndex(episodes, activeEp);
    final visibleEpisodes = sliceEpisodesForRange(episodes, effectiveRangeIndex);

    return [
      if (episodes.length > kEpisodeRangeChunkSize)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: EpisodeRangeChips(
              episodes: episodes,
              selectedRangeIndex: effectiveRangeIndex,
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
              onRangeSelected: (idx) {
                setState(() => _selectedEpisodeRangeIndex = idx);
              },
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
        sliver: SliverGrid(
          gridDelegate: CompactEpisodeGrid.gridDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final ep = visibleEpisodes[index];
              final isActive = ep.episode == activeEp;
              final isWatched = !isActive &&
                  lastWatchedEp != null &&
                  ep.episode <= lastWatchedEp;
              final isDownloaded = getIt.isRegistered<DownloadCubit>() &&
                  getIt<DownloadCubit>().state.isDownloaded(title.id, ep.episode);

              return CompactEpisodeTile(
                episode: ep,
                isActive: isActive,
                isWatched: isWatched,
                isDownloaded: isDownloaded,
                onTap: () {
                  final globalIndex = episodes.indexWhere((e) => e.episode == ep.episode);
                  if (globalIndex >= 0) {
                    setState(() => _selectedEpisodeIndex = globalIndex);
                  }
                  _requestPlayEpisode(ep);
                },
                onLongPress: () {
                  showEpisodeQuickActionsSheet(
                    context,
                    episode: ep,
                    isDownloaded: isDownloaded,
                    onDownload: () => _startEpisodeDownload(title, ep),
                    onMarkWatched: () => _markEpisodeWatched(title, ep),
                  );
                },
              );
            },
            childCount: visibleEpisodes.length,
          ),
        ),
      ),
    ];
  }

  Future<void> _startEpisodeDownload(AnimeTitle title, EpisodeItem ep) async {
    if (!getIt.isRegistered<DownloadCubit>()) return;
    String? streamUrl = ep.fhdUrl ?? ep.hdUrl ?? ep.sdUrl;
    EpisodeItem downloadEp = ep;
    if (getIt.isRegistered<KodikCubit>()) {
      final kodikCubit = getIt<KodikCubit>();
      if (!kodikCubit.state.isAniLibriaActive) {
        final resolved = await kodikCubit.getStreamForEpisode(ep.episode);
        if (resolved != null && resolved.isNotEmpty) {
          streamUrl = resolved;
          downloadEp = EpisodeItem(
            episode: ep.episode,
            name: '${ep.name ?? "Серия ${ep.episode}"} (${kodikCubit.state.activeVoiceoverTitle})',
            fhdUrl: resolved,
            hdUrl: resolved,
            sdUrl: resolved,
            previewUrl: ep.previewUrl,
          );
        }
      }
    }
    if (streamUrl != null && streamUrl.isNotEmpty) {
      final quality = downloadEp.fhdUrl != null
          ? '1080p FHD'
          : (downloadEp.hdUrl != null ? '720p HD' : '480p SD');
      getIt<DownloadCubit>().startSmartDownload(
        title: title,
        episode: downloadEp,
        quality: quality,
      );
    }
  }

  Future<void> _markEpisodeWatched(AnimeTitle title, EpisodeItem ep) async {
    if (!getIt.isRegistered<WatchHistoryCubit>()) return;
    await getIt<WatchHistoryCubit>().saveProgress(
      titleId: title.id,
      titleName: title.russianTitle,
      posterUrl: title.posterMedium,
      episode: ep.episode,
      episodeName: ep.name,
      position: const Duration(minutes: 24),
      duration: const Duration(minutes: 24),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildEpisodeCard(
    BuildContext context,
    AnimeTitle title,
    EpisodeItem ep,
    int index,
    String backdropUrl,
  ) {
    final isSelected = index == _selectedEpisodeIndex;
    final epPreview = ep.previewUrl ?? backdropUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(14),
        scaleFactor: 1.02,
        onPressed: () {
          setState(() => _selectedEpisodeIndex = index);
          _requestPlayEpisode(ep);
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.06),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              // Превью серии с наложенной кнопкой Play
              SizedBox(
                width: 120,
                height: 70,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (epPreview.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(epPreview),
                          fit: BoxFit.cover,
                          memCacheWidth: 250,
                          placeholder: (context, url) => const ColoredBox(color: Colors.black26),
                          errorWidget: (context, url, error) {
                            if (backdropUrl.isNotEmpty && backdropUrl != epPreview) {
                              return CachedNetworkImage(
                                imageUrl: wrapCorsSafeUrl(backdropUrl),
                                fit: BoxFit.cover,
                                memCacheWidth: 250,
                                errorWidget: (_, __, ___) => _buildEpisodePlaceholder(ep.episode),
                              );
                            }
                            return _buildEpisodePlaceholder(ep.episode);
                          },
                        )
                      else
                        _buildEpisodePlaceholder(ep.episode),

                      // Полупрозрачный слой и кнопка Play поверх картинки
                      Container(
                        color: isSelected
                            ? Colors.black.withValues(alpha: 0.35)
                            : Colors.black45,
                      ),
                      Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? AppColors.primary
                                : Colors.black.withValues(alpha: 0.45),
                          ),
                          child: Icon(
                            Icons.play_arrow,
                            color: isSelected ? AppColors.onColor(AppColors.primary) : Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: AppDimensions.spacingMd),

              // Текстовая информация о серии
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Серия ${ep.episode}',
                      style: AppTypography.titleSmall.copyWith(
                        color: isSelected ? AppColors.primaryLight : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (ep.name != null && ep.name!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        ep.name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (ep.opening != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fast_forward_rounded,
                            size: 12,
                            color: AppColors.primaryLight,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Опенинг: ${ep.opening!.formattedRange}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              if (ep.fhdUrl != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '1080p',
                    style: AppTypography.badge.copyWith(
                      fontSize: 9.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

              // Кнопка фоновой загрузки серии (Download Manager)
              if (getIt.isRegistered<DownloadCubit>()) ...[
                const SizedBox(width: 4),
                BlocBuilder<DownloadCubit, DownloadState>(
                  bloc: getIt<DownloadCubit>(),
                  builder: (context, dlState) {
                    final isDownloaded = dlState.isDownloaded(title.id, ep.episode);
                    final task = dlState.getTask(title.id, ep.episode);
                    final isDownloading = task?.status == DownloadStatus.downloading;

                    if (isDownloading) {
                      final pct = ((task?.progress ?? 0) * 100).toInt();
                      return SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: task?.progress,
                                  strokeWidth: 2.2,
                                  color: AppColors.accentSecondary,
                                  backgroundColor: Colors.white12,
                                ),
                                Text(
                                  '$pct%',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    if (task?.status == DownloadStatus.queued) {
                      return const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }

                    if (task?.status == DownloadStatus.paused) {
                      return SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          padding: const EdgeInsets.all(10),
                          icon: const Icon(
                            Icons.pause_circle_rounded,
                            color: Color(0xFFFFB300),
                            size: 22,
                          ),
                          tooltip: 'Загрузка на паузе (нажмите для продолжения)',
                          onPressed: () => getIt<DownloadCubit>().resumeDownload(task!.id),
                        ),
                      );
                    }

                    if (task?.status == DownloadStatus.failed) {
                      return SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          padding: const EdgeInsets.all(10),
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: AppColors.syncError,
                            size: 22,
                          ),
                          tooltip: 'Ошибка загрузки: ${task?.errorMessage ?? ""}. Нажмите для повтора',
                          onPressed: () => getIt<DownloadCubit>().resumeDownload(task!.id),
                        ),
                      );
                    }

                    if (isDownloaded) {
                      return SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          padding: const EdgeInsets.all(10),
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.syncActive,
                            size: 22,
                          ),
                          tooltip: 'Серия скачана офлайн (нажмите для удаления)',
                          onPressed: () => _showDeleteDownloadDialog(context, title, ep),
                        ),
                      );
                    }

                    return SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        padding: const EdgeInsets.all(10),
                        icon: const Icon(
                          Icons.download_for_offline_outlined,
                          color: AppColors.textSecondary,
                          size: 22,
                        ),
                        tooltip: 'Скачать для офлайн-просмотра',
                        onPressed: () async {
                          String? streamUrl = ep.fhdUrl ?? ep.hdUrl ?? ep.sdUrl;
                          EpisodeItem downloadEp = ep;
                          if (getIt.isRegistered<KodikCubit>()) {
                            final kodikCubit = getIt<KodikCubit>();
                            if (!kodikCubit.state.isAniLibriaActive) {
                              final resolved = await kodikCubit.getStreamForEpisode(ep.episode);
                              if (resolved != null && resolved.isNotEmpty) {
                                streamUrl = resolved;
                                downloadEp = EpisodeItem(
                                  episode: ep.episode,
                                  name: '${ep.name ?? "Серия ${ep.episode}"} (${kodikCubit.state.activeVoiceoverTitle})',
                                  fhdUrl: resolved,
                                  hdUrl: resolved,
                                  sdUrl: resolved,
                                  previewUrl: ep.previewUrl,
                                );
                              }
                            }
                          }
                          if (streamUrl != null && streamUrl.isNotEmpty) {
                            final quality = downloadEp.fhdUrl != null ? '1080p FHD' : (downloadEp.hdUrl != null ? '720p HD' : '480p SD');
                            getIt<DownloadCubit>().startSmartDownload(
                              title: title,
                              episode: downloadEp,
                              quality: quality,
                            );
                            final hasNext = title.episodes.any((e) => e.episode == ep.episode + 1);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  hasNext
                                      ? 'Умная загрузка: качаем ${ep.episode} серию и готовим ${ep.episode + 1}...'
                                      : 'Загрузка ${ep.episode} серии началась...',
                                ),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final title = _currentTitle;
    final initialPoster = widget.title.posterOriginal.isNotEmpty
        ? widget.title.posterOriginal
        : (widget.title.posterMedium.isNotEmpty ? widget.title.posterMedium : widget.title.posterSmall);

    String backdropUrl;
    if (_currentTitle.posterOriginal.isNotEmpty) {
      backdropUrl = _currentTitle.posterOriginal;
    } else if (_currentTitle.posterMedium.isNotEmpty) {
      backdropUrl = _currentTitle.posterMedium;
    } else if (initialPoster.isNotEmpty) {
      backdropUrl = initialPoster;
    } else if (title.shikimoriId != null && title.shikimoriId! > 0) {
      backdropUrl = 'https://shikimori.io/system/animes/original/${title.shikimoriId}.jpg';
    } else {
      backdropUrl = _currentTitle.posterSmall;
    }
    backdropUrl = backdropUrl
        .replaceFirst('https://shikimori.me', 'https://shikimori.io')
        .replaceFirst('https://shikimori.one', 'https://shikimori.io')
        .replaceFirst('http://shikimori.me', 'https://shikimori.io')
        .replaceFirst('http://shikimori.one', 'https://shikimori.io');

    final episodes = title.episodes;
    final currentEpisode = episodes.isNotEmpty && _selectedEpisodeIndex < episodes.length
        ? episodes[_selectedEpisodeIndex]
        : (episodes.isNotEmpty ? episodes.first : null);

    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final backdropHeight = (screenHeight * 0.44).clamp(340.0, 480.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  if (isDesktop) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: 56)),
                    SliverToBoxAdapter(
                      child: _buildDesktopHero(
                        context: context,
                        title: title,
                        backdropUrl: backdropUrl,
                        initialPoster: initialPoster,
                        currentEpisode: currentEpisode,
                        episodes: episodes,
                      ),
                    ),
                  ] else ...[
                    // 1. Cinematic Backdrop Header в SliverAppBar с эффектом параллакса и динамического размытия
                    SliverAppBar(
                      expandedHeight: backdropHeight,
                      pinned: true,
                      stretch: true,
                      backgroundColor: AppColors.background,
                      automaticallyImplyLeading: false,
                      flexibleSpace: FlexibleSpaceBar(
                        collapseMode: CollapseMode.parallax,
                        stretchModes: const [
                          StretchMode.zoomBackground,
                          StretchMode.blurBackground,
                        ],
                        background: LayoutBuilder(
                          builder: (context, constraints) {
                            final double maxH = backdropHeight;
                            final double minH = kToolbarHeight + MediaQuery.paddingOf(context).top;
                            final double currentH = constraints.maxHeight;
                            final double collapseRatio = ((maxH - currentH) / (maxH - minH)).clamp(0.0, 1.0);

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                // Размытый фон + чёткий постер по центру без обрезания лица
                                if (backdropUrl.isNotEmpty) ...[
                                  ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: 20,
                                      sigmaY: 20,
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: wrapCorsSafeUrl(backdropUrl),
                                      fit: BoxFit.cover,
                                      memCacheWidth: 480,
                                      httpHeaders: const {
                                        'User-Agent': 'SyncPai-App/1.0',
                                        'Referer': 'https://shikimori.io/',
                                      },
                                      errorWidget: (_, __, ___) =>
                                          const ColoredBox(
                                        color: Color(0xFF0B0E14),
                                      ),
                                    ),
                                  ),
                                  const ColoredBox(color: Color(0x880B0E14)),
                                  Center(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        top: MediaQuery.paddingOf(context).top + 14,
                                        bottom: 22,
                                      ),
                                      child: Hero(
                                        tag: 'anime-poster-${title.id}',
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: AspectRatio(
                                            aspectRatio: 2 / 3,
                                            child: CachedNetworkImage(
                                              imageUrl:
                                                  wrapCorsSafeUrl(backdropUrl),
                                              fit: BoxFit.cover,
                                              alignment: Alignment.topCenter,
                                              memCacheWidth: 1080,
                                              filterQuality: FilterQuality.medium,
                                              httpHeaders: const {
                                                'User-Agent': 'SyncPai-App/1.0',
                                                'Referer':
                                                    'https://shikimori.io/',
                                              },
                                              placeholder: (context, url) =>
                                                  const ColoredBox(
                                                      color: Colors.black26),
                                              errorWidget:
                                                  (context, primaryUrl, error) =>
                                                      CachedNetworkImage(
                                                imageUrl: wrapCorsSafeUrl(
                                                    title.effectiveFallbackPoster),
                                                memCacheWidth: 1080,
                                                fit: BoxFit.cover,
                                                alignment: Alignment.topCenter,
                                                placeholder: (context, url) =>
                                                    const ColoredBox(
                                                        color: Colors.black26),
                                                errorWidget: (context,
                                                        fallbackUrl, error) =>
                                                    Container(
                                                  color: AppColors.surface,
                                                  child: const Center(
                                                    child: Icon(
                                                        Icons.broken_image,
                                                        color: Colors.white54,
                                                        size: 48),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                // Затемнение при сжатии
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: collapseRatio * 0.70),
                                  ),
                                ),

                                // Верхний затемняющий градиент под статус-бар и кнопку «Назад»
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: 140,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.85),
                                          Colors.black.withValues(alpha: 0.40),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Нижний кинематографичный градиент: бесшовное глубокое растворение в фон экрана
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        stops: const [0.0, 0.25, 0.55, 0.80, 1.0],
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.30),
                                          AppColors.background.withValues(alpha: 0.75),
                                          AppColors.background.withValues(alpha: 0.95),
                                          AppColors.background,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Текстовый блок поверх нижнего растворения (плавно растворяется при скролле вверх)
                                Positioned(
                                  left: MediaQuery.sizeOf(context).width <= 360 ? 12.0 : AppDimensions.spacingXl,
                                  right: MediaQuery.sizeOf(context).width <= 360 ? 12.0 : AppDimensions.spacingXl,
                                  bottom: 0,
                                  child: Opacity(
                                    opacity: (1.0 - collapseRatio * 1.8).clamp(0.0, 1.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Метаданные: Статус • Год • Тип • Серии • Рейтинг
                                        _buildMetadataRow(
                                          context,
                                          title,
                                          compact: true,
                                          withShadows: true,
                                        ),

                                        const SizedBox(height: 8),

                                        // Крупное название тайтла
                                        Text(
                                          title.displayTitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.displayMedium.copyWith(
                                            fontSize: MediaQuery.sizeOf(context).width <= 360 ? 19.0 : 24.0,
                                            height: 1.2,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                            color: AppColors.textPrimary,
                                            shadows: const [
                                              Shadow(color: Colors.black, blurRadius: 16, offset: Offset(0, 2)),
                                              Shadow(color: Colors.black87, blurRadius: 30),
                                            ],
                                          ),
                                        ),

                                        // Английское название (если отличается)
                                        if (title.englishTitle.isNotEmpty &&
                                            title.englishTitle != title.displayTitle) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            title.englishTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.bodySmall.copyWith(
                                              color: AppColors.textSecondary,
                                              fontSize: 12.5,
                                              shadows: const [
                                                Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 1)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    // Кликабельные плашки жанров (под постером и названием)
                    if (title.genres.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            MediaQuery.sizeOf(context).width <= 360 ? 12.0 : AppDimensions.spacingXl,
                            12.0,
                            MediaQuery.sizeOf(context).width <= 360 ? 12.0 : AppDimensions.spacingXl,
                            4.0,
                          ),
                          child: _buildGenrePills(context, title),
                        ),
                      ),

                    // 2. Блок действий: Главная кнопка «Смотреть» во всю ширину + аккуратный ряд действий с подписями
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          MediaQuery.sizeOf(context).width <= 360 ? 12.0 : AppDimensions.spacingXl,
                          AppDimensions.spacingLg,
                          MediaQuery.sizeOf(context).width <= 360 ? 12.0 : AppDimensions.spacingXl,
                          AppDimensions.spacingMd,
                        ),
                        child: Column(
                          children: [
                            _buildWatchButton(context, currentEpisode),
                            const SizedBox(height: 14),
                            _buildSecondaryActionsRow(context, title, currentEpisode, backdropUrl),
                          ],
                        ),
                      ),
                    ),

                    // Чип выбора студии озвучки и перевода (AniLibria / Kodik)
                    if (getIt.isRegistered<KodikCubit>())
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppDimensions.spacingXl,
                            0,
                            AppDimensions.spacingXl,
                            AppDimensions.spacingMd,
                          ),
                          child: _buildVoiceoverSelector(context, episodes),
                        ),
                      ),

                    // Описание тайтла (мобильное раскрывающееся, 4 строки)
                    if (title.description.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.spacingXl,
                            vertical: AppDimensions.spacingSm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Сюжет',
                                style: AppTypography.titleMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildExpandableSynopsis(context, title.description),
                            ],
                          ),
                        ),
                      ),
                  ],

              // Блок напоминания о недосмотренной серии (ResumeProgressCard)
              if (getIt.isRegistered<WatchHistoryCubit>())
                BlocBuilder<WatchHistoryCubit, WatchHistoryState>(
                  bloc: getIt<WatchHistoryCubit>(),
                  builder: (context, historyState) {
                    final history = historyState.getForTitle(_currentTitle.id);
                    if (history == null || history.positionMs < 15000 || history.progress >= 0.95) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }

                    final targetEpisode = episodes.firstWhere(
                      (e) => e.episode == history.episode,
                      orElse: () => currentEpisode ?? (episodes.isNotEmpty ? episodes.first : const EpisodeItem(episode: 1)),
                    );

                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.spacingXl,
                          0,
                          AppDimensions.spacingXl,
                          AppDimensions.spacingMd,
                        ),
                        child: ResumeProgressCard(
                          item: history,
                          onResume: () => _requestPlayEpisode(
                            targetEpisode,
                            Duration(milliseconds: history.positionMs),
                          ),
                          onStartFromBeginning: () => _requestPlayEpisode(
                            targetEpisode,
                            Duration.zero,
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // Сегментированный переключатель вкладок через TabBar с кастомным индикатором (анимация скольжения)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingXl,
                    vertical: AppDimensions.spacingSm,
                  ),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.strokeMedium),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      onTap: (index) {
                        HapticFeedback.lightImpact();
                        setState(() => _currentTabIndex = index);
                      },
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: AppColors.onColor(AppColors.primary),
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: const [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_circle_outline_rounded, size: 15),
                              SizedBox(width: 6),
                              Text('Эпизоды'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.movie_outlined, size: 15),
                              SizedBox(width: 6),
                              Text('О тайтле'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.rate_review_outlined, size: 15),
                              SizedBox(width: 6),
                              Text('Отзывы'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ВКЛАДКА 0: СПИСОК СЕРИЙ
              if (_currentTabIndex == 0) ...[
                // Заголовок списка серий
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimensions.spacingXl,
                      AppDimensions.spacingSm,
                      AppDimensions.spacingXl,
                      AppDimensions.spacingMd,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Список серий',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_isLoadingDetails)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (episodes.isNotEmpty)
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${episodes.length} эп.',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Builder(
                                  builder: (context) {
                                    final isCompact = _manualCompactEpisodeGrid ??
                                        (episodes.length > kCompactEpisodeGridThreshold);
                                    return IconButton(
                                      key: const ValueKey('details_episode_view_toggle'),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      tooltip: isCompact ? 'Показать списком' : 'Показать сеткой',
                                      icon: Icon(
                                        isCompact
                                            ? Icons.view_agenda_rounded
                                            : Icons.grid_view_rounded,
                                        color: AppColors.textSecondary,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _manualCompactEpisodeGrid = !isCompact;
                                        });
                                      },
                                    );
                                  },
                                ),
                                if (getIt.isRegistered<KodikCubit>()) ...[
                                  const SizedBox(width: 8),
                                  BlocBuilder<KodikCubit, KodikState>(
                                    bloc: getIt<KodikCubit>(),
                                    builder: (context, kodikState) {
                                    return GestureDetector(
                                      onTap: () {
                                        final epNum = episodes[_selectedEpisodeIndex.clamp(0, episodes.length - 1)].episode;
                                        VoiceoverSelectorSheet.show(context, episodeNumber: epNum);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: kodikState.isAniLibriaActive
                                              ? AppColors.surfaceElevated
                                              : AppColors.primary.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: kodikState.isAniLibriaActive
                                                ? AppColors.strokeMedium
                                                : AppColors.primary.withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(kodikState.selectedTranslation.displayIcon, style: const TextStyle(fontSize: 11)),
                                            const SizedBox(width: 4),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: (MediaQuery.sizeOf(context).width * 0.35).clamp(80.0, 160.0),
                                              ),
                                              child: Text(
                                                kodikState.activeVoiceoverTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTypography.caption.copyWith(
                                                  color: kodikState.isAniLibriaActive
                                                      ? AppColors.textSecondary
                                                      : AppColors.primaryLight,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Список / компактная сетка серий
                if (episodes.isNotEmpty)
                  ..._buildEpisodesSlivers(
                    context: context,
                    title: title,
                    episodes: episodes,
                    backdropUrl: backdropUrl,
                    isDesktop: isDesktop,
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacingXl,
                        vertical: AppDimensions.spacingXl,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        if (_isLoadingDetails) ...[
                          Column(
                            children: List.generate(
                              4,
                              (i) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  height: 86,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.02),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Row(
                                    children: [
                                      ShimmerPlaceholder(width: 120, height: 70, borderRadius: BorderRadius.circular(8)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            ShimmerPlaceholder(width: 96, height: 14, borderRadius: BorderRadius.circular(6)),
                                            const SizedBox(height: 8),
                                            ShimmerPlaceholder(width: 160, height: 11, borderRadius: BorderRadius.circular(6)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.hourglass_top_rounded,
                                        size: 32,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Builder(
                                      builder: (context) {
                                        final statusLower = _currentTitle.status.toLowerCase();
                                        final isUpcoming = statusLower.contains('anons') ||
                                            statusLower.contains('анонс') ||
                                            statusLower.contains('скоро') ||
                                            ((_currentTitle.year ?? 0) >= 2026 &&
                                                !statusLower.contains('released') &&
                                                !statusLower.contains('вышел'));
                                        return Column(
                                          children: [
                                            Text(
                                              isUpcoming
                                                  ? 'Статус: Скоро / Анонс'
                                                  : 'Озвучка отсутствует в базе',
                                              textAlign: TextAlign.center,
                                              style: AppTypography.titleMedium.copyWith(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              isUpcoming
                                                  ? 'Этот сезон ещё не начался или серии только готовятся к публикации. Вы можете добавить его в избранное или в планы.'
                                                  : 'Этот релиз (OVA / спецвыпуск) не озвучен в текущем каталоге',
                                              textAlign: TextAlign.center,
                                              style: AppTypography.bodySmall.copyWith(
                                                color: AppColors.textSecondary,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        if (_mangaBridge != null)
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFFF6B4A),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 10,
                                              ),
                                            ),
                                            icon: const Icon(Icons.menu_book_rounded, size: 18),
                                            label: const Text('Читать мангу'),
                                            onPressed: () => _openMangaReader(_mangaBridge!),
                                          ),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.primary,
                                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          ),
                                          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                                          label: const Text('В планах'),
                                          onPressed: () {
                                            context.read<AnimeListCubit>().setAnimeStatus(
                                                  animeId: _currentTitle.id,
                                                  titleRu: _currentTitle.displayTitle,
                                                  posterUrl: _currentTitle.posterMedium.isNotEmpty
                                                      ? _currentTitle.posterMedium
                                                      : _currentTitle.posterSmall,
                                                  status: AnimeListStatus.planned,
                                                  episodesTotal: _currentTitle.episodesTotal,
                                                  isUserInitiated: true,
                                                );
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('«${_currentTitle.displayTitle}» добавлено в «В планах»'),
                                                duration: const Duration(seconds: 2),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          },
                                        ),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.textSecondary,
                                            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          ),
                                          icon: const Icon(Icons.refresh_rounded, size: 18),
                                          label: const Text('Проверить серии'),
                                          onPressed: () => _loadFullDetails(),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],

              // Блоки «В списках у людей», «Связанные релизы» и «Коллекции» под сериями (Скриншот 1)
              if (_currentTabIndex == 0) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimensions.spacingXl,
                      AppDimensions.spacingLg,
                      AppDimensions.spacingXl,
                      AppDimensions.spacingSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserListsDistributionWidget(
                          stats: _userStats,
                          isLoading: _isLoadingReviews && _userStats.total == 0,
                        ),
                        const SizedBox(height: 24),
                        if (_relatedReleases.isNotEmpty)
                          RelatedReleasesSection(
                            releases: _relatedReleases,
                            onReleaseSelected: _onRelatedReleaseSelected,
                            onShowAllComments: () => setState(() => _currentTabIndex = 2),
                          ),
                        const SizedBox(height: 18),
                        ListenableBuilder(
                          listenable: RecommendationEngine.instance,
                          builder: (context, _) {
                            final catalogTitles = getIt.isRegistered<CatalogCubit>()
                                ? (getIt<CatalogCubit>().state is CatalogLoaded
                                    ? (getIt<CatalogCubit>().state as CatalogLoaded).titles
                                    : const <AnimeTitle>[])
                                : const <AnimeTitle>[];
                            if (catalogTitles.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final entries = getIt.isRegistered<AnimeListCubit>()
                                ? getIt<AnimeListCubit>().state.allEntries
                                : const <UserAnimeEntry>[];
                            final history = getIt.isRegistered<WatchHistoryCubit>()
                                ? getIt<WatchHistoryCubit>().state.history
                                : const <WatchHistoryItem>[];
                            final relatedIds = _relatedReleases
                                .map((r) => int.tryParse(r.id) ?? 0)
                                .where((id) => id > 0)
                                .toSet();
                            final similar = RecommendationEngine.instance.recommendSimilarTo(
                              target: _currentTitle,
                              catalogPool: catalogTitles,
                              userEntries: entries,
                              watchHistory: history,
                              shikimoriSimilar: _shikimoriSimilar,
                              relatedIds: relatedIds,
                            );
                            return ForYouRecommendationsShelf(
                              key: _similarSectionKey,
                              title: 'Похожее по вайбу',
                              picks: similar,
                              onTitleTap: (anime) {
                                context.pushNamed('details', extra: anime);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // ВКЛАДКА 1: О ТАЙТЛЕ (СПИСКИ, СЕЗОНЫ, ВИДЕО & ТРЕЙЛЕРЫ, ТАЙМКОДЫ)
              if (_currentTabIndex == 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.spacingXl),
                    child: AnimeMediaInfoSection(
                      title: _currentTitle,
                      relatedReleases: _relatedReleases,
                      onReleaseSelected: _onRelatedReleaseSelected,
                      videos: _videos,
                      userStats: _userStats,
                      isLoadingStats: _isLoadingReviews && _userStats.total == 0,
                      onOpenAllVideos: () {
                        context.pushNamed('anime-videos', extra: {
                          'title': _currentTitle.displayTitle,
                          'backdrop': backdropUrl,
                          'videos': _videos,
                        });
                      },
                      onShowAllComments: () {
                        setState(() => _currentTabIndex = 2);
                      },
                      onOpenTrailer: () {
                        context.pushNamed('anime-videos', extra: {
                          'title': _currentTitle.displayTitle,
                          'backdrop': backdropUrl,
                          'videos': _videos,
                        });
                      },
                    ),
                  ),
                ),

              // ВКЛАДКА 2: ОТЗЫВЫ СООБЩЕСТВА И РЕЙТИНГИ
              if (_currentTabIndex == 2)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.spacingXl),
                    child: AnimeReviewsSection(
                      reviews: _reviews,
                      aggregate: _aggregate,
                      portalScores: _portalScores,
                      scoreDistribution: _scoreDistribution,
                      isLoading: _isLoadingReviews,
                      title: _currentTitle,
                      onReviewAdded: (newReview) {
                        setState(() {
                          _reviews = [newReview, ..._reviews];
                          final curAgg = _aggregate ?? const AnimeRatingAggregate();
                          final newSyncVotes = curAgg.syncpaiVotesCount + 1;
                          final isPos = newReview.sentiment == ReviewSentiment.positive;
                          final isNeu = newReview.sentiment == ReviewSentiment.neutral;
                          final isNeg = newReview.sentiment == ReviewSentiment.negative;

                          _aggregate = AnimeRatingAggregate(
                            syncpaiScore: newReview.score,
                            syncpaiVotesCount: newSyncVotes,
                            shikimoriScore: curAgg.shikimoriScore,
                            shikimoriVotesCount: curAgg.shikimoriVotesCount,
                            malScore: curAgg.malScore,
                            malVotesCount: curAgg.malVotesCount,
                            positiveCount: curAgg.positiveCount + (isPos ? 1 : 0),
                            neutralCount: curAgg.neutralCount + (isNeu ? 1 : 0),
                            negativeCount: curAgg.negativeCount + (isNeg ? 1 : 0),
                          );
                        });
                      },
                    ),
                  ),
                ),

              const SliverToBoxAdapter(
                child: SizedBox(height: AppDimensions.spacing3xl),
              ),
            ],
          ),

          // 7. Плавающая верхняя стеклянная панель: Кнопка «Назад» и название при скролле
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                color: _showAppBarTitle
                    ? AppColors.background.withValues(alpha: 0.85)
                    : Colors.transparent,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _showAppBarTitle ? 14 : 0,
                    sigmaY: _showAppBarTitle ? 14 : 0,
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacingLg,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          GlassIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            size: 40,
                            iconSize: 18,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: AppDimensions.spacingMd),
                          if (_showAppBarTitle)
                            Expanded(
                              child: Text(
                                title.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.titleSmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 8. Плавающий мини-док активной свернутой комнаты совместного просмотра
          const Positioned.fill(
            child: FloatingRoomOverlay(mobileBottomInset: 24),
          ),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildEpisodePlaceholder(int episodeNum) {
    return Container(
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.movie_creation_outlined, color: Colors.white38, size: 24),
          const SizedBox(height: 2),
          Text(
            'Серия $episodeNum',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
