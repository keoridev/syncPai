import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/network/syncpai_poster_cache_manager.dart';
import 'package:sync_pai/features/catalog/data/services/catalog_persistent_store.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';

AnimeTitle _sample(int id, String title, {int latestEp = 4, String poster = 'https://ex.com/p1.jpg'}) {
  return AnimeTitle(
    id: id,
    code: 'code-$id',
    russianTitle: title,
    englishTitle: title,
    posterSmall: poster,
    posterMedium: poster,
    posterOriginal: poster,
    genres: const ['Экшен', 'Фэнтези'],
    description: 'Описание',
    status: 'ongoing',
    year: 2026,
    latestEpisode: latestEp,
    episodesTotal: 12,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CatalogPersistentStore & SyncPaiPosterCacheManager', () {
    late Directory tempDir;
    late File indexFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('syncpai_cat_cache_test_');
      indexFile = File('${tempDir.path}/catalog_index.json');
      CatalogPersistentStore.instance.setTestFile(indexFile);
    });

    tearDown(() async {
      CatalogPersistentStore.instance.setTestFile(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists catalog releases across sessions and merges ongoing delta updates',
        () async {
      final store = CatalogPersistentStore.instance;
      await store.init();
      expect(store.isEmpty, isTrue);

      final changed1 = await store.mergeAndPersist([
        _sample(101, 'Frieren S2', latestEp: 4),
        _sample(102, 'Solo Leveling', latestEp: 8),
      ]);
      expect(changed1, isTrue);
      expect(await indexFile.exists(), isTrue);

      // Имитируем перезапуск приложения: сбрасываем память и читаем с диска
      store.setTestFile(indexFile);
      await store.init();
      final restored = store.queryLocal(genre: 'Фэнтези');
      expect(restored.length, 2);
      expect(restored.first.latestEpisode, 4);

      // Повторная запись без изменений -> false
      final unchanged = await store.mergeAndPersist([
        _sample(101, 'Frieren S2', latestEp: 4),
      ]);
      expect(unchanged, isFalse);

      // Вышла 5-я серия онгоинга и обновился постер -> слияние и обновление на диске
      final updated = await store.mergeAndPersist([
        _sample(101, 'Frieren S2', latestEp: 5, poster: 'https://ex.com/p2.jpg'),
      ]);
      expect(updated, isTrue);

      final afterMerge = store.queryLocal();
      final item101 = afterMerge.firstWhere((t) => t.id == 101);
      expect(item101.latestEpisode, 5);
      expect(item101.posterMedium, 'https://ex.com/p2.jpg');

      await store.clear();
      expect(store.isEmpty, isTrue);
      expect(await indexFile.exists(), isFalse);
    });

    test('SyncPaiPosterCacheManager configures 30-day TTL and 2500 max objects', () {
      expect(SyncPaiPosterCacheManager.posterStalePeriod, const Duration(days: 30));
      expect(SyncPaiPosterCacheManager.maxPosterObjects, 2500);
      expect(SyncPaiPosterCacheManager.cacheKey, 'syncpai_poster_cache_v1');
    });
  });
}
