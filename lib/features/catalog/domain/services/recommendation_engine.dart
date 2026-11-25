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

  static const Set<String> _nicheGenres = {
    'психологическое',
    'психология',
    'триллер',
    'детектив',
    'сэйнэн',
    'сэйнен',
    'сейнен',
    'исекай',
    'боевые искусства',
    'сверхъестественное',
    'мистика',
    'киберпанк',
    'ужасы',
  };

  static const Set<String> _toneLightGenres = {
    'комедия',
    'романтика',
    'сёдзё',
    'седзе',
    'гарем',
    'этти',
  };

  static String _normalizeFranchiseBase(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    s = s.replaceAll(RegExp(r'\s*\d+\s*сезон.*$'), '');
    s = s.replaceAll(RegExp(r'\s*season\s*\d+.*$'), '');
    s = s.replaceAll(RegExp(r'\s*(ii|iii|iv|v)\s*$'), '');
    s = s.split(':').first.trim();
    s = s.split('—').first.trim();
    return s;
  }

  double _genreWeight(String genre) =>
      _nicheGenres.contains(genre) ? 3.0 : 1.0;

  /// Похожие тайтлы для блока «Похожее по вайбу» на экране деталей аниме.
  List<RecommendedAnimePick> recommendSimilarTo({
    required AnimeTitle target,
    required List<AnimeTitle> catalogPool,
    required List<UserAnimeEntry> userEntries,
    required List<WatchHistoryItem> watchHistory,
    List<AnimeTitle> shikimoriSimilar = const [],
    Set<int> relatedIds = const {},
    int limit = 10,
  }) {
    final vector = buildTasteVector(
      catalogPool: catalogPool,
      userEntries: userEntries,
      watchHistory: watchHistory,
    );
    final blockedIds = <int>{target.id, ...vector.excludedIds, ...relatedIds};
    if (target.shikimoriId != null) {
      blockedIds.add(target.shikimoriId!);
    }
    for (final entry in userEntries) {
      if (entry.status == AnimeListStatus.watching ||
          entry.status == AnimeListStatus.completed ||
          entry.status == AnimeListStatus.dropped) {
        blockedIds.add(entry.animeId);
      }
    }

    final targetBaseRu = _normalizeFranchiseBase(target.russianTitle);
    final targetBaseEn = _normalizeFranchiseBase(target.englishTitle);
    bool isSameFranchise(AnimeTitle item) {
      if (blockedIds.contains(item.id) ||
          (item.shikimoriId != null && blockedIds.contains(item.shikimoriId))) {
        return true;
      }
      final itemBaseRu = _normalizeFranchiseBase(item.russianTitle);
      final itemBaseEn = _normalizeFranchiseBase(item.englishTitle);
      if (targetBaseRu.length >= 4 &&
          itemBaseRu.length >= 4 &&
          (itemBaseRu == targetBaseRu ||
              itemBaseRu.startsWith('$targetBaseRu ') ||
              targetBaseRu.startsWith('$itemBaseRu '))) {
        return true;
      }
      if (targetBaseEn.length >= 4 &&
          itemBaseEn.length >= 4 &&
          (itemBaseEn == targetBaseEn ||
              itemBaseEn.startsWith('$targetBaseEn ') ||
              targetBaseEn.startsWith('$itemBaseEn '))) {
        return true;
      }
      return false;
    }

    final picks = <RecommendedAnimePick>[];
    final seenIds = <int>{};

    // 1. Приоритет: реальные рекомендации сообщества Shikimori (/similar),
    // сопоставленные с локальным каталогом AniLibria для мгновенного воспроизведения.
    if (shikimoriSimilar.isNotEmpty) {
      final catalogByShikiId = <int, AnimeTitle>{};
      final catalogByName = <String, AnimeTitle>{};
      for (final c in catalogPool) {
        if (c.shikimoriId != null && c.shikimoriId! > 0) {
          catalogByShikiId[c.shikimoriId!] = c;
        }
        final ru = c.russianTitle.trim().toLowerCase();
        final en = c.englishTitle.trim().toLowerCase();
        if (ru.isNotEmpty) catalogByName[ru] = c;
        if (en.isNotEmpty) catalogByName[en] = c;
      }

      for (var i = 0; i < shikimoriSimilar.length && picks.length < limit; i++) {
        final shiki = shikimoriSimilar[i];
        if (isSameFranchise(shiki)) continue;
        final matched = catalogByShikiId[shiki.id] ??
            catalogByName[shiki.russianTitle.trim().toLowerCase()] ??
            catalogByName[shiki.englishTitle.trim().toLowerCase()] ??
            shiki;
        if (isSameFranchise(matched) || !seenIds.add(matched.id)) continue;

        final pct = (96 - i * 2).clamp(88, 96);
        picks.add(
          RecommendedAnimePick(
            anime: matched,
            reasonTag: '$pct% схожесть',
            hook: RecommendationHook.postFinaleEcho,
            score: 100.0 - i,
            matchPercent: pct,
          ),
        );
      }
    }

    if (picks.length >= limit) {
      return picks;
    }

    // 2. Строгий локальный фолбэк по взвешенному Jaccard и тональности
    final targetGenres =
        target.genres.map((g) => g.trim().toLowerCase()).where((g) => g.isNotEmpty).toSet();
    final targetHasLightTone = targetGenres.any(_toneLightGenres.contains);
    final minOverlap = targetGenres.length >= 2 ? 2 : targetGenres.length;
    final candidates = <({AnimeTitle anime, double score, double similarity})>[];

    for (final item in catalogPool) {
      if (seenIds.contains(item.id) || isSameFranchise(item)) {
        continue;
      }
      final itemGenres =
          item.genres.map((g) => g.trim().toLowerCase()).where((g) => g.isNotEmpty).toSet();
      final intersection = targetGenres.intersection(itemGenres);
      if (targetGenres.isNotEmpty && intersection.length < minOverlap) {
        continue;
      }

      final union = targetGenres.union(itemGenres);
      double weightedOverlap = 0;
      double weightedUnion = 0;
      for (final g in intersection) {
        weightedOverlap += _genreWeight(g);
      }
      for (final g in union) {
        weightedUnion += _genreWeight(g);
      }
      var similarity = weightedUnion > 0 ? (weightedOverlap / weightedUnion) : 0.0;

      // Штраф за конфликт тональности (комедия/гарем без комедии/романтики в оригинале)
      if (!targetHasLightTone &&
          (itemGenres.contains('комедия') || itemGenres.contains('гарем'))) {
        similarity -= 0.40;
      }
      if (similarity <= 0.15) continue;

      final sameEra = target.year != null &&
          item.year != null &&
          (item.year! - target.year!).abs() <= 4;
      final score = similarity * 10.0 +
          (sameEra ? 1.0 : 0.0) +
          (item.score ?? 7.0) * 0.25 +
          _heavyActionPenalty(item, vector);
      candidates.add((anime: item, score: score, similarity: similarity));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    for (final c in candidates) {
      if (picks.length >= limit) break;
      final pct = (60 + (c.similarity * 35)).round().clamp(60, 95);
      picks.add(
        RecommendedAnimePick(
          anime: c.anime,
          reasonTag: '$pct% схожесть',
          hook: RecommendationHook.postFinaleEcho,
          score: c.score,
          matchPercent: pct,
        ),
      );
    }
    return picks;
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

