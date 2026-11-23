import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/injection.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../watch_history/domain/entities/watch_history_item.dart';
import '../entities/anime_title.dart';

enum RecommendationHook {
  zeigarnik,
  postFinaleEcho,
  coreTaste,
  plannedResurface,
  circadianDiscovery,
}

/// Взвешенный вектор вкусовых предпочтений пользователя.
class UserTasteVector {
  final Map<String, double> genreWeights;
  final Set<int> excludedIds;
  final UserAnimeEntry? lastCompletedEntry;

  const UserTasteVector({
    required this.genreWeights,
    required this.excludedIds,
    this.lastCompletedEntry,
  });

  double scoreGenres(List<String> genres) {
    if (genres.isEmpty || genreWeights.isEmpty) return 0.0;
    double sum = 0.0;
    for (final g in genres) {
      final key = g.trim().toLowerCase();
      sum += genreWeights[key] ?? 0.0;
    }
    return sum;
  }

  String? topMatchingGenre(List<String> genres) {
    String? best;
    double bestWeight = -9999.0;
    for (final g in genres) {
      final w = genreWeights[g.trim().toLowerCase()] ?? 0.0;
      if (w > bestWeight) {
        bestWeight = w;
        best = g.trim();
      }
    }
    return best;
  }

  bool get hasPositiveGenres => genreWeights.values.any((w) => w > 0.0);

  int sharedPositiveGenreCount(List<String> genres) {
    if (genres.isEmpty || genreWeights.isEmpty) return 0;
    final seen = <String>{};
    int count = 0;
    for (final g in genres) {
      final key = g.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      if ((genreWeights[key] ?? 0.0) > 0.0) {
        count++;
      }
    }
    return count;
  }

  bool get isSoftSliceOfLifeProfile {
    const soft = {'романтика', 'повседневность', 'комедия', 'школа'};
    const heavyAction = {
      'экшен',
      'экшн',
      'боевые искусства',
      'сёнен',
      'сенен',
    };
    final positive = genreWeights.entries.where((e) => e.value > 0.0).toList();
    if (positive.isEmpty) return false;
    final hasAnyAction = positive.any((e) => heavyAction.contains(e.key));
    if (hasAnyAction) return false;
    return positive.every((e) => soft.contains(e.key));
  }
}

/// Карточка рекомендации с психологическим триггером и текстовой причиной.
class RecommendedAnimePick {
  final AnimeTitle anime;
  final String reasonTag;
  final RecommendationHook hook;
  final double score;
  final int matchPercent;

  const RecommendedAnimePick({
    required this.anime,
    required this.reasonTag,
    required this.hook,
    required this.score,
    required this.matchPercent,
  });
}

/// Локальный движок поведенческих рекомендаций на основе психологии просмотра
/// (Zeigarnik, Post-Finale Echo, 70/20/10 mix, циркадные бусты и «Не интересно»).
class RecommendationEngine extends ChangeNotifier {
  static final RecommendationEngine instance = RecommendationEngine._();
  RecommendationEngine._();

  static const String _prefHiddenIdsKey = 'hidden_recommendation_ids';
  static const String _prefNegativeGenresKey = 'negative_recommendation_genres';

  final Set<int> _hiddenIds = {};
  final Set<String> _negativeGenres = {};
  bool _initialized = false;

  Set<int> get hiddenIds => Set.unmodifiable(_hiddenIds);

