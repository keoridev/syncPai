import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_dimensions.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/glass_container.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_state.dart';
import 'package:sync_pai/features/anime_details/data/datasources/anime_reviews_provider.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
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
import 'package:sync_pai/features/sync_room/presentation/widgets/sync_room_config_sheet.dart';
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
import 'package:sync_pai/features/downloads/presentation/cubit/download_state.dart';
import 'package:sync_pai/features/torrents/domain/entities/torrent_release.dart';
import 'package:sync_pai/features/torrents/domain/repositories/torrent_repository.dart';
import 'package:sync_pai/features/torrents/data/repositories/torrent_repository_impl.dart';
import 'package:sync_pai/features/torrents/presentation/widgets/torrent_releases_sheet.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_cubit.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_state.dart';
import 'package:sync_pai/features/kodik/presentation/widgets/voiceover_selector_sheet.dart';

/// Детальный экран аниме в премиальном стиле Cinematic Dark / Nordic Dark.
///
/// 1. Cinematic Backdrop на 44% высоты экрана с бесшовным растворением в фон.
/// 2. Крупный заголовок, год и жанры через точку без серых плашек.
/// 3. Акцентная главная кнопка «Смотреть» + матовые круглые glass-кнопки действий.
/// 4. Карточка продолжения просмотра (ResumeProgressCard) с точным прогрессом.
/// 5. Вкладки «Серии», «Инфо & Трейлер» и «Отзывы» с оценками порталов (Shikimori/MAL/AniLibria).
class AnimeDetailsScreen extends StatefulWidget {
  final AnimeTitle title;
  final void Function(AnimeTitle title, EpisodeItem episode, PlayerQuality quality)? onPlayEpisode;
  final void Function(AnimeTitle title, EpisodeItem episode, PlayerQuality quality, Duration position)? onResumeEpisode;
  final void Function(AnimeTitle title, EpisodeItem episode)? onStartSyncRoom;

