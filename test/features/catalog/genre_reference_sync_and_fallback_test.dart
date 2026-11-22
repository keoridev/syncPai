import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/catalog/data/datasources/anime_remote_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';

class _GenreRefMockAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.contains('/references/genres')) {
      final body = jsonEncode({
        'data': [
          {'id': 4, 'name': 'Сёнен'},
          {'id': 5, 'name': 'Сэйнэн'},
          {'id': 7, 'name': 'Школа'},
          {'id': 9, 'name': 'Мистика'},
          {'id': 19, 'name': 'Психология'},
          {'id': 29, 'name': 'Фэнтези'},
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'id': 10,
            'alias': 'test-release',
            'name': {'main': 'Тест Сёнен', 'english': 'Test Shounen'},
            'poster': {'src': 'https://example.com/10.jpg'},
            'year': 2025,
            'genres': [
              {'id': 4, 'name': 'Сёнен'},
            ],
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dynamic AniLibria Genre Reference Sync & Hybrid Alias Matching', () {
    test('fetches live genre references, normalizes ё/е, and omits non-existent genre IDs like Исекай',
        () async {
      final adapter = _GenreRefMockAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final ds = AniLibertyAnimeRemoteDataSourceImpl(customDio: dio);

      await ds.syncGenreReferences(force: true);

      expect(ds.resolveGenreId('Сёнен'), 4);
      expect(ds.resolveGenreId('Сенен'), 4);
      expect(ds.resolveGenreId('сэйнэн'), 5);
      expect(ds.resolveGenreId('Сейнен'), 5);
      expect(ds.resolveGenreId('Мистика'), 9);
      expect(ds.resolveGenreId('Психология'), 19);
      // «Исекай» отсутствует в живом справочнике -> не отправляем битый ID
      expect(ds.resolveGenreId('Исекай'), isNull);

      await ds.getCatalog(page: 1, genres: 'Сёнен');
      final releaseReq = adapter.requests
          .lastWhere((r) => r.path.contains('/catalog/releases'));
      expect(releaseReq.queryParameters['f[genres]'], '4');

      await ds.getCatalog(page: 1, genres: 'Исекай');
      final isekaiReq = adapter.requests
          .lastWhere((r) => r.path.contains('/catalog/releases'));
      expect(isekaiReq.queryParameters.containsKey('f[genres]'), isFalse);
    });

    test('CatalogCubit.matchesGenreOrAlias matches demographic tags and keywords', () {
      const isekaiByDesc = AnimeTitle(
        id: 1,
        code: 'isekai-1',
        russianTitle: 'Перерождение',
        englishTitle: 'Reincarnation',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Фэнтези'],
        description: 'Обычный парень попал в другой мир и переродился магом.',
        status: 'released',
      );
      const seinenByTag = AnimeTitle(
        id: 2,
        code: 'seinen-1',
        russianTitle: 'Тёмный триллер',
        englishTitle: 'Dark Thriller',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Сейнен', 'Психологическое'],
        description: '',
        status: 'released',
      );

      expect(CatalogCubit.matchesGenreOrAlias(isekaiByDesc, 'Исекай'), isTrue);
      expect(CatalogCubit.matchesGenreOrAlias(seinenByTag, 'Сэйнэн'), isTrue);
      expect(CatalogCubit.matchesGenreOrAlias(seinenByTag, 'Психология'), isTrue);
    });
  });
}

