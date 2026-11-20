import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_theme.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/catalog_filter_sheet.dart';

class FakeCatalogRepository implements CatalogRepository {
  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 15}) async => [];
  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int page = 1, int limit = 15}) async => [];
  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogCubit cubit;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    if (!getIt.isRegistered<SharedPreferences>()) {
      getIt.registerSingleton<SharedPreferences>(prefs);
    }
    final repo = FakeCatalogRepository();
    cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
      prefs: prefs,
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('CatalogFilterSheet & Search Bar Synchronization', () {
    testWidgets('Opening CatalogFilterSheet with active genre shows Жанры (1) and highlights chip', (tester) async {
      final state = CatalogLoaded(
        titles: const [],
        filteredTitles: const [],
        selectedGenres: const {'Экшен'},
        sortBy: CatalogSort.updates,
        statusFilter: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: BlocProvider<CatalogCubit>.value(
            value: cubit,
            child: Scaffold(
              body: CatalogFilterSheet(currentState: state),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header shows Жанры (1)
      expect(find.text('Жанры (1)'), findsOneWidget);

      // Сбросить button is visible
      expect(find.text('Сбросить'), findsOneWidget);

      // Экшен chip is selected
      final actionChipFinder = find.widgetWithText(FilterChip, 'Экшен');
      expect(actionChipFinder, findsOneWidget);
      final filterChip = tester.widget<FilterChip>(actionChipFinder);
      expect(filterChip.selected, isTrue);
    });

    testWidgets('Tapping Сбросить in CatalogFilterSheet resets genres, sort, and status in 1 tap', (tester) async {
      final state = CatalogLoaded(
        titles: const [],
        filteredTitles: const [],
        selectedGenres: const {'Экшен'},
        sortBy: CatalogSort.rating,
        statusFilter: 'ongoing',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: BlocProvider<CatalogCubit>.value(
            value: cubit,
            child: Scaffold(
              body: CatalogFilterSheet(currentState: state),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Жанры (1)'), findsOneWidget);
      expect(find.text('Сбросить'), findsOneWidget);

      // Tap Сбросить
      await tester.tap(find.text('Сбросить'));
      await tester.pumpAndSettle();

      // Now genres count is 0
      expect(find.text('Жанры (0)'), findsOneWidget);

      // Сбросить button is now hidden since all filters are default
      expect(find.text('Сбросить'), findsNothing);

      // Экшен chip is no longer selected
      final actionChipFinder = find.widgetWithText(FilterChip, 'Экшен');
      final filterChip = tester.widget<FilterChip>(actionChipFinder);
      expect(filterChip.selected, isFalse);
    });

    test('onCategoryChanged clears searchQuery when switching to genre browsing', () {
      cubit.emit(CatalogLoaded(
        titles: const [],
        filteredTitles: const [],
        searchQuery: 'Маг Целитель',
        isSearching: false,
      ));

      expect((cubit.state as CatalogLoaded).searchQuery, 'Маг Целитель');

      cubit.onCategoryChanged('Комедия');

      expect((cubit.state as CatalogLoaded).searchQuery, isEmpty);
      expect((cubit.state as CatalogLoaded).selectedGenres, contains('Комедия'));
    });
  });
}
