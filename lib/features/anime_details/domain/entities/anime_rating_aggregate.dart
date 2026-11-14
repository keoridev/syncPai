import 'package:equatable/equatable.dart';

/// Агрегированные оценки и распределение тональности отзывов с различных платформ
class AnimeRatingAggregate extends Equatable {
  final double? syncpaiScore;
  final int syncpaiVotesCount;
  final double? shikimoriScore;
  final int shikimoriVotesCount;
  final double? malScore;
  final int malVotesCount;

  final int positiveCount;
  final int neutralCount;
  final int negativeCount;

  const AnimeRatingAggregate({
    this.syncpaiScore,
    this.syncpaiVotesCount = 0,
    this.shikimoriScore,
    this.shikimoriVotesCount = 0,
    this.malScore,
    this.malVotesCount = 0,
    this.positiveCount = 0,
    this.neutralCount = 0,
    this.negativeCount = 0,
  });

  /// Общее число проанализированных отзывов/рецензий
  int get totalSentimentCount => positiveCount + neutralCount + negativeCount;

  /// Процент положительных отзывов (0.0 - 100.0)
  double get positivePercent {
    if (totalSentimentCount == 0) return 0.0;
    return (positiveCount / totalSentimentCount) * 100.0;
  }

  /// Процент нейтральных отзывов (0.0 - 100.0)
  double get neutralPercent {
    if (totalSentimentCount == 0) return 0.0;
    return (neutralCount / totalSentimentCount) * 100.0;
  }

  /// Процент критических/отрицательных отзывов (0.0 - 100.0)
  double get negativePercent {
    if (totalSentimentCount == 0) return 0.0;
    return (negativeCount / totalSentimentCount) * 100.0;
  }

  /// Средневзвешенная общая оценка
  double get overallAverageScore {
    final scores = <double>[];
    if (syncpaiScore != null && syncpaiScore! > 0) scores.add(syncpaiScore!);
    if (shikimoriScore != null && shikimoriScore! > 0) scores.add(shikimoriScore!);
    if (malScore != null && malScore! > 0) scores.add(malScore!);

    if (scores.isEmpty) return 8.8;
    final sum = scores.reduce((a, b) => a + b);
    return double.parse((sum / scores.length).toStringAsFixed(1));
  }

  /// Форматирование числа голосов (например, "48.2K" или "1.2M")
  static String formatVotesCount(int count) {
    if (count <= 0) return '0';
    if (count < 1000) return '$count';
    if (count < 1000000) {
      final k = count / 1000.0;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}K';
    }
    final m = count / 1000000.0;
    return '${m.toStringAsFixed(1)}M';
  }

  Map<String, dynamic> toJson() {
    return {
      'syncpai_score': syncpaiScore,
      'syncpai_votes_count': syncpaiVotesCount,
      'shikimori_score': shikimoriScore,
      'shikimori_votes_count': shikimoriVotesCount,
      'mal_score': malScore,
      'mal_votes_count': malVotesCount,
      'positive_count': positiveCount,
      'neutral_count': neutralCount,
      'negative_count': negativeCount,
    };
  }

  factory AnimeRatingAggregate.fromJson(Map<String, dynamic> json) {
    return AnimeRatingAggregate(
      syncpaiScore: (json['syncpai_score'] as num?)?.toDouble(),
      syncpaiVotesCount: json['syncpai_votes_count'] as int? ?? 0,
      shikimoriScore: (json['shikimori_score'] as num?)?.toDouble(),
      shikimoriVotesCount: json['shikimori_votes_count'] as int? ?? 0,
      malScore: (json['mal_score'] as num?)?.toDouble(),
      malVotesCount: json['mal_votes_count'] as int? ?? 0,
      positiveCount: json['positive_count'] as int? ?? 0,
      neutralCount: json['neutral_count'] as int? ?? 0,
      negativeCount: json['negative_count'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        syncpaiScore,
        syncpaiVotesCount,
        shikimoriScore,
        shikimoriVotesCount,
        malScore,
        malVotesCount,
        positiveCount,
        neutralCount,
        negativeCount,
      ];
}

