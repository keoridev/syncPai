import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/user_lists_stats.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/user_lists_distribution_widget.dart';
import 'package:sync_pai/features/anime_lists/data/datasources/anixart_remote_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';

typedef _AdapterHandler = Future<ResponseBody> Function(RequestOptions options);

class _MockHttpAdapter implements HttpClientAdapter {
  final _AdapterHandler handler;
  _MockHttpAdapter(this.handler);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
}

ResponseBody _jsonBody(Object data, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ShikimoriRemoteDataSourceImpl consolidates details into 1 GraphQL query, enforces User-Agent & 429 retry',
      () async {
    final recordedRequests = <String>[];
    final recordedUserAgents = <String>[];
    int gqlCalls = 0;

    final dio = Dio(BaseOptions(baseUrl: 'https://shikimori.one/api'));
    dio.httpClientAdapter = _MockHttpAdapter((options) async {
      recordedRequests.add('${options.method} ${options.uri.path}');
      recordedUserAgents.add('${options.headers['User-Agent'] ?? ''}');

      if (options.uri.path.endsWith('/graphql')) {
        gqlCalls++;
        if (gqlCalls == 1) {
          // Симулируем первый 429 Too Many Requests — должен сработать 1 ретрай
          return _jsonBody({'error': 'rate_limited'}, statusCode: 429);
        }
        return _jsonBody({
          'data': {
            'animes': [
              {
                'id': '38000',
                'score': 8.5,
                'statusesStats': [
                  {'status': 'watching', 'count': 1200},
                  {'status': 'completed', 'count': 54000},
                  {'status': 'planned', 'count': 8000},
                  {'status': 'on_hold', 'count': 300},
                  {'status': 'dropped', 'count': 400},
                ],
                'scoresStats': [
                  {'score': 10, 'count': 15000},
                  {'score': 9, 'count': 20000},
                  {'score': 8, 'count': 10000},
                ],
                'screenshots': [
                  {'originalUrl': '/system/screenshots/original/1.jpg'},
                ],
                'videos': [
                  {
                    'id': '101',
                    'name': 'PV 1',
                    'url': 'https://youtu.be/VQGCKyvzIM4',
                    'imageUrl': '',
                    'kind': 'pv',
                  },
                ],
              },
            ],
          },
        });
      }
      if (options.uri.path.endsWith('/topics')) {
        return _jsonBody([]);
      }
      if (options.uri.path.endsWith('/franchise')) {
        return _jsonBody({'nodes': [], 'links': []});
      }
      if (options.uri.path.endsWith('/related')) {
        return _jsonBody([]);
      }
      return _jsonBody([]);
    });

    final ds = ShikimoriRemoteDataSourceImpl(
      customDio: dio,
      minRequestInterval: const Duration(milliseconds: 10),
      retry429Delay: const Duration(milliseconds: 10),
    );

    const title = AnimeTitle(
      id: 1,
      code: 'kimetsu',
      russianTitle: 'Клинок, рассекающий демонов',
      englishTitle: 'Demon Slayer',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: [],
      description: '',
      status: 'released',
      shikimoriId: 38000,
    );

    final result = await ds.getReviewsAndRatings(title);

    expect(gqlCalls, 2); // 1й 429 + 1 успешный ретрай
    expect(result.userStats.watching, 1200);
    expect(result.userStats.completed, 54000);
    expect(result.videos.first.title, 'PV 1');
    expect(result.scoreDistribution.first.score, 10);
    expect(recordedUserAgents.every((ua) => ua == 'SyncPai/1.0 (Desktop/Mobile)'), isTrue);
    expect(recordedRequests.any((r) => r.contains('/animes/38000/screenshots')), isFalse);
    expect(recordedRequests.any((r) => r.contains('/animes/38000/videos')), isFalse);
  });

  test('AnixartRemoteDataSourceImpl sends required v2 headers, uses POST /search/profiles/0, and maps 400/403 cleanly',
      () async {
    final seenHeaders = <Map<String, dynamic>>[];
    final seenRequests = <String>[];

    final dio = Dio();
    dio.httpClientAdapter = _MockHttpAdapter((options) async {
      seenHeaders.add(Map<String, dynamic>.from(options.headers));
      seenRequests.add('${options.method} ${options.uri.path}');

      if (options.uri.path.endsWith('/search/profiles/0')) {
        return _jsonBody({'profiles': []}, statusCode: 200);
      }
      if (options.uri.path.endsWith('/profile/999999')) {
        return _jsonBody({'code': 400}, statusCode: 400);
      }
      return _jsonBody({}, statusCode: 403);
    });

    final ds = AnixartRemoteDataSourceImpl(customDio: dio);

    // 1. Numeric ID -> GET /profile/999999 -> clean 400 message without DioException
    await expectLater(
      () => ds.fetchProfileBookmarks(loginOrId: '999999', userId: 'u1'),
      throwsA(
        predicate<AnixartUserNotFoundException>(
          (e) =>
              e.message.contains('Профиль Anixart') &&
              !e.message.contains('DioException'),
        ),
      ),
    );
    expect(seenRequests.first, 'GET /profile/999999');
    expect(seenHeaders.first['API-Version'], 'v2');
    expect(
      seenHeaders.first['User-Agent'],
      'AnixartApp/8.2.2-24110113 (Android 13; SDK 33; arm64-v8a; SyncPai)',
    );

    // 2. Username search -> POST /search/profiles/0
    seenRequests.clear();
    await expectLater(
      () => ds.fetchProfileBookmarks(loginOrId: 'unknown_user', userId: 'u1'),
      throwsA(isA<AnixartUserNotFoundException>()),
    );
    expect(seenRequests.first, 'POST /search/profiles/0');

    // 3. Direct DioException 400 / 429 / timeout mapping helper
    final req = RequestOptions(path: '/profile/1');
    final err400 = DioException(
      requestOptions: req,
      response: Response(requestOptions: req, statusCode: 400),
      type: DioExceptionType.badResponse,
    );
    final msg400 = AnixartRemoteDataSourceImpl.mapUserFriendlyError(err400);
    expect(msg400, contains('Профиль Anixart не найден или закрыт настройками приватности'));
    expect(msg400, isNot(contains('DioException')));

    final errTimeout = DioException(
      requestOptions: req,
      type: DioExceptionType.receiveTimeout,
    );
    final msgTimeout = AnixartRemoteDataSourceImpl.mapUserFriendlyError(errTimeout);
    expect(msgTimeout, contains('Серверы Anixart временно недоступны или ограничивают запросы'));
    expect(msgTimeout, isNot(contains('DioException')));
  });

  test('ShikimoriRemoteDataSourceImpl.normalizeTitleForSearch strips season/part/tags', () {
    expect(
      ShikimoriRemoteDataSourceImpl.normalizeTitleForSearch(
        'Магическая битва 2 сезон (Часть 2) [ТВ-2]',
      ),
      'Магическая битва',
    );
  });

  testWidgets('UserListsDistributionWidget shows fresh-release fallback pill when stats are empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserListsDistributionWidget(
            stats: UserListsStats(),
            isLoading: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('user_lists_fresh_fallback')), findsOneWidget);
    expect(find.text('Свежий релиз — статистика ещё формируется'), findsOneWidget);
  });
}
