import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/services/device_performance_service.dart';
import '../../winter_theme/domain/services/winter_theme_service.dart';
import '../domain/entities/anime_title.dart';
import '../domain/usecases/get_catalog_usecase.dart';
import '../domain/usecases/get_updates.dart';

class _PrefetchEntry {
  final List<AnimeTitle> titles;
  final DateTime timestamp;

  const _PrefetchEntry({
    required this.titles,
    required this.timestamp,
  });
}

/// Сервис фонового предзагрузки категорий и жанров каталога (Tiered Background Prefetching)
/// с двухслойным кэшем (In-Memory + Disk JSON Cache), паузой при активном плеере
/// и умным разогревом обложек постеров с учетом мощности устройства.
class CatalogPrefetchService {
  static final CatalogPrefetchService instance = CatalogPrefetchService._();
  CatalogPrefetchService._();

  static const Duration freshTTL = Duration(minutes: 15);
  static const Duration staleTTL = Duration(hours: 24);
  static const Duration startupDelay = Duration(milliseconds: 2500);
  static const Duration requestSpacing = Duration(milliseconds: 450);

  static const List<String> prefetchBuckets = [
    'ongoing',
    'popular',
    'movies',
    'Экшен',
    'Фэнтези',
    'Романтика',
    'Приключения',
  ];

  final Map<String, _PrefetchEntry> _memoryCache = {};
  Timer? _startupTimer;
  CancelToken _prefetchCancelToken = CancelToken();
  bool _isQueueRunning = false;
  DateTime? _lastQueueRun;

  String _diskKey(String bucket) => 'catalog_prefetch_$bucket';

  /// Нормализация ключа категории / жанра
  String normalizeBucketKey(String key) {
    final clean = key.trim();
    if (clean.isEmpty || clean == 'Все') return 'all';
    if (clean == 'Онгоинги' || clean == 'ongoing' || clean == 'status_ongoing') return 'ongoing';
    if (clean == 'Популярное' || clean == 'popular' || clean == 'rating' || clean == 'sort_rating') return 'popular';
    if (clean == 'Фильмы' || clean == 'Фильм' || clean == 'movies') return 'movies';
    return clean;
  }

