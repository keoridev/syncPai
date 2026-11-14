import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_details/data/services/reviews_cache_manager.dart';
import 'package:sync_pai/features/anime_details/data/utils/review_text_sanitizer.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_rating_aggregate.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_review.dart';

void main() {
  group('1. ReviewTextSanitizer Tests', () {
    test('Cleans BBCode tags and links without leaving raw syntax', () {
      const raw =
          '[b]Прекрасный[/b] тайтл! Посмотрел [anime=5114]Стальной алхимик[/anime], главный герой [character=11]Эдвард[/character] супер.';
      final result = ReviewTextSanitizer.sanitize(raw);

      expect(result.text, contains('Прекрасный тайтл! Посмотрел Стальной алхимик, главный герой Эдвард супер.'));
      expect(result.text.contains('[b]'), isFalse);
      expect(result.text.contains('[/b]'), isFalse);
      expect(result.text.contains('[anime'), isFalse);
      expect(result.text.contains('[character'), isFalse);
      expect(result.containsSpoiler, isFalse);
    });

    test('Correctly identifies spoilers and extracts spoiler block', () {
      const raw = 'Отличное начало, но [spoiler=Сюжет]в конце все погибают[/spoiler], будьте осторожны.';
      final result = ReviewTextSanitizer.sanitize(raw);

      expect(result.containsSpoiler, isTrue);
      expect(result.text, contains('[Спойлер: в конце все погибают]'));
      expect(result.text.contains('[/spoiler]'), isFalse);
    });

    test('Decodes HTML entities and strips HTML tags', () {
      const raw = 'Первый сезон &quot;шедевр&quot;&lt;br/&gt;&lt;p&gt;Второй &amp; третий тоже хороши.&lt;/p&gt;';
      final result = ReviewTextSanitizer.sanitize(raw);

      expect(result.text, contains('Первый сезон "шедевр"'));
      expect(result.text, contains('Второй & третий тоже хороши.'));
      expect(result.text.contains('&quot;'), isFalse);
      expect(result.text.contains('&lt;'), isFalse);
      expect(result.text.contains('&amp;'), isFalse);
    });
  });

  group('2. AnimeReview & AnimeRatingAggregate Domain Models', () {
    test('AnimeReview correctly maps scores to sentiments', () {
      expect(ReviewSentiment.fromScore(9.5), equals(ReviewSentiment.positive));
      expect(ReviewSentiment.fromScore(7.0), equals(ReviewSentiment.positive));
      expect(ReviewSentiment.fromScore(6.5), equals(ReviewSentiment.neutral));
      expect(ReviewSentiment.fromScore(4.0), equals(ReviewSentiment.negative));
      expect(ReviewSentiment.fromScore(null), equals(ReviewSentiment.neutral));
    });

    test('AnimeReview JSON serialization round-trip', () {
      final review = AnimeReview(
        id: 'test_123',
        source: ReviewSource.syncpai,
        authorName: 'OtakuMaster',
        authorAvatarUrl: 'https://syncpai.app/avatar.png',
        score: 9.0,
        sentiment: ReviewSentiment.positive,
        content: 'Потрясающее аниме!',
        containsSpoiler: false,
        createdAt: DateTime(2026, 11, 14, 12, 0),
        likes: 42,
      );

      final json = review.toJson();
      final restored = AnimeReview.fromJson(json);

      expect(restored.id, equals(review.id));
      expect(restored.source, equals(ReviewSource.syncpai));
      expect(restored.authorName, equals(review.authorName));
      expect(restored.score, equals(9.0));
      expect(restored.sentiment, equals(ReviewSentiment.positive));
      expect(restored.content, equals(review.content));
      expect(restored.likes, equals(42));
    });

    test('AnimeRatingAggregate calculates sentiment percentages and overall score', () {
      const aggregate = AnimeRatingAggregate(
        syncpaiScore: 9.4,
        syncpaiVotesCount: 50,
        shikimoriScore: 9.0,
        shikimoriVotesCount: 10000,
        malScore: 8.8,
        malVotesCount: 25000,
        positiveCount: 80,
        neutralCount: 15,
        negativeCount: 5,
      );

      expect(aggregate.totalSentimentCount, equals(100));
      expect(aggregate.positivePercent, equals(80.0));
      expect(aggregate.neutralPercent, equals(15.0));
      expect(aggregate.negativePercent, equals(5.0));
      expect(aggregate.overallAverageScore, closeTo(9.1, 0.1));
      expect(AnimeRatingAggregate.formatVotesCount(25000), equals('25K'));
      expect(AnimeRatingAggregate.formatVotesCount(1200000), equals('1.2M'));
    });
  });

  group('3. ReviewsCacheManager 6-Hour TTL & Invalidation', () {
    test('Returns cached bundle within TTL and invalidates properly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = ReviewsCacheManager(prefs);

      const testKey = 'id_5114';
      final bundle = CachedReviewsBundle(
        reviews: [
          AnimeReview(
            id: 'rev_1',
            source: ReviewSource.shikimori,
            authorName: 'Tester',
            score: 9.0,
            sentiment: ReviewSentiment.positive,
            content: 'Круто',
            createdAt: DateTime.now(),
          ),
        ],
        aggregate: const AnimeRatingAggregate(shikimoriScore: 9.1),
        cachedAt: DateTime.now(),
      );

      // 1. Сохраняем в кэш
      await cache.put(testKey, bundle);

      // 2. Считываем из кэша
      final retrieved = cache.get(testKey);
      expect(retrieved, isNotNull);
      expect(retrieved!.reviews.length, equals(1));
      expect(retrieved.aggregate.shikimoriScore, equals(9.1));

      // 3. Инвалидируем кэш (например, после публикации отзыва)
      await cache.invalidate(testKey);
      final afterInvalidate = cache.get(testKey);
      expect(afterInvalidate, isNull);
    });

    test('Rejects expired bundle beyond 6-hour TTL', () {
      final oldBundle = CachedReviewsBundle(
        reviews: const [],
        aggregate: const AnimeRatingAggregate(),
        cachedAt: DateTime.now().subtract(const Duration(hours: 7)),
      );

      expect(oldBundle.isExpired, isTrue);

      final freshBundle = CachedReviewsBundle(
        reviews: const [],
        aggregate: const AnimeRatingAggregate(),
        cachedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      expect(freshBundle.isExpired, isFalse);
    });
  });
}

