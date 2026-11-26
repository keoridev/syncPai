import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/catalog/domain/entities/anime_title.dart';

/// Автоматический многоисточниковый резолвер постеров аниме:
/// 1. Отбрасывает заглушки Shikimori (`missing_original`, `missing_preview`, `missing_x`).
/// 2. Проверяет кэш `anime_meta_cache` в Supabase.
/// 3. Батчем запрашивает AniList GraphQL (`idMal_in`) — 1 запрос на всю сетку «Анонсы».
/// 4. Фолбек на Jikan v4 (`/v4/anime/{malId}`) с очередью не более 3 параллельных запросов.
/// 5. Сохраняет найденные постеры в `anime_meta_cache`.
class AnimePosterResolver {
  AnimePosterResolver._();
  static final AnimePosterResolver instance = AnimePosterResolver._();

  static final Map<int, String> _memoryCache = {};
  static final Set<int> _emptyCache = {};
  static final Map<int, Future<String?>> _inFlightSingle = {};
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  static bool isMissingOrPlaceholder(String? url) {
    if (url == null || url.trim().isEmpty) return true;
    final lower = url.toLowerCase();
    return lower.contains('missing_original') ||
        lower.contains('missing_preview') ||
        lower.contains('missing_x') ||
        lower.contains('missing_') ||
        lower.contains('no_image') ||
        lower.contains('noimage') ||
        lower.contains('/assets/globals/');
  }

  static String? sanitizeUrl(String? url) {
    if (isMissingOrPlaceholder(url)) return null;
    return url!.trim();
  }

  String? getCachedPoster(int malId) => _memoryCache[malId];

  Future<Map<int, String>> resolveBatchPosters(List<AnimeTitle> titles) async {
    final resolved = <int, String>{};
    final missingIds = <int>[];

    for (final t in titles) {
      if (!isMissingOrPlaceholder(t.posterUrl)) continue;
      final malId = (t.shikimoriId != null && t.shikimoriId! > 0)
          ? t.shikimoriId!
          : t.id;
      if (malId <= 0) continue;
      final mem = _memoryCache[malId];
      if (mem != null) {
        resolved[malId] = mem;
      } else if (!_emptyCache.contains(malId) && !missingIds.contains(malId)) {
        missingIds.add(malId);
      }
    }

    if (missingIds.isEmpty) return resolved;

    // Step A: Supabase anime_meta_cache lookup
    final remainingAfterDb = <int>[];
    try {
      final keys = missingIds.map((id) => 'shiki_$id').toList();
      final rows = await Supabase.instance.client
          .from('anime_meta_cache')
          .select('shikimori_id, payload')
          .inFilter('anime_key', keys);

      final dbHits = <int>{};
      for (final row in rows as List) {
        if (row is! Map) continue;
        final id = (row['shikimori_id'] as num?)?.toInt();
        final payload = row['payload'] is Map ? row['payload'] as Map : null;
        final poster = sanitizeUrl(payload?['poster_url']?.toString());
        if (id != null && poster != null) {
          _memoryCache[id] = poster;
          resolved[id] = poster;
          dbHits.add(id);
        }
      }
      for (final id in missingIds) {
        if (!dbHits.contains(id)) remainingAfterDb.add(id);
      }
    } catch (_) {
      remainingAfterDb.addAll(missingIds);
    }

    if (remainingAfterDb.isEmpty) return resolved;

    // Step B: AniList GraphQL batch lookup (chunks of 25)
    final remainingAfterAnilist = <int>[];
    final newlyFound = <int, String>{};
    for (var i = 0; i < remainingAfterDb.length; i += 25) {
      final chunk = remainingAfterDb.sublist(
        i,
        (i + 25).clamp(0, remainingAfterDb.length),
      );
      final chunkHits = await _fetchAnilistBatch(chunk);
      for (final id in chunk) {
        final url = chunkHits[id];
        if (url != null) {
          _memoryCache[id] = url;
          resolved[id] = url;
          newlyFound[id] = url;
        } else {
          remainingAfterAnilist.add(id);
        }
      }
    }

    // Step C: Jikan v4 fallback (3-concurrent queue, capped to avoid rate limits)
    if (remainingAfterAnilist.isNotEmpty) {
      final jikanTargets = remainingAfterAnilist.take(12).toList();
      for (var i = 0; i < jikanTargets.length; i += 3) {
        final batch = jikanTargets.sublist(
          i,
          (i + 3).clamp(0, jikanTargets.length),
        );
        final results = await Future.wait(
          batch.map((id) async => MapEntry(id, await _fetchJikanSingle(id))),
        );
        for (final entry in results) {
          if (entry.value != null) {
            _memoryCache[entry.key] = entry.value!;
            resolved[entry.key] = entry.value!;
            newlyFound[entry.key] = entry.value!;
          } else {
            _emptyCache.add(entry.key);
          }
        }
      }
    }

    // Step D: Persist newly found posters to Supabase anime_meta_cache
    if (newlyFound.isNotEmpty) {
      unawaited(_persistToSupabase(newlyFound));
    }

    return resolved;
  }

