import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/pai_companion_toast.dart';
import 'package:sync_pai/features/manga/presentation/cubit/manga_read_history_cubit.dart';
import 'package:sync_pai/features/manga/presentation/cubit/user_manga_list_cubit.dart';
import 'package:sync_pai/features/manga/presentation/widgets/user_manga_list_view.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    MascotCompanionService.instance.resetForTest();
  });

  tearDown(() async {
    MascotCompanionService.instance.resetForTest();
    await getIt.reset();
  });

  test('MangaReadHistoryCubit records and persists exact-page history chronologically', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = MangaReadHistoryCubit(prefs);
    await cubit.load();

    final first = MangaHistoryEntry(
      mangaId: 'm-1',
      title: 'Поднятие уровня в одиночку',
      coverUrl: '',
      formatLabel: 'Манхва',
      chapterId: 'c-14',
      chapterLabel: 'Глава 14',
      pageIndex: 18,
      totalPages: 42,
      updatedAt: DateTime(2026, 11, 26, 1, 0),
    );
    await cubit.recordProgress(first);

    expect(cubit.state.entries.length, 1);
    expect(cubit.state.getEntryFor('m-1')?.pageIndex, 18);
    expect(cubit.state.getEntryFor('m-1')?.chapterLabel, 'Глава 14');

    // Reload from SharedPreferences
    final cubit2 = MangaReadHistoryCubit(prefs);
    await cubit2.load();
    expect(cubit2.state.getEntryFor('m-1')?.pageIndex, 18);

    await cubit.close();
    await cubit2.close();
  });

  testWidgets('UserMangaListView shows История tab first with exact chapter and page progress', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final listCubit = UserMangaListCubit(prefs);
    final historyCubit = MangaReadHistoryCubit(prefs);
    await historyCubit.load();
    await historyCubit.recordProgress(
      MangaHistoryEntry(
        mangaId: 'm-9',
        title: 'Берсерк',
        coverUrl: '',
        formatLabel: 'Манга',
        chapterId: 'c-1',
        chapterLabel: 'Глава 1',
        pageIndex: 12,
        totalPages: 30,
        updatedAt: DateTime.now(),
      ),
    );

    getIt.registerSingleton<UserMangaListCubit>(listCubit);
    getIt.registerSingleton<MangaReadHistoryCubit>(historyCubit);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<MangaReadHistoryCubit>.value(
          value: historyCubit,
          child: const Scaffold(
            body: CustomScrollView(
              slivers: [UserMangaListView()],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('manga_list_tab_history')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manga_list_tab_history')));
    await tester.pump();

    expect(find.text('Берсерк'), findsOneWidget);
    expect(find.text('Манга • Глава 1 • Стр. 12/30'), findsOneWidget);

    await listCubit.close();
    await historyCubit.close();
  });

  testWidgets('MascotCompanionService activates Manga Pai-chan persona only in Manga context', (tester) async {
    final service = MascotCompanionService.instance;
    expect(service.isMangaContext, isFalse);
    expect(
      MascotExpression.cheering.mangaAssetPath,
      'assets/mascot/pai_manga_hype.png',
    );

    service.setMangaContext(true);
    expect(service.isMangaContext, isTrue);

    service.notifyMangaBridgeResumed('главы 14');
    expect(
      service.currentReaction?.message,
      'Первоисточник открыт! Продолжаем сюжет прямо с главы 14.',
    );
    expect(
      service.currentReaction?.customAssetPath,
      'assets/mascot/pai_manga_reading.png',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: SizedBox()),
              PaiCompanionToast(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('pai_companion_toast_card')), findsOneWidget);

    service.dismiss();
    await tester.pump();
    service.setMangaContext(false);
    expect(service.isMangaContext, isFalse);
  });
}

