import '../../domain/entities/anime_review.dart';
import '../../../catalog/domain/entities/anime_title.dart';

abstract final class AnimeReviewsProvider {
  /// Получить отзывы и рецензии для выбранного тайтла (fallback при отсутствии сети)
  static List<AnimeReview> getReviewsForTitle(AnimeTitle title) {
    final titleName = title.displayTitle;
    final genres = title.genres.join(', ');

    return [
      AnimeReview(
        id: 'rev_1',
        source: ReviewSource.shikimori,
        authorName: 'Sensei_Critic',
        authorAvatarUrl: null,
        score: 9.6,
        sentiment: ReviewSentiment.positive,
        content: '«$titleName» — это редкий шедевр в жанре $genres. Великолепная анимация, глубокая режиссура и саундтрек от которого мурашки по коже. Опенинг задает идеальный темп с первых секунд.',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        likes: 142,
      ),
      AnimeReview(
        id: 'rev_2',
        source: ReviewSource.anilibria,
        authorName: 'AniLover99',
        authorAvatarUrl: null,
        score: 9.1,
        sentiment: ReviewSentiment.positive,
        content: 'Озвучка на высоте! Персонажи живые, нет затянутых филлеров. Серии пролетают на одном дыхании, особенно эндинг трогает за душу. Обязательно к просмотру в дуэте с другом.',
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        likes: 89,
      ),
      AnimeReview(
        id: 'rev_3',
        source: ReviewSource.mal,
        authorName: 'OtakuChronicles',
        authorAvatarUrl: null,
        score: 8.8,
        sentiment: ReviewSentiment.positive,
        content: 'Один из сильнейших тайтлов года. Рисовка задников просто завораживает. Динамика сюжета держит в напряжении до самого конца.',
        createdAt: DateTime.now().subtract(const Duration(days: 14)),
        likes: 67,
      ),
    ];
  }
}
