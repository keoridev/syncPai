import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/sync_pai_mascot.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/screens/catalog_screen.dart';

class _EmptyCatalogRepo implements CatalogRepository {
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
  testWidgets(
      'CatalogScreen empty and error states render inside SliverToBoxAdapter without LayoutBuilder intrinsic crash',
      (tester) async {
    final repo = _EmptyCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    cubit.emit(const CatalogLoaded(titles: [], filteredTitles: []));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CatalogScreen(),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Ничего не найдено'), findsOneWidget);

    // Also verify SliverToBoxAdapter + SyncPaiMascot (which contains LayoutBuilder)
    cubit.emit(const CatalogError('Network timeout'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SyncPaiMascot), findsWidgets);
    expect(MascotState.emptySearch.id, 'empty-search');

    await cubit.close();
  });
}

