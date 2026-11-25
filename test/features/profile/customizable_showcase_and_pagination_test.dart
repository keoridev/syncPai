import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_progress_repository.dart';
import 'package:sync_pai/features/manga/presentation/screens/manga_details_screen.dart';

class _CountingCatalogRepo implements CatalogRepository {
  int getUpdatesCalls = 0;

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async {
    getUpdatesCalls++;
    return List.generate(
      20,
      (i) => AnimeTitle(
        id: (getUpdatesCalls - 1) * 20 + i + 1,
        code: 'c_$i',
        russianTitle: 'Тайтл $i',
        englishTitle: 'Title $i',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: const ['Экшен'],
        description: '',
        status: 'Онгоинг',
      ),
    );
  }

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];
}

void main() {
  test('ProfileShowcaseConfig serializes mode, customCaption, fullBleedBackdrop, and persists via MangaProgressRepository', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = MangaProgressRepository(prefs);

    const config = ProfileShowcaseConfig(
      mode: ShowcaseMode.dual,
      customCaption: 'Топ манга года',
      fullBleedBackdrop: true,
      selectedManga: FeaturedMangaShowcase(
        mangaId: 'md-1',
        mangaTitle: 'Берсерк',
        coverUrl: '',
        chapterLabel: '42',
        totalChapters: 364,
      ),
    );

    await repo.saveShowcaseConfig(config);
    final loaded = await repo.getShowcaseConfig();
    expect(loaded.mode, ShowcaseMode.dual);
    expect(loaded.customCaption, 'Топ манга года');
    expect(loaded.fullBleedBackdrop, isTrue);
    expect(loaded.selectedManga?.mangaTitle, 'Берсерк');
  });

  test('CatalogCubit.loadNextPage enforces 600ms cooldown against auto-pagination flood', () async {
    final repo = _CountingCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );

    await cubit.loadUpdates();
    expect(repo.getUpdatesCalls, 1);

    await cubit.loadNextPage();
    await cubit.loadNextPage();
    await cubit.loadNextPage();

    // Only 1 loadNextPage call should go through within 600ms
    expect(repo.getUpdatesCalls, 2);

    await cubit.close();
  });

  testWidgets('MangaDetailsScreen builds and renders without crashing when 0 chapters are hosted', (tester) async {
    // Verify MangaDetailsScreen gracefully renders loading/fallback state
    await tester.pumpWidget(
      const MaterialApp(
        home: MangaDetailsScreen(
          mangaId: 'empty-1',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MangaDetailsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}

