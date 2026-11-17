import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/services/episode_prefetch_service.dart';
import 'package:sync_pai/features/sync_room/domain/services/match_recommendation_scorer.dart';
import 'package:sync_pai/features/sync_room/presentation/cubit/coop_match_cubit.dart';

void main() {
  group('EpisodePrefetchService Tests', () {
    late EpisodePrefetchService service;

    setUp(() {
      service = EpisodePrefetchService.instance;
      service.clear();
    });

    test('prefetches and caches direct next episode stream URL', () async {
      const title = AnimeTitle(
        id: 777,
        code: 'solo-leveling',
        russianTitle: 'Поднятие уровня в одиночку',
        englishTitle: 'Solo Leveling',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Экшен', 'Фэнтези'],
        description: 'Слабейший охотник Сон Джин-у',
        status: 'Онгоинг',
        episodes: [
          EpisodeItem(
            episode: 1,
            name: 'Серия 1',
            fhdUrl: 'https://cache.libria.fun/ep1/1080.m3u8',
            hdUrl: 'https://cache.libria.fun/ep1/720.m3u8',
            sdUrl: 'https://cache.libria.fun/ep1/480.m3u8',
          ),
          EpisodeItem(
            episode: 2,
            name: 'Серия 2',
            fhdUrl: 'https://cache.libria.fun/ep2/1080.m3u8',
            hdUrl: 'https://cache.libria.fun/ep2/720.m3u8',
            sdUrl: 'https://cache.libria.fun/ep2/480.m3u8',
          ),
        ],
      );

      final nextEp = title.episodes[1];

      // До предзагрузки кэш пуст
      expect(
        service.getPrefetchedStreamUrl(title.id, nextEp.episode, PlayerQuality.fhd),
        isNull,
      );

      // Запуск предзагрузки следующего эпизода
      final prefetched = await service.prefetchNext(
        title: title,
        currentEpisode: title.episodes[0],
        nextEpisode: nextEp,
        quality: PlayerQuality.fhd,
      );

      expect(prefetched, equals('https://cache.libria.fun/ep2/1080.m3u8'));
      expect(
        service.getPrefetchedStreamUrl(title.id, nextEp.episode, PlayerQuality.fhd),
        equals('https://cache.libria.fun/ep2/1080.m3u8'),
      );
    });

    test('supports different quality profiles for prefetch (720p HD and 1080p FHD)', () async {
      const title = AnimeTitle(
        id: 888,
        code: 'frieren',
        russianTitle: 'Провожающая в последний путь Фрирен',
        englishTitle: 'Sousou no Frieren',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Приключения'],
        description: 'Приключения эльфийки',
        status: 'Завершен',
        episodes: [
          EpisodeItem(episode: 1, name: 'Серия 1'),
          EpisodeItem(
            episode: 2,
            name: 'Серия 2',
            fhdUrl: 'https://cdn.libria.fun/frieren/ep2_1080.m3u8',
            hdUrl: 'https://cdn.libria.fun/frieren/ep2_720.m3u8',
          ),
        ],
      );

      // Предзагрузка в 720p
      final hdUrl = await service.prefetchNext(
        title: title,
        currentEpisode: title.episodes[0],
        nextEpisode: title.episodes[1],
        quality: PlayerQuality.hd,
      );

      expect(hdUrl, equals('https://cdn.libria.fun/frieren/ep2_720.m3u8'));
      expect(
        service.getPrefetchedStreamUrl(title.id, 2, PlayerQuality.hd),
        equals('https://cdn.libria.fun/frieren/ep2_720.m3u8'),
      );
      // FHD кэш пока пуст
      expect(service.getPrefetchedStreamUrl(title.id, 2, PlayerQuality.fhd), isNull);
    });
  });

  group('MatchRecommendationScorer Tests', () {
    final now = DateTime.now();

    test('verifies accurate genre weights per status', () {
      expect(MatchRecommendationScorer.getWeightForStatus(AnimeListStatus.completed), equals(2.0));
      expect(MatchRecommendationScorer.getWeightForStatus(AnimeListStatus.watching), equals(1.5));
      expect(MatchRecommendationScorer.getWeightForStatus(AnimeListStatus.planned), equals(1.0));
      expect(MatchRecommendationScorer.getWeightForStatus(AnimeListStatus.dropped), equals(-2.0));
    });

    test('builds taste vector accurately based on user lists', () {
      final userEntries = [
        UserAnimeEntry(
          id: '1',
          userId: 'u1',
          animeId: 101, // Экшен, Сёнэн
          titleRu: 'Магическая битва',
          status: AnimeListStatus.completed, // +2.0
          updatedAt: now,
        ),
        UserAnimeEntry(
          id: '2',
          userId: 'u1',
          animeId: 102, // Экшен, Фэнтези
          titleRu: 'Поднятие уровня в одиночку',
          status: AnimeListStatus.watching, // +1.5
          updatedAt: now,
        ),
        UserAnimeEntry(
          id: '3',
          userId: 'u1',
          animeId: 103, // Романтика, Повседневность
          titleRu: 'Хоримия',
          status: AnimeListStatus.dropped, // -2.0
          updatedAt: now,
        ),
      ];

      final knownGenres = {
        101: ['Экшен', 'Сёнэн'],
        102: ['Экшен', 'Фэнтези'],
        103: ['Романтика', 'Повседневность'],
      };

      final tasteVector = MatchRecommendationScorer.buildTasteVector(
        userEntries: userEntries,
        knownTitleGenres: knownGenres,
      );

      // Экшен: +2.0 + 1.5 = +3.5
      expect(tasteVector['экшен'], equals(3.5));
      // Сёнэн: +2.0
      expect(tasteVector['сёнэн'], equals(2.0));
      // Фэнтези: +1.5
      expect(tasteVector['фэнтези'], equals(1.5));
      // Романтика: -2.0
      expect(tasteVector['романтика'], equals(-2.0));
      // Повседневность: -2.0
      expect(tasteVector['повседневность'], equals(-2.0));
    });

    test('ranks candidate deck prioritizing user taste vector and Shikimori score', () {
      final userEntries = [
        UserAnimeEntry(
          id: '1',
          userId: 'u1',
          animeId: 501,
          titleRu: 'Атака титанов',
          status: AnimeListStatus.completed, // +2.0 к Экшен и Драма
          updatedAt: now,
        ),
        UserAnimeEntry(
          id: '2',
          userId: 'u1',
          animeId: 502,
          titleRu: 'Скучный романтический тайтл',
          status: AnimeListStatus.dropped, // -2.0 к Романтика
          updatedAt: now,
        ),
      ];

      final knownGenres = {
        501: ['Экшен', 'Драма'],
        502: ['Романтика'],
      };

      const titleAction = AnimeTitle(
        id: 1,
        code: 'vinland',
        russianTitle: 'Сага о Винланде',
        englishTitle: 'Vinland Saga',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        score: 8.7,
        genres: ['Экшен', 'Драма'],
        description: 'Викинги и драма',
        status: 'Завершен',
      );

      const titleRomance = AnimeTitle(
        id: 2,
        code: 'romance-anime',
        russianTitle: 'Романтическая комедия',
        englishTitle: 'Romance Comedy',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        score: 8.8, // чуть выше рейтинг, но жанр брошен пользователем
        genres: ['Романтика'],
        description: 'Любовь в школе',
        status: 'Завершен',
      );

      const titleNeutral = AnimeTitle(
        id: 3,
        code: 'neutral-sci-fi',
        russianTitle: 'Космический рубеж',
        englishTitle: 'Space Sci-Fi',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        score: 7.9,
        genres: ['Фантастика'],
        description: 'Космос',
        status: 'Завершен',
      );

      final candidates = [titleRomance, titleNeutral, titleAction];

      final ranked = MatchRecommendationScorer.rankDeck(
        candidateTitles: candidates,
        userEntries: userEntries,
        knownTitleGenres: knownGenres,
      );

      // titleAction должен стать первым благодаря высокому позитивному скору (+2.0 Экшен + 2.0 Драма)
      expect(ranked.first.id, equals(titleAction.id));
      expect(ranked.first.russianTitle, equals('Сага о Винланде'));

      // titleRomance опускается вниз из-за штрафа -2.0 за брошенный жанр
      expect(ranked.last.id, equals(titleRomance.id));
    });

    test('CoopMatchCubit initializes with ranked deck based on user taste vector', () {
      final userEntries = [
        UserAnimeEntry(
          id: '1',
          userId: 'u1',
          animeId: 10,
          titleRu: 'Магическая битва',
          status: AnimeListStatus.completed,
          updatedAt: now,
        ),
      ];

      const likedAnime = AnimeTitle(
        id: 10,
        code: 'jujutsu',
        russianTitle: 'Магическая битва',
        englishTitle: 'Jujutsu Kaisen',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        score: 8.6,
        genres: ['Сёнэн', 'Мистика'],
        description: '',
        status: 'Онгоинг',
      );

      const candidateFav = AnimeTitle(
        id: 20,
        code: 'chainsaw',
        russianTitle: 'Человек-бензопила',
        englishTitle: 'Chainsaw Man',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        score: 8.5,
        genres: ['Сёнэн', 'Мистика'],
        description: '',
        status: 'Онгоинг',
      );

      const candidateOther = AnimeTitle(
        id: 30,
        code: 'cooking',
        russianTitle: 'Кулинарные поединки',
        englishTitle: 'Food Wars',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        score: 8.2,
        genres: ['Кулинария'],
        description: '',
        status: 'Завершен',
      );

      final cubit = CoopMatchCubit(
        initialDeck: [candidateOther, candidateFav, likedAnime],
        userEntries: userEntries,
      );

      // candidateFav (Сёнэн + Мистика) должен быть в топе колоды для свайпов
      expect(cubit.state.deck.first.id, equals(candidateFav.id));
      expect(cubit.state.currentTitle?.id, equals(candidateFav.id));
      cubit.close();
    });
  });
}
