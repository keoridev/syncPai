import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/player_navigation_guard.dart';
import '../../../../core/widgets/pai_chan_offline_view.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../player/domain/entities/player_quality.dart';
import '../../domain/entities/anime_clip.dart';
import '../../domain/repositories/anime_clips_repository.dart';
import '../controllers/moments_player_pool.dart';
import '../widgets/moments_page_view.dart';

/// Экран «Лента Моментов» (Anime Reels / Shorts)
/// с полноэкранным вертикальным свайпом, удержанием для 2X скорости,
/// пулом из 3 плееров (предзагрузка 0 мс), строгим контролем видеопамяти
/// и мгновенным прыжком в серию с точного таймкода.
class AnimeShortsScreen extends StatefulWidget {
  final bool showBackButton;
  final ValueChanged<AnimeTitle>? onTitleSelected;
  final bool isActive;

  const AnimeShortsScreen({
    super.key,
    this.showBackButton = false,
    this.onTitleSelected,
    this.isActive = true,
  });

  @override
  State<AnimeShortsScreen> createState() => _AnimeShortsScreenState();
}

class _AnimeShortsScreenState extends State<AnimeShortsScreen> {
  late final PageController _pageController;
  late final AnimeClipsRepository _repository;
  late final MomentsPlayerPool _pool;
  List<AnimeClip> _clips = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isResolvingPlayback = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pool = MomentsPlayerPool();
    _repository = getIt.isRegistered<AnimeClipsRepository>()
        ? getIt<AnimeClipsRepository>()
        : _FallbackAnimeClipsRepository();
    _loadClips();
  }

  @override
  void didUpdateWidget(covariant AnimeShortsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (!widget.isActive) {
        _pool.getEntry(_currentIndex)?.player.pause();
      } else {
        _pool.getEntry(_currentIndex)?.player.play();
      }
    }
  }

  Future<void> _loadClips() async {
    setState(() => _isLoading = true);
    try {
      final clips = await _repository.getClips();
      if (mounted) {
        setState(() {
          _clips = clips;
          _isLoading = false;
        });
        if (clips.isNotEmpty) {
          _pool.updateActiveIndex(_currentIndex, clips);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleToggleLike(AnimeClip clip) async {
    final newStatus = await _repository.toggleLike(clip.id);
    if (mounted) {
      setState(() {
        final index = _clips.indexWhere((c) => c.id == clip.id);
        if (index != -1) {
          final updated = _clips[index].copyWith(
            isLiked: newStatus,
            likesCount: newStatus
                ? _clips[index].likesCount + 1
                : (_clips[index].likesCount - 1).clamp(0, 9999999),
          );
          _clips[index] = updated;
        }
      });
    }
  }

  void _handleToggleBookmark(AnimeClip clip) async {
    final newStatus = await _repository.toggleBookmark(clip.id);

    if (mounted) {
      try {
        final listCubit = getIt.isRegistered<AnimeListCubit>()
            ? getIt<AnimeListCubit>()
            : null;
        if (listCubit != null) {
          if (newStatus) {
            await listCubit.setAnimeStatus(
              animeId: clip.animeId,
              titleRu: clip.animeTitle,
              posterUrl: clip.posterUrl,
              status: AnimeListStatus.planned,
              lastEpisode: clip.episodeNumber,
              isUserInitiated: true,
            );
          } else {
            await listCubit.removeAnime(clip.animeId);
          }
        }
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        final index = _clips.indexWhere((c) => c.id == clip.id);
        if (index != -1) {
          _clips[index] = _clips[index].copyWith(isBookmarked: newStatus);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? '«${clip.animeTitle}» добавлено в список «В планах»'
                : 'Тайтл удален из закладок',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static String _normalizeTitleForMatch(String input) {
    return input
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _titleSimilarityScore(AnimeTitle candidate, AnimeClip clip) {
    final targetRu = _normalizeTitleForMatch(clip.animeTitle);
    final targetEn = _normalizeTitleForMatch(clip.englishTitle);
    final candRu = _normalizeTitleForMatch(candidate.russianTitle);
    final candEn = _normalizeTitleForMatch(candidate.englishTitle);

    double best = 0.0;
    for (final t in [targetRu, targetEn]) {
      if (t.isEmpty) continue;
      for (final c in [candRu, candEn]) {
        if (c.isEmpty) continue;
        if (t == c) return 1.0;
        if (c.contains(t) || t.contains(c)) {
          final ratio = t.length < c.length
              ? t.length / c.length
              : c.length / t.length;
          if (ratio >= 0.55 && ratio > best) best = ratio;
        }
        final tTokens = t.split(' ').where((w) => w.length >= 2).toSet();
        final cTokens = c.split(' ').where((w) => w.length >= 2).toSet();
        if (tTokens.isNotEmpty && cTokens.isNotEmpty) {
          final overlap = tTokens.intersection(cTokens).length;
          final jaccard = overlap / tTokens.union(cTokens).length;
          if (jaccard > best) best = jaccard;
        }
      }
    }
    return best;
  }

  Future<AnimeTitle?> _resolveClipTitle(AnimeClip clip) async {
    if (!getIt.isRegistered<CatalogRepository>()) return null;
    final catalogRepo = getIt<CatalogRepository>();

    // Если ID <= 12000, это может быть AniLibria ID — пробуем получить детали,
    // но обязательно сверяем название, чтобы исключить коллизию с Shikimori ID.
    if (clip.animeId > 0 && clip.animeId <= 12000) {
      try {
        final direct = await catalogRepo.getTitleDetails(id: clip.animeId);
        if (_titleSimilarityScore(direct, clip) >= 0.45) {
          return direct;
        }
      } catch (_) {}
    }

    // Поиск по русскому и английскому названию с проверкой релевантности
    AnimeTitle? bestMatch;
    double bestScore = 0.0;
    for (final q in [clip.animeTitle, clip.englishTitle]) {
      final clean = q.trim();
      if (clean.isEmpty) continue;
      try {
        final results = await catalogRepo.searchTitles(clean);
        for (final item in results) {
          final score = _titleSimilarityScore(item, clip);
          if (score > bestScore) {
            bestScore = score;
            bestMatch = item;
          }
        }
        if (bestScore >= 0.75) break;
      } catch (_) {}
    }

    return bestScore >= 0.45 ? bestMatch : null;
  }

  /// КИЛЛЕР-ФИЧА: Открытие серии в плеере с точного таймкода
  Future<void> _handleWatchFromMoment(AnimeClip clip) async {
    if (_isResolvingPlayback) return;
    // Приостанавливаем видео шортса перед переходом в полноэкранный плеер
    _pool.getEntry(_currentIndex)?.player.pause();

    setState(() => _isResolvingPlayback = true);

    try {
      AnimeTitle? resolvedTitle = await _resolveClipTitle(clip);

      resolvedTitle ??= AnimeTitle(
        id: clip.animeId,
        shikimoriId: clip.animeId > 12000 ? clip.animeId : null,
        code: clip.animeId > 12000
            ? 'shikimori_${clip.animeId}'
            : clip.englishTitle.toLowerCase().replaceAll(' ', '-'),
        russianTitle: clip.animeTitle,
        englishTitle: clip.englishTitle,
        posterSmall: clip.posterUrl,
        posterMedium: clip.posterUrl,
        posterOriginal: clip.posterUrl,
        genres: clip.tags.map((t) => t.replaceAll('#', '')).toList(),
        description: clip.caption,
        status: 'Онгоинг',
        episodes: [
          EpisodeItem(
            episode: clip.episodeNumber,
            name: 'Эпизод ${clip.episodeNumber}',
            previewUrl: clip.posterUrl,
            fhdUrl: clip.videoUrl,
            hdUrl: clip.videoUrl,
            sdUrl: clip.videoUrl,
          ),
        ],
      );

      EpisodeItem targetEpisode = resolvedTitle.episodes.firstWhere(
        (ep) => ep.episode == clip.episodeNumber,
        orElse: () {
          if (resolvedTitle!.episodes.isNotEmpty) {
            return resolvedTitle.episodes.first;
          }
          return EpisodeItem(
            episode: clip.episodeNumber,
            name: 'Эпизод ${clip.episodeNumber}',
            previewUrl: clip.posterUrl,
            fhdUrl: clip.videoUrl,
          );
        },
      );

      if (mounted) {
        setState(() => _isResolvingPlayback = false);

        PlayerNavigationGuard.openPlayer(context, extra: {
          'title': resolvedTitle,
          'episode': targetEpisode,
          'quality': PlayerQuality.fhd,
          'initialPosition': Duration(seconds: clip.targetTimestampSeconds),
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResolvingPlayback = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось запустить серию: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Открытие страницы сведений об аниме
  Future<void> _handleOpenDetails(AnimeClip clip) async {
    _pool.getEntry(_currentIndex)?.player.pause();
    AnimeTitle? targetTitle = await _resolveClipTitle(clip);

    targetTitle ??= AnimeTitle(
      id: clip.animeId,
      shikimoriId: clip.animeId > 12000 ? clip.animeId : null,
      code: clip.animeId > 12000
          ? 'shikimori_${clip.animeId}'
          : clip.englishTitle.toLowerCase().replaceAll(' ', '-'),
      russianTitle: clip.animeTitle,
      englishTitle: clip.englishTitle,
      posterSmall: clip.posterUrl,
      posterMedium: clip.posterUrl,
      posterOriginal: clip.posterUrl,
      genres: clip.tags.map((t) => t.replaceAll('#', '')).toList(),
      description: clip.caption,
      status: 'Онгоинг',
    );

    if (mounted) {
      if (widget.onTitleSelected != null) {
        widget.onTitleSelected!(targetTitle);
      } else {
        context.pushNamed('details', extra: targetTitle);
      }
    }
  }

  /// Нативный запуск YouTube Shorts через внешний интент без тормозов WebView
  void _handleOpenYouTube(AnimeClip clip) async {
    final ytId = clip.youtubeId;
    if (ytId != null && ytId.isNotEmpty) {
      final appUri = Uri.parse('vnd.youtube:$ytId');
      final webUri = Uri.parse('https://www.youtube.com/shorts/$ytId');
      try {
        if (await canLaunchUrl(appUri)) {
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return;
      } catch (_) {}
    }

    if (clip.youtubeUrl != null && clip.youtubeUrl!.isNotEmpty) {
      try {
        final uri = Uri.parse(clip.youtubeUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _pool.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (_clips.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: PaiChanOfflineView(
            title: 'Лента недоступна без сети',
            subtitle: 'Пай-тян не может загрузить моменты без подключения к интернету.',
            onRetry: _loadClips,
            onOpenSaved: () => context.push('/lists'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Вертикальный PageView с 3-Player Pool Buffering
          MomentsPageView(
            clips: _clips,
            pool: _pool,
            pageController: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            onToggleLike: _handleToggleLike,
            onToggleBookmark: _handleToggleBookmark,
            onWatchFromMoment: _handleWatchFromMoment,
            onOpenDetails: _handleOpenDetails,
            onOpenYouTube: _handleOpenYouTube,
          ),

          // Верхняя плашка
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    if (widget.showBackButton) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      'Моменты',
                      style: AppTypography.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white70, size: 22),
                      onPressed: _loadClips,
                      tooltip: 'Обновить ленту',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Лоадер перехода в плеер
          if (_isResolvingPlayback)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Загрузка серии и переход к моменту...',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FallbackAnimeClipsRepository implements AnimeClipsRepository {
  @override
  Future<List<AnimeClip>> getClips({bool forceRefresh = false}) async => const [];

  @override
  Future<bool> toggleBookmark(String clipId) async => false;

  @override
  Future<bool> toggleLike(String clipId) async => false;
}
