import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/di/injection.dart';
import '../../../anime_details/data/datasources/shikimori_remote_datasource.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../domain/entities/manga_bridge.dart';
import '../datasources/mangadex_datasource.dart';
import '../datasources/mangaupdates_datasource.dart';

/// Сервис-мост «Аниме -> Манга / Манхва»:
/// 1. In-memory кэш + Supabase-кэш (`anime_manga_bridges`)
/// 2. Shikimori `/animes/{id}/related` (`relation == 'Adaptation'`)
/// 3. MangaDex `/manga` + MangaUpdates `anime.end` (`continueFromChapter = end + 1`)
class AnimeMangaBridgeService {
  static final AnimeMangaBridgeService instance = AnimeMangaBridgeService._();

  AnimeMangaBridgeService._({
    ShikimoriRemoteDataSource? shikimoriDataSource,
    MangaUpdatesDataSource? mangaUpdatesDataSource,
    MangaDexDataSource? mangaDexDataSource,
  })  : _shikimoriOverride = shikimoriDataSource,
        _mangaUpdatesOverride = mangaUpdatesDataSource,
        _mangaDexOverride = mangaDexDataSource;

  factory AnimeMangaBridgeService.forTest({
    required ShikimoriRemoteDataSource shikimoriDataSource,
    required MangaUpdatesDataSource mangaUpdatesDataSource,
    required MangaDexDataSource mangaDexDataSource,
  }) =>
      AnimeMangaBridgeService._(
        shikimoriDataSource: shikimoriDataSource,
        mangaUpdatesDataSource: mangaUpdatesDataSource,
        mangaDexDataSource: mangaDexDataSource,
      );

  final ShikimoriRemoteDataSource? _shikimoriOverride;
  final MangaUpdatesDataSource? _mangaUpdatesOverride;
  final MangaDexDataSource? _mangaDexOverride;

  static const String _prefsBridgePrefix = 'syncpai_manga_bridge_v3_';

  final Map<int, AnimeMangaBridge?> _memoryCache = {};
  final Map<int, Future<AnimeMangaBridge?>> _inFlight = {};
  final Set<int> _confirmedOriginalIds = {};

  ShikimoriRemoteDataSource get _shikimori =>
      _shikimoriOverride ??
      (getIt.isRegistered<ShikimoriRemoteDataSource>()
          ? getIt<ShikimoriRemoteDataSource>()
          : ShikimoriRemoteDataSourceImpl());

  MangaUpdatesDataSource get _mangaUpdates =>
      _mangaUpdatesOverride ??
      (getIt.isRegistered<MangaUpdatesDataSource>()
          ? getIt<MangaUpdatesDataSource>()
          : MangaUpdatesDataSource());

  MangaDexDataSource get _mangaDex =>
      _mangaDexOverride ??
      (getIt.isRegistered<MangaDexDataSource>()
          ? getIt<MangaDexDataSource>()
          : MangaDexDataSource());

