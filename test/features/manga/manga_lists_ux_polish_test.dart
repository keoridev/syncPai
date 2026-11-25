import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/manga/presentation/cubit/user_manga_list_cubit.dart';
import 'package:sync_pai/features/manga/presentation/screens/manga_details_screen.dart';
import 'package:sync_pai/features/manga/presentation/widgets/user_manga_list_view.dart';

class _StubCatalogRepo implements CatalogRepository {
  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int page = 1, int limit = 20}) async =>
      const [];
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('UserMangaListCubit setStatus and removeEntry update state immediately', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = UserMangaListCubit(prefs);
    await cubit.load();

    await cubit.setStatus(
      mangaId: 'm-1',
      mangaTitle: 'Test Manga',
      coverUrl: '',
      status: MangaListStatus.planned,
    );

    expect(cubit.state.getEntryFor('m-1')?.status, MangaListStatus.planned);
    expect(cubit.state.entriesFor(MangaListStatus.planned).length, 1);

    await cubit.removeEntry('m-1');
    expect(cubit.state.getEntryFor('m-1'), isNull);
    expect(cubit.state.entriesFor(MangaListStatus.planned), isEmpty);

    await cubit.close();
  });

  testWidgets('UserMangaListView empty state CTA switches CatalogCubit to Manga mode', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final mangaListCubit = UserMangaListCubit(prefs);
    final repo = _StubCatalogRepo();
    final catalogCubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    await catalogCubit.loadUpdates();

    getIt.registerSingleton<UserMangaListCubit>(mangaListCubit);
    getIt.registerSingleton<CatalogCubit>(catalogCubit);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              UserMangaListView(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Перейти в каталог манги'), findsOneWidget);
    expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('manga_empty_go_catalog_btn')));
    await tester.pump();

    expect(catalogCubit.isMangaMode, isTrue);

    await catalogCubit.close();
    await mangaListCubit.close();
  });

  testWidgets('MangaDetailsScreen shows В списки button and updates label on status selection', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final mangaListCubit = UserMangaListCubit(prefs);
    getIt.registerSingleton<UserMangaListCubit>(mangaListCubit);

    const manga = MangaDexManga(
      id: 'm-42',
      title: 'Solo Test',
      coverUrl: '',
      originalLanguage: 'ko',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: MangaDetailsScreen(
          mangaId: 'm-42',
          initialManga: manga,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('В списки'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('manga_details_list_status_btn')));
    await tester.pumpAndSettle();

    expect(find.text('В планах'), findsOneWidget);
    await tester.tap(find.text('В планах'));
    await tester.pumpAndSettle();

    expect(find.text('В планах'), findsOneWidget);
    expect(mangaListCubit.state.getEntryFor('m-42')?.status, MangaListStatus.planned);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await mangaListCubit.close();
  });
}

