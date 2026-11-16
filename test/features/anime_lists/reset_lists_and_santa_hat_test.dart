import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/sync_pai_mascot.dart';
import 'package:sync_pai/features/anime_lists/data/repositories/anime_list_repository_impl.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/winter_theme/domain/services/winter_theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncPaiMascot — no double Santa hat', () {
    testWidgets('does not overlay extra Santa hat on winterEmpty when winter mascot is enabled', (tester) async {
      await WinterThemeService.instance.setWinterTheme(true);
      await WinterThemeService.instance.setWinterMascot(true);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SyncPaiMascot(
              state: MascotState.emptyAnime,
              animated: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // emptyAnime maps to winterEmpty which already has Santa hat in asset -> 0 extra CustomPaint hats
      final hats = find.descendant(
        of: find.byType(SyncPaiMascot),
        matching: find.byType(CustomPaint),
      );
      expect(hats, findsNothing);

      await WinterThemeService.instance.setWinterTheme(false);
    });
  });

  group('AnimeListCubit.clearAllLists — instant 0ms reset & persistence clear', () {
    test('clears allEntries, resets stats to 0 immediately, and clears SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = AnimeListRepositoryImpl(prefs);
      final cubit = AnimeListCubit(repository: repo);

      await cubit.importAnixartBackup(
        'Статус;Название;Серий\nВ планах;Фрирен;0\nПросмотрено;Блич;366\n',
        userId: 'u1',
      );
      expect(cubit.state.allEntries.length, 2);
      expect(cubit.state.stats.totalTitles, 2);

      // Call clearAllLists and verify 0ms synchronous emission
      final future = cubit.clearAllLists(userId: 'u1');
      expect(cubit.state.allEntries, isEmpty);
      expect(cubit.state.stats.totalTitles, 0);
      expect(cubit.state.stats.plannedTitles, 0);
      expect(cubit.state.stats.completedTitles, 0);

      await future;
      final persisted = await repo.getAllEntries();
      expect(persisted, isEmpty);

      await cubit.close();
    });
  });
}
