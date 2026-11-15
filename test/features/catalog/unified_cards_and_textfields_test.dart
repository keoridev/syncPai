import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/theme/app_theme.dart';
import 'package:sync_pai/core/widgets/app_search_bar.dart';
import 'package:sync_pai/features/anime_lists/data/repositories/anime_list_repository_impl.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/anime_lists/presentation/screens/saved_anime_screen.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/anime_poster_card.dart';
import 'package:sync_pai/features/watch_history/data/repositories/watch_history_repository_impl.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Global InputDecorationTheme & Double-Border Prevention', () {
    test('AppTheme configures InputDecorationTheme with InputBorder.none and filled: false', () {
      final theme = AppTheme.cinemaDark;
      final inputTheme = theme.inputDecorationTheme;

      expect(inputTheme.border, InputBorder.none);
      expect(inputTheme.enabledBorder, InputBorder.none);
      expect(inputTheme.focusedBorder, InputBorder.none);
      expect(inputTheme.disabledBorder, InputBorder.none);
      expect(inputTheme.errorBorder, InputBorder.none);
      expect(inputTheme.focusedErrorBorder, InputBorder.none);
      expect(inputTheme.filled, isFalse);
      expect(inputTheme.isDense, isTrue);
      expect(inputTheme.hoverColor, Colors.transparent);
      expect(inputTheme.focusColor, Colors.transparent);
    });

    testWidgets('AppSearchBar uses 46px outer AnimatedContainer and borderless inner TextField', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: AppSearchBar(
                  controller: controller,
                  hintText: 'Поиск по сохраненным тайтлам...',
                ),
              ),
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      final decoration = textField.decoration!;
      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
      expect(decoration.disabledBorder, InputBorder.none);
      expect(decoration.errorBorder, InputBorder.none);
      expect(decoration.focusedErrorBorder, InputBorder.none);
      expect(decoration.filled, isFalse);

      // Focus the TextField and verify outer AnimatedContainer updates border without inner border
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 200));

      final animatedContainer = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppSearchBar),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final boxDeco = animatedContainer.decoration as BoxDecoration;
      expect(boxDeco.borderRadius, BorderRadius.circular(14));
    });
  });

  group('UnifiedAnimeCard & Catalog == My Lists Grid Unification', () {
    testWidgets('UnifiedAnimeCard renders 16px radius, 0.68 aspect ratio, score pill and status badge', (tester) async {
      const sampleTitle = AnimeTitle(
        id: 777,
        code: 'solo-leveling',
        russianTitle: 'Поднятие уровня в одиночку',
        englishTitle: 'Solo Leveling',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        year: 2024,
        genres: ['Экшен', 'Фэнтези'],
        description: 'Тестовое описание',
        status: 'Онгоинг',
      );

      expect(UnifiedAnimeCard.posterRadius, 16.0);
      expect(UnifiedAnimeCard.posterAspectRatio, 0.68);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 320,
              child: UnifiedAnimeCard(
                title: sampleTitle,
                onTap: () {},
                rating: 8.7,
                statusBadgeText: '4 / 12 эп.',
                watchProgress: 4 / 12,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Поднятие уровня в одиночку'), findsOneWidget);
      expect(find.text('4 / 12 эп.'), findsOneWidget);
      expect(find.text('★ 8.7'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('SavedAnimeScreen renders UnifiedAnimeCard in default Grid mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final listRepo = AnimeListRepositoryImpl(prefs);
      final historyRepo = WatchHistoryRepositoryImpl(prefs);
      final listCubit = AnimeListCubit(repository: listRepo);
      final historyCubit = WatchHistoryCubit(repository: historyRepo);
      addTearDown(() async {
        await listCubit.close();
        await historyCubit.close();
      });

      await listCubit.setAnimeStatus(
        animeId: 1001,
        titleRu: 'Магическая битва',
        posterUrl: 'https://example.com/jjk.jpg',
        status: AnimeListStatus.watching,
        lastEpisode: 5,
        episodesTotal: 24,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: listCubit),
            BlocProvider.value(value: historyCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.cinemaDark,
            home: const SavedAnimeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppSearchBar), findsOneWidget);
      expect(find.byType(UnifiedAnimeCard), findsAtLeastNWidgets(1));
      expect(find.text('5 / 24 эп.'), findsAtLeastNWidgets(1));
    });
  });
}