  bool get _isTestEnv {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  AnimeMangaBridge? getCached(int anilibriaId) => _memoryCache[anilibriaId];

  bool isConfirmedOriginal(int anilibriaId) =>
      _confirmedOriginalIds.contains(anilibriaId);

  Future<AnimeMangaBridge?> getCachedFromPrefs(int anilibriaId) async {
    if (_memoryCache.containsKey(anilibriaId)) {
      return _memoryCache[anilibriaId];
    }
    final local = await _fetchFromPrefs(anilibriaId);
    if (local != null) {
      _memoryCache[anilibriaId] = local;
    }
    return local;
  }

  /// Разрешает первоисточник (мангу/манхву) без блокировки на MangaUpdates.
  Future<AnimeMangaBridge?> resolveForAnime(
    AnimeTitle title, {
    void Function(AnimeMangaBridge updated)? onChapterOffsetUpdated,
  }) {
    if (title.id <= 0) return Future.value(null);
    if (_memoryCache.containsKey(title.id)) {
      return Future.value(_memoryCache[title.id]);
    }
    return _inFlight.putIfAbsent(title.id, () async {
      try {
        final resolved = await _resolveInternal(
          title,
          onChapterOffsetUpdated: onChapterOffsetUpdated,
        );
        _memoryCache[title.id] = resolved;
        return resolved;
      } finally {
        _inFlight.remove(title.id);
      }
    });
  }

  Future<AnimeMangaBridge?> _resolveInternal(
    AnimeTitle title, {
    void Function(AnimeMangaBridge updated)? onChapterOffsetUpdated,
  }) async {
    // 0. Проверяем локальный SharedPreferences-кэш (0ms lookup)
    final localCached = await _fetchFromPrefs(title.id);
    if (localCached != null) {
      return localCached;
    }

    // 1. Проверяем Supabase Bridge Cache (anime_manga_bridges)
    if (!_isTestEnv) {
      final cachedRow = await _fetchFromSupabase(title)
          .timeout(const Duration(milliseconds: 2500), onTimeout: () => null);
      if (cachedRow != null) {
        unawaited(_saveToPrefs(cachedRow));
        return cachedRow;
      }
    }

    // 2. Определяем Shikimori ID и извлекаем первоисточник (Adaptation) с таймаутом 4s
    int? shikimoriId = title.shikimoriId;
    if (shikimoriId == null || shikimoriId <= 0) {
      if (_isTestEnv && _shikimoriOverride == null) return null;
      shikimoriId = await _shikimori
          .resolveShikimoriId(title)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
    }
    if (shikimoriId == null || shikimoriId <= 0) return null;

    final adapted = await _shikimori
        .getAdaptedManga(shikimoriId)
        .timeout(const Duration(seconds: 4), onTimeout: () => null);
    if (adapted == null) {
      _confirmedOriginalIds.add(title.id);
      return null;
    }

    // 3. Быстрый путь: ищем мангу на MangaDex без ожидания медленного MangaUpdates
    final primarySearchTitle = adapted.englishTitle.isNotEmpty
        ? adapted.englishTitle
        : (adapted.russianTitle.isNotEmpty
            ? adapted.russianTitle
            : title.englishTitle);

    final mdManga = await _searchBestMangaDex(
      primarySearchTitle,
      fallbackTitle: adapted.japaneseTitle ?? adapted.russianTitle,
      malId: adapted.malId,
    ).timeout(const Duration(seconds: 4), onTimeout: () => null);
    if (mdManga == null) return null;

    final bridge = AnimeMangaBridge(
      anilibriaId: title.id,
      shikimoriId: shikimoriId,
      mangaDexId: mdManga.id,
      mangaTitle: adapted.displayTitle.isNotEmpty
          ? adapted.displayTitle
          : mdManga.title,
      coverUrl:
          mdManga.coverUrl.isNotEmpty ? mdManga.coverUrl : adapted.coverUrl,
      mangaUpdatesEndChapter: null,
      isManhwa: adapted.isManhwaOrWebtoon || mdManga.isManhwaOrWebtoon,
      chaptersCount: adapted.chaptersCount,
      score: adapted.score,
    );

    unawaited(_saveToPrefs(bridge));
    if (!_isTestEnv) {
      unawaited(_saveToSupabase(bridge));
    }

    // 4. Фоновый неблокирующий запрос MangaUpdates (таймаут 2s) + эвристика при отсутствии данных
    final muQuery = adapted.englishTitle.isNotEmpty
        ? adapted.englishTitle
        : title.englishTitle;
    final episodesCount = title.episodesTotal ?? title.episodes.length;
    unawaited(() async {
      try {
        int? endChapter;
        if (muQuery.trim().isNotEmpty) {
          endChapter = await _mangaUpdates
              .getAnimeEndChapter(muQuery)
              .timeout(const Duration(seconds: 2), onTimeout: () => null);
        }
        final isEstimated = endChapter == null && episodesCount > 0;
        final resolvedEnd = endChapter ??
            (isEstimated
                ? ((episodesCount * 2.5).round() - 1).clamp(0, 9999)
                : null);

        if (resolvedEnd != null) {
          final updated = AnimeMangaBridge(
            anilibriaId: bridge.anilibriaId,
            shikimoriId: bridge.shikimoriId,
            mangaDexId: bridge.mangaDexId,
            mangaTitle: bridge.mangaTitle,
            coverUrl: bridge.coverUrl,
            mangaUpdatesEndChapter: resolvedEnd,
            isEstimatedChapter: isEstimated,
            isManhwa: bridge.isManhwa,
            chaptersCount: bridge.chaptersCount,
            score: bridge.score,
          );
          _memoryCache[title.id] = updated;
          unawaited(_saveToPrefs(updated));
          if (!isEstimated && !_isTestEnv) {
            unawaited(_saveToSupabase(updated));
          }
          onChapterOffsetUpdated?.call(updated);
        }
      } catch (_) {}
    }());

    return bridge;
  }

  Future<AnimeMangaBridge?> _fetchFromPrefs(int anilibriaId) async {
    try {
      final prefs = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsBridgePrefix$anilibriaId');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final mangaDexId = (map['mangaDexId'] ?? '').toString();
      if (mangaDexId.isEmpty) return null;
      return AnimeMangaBridge(
        anilibriaId: anilibriaId,
        shikimoriId: (map['shikimoriId'] as num?)?.toInt(),
        mangaDexId: mangaDexId,
        mangaTitle: (map['mangaTitle'] ?? '').toString(),
        coverUrl: (map['coverUrl'] ?? '').toString(),
        mangaUpdatesEndChapter: (map['mangaUpdatesEndChapter'] as num?)?.toInt(),
        isManhwa: map['isManhwa'] as bool? ?? false,
        chaptersCount: (map['chaptersCount'] as num?)?.toInt(),
        score: (map['score'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToPrefs(AnimeMangaBridge bridge) async {
    try {
      final prefs = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsBridgePrefix${bridge.anilibriaId}',
        jsonEncode({
          'anilibriaId': bridge.anilibriaId,
          'shikimoriId': bridge.shikimoriId,
          'mangaDexId': bridge.mangaDexId,
          'mangaTitle': bridge.mangaTitle,
          'coverUrl': bridge.coverUrl,
          'mangaUpdatesEndChapter': bridge.mangaUpdatesEndChapter,
          'isManhwa': bridge.isManhwa,
          'chaptersCount': bridge.chaptersCount,
          'score': bridge.score,
        }),
      );
    } catch (_) {}
  }

  Future<MangaDexManga?> _searchBestMangaDex(
    String primaryTitle, {
    String? fallbackTitle,
    int? malId,
  }) async {
    final malStr = malId?.toString();
    if (primaryTitle.trim().isNotEmpty) {
      final list = await _mangaDex.searchManga(primaryTitle);
      if (list.isNotEmpty) {
        if (malStr != null) {
          for (final item in list) {
            if (item.malId == malStr) return item;
          }
        }
        return list.first;
      }
    }
    if (fallbackTitle != null &&
        fallbackTitle.trim().isNotEmpty &&
        fallbackTitle.trim() != primaryTitle.trim()) {
      final list = await _mangaDex.searchManga(fallbackTitle);
      if (list.isNotEmpty) {
        if (malStr != null) {
          for (final item in list) {
            if (item.malId == malStr) return item;
          }
        }
        return list.first;
      }
    }
    return null;
  }

  Future<AnimeMangaBridge?> _fetchFromSupabase(AnimeTitle title) async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('anime_manga_bridges')
          .select()
          .eq('anilibria_id', title.id)
          .maybeSingle();

      if (response == null) return null;
      final mdId = (response['mangadex_id'] ?? '').toString().trim();
      if (mdId.isEmpty) return null;

      return AnimeMangaBridge(
        anilibriaId: (response['anilibria_id'] as num?)?.toInt() ?? title.id,
        shikimoriId: (response['shikimori_id'] as num?)?.toInt() ??
            title.shikimoriId,
        mangaDexId: mdId,
        mangaTitle: (response['manga_title'] ?? title.displayTitle).toString(),
        coverUrl: (response['cover_url'] ?? '').toString(),
        mangaUpdatesEndChapter:
            (response['mangaupdates_end_chapter'] as num?)?.toInt(),
        isManhwa: response['is_manhwa'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToSupabase(AnimeMangaBridge bridge) async {
    try {
      final client = Supabase.instance.client;
      await client.from('anime_manga_bridges').upsert(
        {
          'anilibria_id': bridge.anilibriaId,
          'shikimori_id': bridge.shikimoriId,
          'mangadex_id': bridge.mangaDexId,
          'mangaupdates_end_chapter': bridge.mangaUpdatesEndChapter,
          'manga_title': bridge.mangaTitle,
          'cover_url': bridge.coverUrl,
          'is_manhwa': bridge.isManhwa,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'anilibria_id',
      );
    } catch (_) {}
  }
}

