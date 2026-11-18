import '../../../anime_lists/domain/entities/user_anime_entry.dart';

class SharedFavoriteHighlight {
  final int animeId;
  final String title;
  final String posterUrl;
  final double combinedScore;

  const SharedFavoriteHighlight({
    required this.animeId,
    required this.title,
    required this.posterUrl,
    required this.combinedScore,
  });
}

class TasteCompatibilityResult {
  final int percentage;
  final int sharedCount;
  final bool hasEnoughData;
  final List<SharedFavoriteHighlight> highlights;

  const TasteCompatibilityResult({
    required this.percentage,
    required this.sharedCount,
    required this.hasEnoughData,
    this.highlights = const [],
  });
}

/// Клиентский калькулятор совпадения вкусов по `user_anime_lists` (0-100%).
class TasteCompatibilityCalculator {
  static TasteCompatibilityResult calculate(
    List<UserAnimeEntry> myList,
    List<UserAnimeEntry> theirList,
  ) {
    if (myList.isEmpty || theirList.isEmpty) {
      return const TasteCompatibilityResult(
        percentage: 0,
        sharedCount: 0,
        hasEnoughData: false,
      );
    }

    final myMap = <int, UserAnimeEntry>{
      for (final e in myList) e.animeId: e,
    };

    double totalPairScore = 0.0;
    final highlights = <SharedFavoriteHighlight>[];

    for (final theirs in theirList) {
      final mine = myMap[theirs.animeId];
      if (mine == null) continue;

      double statusAgreement;
      if (mine.status == theirs.status &&
          (mine.status == AnimeListStatus.completed ||
              mine.status == AnimeListStatus.watching)) {
        statusAgreement = 1.0;
      } else if (mine.status == theirs.status) {
        statusAgreement = 0.85;
      } else if ((mine.status == AnimeListStatus.completed ||
              mine.status == AnimeListStatus.watching) &&
          (theirs.status == AnimeListStatus.completed ||
              theirs.status == AnimeListStatus.watching)) {
        statusAgreement = 0.72;
      } else if (mine.status == AnimeListStatus.dropped ||
          theirs.status == AnimeListStatus.dropped) {
        statusAgreement = 0.25;
      } else {
        statusAgreement = 0.55;
      }

      final myScore = mine.score ?? 0;
      final theirScore = theirs.score ?? 0;
      double pairScore;
      if (myScore > 0 && theirScore > 0) {
        final proximity = (10 - (myScore - theirScore).abs()).clamp(0, 10) / 10.0;
        pairScore = 0.45 * statusAgreement + 0.55 * proximity;
      } else {
        pairScore = statusAgreement;
      }

      totalPairScore += pairScore;
      final combined = (myScore + theirScore) > 0
          ? (myScore + theirScore) / 2.0 + statusAgreement
          : statusAgreement * 5.0;

      final theirPoster = theirs.posterUrl ?? '';
      final myPoster = mine.posterUrl ?? '';

      highlights.add(
        SharedFavoriteHighlight(
          animeId: theirs.animeId,
          title: theirs.cleanTitleRu.isNotEmpty
              ? theirs.cleanTitleRu
              : mine.cleanTitleRu,
          posterUrl: theirPoster.isNotEmpty ? theirPoster : myPoster,
          combinedScore: combined,
        ),
      );
    }

    final sharedCount = highlights.length;
    if (sharedCount < 2) {
      return TasteCompatibilityResult(
        percentage: 0,
        sharedCount: sharedCount,
        hasEnoughData: false,
        highlights: highlights,
      );
    }

    highlights.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
    final avgSim = totalPairScore / sharedCount;
    final overlapFactor = (sharedCount / 6.0).clamp(0.55, 1.0);
    final percentage =
        ((avgSim * 84.0) + (overlapFactor * 14.0)).round().clamp(12, 98);

    return TasteCompatibilityResult(
      percentage: percentage,
      sharedCount: sharedCount,
      hasEnoughData: true,
      highlights: highlights.take(3).toList(),
    );
  }
}

