import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/catalog_settings.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/anime_poster_card.dart';

class _StubCatalogRepo implements CatalogRepository {
  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async =>
      throw UnimplementedError();
}

void main() {
  testWidgets('CatalogScreen restores 2 к. / 3 к. switcher on mobile and toggles grid columns',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = _StubCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    const items = [
      AnimeTitle(
        id: 1,
        code: 'a1',
        russianTitle: 'Аниме Один',
        englishTitle: 'Anime One',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Экшен'],
        description: '',
        status: 'ongoing',
      ),
      AnimeTitle(
        id: 2,
        code: 'a2',
        russianTitle: 'Аниме Два',
        englishTitle: 'Anime Two',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Фэнтези'],
        description: '',
        status: 'released',
      ),
      AnimeTitle(
        id: 3,
        code: 'a3',
        russianTitle: 'Аниме Три',
        englishTitle: 'Anime Three',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Комедия'],
        description: '',
        status: 'released',
      ),
    ];
    cubit.emit(const CatalogLoaded(
      titles: items,
      filteredTitles: items,
      gridDensity: CatalogGridDensity.standard,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CatalogScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('catalog_grid_columns_toggle')), findsOneWidget);
    expect(find.text('2 к.'), findsOneWidget);
    expect(tester.widget<AnimePosterCard>(find.byType(AnimePosterCard).first).isCompact, isFalse);

    await tester.tap(find.byKey(const ValueKey('catalog_grid_columns_toggle')));
    await tester.pump();

    expect(find.text('3 к.'), findsOneWidget);
    expect(tester.widget<AnimePosterCard>(find.byType(AnimePosterCard).first).isCompact, isTrue);

    await cubit.close();
  });
}
