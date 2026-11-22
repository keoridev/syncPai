import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/services/recommendation_engine.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/for_you_recommendations_shelf.dart';
import 'package:sync_pai/features/watch_history/domain/entities/watch_history_item.dart';

AnimeTitle _makeTitle(
  int id,
  String name, {
  List<String> genres = const ['Экшен', 'Фэнтези'],
  int year = 2025,
  double score = 8.4,
}) {
  return AnimeTitle(
    id: id,
    code: 'anime-$id',
    russianTitle: name,
    englishTitle: name,
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: genres,
    description: '',
    status: 'released',
    year: year,
    score: score,
    episodesTotal: 12,
    latestEpisode: 12,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]',
    unicode: true,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RecommendationEngine.instance.resetForTest();
  });

  group('RecommendationEngine behavioral psychology scoring', () {
    test('excludes completed/dropped, resurfaces planned, and triggers Post-Finale Echo & Zeigarnik',
        () {
      final engine = RecommendationEngine.instance;
      final now = DateTime(2026, 11, 23, 2, 0); // Late night -> Ночной вайб

      final pool = [
        _makeTitle(1, 'Completed Hero', genres: ['Экшен', 'Фэнтези']),
        _makeTitle(2, 'Dropped Bore', genres: ['Спорт']),
        _makeTitle(3, 'Watching Now', genres: ['Экшен', 'Фэнтези']),
        _makeTitle(4, 'Planned Gem', genres: ['Фэнтези', 'Приключения']),
        _makeTitle(5, 'Echo Sequel Match', genres: ['Экшен', 'Фэнтези'], year: 2025),
        _makeTitle(6, 'Night Mystery', genres: ['Психология', 'Мистика'], year: 2024),
        _makeTitle(7, 'Core Taste Match', genres: ['Экшен', 'Фэнтези', 'Комедия']),
      ];

      final entries = [
        UserAnimeEntry(
          id: 'e1',
          userId: 'u1',
          animeId: 1,
          titleRu: 'Completed Hero',
          status: AnimeListStatus.completed,
          lastEpisode: 12,
          episodesTotal: 12,
          score: 9.5,
          updatedAt: DateTime(2026, 11, 22),
        ),
        UserAnimeEntry(
          id: 'e2',
          userId: 'u1',
          animeId: 2,
          titleRu: 'Dropped Bore',
          status: AnimeListStatus.dropped,
          lastEpisode: 2,
          score: 3.0,
          updatedAt: DateTime(2026, 11, 20),
        ),
        UserAnimeEntry(
          id: 'e3',
          userId: 'u1',
          animeId: 3,
          titleRu: 'Watching Now',
          status: AnimeListStatus.watching,
          lastEpisode: 5,
          episodesTotal: 12,
          updatedAt: DateTime(2026, 11, 22),
        ),
        UserAnimeEntry(
          id: 'e4',
          userId: 'u1',
          animeId: 4,
          titleRu: 'Planned Gem',
          status: AnimeListStatus.planned,
          updatedAt: DateTime(2026, 11, 21),
        ),
      ];

      final history = [
        WatchHistoryItem(
          titleId: 3,
          titleName: 'Watching Now',
          posterUrl: '',
          episode: 5,
          positionMs: 120000,
          durationMs: 1400000,
          updatedAt: DateTime(2026, 11, 22),
        ),
      ];

      final picks = engine.generateForYouFeed(
        catalogPool: pool,
        userEntries: entries,
        watchHistory: history,
        now: now,
      );

      final ids = picks.map((p) => p.anime.id).toList();
      expect(ids.contains(1), isFalse); // completed excluded
      expect(ids.contains(2), isFalse); // dropped excluded
      expect(ids.contains(3), isTrue); // Zeigarnik watching
      expect(ids.contains(4), isTrue); // Planned resurfaced
      expect(ids.contains(5), isTrue); // Post-Finale Echo
      expect(ids.contains(6), isTrue); // Late-night circadian discovery

      for (final p in picks) {
        expect(emojiRegex.hasMatch(p.reasonTag), isFalse);
      }

      expect(
        picks.any((p) => p.reasonTag == 'Новая серия • Из «Смотрю»'),
        isTrue,
      );
      expect(
        picks.any((p) => p.reasonTag == 'После «Completed Hero»'),
        isTrue,
      );
      expect(
        picks.any((p) => p.reasonTag == 'Из вашего списка «В планах»'),
        isTrue,
      );
      expect(
        picks.any((p) => p.reasonTag == 'Ночной вайб'),
        isTrue,
      );
    });

    test('dismissRecommendation permanently hides title and penalizes its genres',
        () async {
      final engine = RecommendationEngine.instance;
      final dismissed = _makeTitle(5, 'Echo Sequel Match', genres: ['Экшен', 'Фэнтези']);

      await engine.dismissRecommendation(dismissed);
      expect(engine.hiddenIds.contains(5), isTrue);

      final picks = engine.generateForYouFeed(
        catalogPool: [
          dismissed,
          _makeTitle(6, 'Other', genres: ['Комедия']),
        ],
        userEntries: [
          UserAnimeEntry(
            id: 'e1',
            userId: 'u1',
            animeId: 99,
            titleRu: 'Starter',
            status: AnimeListStatus.planned,
            updatedAt: DateTime(2026, 11, 22),
          ),
        ],
        watchHistory: const [],
      );

      expect(picks.any((p) => p.anime.id == 5), isFalse);
    });

    testWidgets('ForYouRecommendationsShelf renders cards and dismisses via «Не интересно»',
        (tester) async {
      final anime = _makeTitle(10, 'Frieren Beyond');
      AnimeTitle? dismissedItem;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForYouRecommendationsShelf(
              title: 'Для тебя',
              picks: [
                RecommendedAnimePick(
                  anime: anime,
                  reasonTag: 'Совпадение 94% • Фэнтези',
                  hook: RecommendationHook.coreTaste,
                  score: 9.5,
                  matchPercent: 94,
                ),
              ],
              onTitleTap: (_) {},
              onDismissPick: (a) => dismissedItem = a,
            ),
          ),
        ),
      );

      expect(find.text('Для тебя'), findsOneWidget);
      expect(find.text('Совпадение 94% • Фэнтези'), findsOneWidget);
      expect(find.text('Frieren Beyond'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rec_more_10')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('rec_not_interested_10')));
      await tester.pumpAndSettle();

      expect(dismissedItem?.id, 10);
      expect(RecommendationEngine.instance.hiddenIds.contains(10), isTrue);
    });
  });
}

