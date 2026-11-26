import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/features/catalog/data/services/anime_meta_enrichment_service.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_progress_repository.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/manga/presentation/cubit/manga_read_history_cubit.dart';
import 'package:sync_pai/features/manga/presentation/screens/manga_reader_screen.dart';

class _ShikimoriHdAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'id': 52299,
        'score': '8.74',
        'scored_by': 120000,
        'image': {'original': '/system/animes/original/52299.jpg'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _ChaptersFakeDs extends MangaDexDataSource {
  @override
  Future<List<MangaDexChapter>> getChapters(
    String mangaId, {
    String? title,
    String? originalTitle,
  }) async {
    return const [
      MangaDexChapter(
        id: 'c-31',
        chapterNumber: 31,
        chapterLabel: '31',
        title: 'Тридцать первая',
        translatedLanguage: 'ru',
      ),
      MangaDexChapter(
        id: 'c-55',
        chapterNumber: 55,
        chapterLabel: '55',
        title: 'Пятьдесят пятая',
        translatedLanguage: 'ru',
      ),
    ];
  }

  @override
  Future<({List<String> dataUrls, List<String> dataSaverUrls})>
      getChapterPagesWithFallback(String chapterId) async {
    return (dataUrls: const <String>[], dataSaverUrls: const <String>[]);
  }
}

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

  test('AnimeMetaEnrichmentService fetches HD Shikimori poster & score and caches for 7d', () async {
    final prefs = await SharedPreferences.getInstance();
    final adapter = _ShikimoriHdAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://shikimori.io/api'));
    dio.httpClientAdapter = adapter;

    final service = AnimeMetaEnrichmentService(dio: dio, prefs: prefs);
    const title = AnimeTitle(
      id: 101,
      shikimoriId: 52299,
      code: 'sl',
      russianTitle: 'Поднятие уровня',
      englishTitle: 'Solo Leveling',
      posterSmall: 'https://anilibria.top/small.jpg',
      posterMedium: 'https://anilibria.top/med.jpg',
      posterOriginal: 'https://anilibria.top/orig.jpg',
      genres: [],
      description: '',
      status: '',
    );

    final enriched1 = await service.enrichSingle(title);
    expect(enriched1.posterOriginal, 'https://shikimori.one/system/animes/original/52299.jpg');
    expect(enriched1.score, 8.74);
    expect(enriched1.fallbackPosterUrl, 'https://anilibria.top/med.jpg');
    expect(adapter.calls, 1);

    final enriched2 = await service.enrichSingle(title);
    expect(enriched2.score, 8.74);
    expect(adapter.calls, 1);
  });

  testWidgets('MangaReaderScreen preserves saved Chapter 55 when bridge suggests Chapter 31', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final historyCubit = MangaReadHistoryCubit(prefs);
    await historyCubit.load();
    await historyCubit.recordProgress(
      MangaHistoryEntry(
        mangaId: 'md-solo',
        title: 'Поднятие уровня',
        coverUrl: '',
        formatLabel: 'Манхва',
        chapterId: 'c-55',
        chapterLabel: 'Глава 55',
        pageIndex: 12,
        totalPages: 30,
        updatedAt: DateTime.now(),
      ),
    );
    getIt.registerSingleton<MangaReadHistoryCubit>(historyCubit);

    const bridge = AnimeMangaBridge(
      anilibriaId: 101,
      mangaDexId: 'md-solo',
      mangaTitle: 'Поднятие уровня',
      coverUrl: '',
      mangaUpdatesEndChapter: 30,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MangaReaderScreen(
          bridge: bridge,
          initialChapter: 31,
          dataSource: _ChaptersFakeDs(),
          progressRepository: MangaProgressRepository(prefs),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Глава 55'), findsWidgets);
    expect(
      MascotCompanionService.instance.currentReaction?.message,
      'Продолжаем с сохранённой страницы (Глава 55, стр. 12).',
    );

    MascotCompanionService.instance.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await historyCubit.close();
  });
}

