import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Ограниченный 30-дневный дисковый кэш для постеров аниме (~120–180 МБ).
/// Использует URL постера в качестве ключа кэша и автоматически обновляет TTL при чтении.
class SyncPaiPosterCacheManager extends CacheManager with ImageCacheManager {
  static const String cacheKey = 'syncpai_poster_cache_v1';
  static const Duration posterStalePeriod = Duration(days: 30);
  static const int maxPosterObjects = 2500;

  static SyncPaiPosterCacheManager? _instance;
  static SyncPaiPosterCacheManager get instance {
    return _instance ??= SyncPaiPosterCacheManager._();
  }

  SyncPaiPosterCacheManager._()
      : super(
          Config(
            cacheKey,
            stalePeriod: posterStalePeriod,
            maxNrOfCacheObjects: maxPosterObjects,
          ),
        );

  /// Подсчёт фактического объёма кэша обложек на диске (в байтах).
  static Future<int> getDiskUsageBytes() async {
    if (kIsWeb) return 0;
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory('${tempDir.path}/$cacheKey');
      if (!await cacheDir.exists()) return 0;
      int total = 0;
      await for (final entity in cacheDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<double> getDiskUsageMb() async {
    final bytes = await getDiskUsageBytes();
    return bytes / (1024 * 1024);
  }

  static Future<void> clearPosterCache() async {
    try {
      await instance.emptyCache();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        final tempDir = await getTemporaryDirectory();
        final cacheDir = Directory('${tempDir.path}/$cacheKey');
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}

