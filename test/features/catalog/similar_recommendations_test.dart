import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/services/recommendation_engine.dart';

class _SimilarShikimoriAdapter implements HttpClientAdapter {
  Uri? lastUri;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    return ResponseBody.fromString(
      jsonEncode([
        {
          'id': 54900,
          'name': 'Wind Breaker',
          'russian': 'Ветролом',
          'kind': 'tv',
          'status': 'released',
          'aired_on': '2024-04-05',
          'score': '7.8',
          'image': {
            'original': '/system/animes/original/54900.jpg',
            'preview': '/system/animes/preview/54900.jpg',
          },
        },
        {
          'id': 31043,
          'name': 'Boku dake ga Inai Machi',
          'russian': 'Город, в котором меня нет',
          'kind': 'tv',
          'status': 'released',
          'aired_on': '2016-01-08',
          'score': '8.3',
          'image': {
            'original': '/system/animes/original/31043.jpg',
            'preview': '/system/animes/preview/31043.jpg',
          },
        },
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test('ShikimoriRemoteDataSourceImpl.getSimilarAnimes queries /animes/{id}/similar and maps AnimeTitle', () async {
    final dio = Dio();
    dio.transformer = SyncTransformer();
    final adapter = _SimilarShikimoriAdapter();
    dio.httpClientAdapter = adapter;

    final ds = ShikimoriRemoteDataSourceImpl(
      customDio: dio,
      minRequestInterval: Duration.zero,
    );

    final similar = await ds.getSimilarAnimes(42249);
    expect(adapter.lastUri?.host, 'shikimori.io');
    expect(adapter.lastUri?.path, '/api/animes/42249/similar');
    expect(similar, hasLength(2));
    expect(similar.first.russianTitle, 'Ветролом');
    expect(similar[1].russianTitle, 'Город, в котором меня нет');
  });

  test('RecommendationEngine.recommendSimilarTo excludes sequels, penalizes comedy/harem mismatch, and prioritizes Shikimori /similar', () {
    const tokyoRevengers = AnimeTitle(
      id: 42249,
      shikimoriId: 42249,
      code: 'tokyo-revengers',
      russianTitle: 'Токийские мстители',
      englishTitle: 'Tokyo Revengers',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Экшен', 'Драма', 'Сверхъестественное'],
      description: '',
      status: 'Вышел',
      year: 2021,
    );

    const sequel = AnimeTitle(
      id: 50608,
      shikimoriId: 50608,
      code: 'tokyo-revengers-2',
      russianTitle: 'Токийские мстители 2 сезон',
      englishTitle: 'Tokyo Revengers Season 2',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Экшен', 'Драма', 'Сверхъестественное'],
      description: '',
      status: 'Вышел',
      year: 2023,
    );

    const ranma = AnimeTitle(
      id: 210,
      shikimoriId: 210,
      code: 'ranma',
      russianTitle: 'Ранма 1/2',
      englishTitle: 'Ranma 1/2',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Экшен', 'Комедия', 'Романтика', 'Гарем'],
      description: '',
      status: 'Вышел',
      year: 2024,
    );

    const erased = AnimeTitle(
      id: 31043,
      shikimoriId: 31043,
      code: 'erased',
      russianTitle: 'Город, в котором меня нет',
      englishTitle: 'Erased',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Психологическое', 'Драма', 'Сверхъестественное', 'Триллер'],
      description: '',
      status: 'Вышел',
      year: 2016,
      score: 8.3,
    );

    const windBreakerShiki = AnimeTitle(
      id: 54900,
      shikimoriId: 54900,
      code: 'shiki_54900',
      russianTitle: 'Ветролом',
      englishTitle: 'Wind Breaker',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: [],
      description: '',
      status: 'Вышел',
    );

    final picks = RecommendationEngine.instance.recommendSimilarTo(
      target: tokyoRevengers,
      catalogPool: const [sequel, ranma, erased],
      userEntries: const [],
      watchHistory: const [],
      shikimoriSimilar: const [windBreakerShiki],
    );

    expect(picks.any((p) => p.anime.id == sequel.id), isFalse);
    expect(picks.any((p) => p.anime.id == ranma.id), isFalse);
    expect(picks.first.anime.russianTitle, 'Ветролом');
    expect(picks.first.reasonTag, contains('% схожесть'));
    expect(picks.any((p) => p.anime.id == erased.id), isTrue);
  });
}

