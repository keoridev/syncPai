import 'package:flutter/foundation.dart';
import '../../../../app/di/injection.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';

/// Локальный легковесный скорер аффинити/предпочтений пользователя для Anime Match.
/// Строит вектор вкусов (taste vector) по пользовательским закладкам (user_anime_lists):
/// - «Просмотрено» (completed): +2.0
/// - «Смотрю» (watching): +1.5
/// - «В планах» (planned): +1.0
/// - «Брошено» (dropped): -2.0
///
/// Комбинирует оценку Shikimori (рейтинг) с жанровым аффинити-скором,
/// гарантируя, что свайпы в AnimeMatchScreen в первую очередь предлагают
/// тайтлы, идеально соответствующие персональным вкусам пользователя.
class MatchRecommendationScorer {
  static const double weightCompleted = 2.0; // «Просмотрено»
  static const double weightWatching = 1.5;   // «Смотрю»
  static const double weightPlanned = 1.0;    // «В планах»
  static const double weightDropped = -2.0;   // «Брошено»

  /// Получить вес для статуса тайтла в списках пользователя
  static double getWeightForStatus(AnimeListStatus status) {
    switch (status) {
      case AnimeListStatus.completed:
        return weightCompleted;
      case AnimeListStatus.watching:
        return weightWatching;
      case AnimeListStatus.planned:
        return weightPlanned;
      case AnimeListStatus.dropped:
        return weightDropped;
    }
  }

  /// Построение вектора предпочтений пользователя: Map<Жанр, Скор>
  static Map<String, double> buildTasteVector({
    required List<UserAnimeEntry> userEntries,
    Map<int, List<String>>? knownTitleGenres,
  }) {
    final tasteVector = <String, double>{};
    if (userEntries.isEmpty) return tasteVector;

    for (final entry in userEntries) {
      final weight = getWeightForStatus(entry.status);
      final genres = knownTitleGenres?[entry.animeId] ?? const <String>[];
      for (final g in genres) {
        final key = g.trim().toLowerCase();
        if (key.isNotEmpty) {
          tasteVector[key] = (tasteVector[key] ?? 0.0) + weight;
        }
      }
    }
    return tasteVector;
  }

  /// Расчет аффинити-скора конкретного тайтла по его жанрам
  static double calculateAffinityScore(
    AnimeTitle title,
    Map<String, double> tasteVector,
  ) {
    if (tasteVector.isEmpty || title.genres.isEmpty) return 0.0;

    double affinity = 0.0;
    for (final genre in title.genres) {
      final key = genre.trim().toLowerCase();
      if (tasteVector.containsKey(key)) {
        affinity += tasteVector[key]!;
      }
    }
    return affinity;
  }

  /// Расчет итогового комбинированного скора (Shikimori Rating + Genre Affinity)
  static double calculateTotalScore({
    required AnimeTitle title,
    required Map<String, double> tasteVector,
    Set<int>? completedOrDroppedIds,
  }) {
    // 1. Базовый рейтинг Shikimori (обычно от 1.0 до 10.0, дефолт 7.5)
    final double rating = title.score ?? 7.5;

    // 2. Жанровый аффинити-скор пользователя
    final double affinity = calculateAffinityScore(title, tasteVector);

    // 3. Комбинированный вес: рейтинг Shikimori + персональный жанровый аффинити-скор
    double score = rating + affinity;

    // 4. Понижаем приоритет тайтлов, которые пользователь уже полностью посмотрел или бросил,
    // чтобы колода свайпов фокусировалась на новых неизведанных тайтлах
    if (completedOrDroppedIds != null) {
      if (completedOrDroppedIds.contains(title.id) ||
          (title.shikimoriId != null && completedOrDroppedIds.contains(title.shikimoriId))) {
        score -= 5.0;
      }
    }

    return score;
  }

  /// Ранжирование колоды кандидатов для Anime Match
  static List<AnimeTitle> rankDeck({
    required List<AnimeTitle> candidateTitles,
    required List<UserAnimeEntry> userEntries,
    Map<int, List<String>>? knownTitleGenres,
  }) {
    if (candidateTitles.isEmpty) return candidateTitles;

    final genresMap = Map<int, List<String>>.from(knownTitleGenres ?? const {});
    for (final title in candidateTitles) {
      if (title.genres.isNotEmpty) {
        genresMap[title.id] = title.genres;
        if (title.shikimoriId != null && title.shikimoriId! > 0) {
          genresMap[title.shikimoriId!] = title.genres;
        }
      }
    }

    // Дополняем жанры из кэша каталога, если доступен
    try {
      if (getIt.isRegistered<CatalogCubit>()) {
        final catState = getIt<CatalogCubit>().state;
        if (catState is CatalogLoaded) {
          for (final t in catState.titles) {
            if (t.genres.isNotEmpty) {
              genresMap[t.id] = t.genres;
              if (t.shikimoriId != null && t.shikimoriId! > 0) {
                genresMap[t.shikimoriId!] = t.genres;
              }
            }
          }
        }
      }
    } catch (_) {}

    final tasteVector = buildTasteVector(
      userEntries: userEntries,
      knownTitleGenres: genresMap,
    );

    final completedOrDroppedIds = <int>{};
    for (final e in userEntries) {
      if (e.status == AnimeListStatus.completed || e.status == AnimeListStatus.dropped) {
        completedOrDroppedIds.add(e.animeId);
      }
    }

    final ranked = List<AnimeTitle>.from(candidateTitles);
    ranked.sort((a, b) {
      final scoreA = calculateTotalScore(
        title: a,
        tasteVector: tasteVector,
        completedOrDroppedIds: completedOrDroppedIds,
      );
      final scoreB = calculateTotalScore(
        title: b,
        tasteVector: tasteVector,
        completedOrDroppedIds: completedOrDroppedIds,
      );
      return scoreB.compareTo(scoreA); // По убыванию скора
    });

    debugPrint(
      '[MatchRecommendationScorer] Колода отранжирована (${ranked.length} тайтлов). '
      'Топ-1: «${ranked.first.displayTitle}», '
      'Taste Vector: $tasteVector',
    );

    return ranked;
  }

  /// Автоматическое ранжирование колоды с получением списков из `getIt<AnimeListCubit>()`
  static List<AnimeTitle> rankDeckAuto(List<AnimeTitle> candidateTitles) {
    if (candidateTitles.isEmpty) return candidateTitles;
    List<UserAnimeEntry> userEntries = const [];
    try {
      if (getIt.isRegistered<AnimeListCubit>()) {
        userEntries = getIt<AnimeListCubit>().state.allEntries;
      }
    } catch (_) {}

    return rankDeck(
      candidateTitles: candidateTitles,
      userEntries: userEntries,
    );
  }
}
