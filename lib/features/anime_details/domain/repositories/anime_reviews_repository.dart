import '../../../catalog/domain/entities/anime_title.dart';
import '../entities/anime_rating_aggregate.dart';
import '../entities/anime_review.dart';

class ReviewsAggregateResult {
  final List<AnimeReview> reviews;
  final AnimeRatingAggregate aggregate;
  final int? resolvedShikimoriId;
  final int? resolvedMalId;

  const ReviewsAggregateResult({
    required this.reviews,
    required this.aggregate,
    this.resolvedShikimoriId,
    this.resolvedMalId,
  });
}

abstract class AnimeReviewsRepository {
  Future<ReviewsAggregateResult> getReviewsAndRatings(AnimeTitle title);

  Future<AnimeReview> submitReview({
    required AnimeTitle title,
    required String userId,
    required String userName,
    String? userAvatar,
    required double score,
    required String content,
    required bool containsSpoiler,
  });
}
