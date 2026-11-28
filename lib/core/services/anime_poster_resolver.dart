import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/catalog/domain/entities/anime_entity.dart';
import '../../features/catalog/domain/entities/anime_title.dart';
import 'playback_bandwidth_guard.dart';

class PosterCandidate {
  final String source;
  final String url;

  const PosterCandidate(this.source, this.url);
}

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
  static final Map<String, String> _titleMemoryCache = {};
  static final Set<String> _titleEmptyCache = {};
  static final Map<String, Future<String?>> _inFlightTitle = {};
  static final Map<String, bool> _aspectRatioCache = {};
  static final ValueNotifier<int> overrideRevision = ValueNotifier<int>(0);
  static const String _v3CacheKey = 'poster_url_cache_v3';
  static bool _prefsLoaded = false;
  static Future<void>? _prefsLoadFuture;
  static Timer? _saveDebounceTimer;
  static const int _maxConcurrentResolves = 4;
  static int _activeResolves = 0;
  static final List<Completer<void>> _resolveWaiters = [];

  static Future<void> _anilistQueueTail = Future<void>.value();
  static DateTime? _lastAnilistAt;
  static DateTime? _anilistRateLimitedUntil;
  static const Duration _anilistMinInterval = Duration(milliseconds: 1200);
  static final Set<int> _pendingAnilistIds = {};
  static final Map<int, Completer<String?>> _pendingAnilistCompleters = {};
  static Timer? _anilistCoalesceTimer;

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

  static bool isAniLibriaWatermarkedUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('anilibria.top') ||
        lower.contains('anilibria.tv') ||
        lower.contains('anilibria.app') ||
        lower.contains('anilibria') ||
        lower.contains('libria') ||
        lower.contains('weekstorm');
  }

  static String? extractFranchiseParentTitle(String raw) {
    var parent = raw.trim();
    if (parent.isEmpty) return null;
    parent = parent.replaceAll(
      RegExp(r'\s*[—–-]\s*(новая озвучка|переозвучка).*', caseSensitive: false),
      '',
    );
    parent = parent.replaceAll(
      RegExp(
        r'\s*(?:сезон|season|part|часть|tv)\s*\d+$',
        caseSensitive: false,
      ),
      '',
    );
    parent = parent.replaceAll(
      RegExp(r'\s+\d+(?:\s*(?:nd|rd|th))?$', caseSensitive: false),
      '',
    );
    parent = parent.replaceAll(
      RegExp(r'\s+(?:II|III|IV|V)$'),
      '',
    );
    if (parent.contains(':')) {
      parent = parent.split(':').first.trim();
    }
    parent = parent.trim();
    if (parent.isEmpty || parent.toLowerCase() == raw.trim().toLowerCase()) {
      return null;
    }
    return parent;
  }

  /// Ранняя гидрация дискового кэша постеров в память на старте приложения.
  static Future<void> init({SharedPreferences? prefs}) =>
      instance._ensurePrefsLoaded(prefsOverride: prefs);

  Future<void> _ensurePrefsLoaded({SharedPreferences? prefsOverride}) {
    if (_prefsLoaded) return Future.value();
    return _prefsLoadFuture ??= () async {
      try {
        final prefs = prefsOverride ?? await SharedPreferences.getInstance();
        final v3Raw = prefs.getString(_v3CacheKey);
        if (v3Raw != null && v3Raw.isNotEmpty) {
          final decoded = jsonDecode(v3Raw);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final k = entry.key.toString();
              final v = sanitizeUrl(entry.value?.toString());
              if (k.isEmpty || v == null || isAniLibriaWatermarkedUrl(v)) {
                continue;
              }
              if (k.startsWith('id:')) {
                final id = int.tryParse(k.substring(3));
                if (id != null && id > 0) {
                  _memoryCache.putIfAbsent(id, () => v);
                }
              } else {
                _titleMemoryCache.putIfAbsent(k, () => v);
              }
            }
          }
        }
      } catch (_) {
      } finally {
        _prefsLoaded = true;
      }
    }();
  }

  Future<void> _saveTitleCacheToPrefs() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final combined = <String, String>{};
        final idEntries = _memoryCache.entries.toList();
        final cappedIds = idEntries.length > 600
            ? idEntries.sublist(idEntries.length - 600)
            : idEntries;
        for (final e in cappedIds) {
          combined['id:${e.key}'] = e.value;
        }
        final titleEntries = _titleMemoryCache.entries.toList();
        final cappedTitles = titleEntries.length > 400
            ? titleEntries.sublist(titleEntries.length - 400)
            : titleEntries;
        for (final e in cappedTitles) {
          combined[e.key] = e.value;
        }
        await prefs.setString(_v3CacheKey, jsonEncode(combined));
      } catch (_) {}
    });
  }

  void _prefetchImageBytes(Iterable<String> urls) {
    if (PlaybackBandwidthGuard.isVideoPlaying.value) return;
    final unique = urls.where((u) => u.startsWith('http')).toSet().take(18).toList();
    if (unique.isEmpty) return;
    unawaited(() async {
      for (var i = 0; i < unique.length; i += 6) {
        if (PlaybackBandwidthGuard.isVideoPlaying.value) return;
        final chunk = unique.sublist(i, (i + 6).clamp(0, unique.length));
        await Future.wait(
          chunk.map(
            (url) => DefaultCacheManager()
                .downloadFile(url)
                .then<void>((_) {}, onError: (_) {}),
          ),
        );
      }
    }());
  }

  static String normalizeTitleKey(String raw) {
    var clean = raw.toLowerCase();
    clean = clean.replaceAll(
      RegExp(r'^.*?представляют\s*[—–:\-]\s*', caseSensitive: false),
      '',
    );
    clean = clean.replaceAll(
      RegExp(r'\bpresents\s*[—–:\-]\s*', caseSensitive: false),
      ' ',
    );
    clean = clean.replaceAll(
      RegExp(r'\s*[—–-]\s*(новая озвучка|переозвучка).*'),
      '',
    );
    clean = clean.replaceAll(
      RegExp(r'\b(?:часть|part)\s*\d*\b', caseSensitive: false),
      ' ',
    );
    clean = clean.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    clean = clean.replaceAll(RegExp(r'[^a-z0-9а-яё\s]'), ' ');
    return clean.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool isShikimoriUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('shikimori.');
  }

  /// Проверяет, что постер имеет вертикальные пропорции (`width / height <= 0.82`)
  /// и не является квадратным/широким тизерным кадром (`制作決定`).
  Future<bool> isVerticalKeyArt(String url) async {
    final cached = _aspectRatioCache[url];
    if (cached != null) return cached;
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(milliseconds: 2500),
          headers: const {'User-Agent': 'SyncPai-App/1.0'},
        ),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        _aspectRatioCache[url] = false;
        return false;
      }
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(data));
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      final ok = h > 0 && (w / h) <= 0.82;
      _aspectRatioCache[url] = ok;
      return ok;
    } catch (_) {
      return false;
    }
  }

  String? getCachedPoster(int malId) => _memoryCache[malId];

  String? getCachedSync({
    int? malId,
    String? title,
    String? englishTitle,
  }) {
    final hit = getCachedCleanPoster(malId: malId, title: title) ??
        (englishTitle != null && englishTitle.trim().isNotEmpty
            ? getCachedCleanPoster(title: englishTitle)
            : null);
    if (hit == null || isAniLibriaWatermarkedUrl(hit)) return null;
    return hit;
  }

  String? getCachedCleanPoster({int? malId, String? title}) {
    if (malId != null && malId > 0) {
      final byId = _memoryCache[malId];
      if (byId != null && !isAniLibriaWatermarkedUrl(byId)) return byId;
    }
    if (title != null && title.trim().isNotEmpty) {
      final key = normalizeTitleKey(title);
      if (key.isNotEmpty) {
        final byTitle = _titleMemoryCache[key];
        if (byTitle != null && !isAniLibriaWatermarkedUrl(byTitle)) {
          return byTitle;
        }
      }
    }
    return null;
  }

  /// Синхронно применяет кэшированные постеры за 0 мс, удаляя watermarked AniLibria URL,
  /// и запускает фоновое пакетное разрешение недостающих обложек без блокировки UI.
  List<AnimeEntity> applyCachedPostersSyncEntities(List<AnimeEntity> entities) {
    if (entities.isEmpty) return entities;
    final updated = List<AnimeEntity>.from(entities);
    var hasUnresolved = false;

    for (var i = 0; i < updated.length; i++) {
      final e = updated[i];
      final sanitized = sanitizeUrl(e.posterUrl);
      final isShikiTeaserRisk = isShikimoriUrl(sanitized) &&
          ((e.year == null || e.year! >= 2025) ||
              (sanitized?.contains('/preview/') ?? false));
      final isClean = sanitized != null &&
          !isAniLibriaWatermarkedUrl(sanitized) &&
          !isShikiTeaserRisk;
      if (isClean) continue;

      final preservedFallback = isAniLibriaWatermarkedUrl(e.posterUrl)
          ? e.posterUrl!
          : (sanitized ?? e.fallbackPosterUrl);
      final cached = getCachedSync(
        malId: e.shikimoriId > 0 ? e.shikimoriId : null,
        title: e.titleRu,
        englishTitle: e.titleEn,
      );
      if (cached != null) {
        updated[i] = e.copyWith(
          posterUrl: cached,
          fallbackPosterUrl: preservedFallback,
        );
      } else {
        updated[i] = e.copyWith(
          clearPosterUrl: true,
          fallbackPosterUrl: preservedFallback,
        );
        hasUnresolved = true;
      }
    }

    if (hasUnresolved && !PlaybackBandwidthGuard.isVideoPlaying.value) {
      unawaited(resolveBatchEntities(updated));
    }
    return updated;
  }

  /// Синхронно применяет кэшированные постеры [AnimeTitle] за 0 мс и догружает недостающие в фоне.
  List<AnimeTitle> applyCachedPostersSync(List<AnimeTitle> titles) {
    if (titles.isEmpty) return titles;
    final updated = List<AnimeTitle>.from(titles);
    var hasUnresolved = false;

    for (var i = 0; i < updated.length; i++) {
      final t = updated[i];
      final sanitized = sanitizeUrl(t.posterUrl);
      final isShikiTeaserRisk = isShikimoriUrl(sanitized) &&
          ((t.year == null || t.year! >= 2025) ||
              (sanitized?.contains('/preview/') ?? false));
      final isClean = sanitized != null &&
          !isAniLibriaWatermarkedUrl(sanitized) &&
          !isShikiTeaserRisk;
      if (isClean) continue;

      final preservedFallback = isAniLibriaWatermarkedUrl(t.posterUrl)
          ? t.posterUrl
          : (sanitized ?? t.fallbackPosterUrl);
      final malId = (t.shikimoriId != null && t.shikimoriId! > 0)
          ? t.shikimoriId!
          : t.id;
      final cached = getCachedSync(
        malId: malId > 0 ? malId : null,
        title: t.russianTitle.isNotEmpty ? t.russianTitle : t.displayTitle,
        englishTitle: t.englishTitle,
      );
      if (cached != null) {
        updated[i] = t.copyWith(
          posterSmall: cached,
          posterMedium: cached,
          posterOriginal: cached,
          fallbackPosterUrl: preservedFallback,
        );
      } else {
        updated[i] = t.copyWith(
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          fallbackPosterUrl: preservedFallback,
        );
        hasUnresolved = true;
      }
    }

    if (hasUnresolved && !PlaybackBandwidthGuard.isVideoPlaying.value) {
      unawaited(resolveBatch(updated));
    }
    return updated;
  }

  /// Батч-резолв чистых обложек для [AnimeEntity] до эмита в UI.
  /// Удаляет временные watermarked URL AniLibria из [posterUrl] (сохраняя их в [fallbackPosterUrl]).
  Future<List<AnimeEntity>> resolveBatchEntities(
    List<AnimeEntity> entities,
  ) async {
    if (entities.isEmpty) return entities;
    await _ensurePrefsLoaded();

    final updated = List<AnimeEntity>.from(entities);
    final unresolvedIndices = <int>[];
    final missingMalIds = <int>[];

    for (var i = 0; i < updated.length; i++) {
      final e = updated[i];
      final sanitized = sanitizeUrl(e.posterUrl);
      final isShikiTeaserRisk = isShikimoriUrl(sanitized) &&
          ((e.year == null || e.year! >= 2025) ||
              (sanitized?.contains('/preview/') ?? false));
      final isClean = sanitized != null &&
          !isAniLibriaWatermarkedUrl(sanitized) &&
          !isShikiTeaserRisk;
      if (isClean) continue;

      final preservedFallback = isAniLibriaWatermarkedUrl(e.posterUrl)
          ? e.posterUrl!
          : (sanitized ?? e.fallbackPosterUrl);
      final cached = getCachedSync(
        malId: e.shikimoriId > 0 ? e.shikimoriId : null,
        title: e.titleRu,
        englishTitle: e.titleEn,
      );
      if (cached != null) {
        updated[i] = e.copyWith(
          posterUrl: cached,
          fallbackPosterUrl: preservedFallback,
        );
      } else {
        updated[i] = e.copyWith(
          clearPosterUrl: true,
          fallbackPosterUrl: preservedFallback,
        );
        unresolvedIndices.add(i);
        if (e.shikimoriId > 0 && !missingMalIds.contains(e.shikimoriId)) {
          missingMalIds.add(e.shikimoriId);
        }
      }
    }

    if (unresolvedIndices.isEmpty || PlaybackBandwidthGuard.isVideoPlaying.value) {
      return updated;
    }

    final idHits = missingMalIds.isNotEmpty
        ? await resolveBatchIds(missingMalIds).timeout(
            const Duration(seconds: 3),
            onTimeout: () => const <int, String>{},
          )
        : const <int, String>{};

    final stillMissing = <int>[];
    for (final idx in unresolvedIndices) {
      final e = updated[idx];
      final hit = e.shikimoriId > 0 ? idHits[e.shikimoriId] : null;
      if (hit != null) {
        updated[idx] = e.copyWith(posterUrl: hit);
      } else if (e.displayTitle.trim().isNotEmpty) {
        stillMissing.add(idx);
      }
    }

    if (stillMissing.isNotEmpty) {
      final resolvedList = await Future.wait(
        stillMissing.take(16).map((idx) async {
          final e = updated[idx];
          final url = await resolvePoster(
            malId: e.shikimoriId > 0 ? e.shikimoriId : null,
            title: e.displayTitle,
            fallbackTitle: e.titleEn.isNotEmpty ? e.titleEn : null,
          );
          return MapEntry(idx, url);
        }),
      ).timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => const <MapEntry<int, String?>>[],
      );
      final prefetched = <String>[];
      for (final entry in resolvedList) {
        final url = entry.value;
        if (url != null && !isAniLibriaWatermarkedUrl(url)) {
          updated[entry.key] = updated[entry.key].copyWith(posterUrl: url);
          prefetched.add(url);
        }
      }
      if (prefetched.isNotEmpty) {
        _prefetchImageBytes(prefetched);
      }
    }

    return updated;
  }

  /// Батч-резолв чистых обложек для [AnimeTitle] до эмита в UI.
  Future<List<AnimeTitle>> resolveBatch(List<AnimeTitle> titles) async {
    if (titles.isEmpty) return titles;
    await _ensurePrefsLoaded();

    final updated = List<AnimeTitle>.from(titles);
    final unresolvedIndices = <int>[];
    final missingMalIds = <int>[];

    for (var i = 0; i < updated.length; i++) {
      final t = updated[i];
      final sanitized = sanitizeUrl(t.posterUrl);
      final isShikiTeaserRisk = isShikimoriUrl(sanitized) &&
          ((t.year == null || t.year! >= 2025) ||
              (sanitized?.contains('/preview/') ?? false));
      final isClean = sanitized != null &&
          !isAniLibriaWatermarkedUrl(sanitized) &&
          !isShikiTeaserRisk;
      if (isClean) continue;

      final preservedFallback = isAniLibriaWatermarkedUrl(t.posterUrl)
          ? t.posterUrl
          : (sanitized ?? t.fallbackPosterUrl);
      final malId = (t.shikimoriId != null && t.shikimoriId! > 0)
          ? t.shikimoriId!
          : t.id;
      final cached = getCachedSync(
        malId: malId > 0 ? malId : null,
        title: t.russianTitle.isNotEmpty ? t.russianTitle : t.displayTitle,
        englishTitle: t.englishTitle,
      );
      if (cached != null) {
        updated[i] = t.copyWith(
          posterSmall: cached,
          posterMedium: cached,
          posterOriginal: cached,
          fallbackPosterUrl: preservedFallback,
        );
      } else {
        updated[i] = t.copyWith(
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          fallbackPosterUrl: preservedFallback,
        );
        unresolvedIndices.add(i);
        if (malId > 0 && !missingMalIds.contains(malId)) {
          missingMalIds.add(malId);
        }
      }
    }

    if (unresolvedIndices.isEmpty || PlaybackBandwidthGuard.isVideoPlaying.value) {
      return updated;
    }

    final idHits = missingMalIds.isNotEmpty
        ? await resolveBatchIds(missingMalIds).timeout(
            const Duration(seconds: 3),
            onTimeout: () => const <int, String>{},
          )
        : const <int, String>{};

    final stillMissing = <int>[];
    for (final idx in unresolvedIndices) {
      final t = updated[idx];
      final malId = (t.shikimoriId != null && t.shikimoriId! > 0)
          ? t.shikimoriId!
          : t.id;
      final hit = malId > 0 ? idHits[malId] : null;
      if (hit != null) {
        updated[idx] = t.copyWith(
          posterSmall: hit,
          posterMedium: hit,
          posterOriginal: hit,
        );
      } else if (t.displayTitle.trim().isNotEmpty) {
        stillMissing.add(idx);
      }
    }

    if (stillMissing.isNotEmpty) {
      final resolvedList = await Future.wait(
        stillMissing.take(16).map((idx) async {
          final t = updated[idx];
          final malId = (t.shikimoriId != null && t.shikimoriId! > 0)
              ? t.shikimoriId
              : t.id;
          final url = await resolvePoster(
            malId: malId,
            title: t.displayTitle,
            fallbackTitle: t.englishTitle.isNotEmpty ? t.englishTitle : null,
          );
          return MapEntry(idx, url);
        }),
      ).timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => const <MapEntry<int, String?>>[],
      );
      for (final entry in resolvedList) {
        final url = entry.value;
        if (url != null && !isAniLibriaWatermarkedUrl(url)) {
          updated[entry.key] = updated[entry.key].copyWith(
            posterSmall: url,
            posterMedium: url,
            posterOriginal: url,
          );
        }
      }
    }

    return updated;
  }

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

    if (missingIds.isEmpty || PlaybackBandwidthGuard.isVideoPlaying.value) {
      return resolved;
    }

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

    // Step A2: Shikimori bulk ID lookup (/api/animes?ids=...)
    final remainingAfterShiki = <int>[];
    final newlyFound = <int, String>{};
    for (var i = 0; i < remainingAfterDb.length; i += 50) {
      final chunk = remainingAfterDb.sublist(
        i,
        (i + 50).clamp(0, remainingAfterDb.length),
      );
      final shikiHits = await _fetchShikimoriBulkByIds(chunk);
      for (final id in chunk) {
        final url = shikiHits[id];
        if (url != null) {
          _memoryCache[id] = url;
          resolved[id] = url;
          newlyFound[id] = url;
        } else {
          remainingAfterShiki.add(id);
        }
      }
    }

    if (remainingAfterShiki.isEmpty) {
      if (newlyFound.isNotEmpty) unawaited(_persistToSupabase(newlyFound));
      return resolved;
    }

    // Step B: AniList GraphQL multi-alias batch lookup (chunks of 20, rate-limited)
    final remainingAfterAnilist = <int>[];
    for (var i = 0; i < remainingAfterShiki.length; i += 20) {
      final chunk = remainingAfterShiki.sublist(
        i,
        (i + 20).clamp(0, remainingAfterShiki.length),
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

  Future<Map<int, String>> resolveBatchIds(List<int> malIds) async {
    await _ensurePrefsLoaded();
    final resolved = <int, String>{};
    final missingIds = <int>[];

    for (final id in malIds) {
      if (id <= 0) continue;
      final mem = _memoryCache[id];
      if (mem != null) {
        resolved[id] = mem;
      } else if (!_emptyCache.contains(id) && !missingIds.contains(id)) {
        missingIds.add(id);
      }
    }
    if (missingIds.isEmpty || PlaybackBandwidthGuard.isVideoPlaying.value) {
      return resolved;
    }

    final remainingAfterAnilist = <int>[];
    final newlyFound = <int, String>{};
    for (var i = 0; i < missingIds.length; i += 25) {
      final chunk = missingIds.sublist(
        i,
        (i + 25).clamp(0, missingIds.length),
      );
      final anilistHits = await _fetchAnilistBatch(chunk);
      for (final id in chunk) {
        final url = anilistHits[id];
        if (url != null) {
          _memoryCache[id] = url;
          resolved[id] = url;
          newlyFound[id] = url;
        } else {
          remainingAfterAnilist.add(id);
        }
      }
    }

    final remainingAfterShiki = <int>[];
    for (var i = 0; i < remainingAfterAnilist.length; i += 50) {
      final chunk = remainingAfterAnilist.sublist(
        i,
        (i + 50).clamp(0, remainingAfterAnilist.length),
      );
      final shikiHits = await _fetchShikimoriBulkByIds(chunk);
      for (final id in chunk) {
        final url = shikiHits[id];
        if (url != null && await isVerticalKeyArt(url)) {
          _memoryCache[id] = url;
          resolved[id] = url;
          newlyFound[id] = url;
        } else {
          remainingAfterShiki.add(id);
        }
      }
    }

    if (remainingAfterShiki.isNotEmpty) {
      for (final id in remainingAfterShiki.take(6)) {
        final jikanUrl = await _fetchJikanSingle(id);
        if (jikanUrl != null) {
          _memoryCache[id] = jikanUrl;
          resolved[id] = jikanUrl;
          newlyFound[id] = jikanUrl;
        }
      }
    }

    if (newlyFound.isNotEmpty) {
      unawaited(_saveTitleCacheToPrefs());
      _prefetchImageBytes(newlyFound.values);
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

    final completer = Completer<String?>();
    _pendingAnilistCompleters[malId] = completer;
    _pendingAnilistIds.add(malId);
    _inFlightSingle[malId] = completer.future;

    if (_pendingAnilistIds.length >= 25) {
      _anilistCoalesceTimer?.cancel();
      _flushPendingAnilistBatch();
    } else {
      _anilistCoalesceTimer ??= Timer(
        const Duration(milliseconds: 50),
        _flushPendingAnilistBatch,
      );
    }

    return completer.future;
  }

  void _flushPendingAnilistBatch() {
    _anilistCoalesceTimer = null;
    if (_pendingAnilistIds.isEmpty) return;
    final batch = _pendingAnilistIds.take(25).toList();
    _pendingAnilistIds.removeAll(batch);
    if (_pendingAnilistIds.isNotEmpty) {
      _anilistCoalesceTimer = Timer(
        const Duration(milliseconds: 50),
        _flushPendingAnilistBatch,
      );
    }

    unawaited(() async {
      try {
        final anilistHits = await _fetchAnilistBatch(batch);
        final missingAfterAnilist =
            batch.where((id) => !anilistHits.containsKey(id)).toList();
        final shikiHits = missingAfterAnilist.isNotEmpty
            ? await _fetchShikimoriBulkByIds(missingAfterAnilist)
            : const <int, String>{};

        final newlyFound = <int, String>{};
        for (final id in batch) {
          var url = anilistHits[id];
          if (url == null) {
            final shikiUrl = shikiHits[id];
            if (shikiUrl != null && await isVerticalKeyArt(shikiUrl)) {
              url = shikiUrl;
            } else {
              url = await _fetchJikanSingle(id);
            }
          }
          if (url != null) {
            _memoryCache[id] = url;
            newlyFound[id] = url;
          } else {
            _emptyCache.add(id);
          }
          _pendingAnilistCompleters.remove(id)?.complete(url);
          _inFlightSingle.remove(id);
        }
        if (newlyFound.isNotEmpty) {
          unawaited(_saveTitleCacheToPrefs());
          _prefetchImageBytes(newlyFound.values);
          unawaited(_persistToSupabase(newlyFound));
        }
      } catch (_) {
        for (final id in batch) {
          _pendingAnilistCompleters.remove(id)?.complete(null);
          _inFlightSingle.remove(id);
        }
      }
    }());
  }

  Future<String?> resolveCleanPoster({
    int? malId,
    required String title,
    String? fallbackTitle,
  }) =>
      resolvePoster(
        malId: malId,
        title: title,
        fallbackTitle: fallbackTitle,
      );

  Future<void> _acquireResolveSlot() async {
    if (_activeResolves < _maxConcurrentResolves) {
      _activeResolves++;
      return;
    }
    final completer = Completer<void>();
    _resolveWaiters.add(completer);
    await completer.future;
  }

  void _releaseResolveSlot() {
    if (_resolveWaiters.isNotEmpty) {
      final next = _resolveWaiters.removeAt(0);
      if (!next.isCompleted) next.complete();
    } else if (_activeResolves > 0) {
      _activeResolves--;
    }
  }

  Future<String?> resolvePoster({
    int? malId,
    required String title,
    String? fallbackTitle,
    String? mediaType,
  }) async {
    await _ensurePrefsLoaded();
    final cached = getCachedCleanPoster(malId: malId, title: title) ??
        (fallbackTitle != null
            ? getCachedCleanPoster(title: fallbackTitle)
            : null);
    if (cached != null) return cached;
    if (PlaybackBandwidthGuard.isVideoPlaying.value) return null;

    final key = normalizeTitleKey(title);
    if (key.isEmpty && (malId == null || malId <= 0)) return null;
    if (key.isNotEmpty && _titleMemoryCache.containsKey(key)) {
      return _titleMemoryCache[key];
    }
    if (key.isNotEmpty && _titleEmptyCache.contains(key)) return null;

    if (key.isNotEmpty) {
      final existing = _inFlightTitle[key];
      if (existing != null) return existing;
    }

    final future = () async {
      await _acquireResolveSlot();
      try {
        if (malId != null && malId > 0) {
          final byId = await resolveSinglePoster(malId: malId);
          if (byId != null) {
            if (key.isNotEmpty) {
              _titleMemoryCache[key] = byId;
              unawaited(_saveTitleCacheToPrefs());
            }
            return byId;
          }
        }

        if (key.isEmpty) return null;

        final parentRu = extractFranchiseParentTitle(title);
        final parentEn = fallbackTitle != null
            ? extractFranchiseParentTitle(fallbackTitle)
            : null;
        final queries = <String>[
          if (fallbackTitle != null && fallbackTitle.trim().isNotEmpty)
            normalizeTitleKey(fallbackTitle),
          key,
          if (parentEn != null) normalizeTitleKey(parentEn),
          if (parentRu != null) normalizeTitleKey(parentRu),
        ].where((q) => q.isNotEmpty).toSet().toList();

        String? url;
        final isMangaOrRanobe = mediaType == 'manga' || mediaType == 'ranobe';
        if (isMangaOrRanobe) {
          for (final q in queries) {
            url = await _fetchShikimoriMangaOrRanobeBySearch(
              q,
              ranobeFirst: mediaType == 'ranobe',
            );
            if (url != null) break;
          }
        }
        if (url == null) {
          for (final q in queries) {
            url = await _fetchAnilistBySearch(q);
            if (url != null) break;
          }
        }
        if (url == null) {
          for (final q in queries) {
            url = await _fetchJikanBySearch(q);
            if (url != null) break;
          }
        }
        if (url == null) {
          for (final q in queries) {
            final shikiUrl = await _fetchShikimoriBySearch(q);
            if (shikiUrl != null && await isVerticalKeyArt(shikiUrl)) {
              url = shikiUrl;
              break;
            }
          }
        }
        if (url == null && !isMangaOrRanobe) {
          for (final q in queries) {
            url = await _fetchShikimoriMangaOrRanobeBySearch(q);
            if (url != null) break;
          }
        }
        if (url != null) {
          _titleMemoryCache[key] = url;
          unawaited(_saveTitleCacheToPrefs());
          return url;
        }
        _titleEmptyCache.add(key);
        return null;
      } finally {
        _releaseResolveSlot();
        if (key.isNotEmpty) _inFlightTitle.remove(key);
      }
    }();

    if (key.isNotEmpty) {
      _inFlightTitle[key] = future;
    }
    return future;
  }

  static int? _extractSequelNumber(String raw) {
    final lower = raw.toLowerCase();
    final mSeason = RegExp(
      r'(?:сезон|season|part|часть)\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (mSeason != null) return int.tryParse(mSeason.group(1)!);
    final mTrailing = RegExp(r'\b(\d+)\s*$').firstMatch(lower.trim());
    if (mTrailing != null) return int.tryParse(mTrailing.group(1)!);
    final mRoman = RegExp(r'\b(II|III|IV|V)\s*$').firstMatch(raw.trim());
    if (mRoman != null) {
      switch (mRoman.group(1)) {
        case 'II':
          return 2;
        case 'III':
          return 3;
        case 'IV':
          return 4;
        case 'V':
          return 5;
      }
    }
    return null;
  }

  static bool isTitleMatchStrict(String query, List<String?> candidates) {
    final qNorm = normalizeTitleKey(query);
    if (qNorm.isEmpty) return false;
    final qTokens = qNorm.split(' ').where((t) => t.isNotEmpty).toSet();
    if (qTokens.isEmpty) return false;
    final qSeq = _extractSequelNumber(query);

    for (final cand in candidates) {
      if (cand == null || cand.trim().isEmpty) continue;
      final cNorm = normalizeTitleKey(cand);
      if (cNorm.isEmpty) continue;
      final cTokens = cNorm.split(' ').where((t) => t.isNotEmpty).toSet();
      if (cTokens.isEmpty) continue;
      final maxLen =
          qTokens.length > cTokens.length ? qTokens.length : cTokens.length;
      final overlap = qTokens.intersection(cTokens).length / maxLen;
      final cSeq = _extractSequelNumber(cand);
      final seqMatches = (qSeq == null && cSeq == null) || (qSeq == cSeq);
      if (overlap >= 0.75 && seqMatches) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _fetchJikanBySearch(String search) async {
    try {
      final res = await _dio.get(
        'https://api.jikan.moe/v4/anime',
        queryParameters: {'q': search, 'limit': 3},
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data['data'];
        if (data is List) {
          for (final item in data) {
            if (item is! Map) continue;
            if (!isTitleMatchStrict(search, [
              item['title']?.toString(),
              item['title_english']?.toString(),
            ])) {
              continue;
            }
            final images = item['images'];
            if (images is Map) {
              final webp = images['webp'] is Map ? images['webp'] as Map : null;
              final jpg = images['jpg'] is Map ? images['jpg'] as Map : null;
              final url = sanitizeUrl(
                (webp?['large_image_url'] ??
                        jpg?['large_image_url'] ??
                        webp?['image_url'] ??
                        jpg?['image_url'])
                    ?.toString(),
              );
              if (url != null) return url;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _fetchAnilistBySearch(String search) async {
    const query = r'''
query ($search: String) {
  Media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
    idMal
    title {
      romaji
      english
      native
    }
    coverImage {
      extraLarge
      large
    }
  }
}
''';
    try {
      final blockedUntil = _anilistRateLimitedUntil;
      if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
        return null;
      }
      final res = await _enqueueAnilistRequest(
        () => _dio.post(
          'https://graphql.anilist.co',
          data: {
            'query': query,
            'variables': {'search': search},
          },
          options: Options(
            validateStatus: (status) => status != null && status < 500,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ),
      );
      if ((res.statusCode == 200 || res.statusCode == 404) && res.data is Map) {
        final media = res.data['data']?['Media'];
        if (media is Map) {
          final titleObj = media['title'] is Map ? media['title'] as Map : null;
          if (!isTitleMatchStrict(search, [
            titleObj?['romaji']?.toString(),
            titleObj?['english']?.toString(),
            titleObj?['native']?.toString(),
          ])) {
            return null;
          }
          final cover =
              media['coverImage'] is Map ? media['coverImage'] as Map : null;
          final url = sanitizeUrl(
            (cover?['extraLarge'] ?? cover?['large'])?.toString(),
          );
          final idMal = (media['idMal'] as num?)?.toInt();
          if (url != null) {
            if (idMal != null && idMal > 0) {
              _memoryCache[idMal] = url;
            }
            return url;
          }
        }
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        final retryAfterRaw = e.response?.headers.value('retry-after');
        final retrySecs =
            (int.tryParse(retryAfterRaw ?? '') ?? 30).clamp(30, 60);
        _anilistRateLimitedUntil =
            DateTime.now().add(Duration(seconds: retrySecs));
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _fetchShikimoriMangaOrRanobeBySearch(
    String search, {
    bool ranobeFirst = false,
  }) async {
    final endpoints = ranobeFirst
        ? const [
            'https://shikimori.io/api/ranobe',
            'https://shikimori.io/api/mangas',
          ]
        : const [
            'https://shikimori.io/api/mangas',
            'https://shikimori.io/api/ranobe',
          ];
    for (final endpoint in endpoints) {
      try {
        final res = await _dio.get(
          endpoint,
          queryParameters: {'search': search, 'limit': 3},
          options: Options(
            headers: const {
              'User-Agent': 'SyncPai-App/1.0',
              'Accept': 'application/json',
            },
          ),
        );
        if (res.statusCode == 200 && res.data is List) {
          for (final item in res.data as List) {
            if (item is! Map || item['image'] is! Map) continue;
            if (!isTitleMatchStrict(search, [
              item['russian']?.toString(),
              item['name']?.toString(),
            ])) {
              continue;
            }
            final img = item['image'] as Map;
            final raw =
                (img['original'] ?? img['preview'])?.toString().trim() ?? '';
            if (raw.isNotEmpty && !isMissingOrPlaceholder(raw)) {
              if (raw.startsWith('//')) return 'https:$raw';
              if (raw.startsWith('http')) return raw;
              return 'https://shikimori.io$raw';
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _fetchShikimoriBySearch(String search) async {
    try {
      final res = await _dio.get(
        'https://shikimori.io/api/animes',
        queryParameters: {'search': search, 'limit': 3},
        options: Options(
          headers: const {
            'User-Agent': 'SyncPai-App/1.0',
            'Accept': 'application/json',
          },
        ),
      );
      if (res.statusCode == 200 && res.data is List) {
        for (final item in res.data as List) {
          if (item is! Map || item['image'] is! Map) continue;
          if (!isTitleMatchStrict(search, [
            item['russian']?.toString(),
            item['name']?.toString(),
          ])) {
            continue;
          }
          final img = item['image'] as Map;
          final raw =
              (img['original'] ?? img['preview'])?.toString().trim() ?? '';
          if (raw.isNotEmpty && !isMissingOrPlaceholder(raw)) {
            if (raw.startsWith('//')) return 'https:$raw';
            if (raw.startsWith('http')) return raw;
            return 'https://shikimori.io$raw';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<T> _enqueueAnilistRequest<T>(Future<T> Function() action) {
    final next = _anilistQueueTail.then((_) async {
      final blockedUntil = _anilistRateLimitedUntil;
      if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
        throw DioException(
          requestOptions: RequestOptions(path: 'https://graphql.anilist.co'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: 'https://graphql.anilist.co'),
            statusCode: 429,
          ),
        );
      }
      final last = _lastAnilistAt;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        if (elapsed < _anilistMinInterval) {
          await Future<void>.delayed(_anilistMinInterval - elapsed);
        }
      }
      _lastAnilistAt = DateTime.now();
      try {
        return await action();
      } on DioException catch (e) {
        if (e.response?.statusCode == 429) {
          final retryAfterRaw = e.response?.headers.value('retry-after');
          final retrySecs =
              (int.tryParse(retryAfterRaw ?? '') ?? 30).clamp(30, 60);
          _anilistRateLimitedUntil =
              DateTime.now().add(Duration(seconds: retrySecs));
        }
        rethrow;
      }
    });
    _anilistQueueTail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<Map<int, String>> _fetchShikimoriBulkByIds(List<int> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final res = await _dio.get(
        'https://shikimori.one/api/animes',
        queryParameters: {
          'ids': ids.join(','),
          'limit': ids.length.clamp(1, 50),
        },
        options: Options(
          headers: const {
            'User-Agent': 'SyncPai-App/1.0',
            'Accept': 'application/json',
          },
        ),
      );
      if (res.statusCode == 200 && res.data is List) {
        final out = <int, String>{};
        for (final item in res.data as List) {
          if (item is! Map) continue;
          final id = (item['id'] as num?)?.toInt();
          final img = item['image'] is Map ? item['image'] as Map : null;
          final raw =
              (img?['preview'] ?? img?['original'])?.toString().trim() ?? '';
          if (id != null && raw.isNotEmpty && !isMissingOrPlaceholder(raw)) {
            final full = raw.startsWith('//')
                ? 'https:$raw'
                : (raw.startsWith('http') ? raw : 'https://shikimori.io$raw');
            out[id] = full;
          }
        }
        return out;
      }
    } catch (_) {}
    return const {};
  }

  Future<Map<int, String>> _fetchAnilistBatch(List<int> malIds) async {
    if (malIds.isEmpty) return const {};
    final batch = malIds.take(25).toList();
    final blockedUntil = _anilistRateLimitedUntil;
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
      return _fetchShikimoriBulkByIds(batch);
    }
    final buf = StringBuffer('query { ');
    for (var i = 0; i < batch.length; i++) {
      buf.write(
        'q$i: Media(idMal: ${batch[i]}, type: ANIME) { idMal coverImage { extraLarge large } } ',
      );
    }
    buf.write('}');

    try {
      final res = await _enqueueAnilistRequest(
        () => _dio.post(
          'https://graphql.anilist.co',
          data: {'query': buf.toString()},
          options: Options(
            validateStatus: (status) => status != null && status < 500,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ),
      );
      if ((res.statusCode == 200 || res.statusCode == 404) && res.data is Map) {
        final data = res.data['data'];
        if (data is Map) {
          final out = <int, String>{};
          for (final entry in data.entries) {
            final item = entry.value;
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
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        final retryAfterRaw = e.response?.headers.value('retry-after');
        final retrySecs = (int.tryParse(retryAfterRaw ?? '') ?? 30).clamp(30, 60);
        _anilistRateLimitedUntil =
            DateTime.now().add(Duration(seconds: retrySecs));
        return _fetchShikimoriBulkByIds(batch);
      }
      if (kDebugMode) {
        debugPrint('[AnimePosterResolver] AniList batch error: $e');
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
            (jpg?['large_image_url'] ??
                    webp?['large_image_url'] ??
                    jpg?['image_url'] ??
                    webp?['image_url'])
                ?.toString(),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> setManualPosterOverride({
    int? malId,
    required String title,
    String? englishTitle,
    required String url,
  }) async {
    await _ensurePrefsLoaded();
    final clean = sanitizeUrl(url);
    if (clean == null) return;
    if (malId != null && malId > 0) {
      _memoryCache[malId] = clean;
      _emptyCache.remove(malId);
    }
    final keyRu = normalizeTitleKey(title);
    if (keyRu.isNotEmpty) {
      _titleMemoryCache[keyRu] = clean;
      _titleEmptyCache.remove(keyRu);
    }
    if (englishTitle != null && englishTitle.trim().isNotEmpty) {
      final keyEn = normalizeTitleKey(englishTitle);
      if (keyEn.isNotEmpty) {
        _titleMemoryCache[keyEn] = clean;
        _titleEmptyCache.remove(keyEn);
      }
    }
    unawaited(_saveTitleCacheToPrefs());
    _prefetchImageBytes([clean]);
    overrideRevision.value++;
    if (malId != null && malId > 0) {
      unawaited(_persistToSupabase({malId: clean}));
    }
  }

  /// Загружает до 4 вариантов обложек из AniList, MAL (Jikan) и Shikimori для ручного выбора.
  Future<List<PosterCandidate>> fetchPosterCandidates({
    int? malId,
    required String title,
    String? englishTitle,
  }) async {
    final searchQuery = (englishTitle != null && englishTitle.trim().isNotEmpty)
        ? normalizeTitleKey(englishTitle)
        : normalizeTitleKey(title);
    final ruQuery = normalizeTitleKey(title);
    final effectiveQuery = searchQuery.isNotEmpty ? searchQuery : ruQuery;

    final results = await Future.wait<PosterCandidate?>([
      () async {
        if (malId != null && malId > 0) {
          final hit = await _fetchAnilistBatch([malId]);
          final url = hit[malId];
          if (url != null) return PosterCandidate('AniList', url);
        }
        if (effectiveQuery.isNotEmpty) {
          final url = await _fetchAnilistBySearch(effectiveQuery);
          if (url != null) return PosterCandidate('AniList', url);
        }
        return null;
      }(),
      () async {
        if (malId != null && malId > 0) {
          final url = await _fetchJikanSingle(malId);
          if (url != null) return PosterCandidate('MAL', url);
        }
        if (effectiveQuery.isNotEmpty) {
          final url = await _fetchJikanBySearch(effectiveQuery);
          if (url != null) return PosterCandidate('MAL', url);
        }
        return null;
      }(),
      () async {
        if (malId != null && malId > 0) {
          final hit = await _fetchShikimoriBulkByIds([malId]);
          final url = hit[malId];
          if (url != null) return PosterCandidate('Shikimori', url);
        }
        if (effectiveQuery.isNotEmpty) {
          final url = await _fetchShikimoriBySearch(effectiveQuery);
          if (url != null) return PosterCandidate('Shikimori', url);
        }
        return null;
      }(),
      () async {
        if (ruQuery.isNotEmpty && ruQuery != effectiveQuery) {
          final url = await _fetchAnilistBySearch(ruQuery) ??
              await _fetchShikimoriBySearch(ruQuery);
          if (url != null) return PosterCandidate('Alt', url);
        }
        return null;
      }(),
    ]);

    final seen = <String>{};
    final out = <PosterCandidate>[];
    for (final c in results) {
      if (c != null && seen.add(c.url)) {
        out.add(c);
        if (out.length >= 4) break;
      }
    }
    return out;
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