  const AnimeDetailsScreen({
    super.key,
    required this.title,
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
  Map<String, double>? _portalScores;
  List<RelatedAnimeRelease> _relatedReleases = [];
  List<AnimeVideoItem> _videos = [];
  UserListsStats _userStats = const UserListsStats();
  List<ScoreDistributionItem> _scoreDistribution = [];
  bool _isLoadingReviews = false;
  bool _isDescriptionExpanded = false;
  bool _isLoadingDetails = false;
  bool _isOpeningEpisode = false;
  late final ScrollController _scrollController;
  bool _showAppBarTitle = false;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;
    _reviews = AnimeReviewsProvider.getReviewsForTitle(widget.title);
    _scrollController = ScrollController()..addListener(_handleScroll);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index != _currentTabIndex) {
        setState(() => _currentTabIndex = _tabController.index);
      }
    });
    if (_currentTitle.episodes.length <= 1) {
      _loadFullDetails();
    }
    _loadShikimoriReviews();
    if (getIt.isRegistered<KodikCubit>()) {
      getIt<KodikCubit>().loadVoiceovers(
        shikimoriId: _currentTitle.shikimoriId,
        title: _currentTitle.displayTitle,
      );
    }
  }

  Future<void> _loadShikimoriReviews() async {
    setState(() => _isLoadingReviews = true);
    try {
      final shikiSource = getIt.isRegistered<ShikimoriRemoteDataSource>()
          ? getIt<ShikimoriRemoteDataSource>()
          : ShikimoriRemoteDataSourceImpl();
      final result = await shikiSource.getReviewsAndRatings(_currentTitle);
      if (mounted) {
        setState(() {
          _reviews = result.reviews;
          _portalScores = result.portalScores;
          _relatedReleases = result.relatedReleases;
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
            context.pushNamed('details', extra: matched);
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
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSecondaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color iconColor = AppColors.textPrimary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIconButton(
              icon: icon,
              size: 46,
              iconSize: 20,
              iconColor: iconColor,
              onTap: onTap,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 66,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
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

  Future<void> _loadFullDetails() async {
    setState(() => _isLoadingDetails = true);
    try {
      final releaseId = _currentTitle.id;
      final titleRu = _currentTitle.russianTitle;
      final titleEn = _currentTitle.englishTitle;
      final displayTitle = titleRu.isNotEmpty ? titleRu : titleEn;

      // Получаем видеопотоки напрямую через AniLiberty API
      final List<EpisodeItem> directEpisodes = [];
      if (getIt.isRegistered<GetPlayerLinksUseCase>()) {
        try {
          final translations = await getIt<GetPlayerLinksUseCase>().call(
            releaseId,
            title: displayTitle,
          );
          if (translations.isNotEmpty) {
            final direct = translations.where((t) => t.isDirectStream && t.episodes.isNotEmpty);
            if (direct.isNotEmpty) {
              directEpisodes.addAll(direct.first.episodes.map((e) => e.toEpisodeItem()));
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          if (directEpisodes.isNotEmpty) {
            _currentTitle = _currentTitle.copyWith(
              episodes: directEpisodes,
              episodesTotal: directEpisodes.length,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingDetails = false);
      }
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



  @override
  Widget build(BuildContext context) {
    final title = _currentTitle;
    final initialPoster = widget.title.posterOriginal.isNotEmpty
        ? widget.title.posterOriginal
        : (widget.title.posterMedium.isNotEmpty ? widget.title.posterMedium : widget.title.posterSmall);

    String backdropUrl;
    if (initialPoster.isNotEmpty && !initialPoster.contains('anilibria.top/upload/release/350x500')) {
      backdropUrl = initialPoster;
    } else if (widget.title.shikimoriId != null && widget.title.shikimoriId! > 0) {
      backdropUrl = 'https://shikimori.io/system/animes/original/${widget.title.shikimoriId}.jpg';
    } else if (widget.title.id > 0) {
      backdropUrl = 'https://shikimori.io/system/animes/original/${widget.title.id}.jpg';
    } else {
      backdropUrl = _currentTitle.posterOriginal.isNotEmpty
          ? _currentTitle.posterOriginal
          : (_currentTitle.posterMedium.isNotEmpty ? _currentTitle.posterMedium : _currentTitle.posterSmall);
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
    final backdropHeight = (screenHeight * 0.44).clamp(340.0, 480.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
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
                          // Четкий оригинальный HD-арт без размытия и потери детализации
                          if (backdropUrl.isNotEmpty)
                            Hero(
                              tag: 'anime-poster-${title.id}',
                              child: CachedNetworkImage(
                                imageUrl: wrapCorsSafeUrl(backdropUrl),
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                memCacheWidth: 1080,
                                filterQuality: FilterQuality.medium,
                                httpHeaders: const {
                                  'User-Agent': 'SyncPai-App/1.0',
                                  'Referer': 'https://shikimori.io/',
                                },
                                placeholder: (context, url) => const ColoredBox(color: Colors.black26),
                                errorWidget: (context, primaryUrl, error) => CachedNetworkImage(
                                  imageUrl: wrapCorsSafeUrl(title.effectiveFallbackPoster),
                                  memCacheWidth: 1080,
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
                                  // Метаданные: Статус • Год • Серии
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (title.status.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: AppColors.primary.withValues(alpha: 0.4),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            title.status,
                                            style: AppTypography.badge.copyWith(
                                              color: AppColors.primaryLight,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (title.year != null) ...[
                                        Text(
                                          '${title.year}',
                                          style: AppTypography.labelMedium.copyWith(
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const Text('•', style: TextStyle(color: AppColors.textMuted)),
                                      ],
                                      Text(
                                        title.episodesBadgeText,
                                        style: AppTypography.labelMedium.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Крупное название тайтла с четкими тенями для безупречной читаемости на светлых постерах
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

                                  // Жанры через точку без серых плашек с глубокой тенью
                                  if (title.genres.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      title.genres.join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w400,
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
                      // Главная кнопка «Смотреть»: крупная, акцентная моно-пилюля во всю ширину
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoadingDetails
                              ? null
                              : (currentEpisode != null
                                  ? () => _requestPlayEpisode(currentEpisode)
                                  : () => _loadFullDetails()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentEpisode != null
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.surfaceElevated,
                            foregroundColor: AppColors.textPrimary,
                            elevation: currentEpisode != null ? 3 : 0,
                            shadowColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: currentEpisode != null
                                    ? Theme.of(context).colorScheme.primary
                                    : AppColors.strokeMedium,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: _isLoadingDetails
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      currentEpisode != null ? Icons.play_arrow_rounded : Icons.search_rounded,
                                      size: 24,
                                      color: AppColors.textPrimary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          currentEpisode != null && currentEpisode.episode > 1
                                              ? 'Серия ${currentEpisode.episode} • Смотреть'
                                              : (currentEpisode != null ? 'Смотреть' : 'Найти в AniLibria'),
                                          maxLines: 1,
                                          style: AppTypography.labelLarge.copyWith(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Второстепенные действия в равномерный ряд с подписями
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildSecondaryActionButton(
                            icon: Icons.group_outlined,
                            label: 'Вместе',
                            onTap: currentEpisode != null
                                ? () {
                                    widget.onStartSyncRoom?.call(title, currentEpisode);
                                    SyncRoomConfigSheet.show(
                                      context,
                                      title: title,
                                      episode: currentEpisode,
                                      onConfirm: ({
                                        required int maxPeers,
                                        required bool isHostControlOnly,
                                        required PlayerQuality quality,
                                        required String roomCode,
                                      }) {},
                                    );
                                  }
                                : null,
                          ),
                          _buildSecondaryActionButton(
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
                                return _buildSecondaryActionButton(
                                  icon: isInList ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                  iconColor: isInList ? AppColors.primaryLight : AppColors.textPrimary,
                                  label: isInList ? entry.status.labelRu : 'В закладки',
                                  onTap: () => _showAnimeStatusSheet(context, title, entry),
                                );
                              },
                            ),
                          _buildSecondaryActionButton(
                            icon: Icons.cloud_download_outlined,
                            label: 'Скачать',
                            onTap: () => _openTorrentsSheet(context),
                          ),
                        ],
                      ),
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
                    child: BlocBuilder<KodikCubit, KodikState>(
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
                    ),
                  ),
                ),

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

              // Описание тайтла (раскрывающееся, аккуратная типографика)
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
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isDescriptionExpanded = !_isDescriptionExpanded;
                            });
                          },
                          child: Text(
                            title.description,
                            maxLines: _isDescriptionExpanded ? null : 3,
                            overflow: _isDescriptionExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: AppTypography.bodyMedium.copyWith(
                              height: 1.55,
                              fontSize: 13.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (title.description.length > 120) ...[
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isDescriptionExpanded = !_isDescriptionExpanded;
                              });
                            },
                            child: Text(
                              _isDescriptionExpanded ? 'Свернуть' : 'Подробнее',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
                      labelColor: AppColors.textPrimary,
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

                // Карточки серий в стиле 16:9 с превью слева и тонким разделителем
                if (episodes.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final ep = episodes[index];
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
                                                  placeholder: (context, url) =>
                                                      const ColoredBox(color: Colors.black26),
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
                                                  child: const Icon(
                                                    Icons.play_arrow,
                                                    color: Colors.white,
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
                                          children: [
                                            Text(
                                              'Серия ${ep.episode}',
                                              style: AppTypography.titleSmall.copyWith(
                                                color: isSelected
                                                    ? AppColors.primaryLight
                                                    : AppColors.textPrimary,
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
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
                          },
                        childCount: episodes.length,
                      ),
                    ),
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
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Загрузка серий и плеера...',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
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
                                    Text(
                                      _currentTitle.status.toLowerCase().contains('скоро') ||
                                              _currentTitle.status.toLowerCase().contains('анонс')
                                          ? 'Статус: Скоро / Анонс'
                                          : 'Серии пока не вышли в озвучке',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.titleMedium.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Этот сезон еще не начался или серии только готовятся к публикации. Вы можете добавить его в избранное или в планы.',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: [
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
                        UserListsDistributionWidget(stats: _userStats),
                        const SizedBox(height: 24),
                        if (_relatedReleases.isNotEmpty)
                          RelatedReleasesSection(
                            releases: _relatedReleases,
                            onReleaseSelected: _onRelatedReleaseSelected,
                            onShowAllComments: () => setState(() => _currentTabIndex = 2),
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
                      portalScores: _portalScores,
                      scoreDistribution: _scoreDistribution,
                      isLoading: _isLoadingReviews,
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
        ],
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
