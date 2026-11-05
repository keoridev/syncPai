import '../../domain/entities/anime_review.dart';
import '../../../catalog/domain/entities/anime_title.dart';

abstract final class AnimeReviewsProvider {
  /// Получить отзывы и рецензии для выбранного тайтла
  static List<AnimeReview> getReviewsForTitle(AnimeTitle title) {
    final titleName = title.displayTitle;
    final genres = title.genres.join(', ');

    return [
      AnimeReview(
        id: 'rev_1',
        author: 'Sensei_Critic',
        avatar: '🦊',
        score: 9.6,
        source: 'Shikimori',
        date: '3 дня назад',
        likes: 142,
        text: '«$titleName» — это редкий шедевр в жанре $genres. Великолепная анимация, глубокая режиссура и саундтрек от которого мурашки по коже. Опенинг задает идеальный темп с первых секунд.',
      ),
      AnimeReview(
        id: 'rev_2',
        author: 'AniLover99',
        avatar: '🐱',
        score: 9.1,
        source: 'AniLibria',
        date: 'Неделю назад',
        likes: 89,
        text: 'Озвучка на высоте! Персонажи живые, нет затянутых филлеров. Серии пролетают на одном дыхании, особенно эндинг трогает за душу. Обязательно к просмотру в дуэте с другом.',
      ),
      AnimeReview(
        id: 'rev_3',
        author: 'OtakuChronicles',
        avatar: '🐼',
        score: 8.8,
        source: 'MyAnimeList',
        date: '2 недели назад',
        likes: 67,
        text: 'Один из сильнейших тайтлов года. Рисовка задников просто завораживает. Динамика сюжета держит в напряжении до самого конца.',
      ),
    ];
  }
}