  Future<SharedPreferences> _getPrefs() async {
    if (getIt.isRegistered<SharedPreferences>()) {
      return getIt<SharedPreferences>();
    }
    return SharedPreferences.getInstance();
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await _getPrefs();
      final rawIds = prefs.getStringList(_prefHiddenIdsKey) ?? const [];
      for (final s in rawIds) {
        final id = int.tryParse(s);
        if (id != null) _hiddenIds.add(id);
      }
      final rawGenres = prefs.getStringList(_prefNegativeGenresKey) ?? const [];
      _negativeGenres.addAll(rawGenres.map((g) => g.trim().toLowerCase()));
    } catch (_) {}
    _initialized = true;
  }

  /// Постоянно скрыть тайтл по кнопке «Не интересно» и снизить вес его жанров.
  Future<void> dismissRecommendation(AnimeTitle anime) async {
    await init();
    _hiddenIds.add(anime.id);
    for (final g in anime.genres) {
      final clean = g.trim().toLowerCase();
      if (clean.isNotEmpty) {
        _negativeGenres.add(clean);
      }
    }
    notifyListeners();

    try {
      final prefs = await _getPrefs();
      await prefs.setStringList(
        _prefHiddenIdsKey,
        _hiddenIds.map((e) => e.toString()).toList(),
      );
      await prefs.setStringList(
        _prefNegativeGenresKey,
        _negativeGenres.toList(),
      );
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest() {
    _hiddenIds.clear();
    _negativeGenres.clear();
    _initialized = true;
  }

  /// Построение динамического вектора вкусов пользователя.
  UserTasteVector buildTasteVector({
    required List<AnimeTitle> catalogPool,
    required List<UserAnimeEntry> userEntries,
    required List<WatchHistoryItem> watchHistory,
    Set<int> favoriteIds = const {},
  }) {
    final catalogById = {for (final a in catalogPool) a.id: a};
    final weights = <String, double>{};
    final excluded = <int>{..._hiddenIds};

    void addGenreWeight(List<String> genres, double delta) {
      for (final g in genres) {
        final k = g.trim().toLowerCase();
        if (k.isEmpty) continue;
        weights[k] = (weights[k] ?? 0.0) + delta;
      }
    }

    // Штраф за жанры из отклонённых («Не интересно») карточек
    for (final ng in _negativeGenres) {
      weights[ng] = (weights[ng] ?? 0.0) - 2.5;
    }

    UserAnimeEntry? lastCompleted;
    for (final entry in userEntries) {
      final meta = catalogById[entry.animeId];
      final genres = meta?.genres ?? const <String>[];

      final isFavoriteOrHighRated = favoriteIds.contains(entry.animeId) ||
          (entry.score != null && entry.score! >= 9.0);
      if (isFavoriteOrHighRated) {
        addGenreWeight(genres, 5.0);
      }

      switch (entry.status) {
        case AnimeListStatus.completed:
          excluded.add(entry.animeId);
          addGenreWeight(genres, 3.0);
          if (lastCompleted == null ||
              entry.updatedAt.isAfter(lastCompleted.updatedAt)) {
            lastCompleted = entry;
          }
          break;
        case AnimeListStatus.watching:
          addGenreWeight(genres, 2.0);
          final latest = meta?.latestEpisode ?? meta?.episodesTotal ?? entry.episodesTotal;
          if (latest != null && entry.lastEpisode >= latest) {
            excluded.add(entry.animeId);
          }
          break;
        case AnimeListStatus.planned:
          addGenreWeight(genres, 1.5);
          break;
        case AnimeListStatus.dropped:
          excluded.add(entry.animeId);
          addGenreWeight(genres, -4.0);
          break;
      }

      if (entry.score != null && entry.score! <= 4.0) {
        addGenreWeight(genres, -4.0);
      }
    }

    // Высокая скорость бинджа (>= 3 серий в одной сессии / истории)
    for (final hist in watchHistory) {
      if (hist.episode >= 3) {
        final meta = catalogById[hist.titleId];
        if (meta != null) {
          addGenreWeight(meta.genres, 2.5);
        }
      }
    }

    return UserTasteVector(
      genreWeights: weights,
      excludedIds: excluded,
      lastCompletedEntry: lastCompleted,
    );
  }

  static const Set<String> _heavyActionGenres = {
    'экшен',
    'экшн',
    'боевые искусства',
    'сёнен',
    'сенен',
  };

  static double _heavyActionPenalty(AnimeTitle candidate, UserTasteVector vector) {
    if (!vector.isSoftSliceOfLifeProfile) return 0.0;
    final totalEps = math.max(
      candidate.episodesTotal ?? 0,
      candidate.episodes.length,
    );
    if (totalEps <= 50) return 0.0;
    final isHeavyAction = candidate.genres.any(
      (g) => _heavyActionGenres.contains(g.trim().toLowerCase()),
    );
    return isHeavyAction ? -6.0 : 0.0;
  }

  /// Формирование персонализированной ленты «Для тебя» по правилу 70 / 20 / 10 + Zeigarnik + Post-Finale Echo.
  List<RecommendedAnimePick> generateForYouFeed({
    required List<AnimeTitle> catalogPool,
    required List<UserAnimeEntry> userEntries,
    required List<WatchHistoryItem> watchHistory,
    Set<int> favoriteIds = const {},
    DateTime? now,
    int limit = 16,
  }) {
    if (catalogPool.isEmpty || (userEntries.isEmpty && watchHistory.isEmpty)) {
      return const [];
    }

    final currentNow = now ?? DateTime.now();
    final vector = buildTasteVector(
      catalogPool: catalogPool,
      userEntries: userEntries,
      watchHistory: watchHistory,
      favoriteIds: favoriteIds,
    );

    final catalogById = {for (final a in catalogPool) a.id: a};
    final usedIds = <int>{};
    final picks = <RecommendedAnimePick>[];

    // 1. Zeigarnik Hook: активные тайтлы из «Смотрю», где есть новая серия или пауза
    for (final entry in userEntries) {
      if (entry.status != AnimeListStatus.watching) continue;
      if (vector.excludedIds.contains(entry.animeId)) continue;
      final anime = catalogById[entry.animeId];
      if (anime == null) continue;
      if (usedIds.add(anime.id)) {
        picks.add(
          RecommendedAnimePick(
            anime: anime,
            reasonTag: 'Новинка',
            hook: RecommendationHook.zeigarnik,
            score: 100.0,
            matchPercent: 98,
          ),
        );
      }
      if (picks.length >= 2) break;
    }

    // 2. Post-Finale Emotional Echo: после последнего завершённого аниме
    final lastCompleted = vector.lastCompletedEntry;
    final lastCompletedAnime =
        lastCompleted != null ? catalogById[lastCompleted.animeId] : null;
    if (lastCompleted != null) {
      final targetGenres = (lastCompletedAnime?.genres ?? const <String>[])
          .map((g) => g.trim().toLowerCase())
          .toSet();
      final echoCandidates = <({AnimeTitle anime, double score})>[];

      for (final candidate in catalogPool) {
        if (vector.excludedIds.contains(candidate.id) ||
            usedIds.contains(candidate.id)) {
          continue;
        }
        if (vector.hasPositiveGenres &&
            vector.sharedPositiveGenreCount(candidate.genres) < 1) {
          continue;
        }
        final penalty = _heavyActionPenalty(candidate, vector);
        if (penalty < 0) continue;
        final cGenres =
            candidate.genres.map((g) => g.trim().toLowerCase()).toSet();
        final overlap = targetGenres.intersection(cGenres).length;
        final sameEra = lastCompletedAnime?.year != null &&
            candidate.year != null &&
            (candidate.year! - lastCompletedAnime!.year!).abs() <= 3;

        if (overlap >= 2 || (targetGenres.isEmpty && sameEra) || overlap >= 1 && sameEra) {
          final s = overlap * 3.0 +
              (sameEra ? 1.5 : 0.0) +
              (candidate.score ?? 7.0) * 0.4 +
              penalty;
          echoCandidates.add((anime: candidate, score: s));
        }
      }
      echoCandidates.sort((a, b) => b.score.compareTo(a.score));
      for (final c in echoCandidates.take(2)) {
        if (usedIds.add(c.anime.id)) {
          picks.add(
            RecommendedAnimePick(
              anime: c.anime,
              reasonTag: 'Похожее',
              hook: RecommendationHook.postFinaleEcho,
              score: c.score,
              matchPercent: 94,
            ),
          );
        }
      }
    }

    // Оставшийся бюджет ленты делим по правилу 70% Core Taste / 20% Planned / 10% Circadian
    final remainingSlots = math.max(0, limit - picks.length);
    final plannedQuota = math.max(1, (remainingSlots * 0.2).round());
    final circadianQuota = math.max(1, (remainingSlots * 0.1).round());
    final coreQuota = math.max(1, remainingSlots - plannedQuota - circadianQuota);

    // 4. 20% Forgotten «В планах» Resurfacing
    final plannedCandidates = <({AnimeTitle anime, double score})>[];
    for (final entry in userEntries) {
      if (entry.status != AnimeListStatus.planned) continue;
      if (vector.excludedIds.contains(entry.animeId) ||
          usedIds.contains(entry.animeId)) {
        continue;
      }
      final anime = catalogById[entry.animeId];
      if (anime == null) continue;
      final score = vector.scoreGenres(anime.genres) + (anime.score ?? 7.0) * 0.3;
      plannedCandidates.add((anime: anime, score: score));
    }
    plannedCandidates.sort((a, b) => b.score.compareTo(a.score));
    for (final c in plannedCandidates.take(plannedQuota)) {
      if (usedIds.add(c.anime.id)) {
        picks.add(
          RecommendedAnimePick(
            anime: c.anime,
            reasonTag: 'Из планов',
            hook: RecommendationHook.plannedResurface,
            score: c.score,
            matchPercent: 90,
          ),
        );
      }
    }

    // 5. 10% Circadian & Anti-Bubble Discovery
    final circadianInfo = _circadianBoostConfig(currentNow);
    final circadianCandidates = <({AnimeTitle anime, double score})>[];
    for (final candidate in catalogPool) {
      if (vector.excludedIds.contains(candidate.id) ||
          usedIds.contains(candidate.id)) {
        continue;
      }
      final penalty = _heavyActionPenalty(candidate, vector);
      if (penalty < 0) continue;
      final hasBoostGenre = candidate.genres.any(
        (g) => circadianInfo.genres.contains(g.trim().toLowerCase()),
      );
      if (hasBoostGenre) {
        final s = (candidate.score ?? 7.2) +
            vector.scoreGenres(candidate.genres) * 0.3 +
            penalty;
        circadianCandidates.add((anime: candidate, score: s));
      }
    }
    circadianCandidates.sort((a, b) => b.score.compareTo(a.score));
    for (final c in circadianCandidates.take(circadianQuota)) {
      if (usedIds.add(c.anime.id)) {
        picks.add(
          RecommendedAnimePick(
            anime: c.anime,
            reasonTag: circadianInfo.label,
            hook: RecommendationHook.circadianDiscovery,
            score: c.score,
            matchPercent: 86,
          ),
        );
      }
    }

    // 3. 70% Core Taste Match
    final coreCandidates = <({AnimeTitle anime, double score, String? topGenre})>[];
    for (final candidate in catalogPool) {
      if (vector.excludedIds.contains(candidate.id) ||
          usedIds.contains(candidate.id)) {
        continue;
      }
      if (vector.hasPositiveGenres &&
          vector.sharedPositiveGenreCount(candidate.genres) < 1) {
        continue;
      }
      final tasteScore = vector.scoreGenres(candidate.genres);
      final penalty = _heavyActionPenalty(candidate, vector);
      if (penalty < 0) continue;
      final totalScore = tasteScore + ((candidate.score ?? 7.0) * 0.4) + penalty;
      coreCandidates.add((
        anime: candidate,
        score: totalScore,
        topGenre: vector.topMatchingGenre(candidate.genres),
      ));
    }
    coreCandidates.sort((a, b) => b.score.compareTo(a.score));
    for (final c in coreCandidates.take(coreQuota)) {
      if (usedIds.add(c.anime.id)) {
        final pct = (72 + (c.score * 2.1)).round().clamp(68, 99);
        picks.add(
          RecommendedAnimePick(
            anime: c.anime,
            reasonTag: '$pct% совпадение',
            hook: RecommendationHook.coreTaste,
            score: c.score,
            matchPercent: pct,
          ),
        );
      }
    }

    return picks.take(limit).toList();
  }

  /// Похожие тайтлы для блока «Похожее по вайбу» на экране деталей аниме.
  List<RecommendedAnimePick> recommendSimilarTo({
    required AnimeTitle target,
    required List<AnimeTitle> catalogPool,
    required List<UserAnimeEntry> userEntries,
    required List<WatchHistoryItem> watchHistory,
    int limit = 10,
  }) {
    final vector = buildTasteVector(
      catalogPool: catalogPool,
      userEntries: userEntries,
      watchHistory: watchHistory,
    );
    final blockedIds = <int>{target.id, ...vector.excludedIds};
    for (final entry in userEntries) {
      if (entry.status == AnimeListStatus.watching ||
          entry.status == AnimeListStatus.completed ||
          entry.status == AnimeListStatus.dropped) {
        blockedIds.add(entry.animeId);
      }
    }
    final targetGenres =
        target.genres.map((g) => g.trim().toLowerCase()).where((g) => g.isNotEmpty).toSet();
    final minOverlap = targetGenres.length >= 2 ? 2 : targetGenres.length;
    final candidates = <({AnimeTitle anime, double score, int overlap})>[];

    for (final item in catalogPool) {
      if (blockedIds.contains(item.id)) {
        continue;
      }
      final itemGenres =
          item.genres.map((g) => g.trim().toLowerCase()).where((g) => g.isNotEmpty).toSet();
      final overlap = targetGenres.intersection(itemGenres).length;
      if (targetGenres.isNotEmpty && overlap < minOverlap) continue;
      final penalty = _heavyActionPenalty(item, vector);
      final sameEra = target.year != null &&
          item.year != null &&
          (item.year! - target.year!).abs() <= 4;
      final score = overlap * 3.2 +
          (sameEra ? 1.2 : 0.0) +
          vector.scoreGenres(item.genres) * 0.25 +
          (item.score ?? 7.0) * 0.3 +
          penalty;
      candidates.add((anime: item, score: score, overlap: overlap));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((c) {
      final pct = (74 + c.overlap * 6).clamp(74, 98);
      return RecommendedAnimePick(
        anime: c.anime,
        reasonTag: 'Совпадение $pct% по вайбу',
        hook: RecommendationHook.postFinaleEcho,
        score: c.score,
        matchPercent: pct,
      );
    }).toList();
  }

  ({Set<String> genres, String label}) _circadianBoostConfig(DateTime now) {
    final hour = now.hour;
    if (hour >= 0 && hour < 5) {
      return (
        genres: {'психология', 'психологическое', 'мистика', 'триллер', 'романтика', 'повседневность'},
        label: 'Ночной вайб',
      );
    }
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (isWeekend) {
      return (
        genres: {'приключения', 'фэнтези', 'фильм'},
        label: 'Выбор выходного дня',
      );
    }
    return (
      genres: {'экшен', 'экшн', 'фэнтези', 'комедия'},
      label: 'Вечерний подбор',
    );
  }
}