  /// Получение тайтлов из кэша в 0мс (сначала In-Memory, затем Disk Fallback)
  List<AnimeTitle>? getCached(String rawKey) {
    final key = normalizeBucketKey(rawKey);

    // 1. Проверяем In-Memory кэш
    if (_memoryCache.containsKey(key)) {
      final entry = _memoryCache[key]!;
      if (DateTime.now().difference(entry.timestamp) < staleTTL) {
        return entry.titles;
      } else {
        _memoryCache.remove(key);
      }
    }

    // 2. Проверяем персистентный диск (SharedPreferences)
    try {
      final prefs = _getPrefs();
      if (prefs != null) {
        final rawJson = prefs.getString(_diskKey(key));
        if (rawJson != null && rawJson.isNotEmpty) {
          final decoded = jsonDecode(rawJson);
          if (decoded is Map) {
            final ts = decoded['timestamp'] is int
                ? DateTime.fromMillisecondsSinceEpoch(decoded['timestamp'] as int)
                : DateTime.now();
            if (DateTime.now().difference(ts) < staleTTL && decoded['items'] is List) {
              final titles = (decoded['items'] as List)
                  .whereType<Map>()
                  .map((item) => AnimeTitle.fromJson(Map<String, dynamic>.from(item)))
                  .toList();
              if (titles.isNotEmpty) {
                _memoryCache[key] = _PrefetchEntry(titles: titles, timestamp: ts);
                return titles;
              }
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Свежий ли кэш (< 15 минут)
  bool isFresh(String rawKey) {
    final key = normalizeBucketKey(rawKey);
    final entry = _memoryCache[key];
    if (entry != null) {
      return DateTime.now().difference(entry.timestamp) < freshTTL;
    }
    return false;
  }

  /// Устарел ли кэш (>= 15 минут или отсутствует)
  bool isStale(String rawKey) {
    return !isFresh(rawKey);
  }

  /// Сохранение в двухслойный кэш (In-Memory + Disk JSON)
  Future<void> putCache(String rawKey, List<AnimeTitle> titles) async {
    if (titles.isEmpty) return;
    final key = normalizeBucketKey(rawKey);
    final now = DateTime.now();

    _memoryCache[key] = _PrefetchEntry(titles: titles, timestamp: now);

    try {
      final prefs = _getPrefs();
      if (prefs != null) {
        final payload = jsonEncode({
          'timestamp': now.millisecondsSinceEpoch,
          'items': titles.take(30).map((t) => t.toJson()).toList(),
        });
        await prefs.setString(_diskKey(key), payload);
      }
    } catch (_) {}
  }

  SharedPreferences? _getPrefs() {
    try {
      if (getIt.isRegistered<SharedPreferences>()) {
        return getIt<SharedPreferences>();
      }
    } catch (_) {}
    return null;
  }

  bool get _isTestEnv {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
      if (WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding')) return true;
    } catch (_) {}
    return false;
  }

  /// Запуск очереди предзагрузки категорий
  void startPrefetchQueue() {
    if (_isTestEnv) return;
    if (_isQueueRunning) return;

    // Не перезапускаем очередь чаще раза в 10 минут
    if (_lastQueueRun != null && DateTime.now().difference(_lastQueueRun!) < const Duration(minutes: 10)) {
      return;
    }

    if (_prefetchCancelToken.isCancelled) {
      _prefetchCancelToken = CancelToken();
    }

    _startupTimer?.cancel();
    _startupTimer = Timer(startupDelay, () {
      _runQueue();
    });
  }

  /// Останавливает фоновую очередь предзагрузки только при полном завершении работы
  void dispose() {
    _startupTimer?.cancel();
    _startupTimer = null;
    if (!_prefetchCancelToken.isCancelled) {
      _prefetchCancelToken.cancel('CatalogPrefetchService disposed');
    }
    _isQueueRunning = false;
  }

  Future<void> _runQueue() async {
    if (_isQueueRunning || _prefetchCancelToken.isCancelled) return;
    _isQueueRunning = true;
    _lastQueueRun = DateTime.now();

    try {
      for (final bucket in prefetchBuckets) {
        if (_prefetchCancelToken.isCancelled) break;

        // 1. Пауза очереди, если сейчас активен просмотр видео в плеере
        while (WinterThemeService.instance.isVideoPlayerActive) {
          if (_prefetchCancelToken.isCancelled) return;
          await Future.delayed(const Duration(seconds: 2));
        }

        // 2. Если уже есть свежий кэш (< 15 мин), пропускаем запрос к API
        if (isFresh(bucket)) {
          continue;
        }

        // 3. Выполняем последовательный сетевой запрос со своим независимым _prefetchCancelToken
        final titles = await _fetchBucketData(bucket);
        if (_prefetchCancelToken.isCancelled) break;

        if (titles.isNotEmpty) {
          await putCache(bucket, titles);

          // 4. Аппаратный прогрев обложек (первые 6 постеров на mid/high устройствах)
          _warmupImages(titles);
        }

        // 5. Задержка 450 мс между запросами для защиты от rate limits
        await Future.delayed(requestSpacing);
      }
    } catch (_) {
      // Игнорируем сетевые ошибки в фоновой предзагрузке
    } finally {
      _isQueueRunning = false;
    }
  }

  Future<List<AnimeTitle>> _fetchBucketData(String bucket) async {
    try {
      GetCatalogUseCase? useCase;
      if (getIt.isRegistered<GetCatalogUseCase>()) {
        useCase = getIt<GetCatalogUseCase>();
      }

      if (useCase != null) {
        String? status;
        String? sort;
        String? genres;

        switch (bucket) {
          case 'ongoing':
            status = 'ongoing';
            break;
          case 'popular':
            sort = 'rating';
            break;
          case 'movies':
            genres = 'Фильм';
            break;
          default:
            genres = bucket;
            break;
        }

        final entities = await useCase(
          page: 1,
          limit: 40,
          genres: genres,
          sort: sort,
          status: status,
          cancelToken: _prefetchCancelToken,
        );

        if (entities.isNotEmpty) {
          return entities.map((e) => e.toAnimeTitle()).toList();
        }
      }

      // Fallback на getUpdates
      if (getIt.isRegistered<GetUpdates>()) {
        return await getIt<GetUpdates>()(page: 1, limit: 40);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return [];
    } catch (_) {}

    return [];
  }

  /// Прогрев обложек с проверкой уровня производительности устройства
  void _warmupImages(List<AnimeTitle> titles) {
    final tier = DevicePerformanceService.instance.tier;
    if (tier == DeviceTier.low) {
      // На бюджетных устройствах пропускаем прогрев декодирования в ОЗУ
      return;
    }

    final countToWarm = math.min(6, titles.length);
    for (int i = 0; i < countToWarm; i++) {
      final url = titles[i].posterUrl;
      if (url.isNotEmpty) {
        try {
          final provider = CachedNetworkImageProvider(url);
          provider.resolve(const ImageConfiguration());
        } catch (_) {}
      }
    }
  }

  @visibleForTesting
  void clearCache() {
    _memoryCache.clear();
    _startupTimer?.cancel();
    _isQueueRunning = false;
    _lastQueueRun = null;
  }
}
