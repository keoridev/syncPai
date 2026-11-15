import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_lists/data/datasources/anixart_csv_parser.dart';
import 'package:sync_pai/features/anime_lists/data/repositories/anime_list_repository_impl.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';

class _MockEnricherAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri.toString();
    final query = options.uri.queryParameters['f[search]'] ??
        options.uri.queryParameters['search'] ??
        '';

    dynamic payload = <dynamic>[];

    if (uri.contains('anilibria.top')) {
      if (query.contains('Магическая битва')) {
        payload = [
          {
            'id': 9501,
            'poster': {
              'optimized': {'src': '/storage/releases/posters/9501.jpg'},
            },
            'episodes_total': 24,
          },
        ];
      } else {
        payload = <dynamic>[];
      }
    } else if (uri.contains('shikimori.one')) {
      if (query.contains('Фрирен')) {
        payload = [
          {
            'id': 52991,
            'image': {
              'original': '/system/animes/original/52991.jpg',
            },
            'episodes': 28,
          },
        ];
      }
    }

    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnixartCsvParser — BOM, delimiters, headers & status mapping', () {
    test('parses UTF-8 BOM + semicolon CSV with Russian headers into proper statuses', () {
      const csv = '\uFEFFСтатус;Название;Серий;Оценка\n'
          'Смотрю;Магическая битва;12;9\n'
          'В планах;Фрирен;0;0\n'
          'Просмотрено;Стальной алхимик: Братство;64;10\n'
          'Отложено;Оверлорд;5;7\n'
          'Брошено;Рандом;2;3\n';

      final entries = AnixartCsvParser.parseCsv(csv, userId: 'u1');
      expect(entries.length, 5);

      expect(entries[0].titleRu, 'Магическая битва');
      expect(entries[0].status, AnimeListStatus.watching);
      expect(entries[0].lastEpisode, 12);

      expect(entries[1].titleRu, 'Фрирен');
      expect(entries[1].status, AnimeListStatus.planned);

      expect(entries[2].titleRu, 'Стальной алхимик: Братство');
      expect(entries[2].status, AnimeListStatus.completed);
      expect(entries[2].lastEpisode, 64);

      expect(entries[3].titleRu, 'Оверлорд');
      expect(entries[3].status, AnimeListStatus.dropped);

      expect(entries[4].titleRu, 'Рандом');
      expect(entries[4].status, AnimeListStatus.dropped);
    });

    test('auto-detects tab delimiter and English headers', () {
      const tsv = 'Title\tList\tEpisodes\n'
          'Solo Leveling\twatching\t8\n'
          'Steins;Gate\tcompleted\t24\n'
          'Dandadan\tplanned\t0\n';

      final entries = AnixartCsvParser.parseCsv(tsv, userId: 'u1');
      expect(entries.length, 3);
      expect(entries[0].status, AnimeListStatus.watching);
      expect(entries[0].lastEpisode, 8);
      expect(entries[1].status, AnimeListStatus.completed);
      expect(entries[1].lastEpisode, 24);
      expect(entries[2].status, AnimeListStatus.planned);
    });

    test('normalizeAnimeKey strips case, punctuation and extra whitespace', () {
      expect(
        normalizeAnimeKey('  Магическая битва!! '),
        equals(normalizeAnimeKey('магическая   битва')),
      );
      expect(
        normalizeAnimeKey('Re:Zero — Начало жизни'),
        equals(normalizeAnimeKey('re zero начало жизни')),
      );
    });
  });

  group('AnimeListRepositoryImpl — strict deduplication on import', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('re-importing CSV and intra-file duplicates updates in-place without duplicates', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = AnimeListRepositoryImpl(prefs);

      const csv1 = '\uFEFFСтатус;Название;Серий\n'
          'Смотрю;Магическая битва;12\n'
          'В планах;Фрирен;0\n'
          'Просмотрено;Стальной алхимик: Братство;64\n';

      final res1 = await repo.importAnixartBackup(csv1, userId: 'user_1');
      expect(res1.addedCount, 3);
      expect(res1.updatedCount, 0);

      var list = await repo.getAllEntries();
      expect(list.length, 3);

      // Simulate existing poster & higher episode progress on one entry
      final jjk = list.firstWhere((e) => e.titleRu == 'Магическая битва');
      await repo.upsertEntry(
        jjk.copyWith(
          posterUrl: 'https://existing.example/jjk.jpg',
          lastEpisode: 15,
        ),
      );

      // Second import contains:
      // - case + punctuation variation of "Магическая битва" with lower episode (10)
      // - another intra-batch duplicate of "Магическая битва" with higher episode (20)
      // - existing "Фрирен" and "Стальной алхимик: Братство"
      const csv2 = '\uFEFFСтатус;Название;Серий\n'
          'Смотрю;Магическая битва!;10\n'
          'Смотрю;магическая битва;20\n'
          'В планах;Фрирен;1\n'
          'Просмотрено;Стальной алхимик: Братство;64\n';

      final res2 = await repo.importAnixartBackup(csv2, userId: 'user_1');
      expect(res2.addedCount, 0);
      expect(res2.updatedCount, 3);

      list = await repo.getAllEntries();
      expect(list.length, 3);

      final updatedJjk = list.firstWhere(
        (e) => normalizeAnimeKey(e.titleRu) == normalizeAnimeKey('Магическая битва'),
      );
      expect(updatedJjk.posterUrl, 'https://existing.example/jjk.jpg');
      expect(updatedJjk.lastEpisode, 20);
    });
  });

  group('ImportPosterEnricher & AnimeListCubit — background poster enrichment', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('enriches missing posters via AniLibria and Shikimori fallback', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = AnimeListRepositoryImpl(prefs);
      final cubit = AnimeListCubit(repository: repo);

      const csv = '\uFEFFСтатус;Название;Серий\n'
          'Смотрю;Магическая битва;12\n'
          'В планах;Фрирен;0\n';

      await cubit.importAnixartBackup(csv, userId: 'user_2');
      expect(cubit.state.allEntries.length, 2);
      expect(cubit.state.allEntries.every((e) => e.posterUrl == null), isTrue);

      final mockDio = Dio()..httpClientAdapter = _MockEnricherAdapter();
      await cubit.enrichImportedEntriesInBackground(
        cubit.state.allEntries,
        dio: mockDio,
      );

      final jjk = cubit.state.allEntries.firstWhere((e) => e.titleRu == 'Магическая битва');
      expect(jjk.posterUrl, 'https://anilibria.top/storage/releases/posters/9501.jpg');
      expect(jjk.animeId, 9501);
      expect(jjk.episodesTotal, 24);

      final frieren = cubit.state.allEntries.firstWhere((e) => e.titleRu == 'Фрирен');
      expect(frieren.animeId, 52991);
      expect(frieren.posterUrl, 'https://shikimori.one/system/animes/original/52991.jpg');
      expect(frieren.episodesTotal, 28);

      // Verify persisted in repository as well
      final persisted = await repo.getAllEntries();
      expect(
        persisted.firstWhere((e) => e.animeId == 9501).posterUrl,
        'https://anilibria.top/storage/releases/posters/9501.jpg',
      );
      expect(
        persisted.firstWhere((e) => e.animeId == 52991).posterUrl,
        'https://shikimori.one/system/animes/original/52991.jpg',
      );

      await cubit.close();
    });
  });
}
