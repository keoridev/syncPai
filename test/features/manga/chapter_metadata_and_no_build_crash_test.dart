import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/widgets/mascot/pai_companion_toast.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/manga/presentation/screens/manga_details_screen.dart';

class _RichChaptersAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'id': 'chap-14',
            'attributes': {
              'volume': '2',
              'chapter': '14',
              'title': 'Начало',
              'pages': 34,
              'translatedLanguage': 'ru',
            },
            'relationships': [
              {
                'type': 'scanlation_group',
                'attributes': {'name': 'DreamTeam'},
              },
            ],
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  setUp(() {
    MascotCompanionService.instance.resetForTest();
  });

  tearDown(() {
    MascotCompanionService.instance.resetForTest();
  });

  test('MangaDexDataSource.getChapters includes scanlation_group and parses rich chapter metadata', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.mangadex.org'));
    final adapter = _RichChaptersAdapter();
    dio.httpClientAdapter = adapter;
    final ds = MangaDexDataSource(customDio: dio);

    final chapters = await ds.getChapters('manga-1');
    expect(adapter.lastOptions?.queryParameters['includes[]'], ['scanlation_group']);
    expect(chapters.length, 1);
    final ch = chapters.first;
    expect(ch.volume, '2');
    expect(ch.chapterLabel, '14');
    expect(ch.title, 'Начало');
    expect(ch.pagesCount, 34);
    expect(ch.translatorGroup, 'DreamTeam');
    expect(ch.translatedLanguage, 'ru');
    expect(ch.displayTitle, 'Том 2 • Глава 14 — Начало');
    expect(ch.secondaryMeta, '34 стр. • DreamTeam');
  });

  testWidgets('MangaDetailsScreen alongside PaiCompanionToast does not throw setState/markNeedsBuild during build', (tester) async {
    const manga = MangaDexManga(
      id: 'safe-1',
      title: 'Safe Manga',
      coverUrl: '',
      originalLanguage: 'ja',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            MangaDetailsScreen(
              mangaId: 'safe-1',
              initialManga: manga,
            ),
            PaiCompanionToast(),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}