  Future<String?> resolveSinglePoster({required int malId}) {
    if (malId <= 0) return Future.value(null);
    final mem = _memoryCache[malId];
    if (mem != null) return Future.value(mem);
    if (_emptyCache.contains(malId)) return Future.value(null);

    final existing = _inFlightSingle[malId];
    if (existing != null) return existing;

    final future = () async {
      try {
        final batchHits = await _fetchAnilistBatch([malId]);
        var url = batchHits[malId];
        url ??= await _fetchJikanSingle(malId);
        if (url != null) {
          _memoryCache[malId] = url;
          unawaited(_persistToSupabase({malId: url}));
          return url;
        }
        _emptyCache.add(malId);
        return null;
      } finally {
        _inFlightSingle.remove(malId);
      }
    }();

    _inFlightSingle[malId] = future;
    return future;
  }

  Future<Map<int, String>> _fetchAnilistBatch(List<int> malIds) async {
    if (malIds.isEmpty) return const {};
    const query = r'''
query ($ids: [Int]) {
  Page(perPage: 25) {
    media(idMal_in: $ids, type: ANIME) {
      idMal
      coverImage {
        extraLarge
        large
      }
    }
  }
}
''';
    try {
      final res = await _dio.post(
        'https://graphql.anilist.co',
        data: {
          'query': query,
          'variables': {'ids': malIds},
        },
        options: Options(
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final page = res.data['data']?['Page'];
        final media = page is Map ? page['media'] : null;
        if (media is List) {
          final out = <int, String>{};
          for (final item in media) {
            if (item is! Map) continue;
            final idMal = (item['idMal'] as num?)?.toInt();
            final cover = item['coverImage'] is Map
                ? item['coverImage'] as Map
                : null;
            final url = sanitizeUrl(
              (cover?['extraLarge'] ?? cover?['large'])?.toString(),
            );
            if (idMal != null && url != null) {
              out[idMal] = url;
            }
          }
          return out;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AnimePosterResolver] AniList batch error: $e');
      }
    }
    return const {};
  }

  Future<String?> _fetchJikanSingle(int malId) async {
    try {
      final res = await _dio.get('https://api.jikan.moe/v4/anime/$malId');
      if (res.statusCode == 200 && res.data is Map) {
        final images = res.data['data']?['images'];
        if (images is Map) {
          final webp = images['webp'] is Map ? images['webp'] as Map : null;
          final jpg = images['jpg'] is Map ? images['jpg'] as Map : null;
          return sanitizeUrl(
            (webp?['large_image_url'] ??
                    jpg?['large_image_url'] ??
                    webp?['image_url'] ??
                    jpg?['image_url'])
                ?.toString(),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistToSupabase(Map<int, String> posters) async {
    try {
      final client = Supabase.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = posters.entries
          .map((e) => {
                'anime_key': 'shiki_${e.key}',
                'shikimori_id': e.key,
                'payload': {'poster_url': e.value},
                'updated_at': now,
              })
          .toList();
      await client
          .from('anime_meta_cache')
          .upsert(rows, onConflict: 'anime_key');
    } catch (_) {}
  }
}

