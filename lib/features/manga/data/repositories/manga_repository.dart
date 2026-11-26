import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/injection.dart';
import '../../../anime_details/data/datasources/shikimori_remote_datasource.dart';
import '../../domain/entities/manga_bridge.dart';
import '../datasources/desu_datasource.dart';
import '../datasources/mangadex_datasource.dart';
import '../datasources/mangalib_datasource.dart';
import '../datasources/remanga_datasource.dart';
import '../datasources/senkuro_datasource.dart';

/// Единый репозиторий манги и манхвы:
/// - Первичные русскоязычные источники: ReManga + Desu.uno
/// - Третичный fallback: MangaDex
/// - Дедупликация in-flight запросов + LRU кэш (12 страниц) + SharedPreferences (6ч TTL)
class MangaRepository {
  static final MangaRepository instance = MangaRepository();

  static const int maxMemoryPages = 12;
  static const Duration diskCacheTtl = Duration(hours: 6);
  static const String _diskPrefix = 'manga_cache_v4_';
  static const List<String> filterTabs = [
    'all',
    'manhwa',
    'manga',
    'popular',
    'completed',
  ];

  final RemangaDataSource _remanga;
  final DesuDataSource _desu;
  final MangaDexDataSource _mangadex;
  final SenkuroDataSource _senkuro;
  final MangaLibDataSource _mangalib;
  final ShikimoriRemoteDataSource? _shikimoriOverride;
  final SharedPreferences? _prefsOverride;
  bool _legacyCachePurged = false;

  final LinkedHashMap<String, List<MangaDexManga>> _memoryLru = LinkedHashMap();
  final Map<String, Future<List<MangaDexManga>>> _inFlight = {};

  MangaRepository({
    RemangaDataSource? remanga,
    DesuDataSource? desu,
    MangaDexDataSource? mangadex,
    SenkuroDataSource? senkuro,
    MangaLibDataSource? mangalib,
    ShikimoriRemoteDataSource? shikimori,
    SharedPreferences? prefs,
  })  : _remanga = remanga ?? RemangaDataSource(),
        _desu = desu ?? DesuDataSource(),
        _mangadex = mangadex ?? MangaDexDataSource(),
        _senkuro = senkuro ?? SenkuroDataSource(),
        _mangalib = mangalib ?? MangaLibDataSource(),
        _shikimoriOverride = shikimori,
        _prefsOverride = prefs;

  Future<SharedPreferences> _getPrefs() async {
    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    if (!_legacyCachePurged) {
      _legacyCachePurged = true;
      await purgeLegacyDiskCache(prefs);
    }
    return prefs;
  }

  /// Удаляет устаревшие ключи дискового кэша (`manga_cache_v1*`, `v2*`, `v3*`).
  Future<void> purgeLegacyDiskCache([SharedPreferences? prefsOverride]) async {
    try {
      final prefs = prefsOverride ?? _prefsOverride ?? await SharedPreferences.getInstance();
      final legacyKeys = prefs.getKeys().where(
            (k) =>
                k.startsWith('manga_cache_v1') ||
                k.startsWith('manga_cache_v2') ||
                k.startsWith('manga_cache_v3'),
          ).toList();
      for (final key in legacyKeys) {
        await prefs.remove(key);
      }
      if (kDebugMode && legacyKeys.isNotEmpty) {
        debugPrint(
          '[MangaRepository] Purged ${legacyKeys.length} legacy disk cache entries',
        );
      }
    } catch (_) {}
  }

  List<MangaDexManga>? getCachedCatalogPage({
    required String tab,
    required int page,
    required bool russianOnly,
  }) {
    final key = _catalogKey(tab, page, russianOnly);
    final cached = _memoryLru.remove(key);
    if (cached != null) {
      _memoryLru[key] = cached; // Refresh LRU order
    }
    return cached;
  }

  String _catalogKey(String tab, int page, bool russianOnly) =>
      'cat_${tab}_${page}_${russianOnly ? 'ru' : 'all'}';

  void _putLru(String key, List<MangaDexManga> items) {
    _memoryLru.remove(key);
    _memoryLru[key] = items;
    while (_memoryLru.length > maxMemoryPages) {
      _memoryLru.remove(_memoryLru.keys.first);
    }
  }

  Future<List<MangaDexManga>?> _readDiskCache(String key) async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString('$_diskPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final cachedAtMs = (map['cachedAt'] as num?)?.toInt() ?? 0;
      if (cachedAtMs <= 0) return null;
      final age = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
      if (age > diskCacheTtl.inMilliseconds) return null;
      final list = map['items'];
      if (list is! List) return null;
      final parsed = list
          .whereType<Map>()
          .map((m) => MangaDexManga.fromJson(Map<String, dynamic>.from(m)))
          .where((m) => m.id.isNotEmpty)
          .toList();
      return parsed.isNotEmpty ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDiskCache(String key, List<MangaDexManga> items) async {
    if (items.isEmpty) return;
    try {
      final prefs = await _getPrefs();
      await prefs.setString(
        '$_diskPrefix$key',
        jsonEncode({
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
          'items': items.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  Future<List<MangaDexManga>> getCatalog({
    String tab = 'all',
    int page = 1,
    int count = 30,
    bool russianOnly = true,
  }) {
    final key = _catalogKey(tab, page, russianOnly);
    final mem = getCachedCatalogPage(tab: tab, page: page, russianOnly: russianOnly);
    if (mem != null && mem.isNotEmpty) {
      return Future.value(mem);
    }

    return _inFlight.putIfAbsent(key, () async {
      try {
        if (page == 1) {
          final disk = await _readDiskCache(key);
          if (disk != null && disk.isNotEmpty) {
            _putLru(key, disk);
            return disk;
          }
        }

        List<MangaDexManga> items = const [];
        if (russianOnly) {
          final int? remangaType = tab == 'manhwa'
              ? 1
              : (tab == 'manga' ? 0 : null);
          final remangaOrder = tab == 'popular' ? '-votes' : '-rating';
          if (tab != 'completed') {
            items = await _remanga.browseCatalog(
              page: page,
              count: count,
              ordering: remangaOrder,
              type: remangaType,
            );
          }

          if (items.isEmpty) {
            final desuKinds = tab == 'manhwa'
                ? 'manhwa'
                : (tab == 'manga' ? 'manga' : null);
            items = await _desu.browseCatalog(
              page: page,
              limit: count,
              order: tab == 'popular' ? 'popular' : 'updated',
              kinds: desuKinds,
            );
          }
        }

        if (items.isEmpty) {
          final origLang = tab == 'manhwa'
              ? 'ko'
              : (tab == 'manga' ? 'ja' : null);
          final order = tab == 'popular' ? 'rating' : 'followedCount';
          final status = tab == 'completed' ? 'completed' : null;
          items = await _mangadex.browseManga(
            originalLanguage: origLang,
            availableTranslatedLanguage: russianOnly ? 'ru' : null,
            status: status,
            order: order,
            limit: count,
            offset: (page - 1) * count,
          );
        }

        if (items.isNotEmpty) {
          _putLru(key, items);
          if (page == 1) {
            unawaited(_writeDiskCache(key, items));
          }
        }
        return items;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  Future<List<MangaDexManga>> prefetchPage1({int count = 24}) =>
      getCatalog(tab: 'all', page: 1, count: count, russianOnly: true);

  Future<void> prefetchAllFilterTabs({int count = 24}) async {
    await Future.wait(
      filterTabs.map(
        (tab) => getCatalog(
          tab: tab,
          page: 1,
          count: count,
          russianOnly: true,
        ).catchError((_) => const <MangaDexManga>[]),
      ),
    );
  }

  /// Оптимистичная 0ms-фильтрация по уже загруженным в LRU-кэш элементам.
  List<MangaDexManga> optimisticFilterFromMemory({required String tab}) {
    final seenIds = <String>{};
    final pool = <MangaDexManga>[];
    for (final pageList in _memoryLru.values) {
      for (final item in pageList) {
        if (seenIds.add(item.id)) {
          pool.add(item);
        }
      }
    }
    if (pool.isEmpty) return const [];

    switch (tab) {
      case 'manhwa':
        return pool
            .where((m) => m.originalLanguage == 'ko' || m.isManhwaOrWebtoon)
            .toList();
      case 'manga':
        return pool.where((m) => m.originalLanguage == 'ja').toList();
      case 'completed':
        return pool
            .where((m) => m.status?.toLowerCase() == 'completed')
            .toList();
      case 'popular':
        return List<MangaDexManga>.from(pool)
          ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      default:
        return pool;
    }
  }

  static String _normalizeForDedup(String input) {
    return input
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<List<MangaDexManga>> searchManga(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const []);
    final normalized = trimmed.replaceAll('ё', 'е').replaceAll('Ё', 'Е');
    final key = 'search_${_normalizeForDedup(trimmed)}';
    return _inFlight.putIfAbsent(key, () async {
      try {
        final queries = <String>[
          trimmed,
          if (normalized != trimmed) normalized,
        ];
        final futures = <Future<List<MangaDexManga>>>[];
        for (final q in queries) {
          futures.add(_senkuro.searchManga(q, first: 15).catchError((_) => const <MangaDexManga>[]));
          futures.add(_mangalib.searchManga(q).catchError((_) => const <MangaDexManga>[]));
          futures.add(_remanga.searchCatalog(q, count: 20).catchError((_) => const <MangaDexManga>[]));
          futures.add(_desu.browseCatalog(search: q, limit: 20).catchError((_) => const <MangaDexManga>[]));
        }
        final results = await Future.wait(futures);
        final merged = <MangaDexManga>[];
        final seenKeys = <String>{};
        for (final list in results) {
          for (final item in list) {
            final norm = _normalizeForDedup(item.title);
            final dedupKey = norm.isNotEmpty
                ? '$norm|${item.originalLanguage ?? ''}'
                : item.id;
            if (seenKeys.add(dedupKey)) {
              merged.add(item);
            }
          }
        }
        if (merged.isNotEmpty) return merged;
        return await _mangadex.searchManga(trimmed, limit: 30);
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  Future<MangaDexManga?> getMangaDetails(String id) async {
    if (id.startsWith('remanga:')) {
      return _remanga.getTitleDetails(id);
    }
    if (id.startsWith('desu:')) {
      final list = await _desu.browseCatalog(search: id.replaceFirst('desu:', ''), limit: 1);
      return list.isNotEmpty ? list.first : null;
    }
    if (id.startsWith('senkuro:') || id.startsWith('mangalib:')) {
      return null;
    }
    return _mangadex.getMangaById(id);
  }

  static String sanitizeSearchQuery(String raw) {
    return raw
        .replaceAll(RegExp(r'\s*[~:(\—–].*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> buildNormalizedQueries(
    String? originalTitle,
    String? title,
  ) {
    final candidates = <String>[];
    void addIfValid(String? val) {
      final t = val?.trim() ?? '';
      if (t.isNotEmpty && !candidates.contains(t)) {
        candidates.add(t);
      }
      final noYo = t.replaceAll('ё', 'е').replaceAll('Ё', 'Е');
      if (noYo.isNotEmpty && !candidates.contains(noYo)) {
        candidates.add(noYo);
      }
    }

    if (originalTitle != null && originalTitle.trim().isNotEmpty) {
      addIfValid(sanitizeSearchQuery(originalTitle));
    }
    if (title != null && title.trim().isNotEmpty) {
      addIfValid(sanitizeSearchQuery(title));
    }
    addIfValid(originalTitle);
    addIfValid(title);
    return candidates;
  }

  Future<List<MangaDexChapter>> _searchSenkuroChapters(
    List<String> queries,
  ) async {
    for (final q in queries) {
      final matches = await _senkuro.searchManga(q, first: 5);
      for (final match in matches.take(2)) {
        final chapters = await _senkuro.getChapters(match.id);
        if (chapters.isNotEmpty) return chapters;
      }
    }
    return const [];
  }

  Future<List<MangaDexChapter>> _searchMangaLibChapters(
    List<String> queries,
  ) async {
    for (final q in queries) {
      final matches = await _mangalib.searchManga(q);
      for (final match in matches.take(2)) {
        final chapters = await _mangalib.getChapters(match.id);
        if (chapters.isNotEmpty) return chapters;
      }
    }
    return const [];
  }

  Future<List<MangaDexChapter>> _searchDesuChapters(List<String> queries) async {
    for (final q in queries) {
      final matches = await _desu.browseCatalog(search: q, limit: 5);
      for (final match in matches.take(2)) {
        final chapters = await _desu.getChapters(match.id);
        if (chapters.isNotEmpty) return chapters;
      }
    }
    return const [];
  }

  Future<List<MangaDexChapter>> _searchRemangaChapters(
    List<String> queries,
  ) async {
    for (final q in queries) {
      final chapters = await _remanga.getChaptersByTitle(title: q);
      if (chapters.isNotEmpty) return chapters;
    }
    return const [];
  }

  static bool _startsFromChapterOne(List<MangaDexChapter> chapters) {
    if (chapters.isEmpty) return false;
    final firstNum = chapters.first.chapterNumber;
    if (firstNum == null) return true;
    return firstNum <= 1.5;
  }

  static List<MangaDexChapter> _pickMostCompleteRun(
    List<List<MangaDexChapter>> candidates,
  ) {
    final nonEmpty = candidates.where((c) => c.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const [];
    final complete = nonEmpty.where(_startsFromChapterOne).toList();
    final pool = complete.isNotEmpty ? complete : nonEmpty;
    pool.sort((a, b) => b.length.compareTo(a.length));
    return pool.first;
  }

  Future<List<String>> _resolveShikimoriRomajiQueries(String title) async {
    final shiki = _shikimoriOverride ??
        (getIt.isRegistered<ShikimoriRemoteDataSource>()
            ? getIt<ShikimoriRemoteDataSource>()
            : null);
    if (shiki == null) return const [];
    final cleaned = sanitizeSearchQuery(title);
    if (cleaned.isEmpty) return const [];
    try {
      final matches = await shiki.searchMangas(cleaned, limit: 5);
      final out = <String>[];
      for (final m in matches) {
        final en = sanitizeSearchQuery(m.english);
        if (en.isNotEmpty && !out.contains(en)) out.add(en);
        final rawEn = m.english.trim();
        if (rawEn.isNotEmpty && !out.contains(rawEn)) out.add(rawEn);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  void _logResolution(String source, String title, int count) {
    if (!kDebugMode) return;
    debugPrint('[MangaRepository] "$title" -> $source ($count chapters)');
  }

  static final Map<String, List<MangaDexChapter>> _chaptersMemCache = {};

  /// Потоковая загрузка глав:
  /// 1. Мгновенно отдаёт кэш (`manga_cache_v4_chapters_*`), если он есть.
  /// 2. Потоково эмитит пачки по 100 глав из Senkuro или фолбек-источников.
  Stream<List<MangaDexChapter>> fetchChaptersStream(MangaDexManga manga) async* {
    final mem = _chaptersMemCache[manga.id];
    if (mem != null && mem.isNotEmpty) {
      yield mem;
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('${_diskPrefix}chapters_${manga.id}');
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          final cachedList = decoded
              .whereType<Map>()
              .map((m) => MangaDexChapter.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          if (cachedList.isNotEmpty) {
            _chaptersMemCache[manga.id] = cachedList;
            yield cachedList;
          }
        }
      } catch (_) {}
    }

    List<MangaDexChapter> latest = const [];
    if (!manga.id.startsWith('remanga:') && !manga.id.startsWith('desu:')) {
      final queries = buildNormalizedQueries(manga.originalTitle, manga.title);
      for (final q in queries) {
        try {
          final matches = await _senkuro.searchManga(q, first: 5);
          for (final match in matches.take(2)) {
            await for (final batch in _senkuro.getChaptersStream(match.id)) {
              if (batch.isNotEmpty) {
                latest = batch;
                yield batch;
              }
            }
            if (latest.isNotEmpty && _startsFromChapterOne(latest)) {
              _chaptersMemCache[manga.id] = latest;
              _saveChaptersDiskCache(manga.id, latest);
              return;
            }
          }
        } catch (_) {}
      }
    }

    final full = await getChapters(manga);
    if (full.isNotEmpty) {
      _chaptersMemCache[manga.id] = full;
      _saveChaptersDiskCache(manga.id, full);
      yield full;
    }
  }

  Future<void> _saveChaptersDiskCache(
    String mangaId,
    List<MangaDexChapter> chapters,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${_diskPrefix}chapters_$mangaId',
        jsonEncode(chapters.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Загружает русские главы с ReManga, Desu.uno и MangaDex, выбирая самый полный ряд с 1-й главы.
  Future<List<MangaDexChapter>> getChapters(MangaDexManga manga) async {
    final queries = buildNormalizedQueries(manga.originalTitle, manga.title);

    if (manga.id.startsWith('mangalib:')) {
      final mlChapters = await _mangalib.getChapters(manga.id);
      if (mlChapters.isNotEmpty && _startsFromChapterOne(mlChapters)) {
        _logResolution('MangaLib', manga.title, mlChapters.length);
        return mlChapters;
      }
    }

    if (manga.id.startsWith('senkuro:')) {
      final skChapters = await _senkuro.getChapters(manga.id);
      if (skChapters.isNotEmpty && _startsFromChapterOne(skChapters)) {
        _logResolution('Senkuro', manga.title, skChapters.length);
        return skChapters;
      }
    }

    if (manga.id.startsWith('remanga:')) {
      final remangaChapters = await _remanga.getChaptersByDir(manga.id);
      final freeRemanga = remangaChapters.where((c) => !c.isPaid).toList();
      final hasPaidGaps =
          remangaChapters.any((c) => c.isPaid) ||
          freeRemanga.isEmpty ||
          !_startsFromChapterOne(freeRemanga);

      if (!hasPaidGaps && freeRemanga.isNotEmpty) {
        _logResolution('ReManga', manga.title, freeRemanga.length);
        return freeRemanga;
      }

      var desuChapters = await _searchDesuChapters(queries);
      if (freeRemanga.isEmpty && desuChapters.isEmpty) {
        final shikiQueries = await _resolveShikimoriRomajiQueries(manga.title);
        if (shikiQueries.isNotEmpty) {
          desuChapters = await _searchDesuChapters(shikiQueries);
        }
      }
      if (freeRemanga.isEmpty && desuChapters.isNotEmpty) {
        _logResolution('Desu', manga.title, desuChapters.length);
        return desuChapters;
      }
      if (freeRemanga.isNotEmpty && desuChapters.isNotEmpty) {
        final freeByNum = <String, MangaDexChapter>{
          for (final c in freeRemanga) c.chapterLabel: c,
        };
        for (final d in desuChapters) {
          freeByNum.putIfAbsent(d.chapterLabel, () => d);
        }
        final merged = freeByNum.values.toList()
          ..sort((a, b) {
            final na = a.chapterNumber ?? 999999.0;
            final nb = b.chapterNumber ?? 999999.0;
            return na.compareTo(nb);
          });
        _logResolution('ReManga+Desu', manga.title, merged.length);
        return merged;
      }
      if (freeRemanga.isNotEmpty) {
        _logResolution('ReManga', manga.title, freeRemanga.length);
        return freeRemanga;
      }

      final mdFallback = await _mangadex.getChapters(
        manga.id,
        title: manga.title,
        originalTitle: manga.originalTitle,
      );
      _logResolution('MangaDex', manga.title, mdFallback.length);
      return mdFallback;
    }

    if (manga.id.startsWith('desu:')) {
      final desuChapters = await _desu.getChapters(manga.id);
      if (desuChapters.isNotEmpty && _startsFromChapterOne(desuChapters)) {
        _logResolution('Desu', manga.title, desuChapters.length);
        return desuChapters;
      }
      var remangaCh =
          (await _searchRemangaChapters(queries)).where((c) => !c.isPaid).toList();
      if (desuChapters.isEmpty && remangaCh.isEmpty) {
        final shikiQueries = await _resolveShikimoriRomajiQueries(manga.title);
        if (shikiQueries.isNotEmpty) {
          remangaCh = (await _searchRemangaChapters(shikiQueries))
              .where((c) => !c.isPaid)
              .toList();
        }
      }
      final best = _pickMostCompleteRun([desuChapters, remangaCh]);
      if (best.isNotEmpty) {
        _logResolution(best.first.source, manga.title, best.length);
        return best;
      }
      final mdFallback = await _mangadex.getChapters(
        manga.id,
        title: manga.title,
        originalTitle: manga.originalTitle,
      );
      _logResolution('MangaDex', manga.title, mdFallback.length);
      return mdFallback;
    }

    // Приоритетный порядок: Senkuro -> MangaLib -> ReManga -> Desu.uno -> MangaDex.
    // Возвращаем первый источник с валидным русским рядом с ~1-й главы, либо самый полный ряд.
    Future<List<MangaDexChapter>> tryAllRussianSources(
      List<String> qList,
    ) async {
      final senkuroCh = await _searchSenkuroChapters(qList);
      if (senkuroCh.isNotEmpty && _startsFromChapterOne(senkuroCh)) {
        _logResolution('Senkuro', manga.title, senkuroCh.length);
        return senkuroCh;
      }

      final mangalibCh = await _searchMangaLibChapters(qList);
      if (mangalibCh.isNotEmpty && _startsFromChapterOne(mangalibCh)) {
        _logResolution('MangaLib', manga.title, mangalibCh.length);
        return mangalibCh;
      }

      final remangaFree = (await _searchRemangaChapters(qList))
          .where((c) => !c.isPaid)
          .toList();
      if (remangaFree.isNotEmpty && _startsFromChapterOne(remangaFree)) {
        _logResolution('ReManga', manga.title, remangaFree.length);
        return remangaFree;
      }

      final desuCh = await _searchDesuChapters(qList);
      if (desuCh.isNotEmpty && _startsFromChapterOne(desuCh)) {
        _logResolution('Desu', manga.title, desuCh.length);
        return desuCh;
      }

      return _pickMostCompleteRun([senkuroCh, mangalibCh, remangaFree, desuCh]);
    }

    var bestRu = await tryAllRussianSources(queries);
    if (bestRu.isEmpty) {
      final shikiQueries = await _resolveShikimoriRomajiQueries(manga.title);
      if (shikiQueries.isNotEmpty) {
        bestRu = await tryAllRussianSources(shikiQueries);
      }
    }

    if (bestRu.isNotEmpty) {
      _logResolution(bestRu.first.source, manga.title, bestRu.length);
      return bestRu;
    }

    final mdCh = await _mangadex.getChapters(
      manga.id,
      title: manga.title,
      originalTitle: manga.originalTitle,
    );
    final mdRu =
        mdCh.where((c) => c.translatedLanguage.toLowerCase() == 'ru').toList();
    if (mdRu.isNotEmpty) {
      _logResolution('MangaDex(ru)', manga.title, mdRu.length);
      return mdRu;
    }

    _logResolution('MangaDex(fallback)', manga.title, mdCh.length);
    return mdCh;
  }

  Future<({List<String> dataUrls, List<String> dataSaverUrls})>
      getChapterPagesWithFallback(String chapterId) async {
    if (chapterId.startsWith('senkuro:')) {
      final urls = await _senkuro.getChapterPages(chapterId);
      return (dataUrls: urls, dataSaverUrls: const <String>[]);
    }
    if (chapterId.startsWith('mangalib:')) {
      final urls = await _mangalib.getChapterPages(chapterId);
      return (dataUrls: urls, dataSaverUrls: const <String>[]);
    }
    if (chapterId.startsWith('remanga:')) {
      final urls = await _remanga.getChapterPages(chapterId);
      return (dataUrls: urls, dataSaverUrls: const <String>[]);
    }
    if (chapterId.startsWith('desu:')) {
      final urls = await _desu.getChapterPages(chapterId);
      return (dataUrls: urls, dataSaverUrls: const <String>[]);
    }
    return _mangadex.getChapterPagesWithFallback(chapterId);
  }

  /// Загружает страницы главы с прозрачным обходом 402/403 paywall на ReManga через Desu.uno / MangaDex.
  Future<({List<String> dataUrls, List<String> dataSaverUrls})>
      getChapterPagesForChapter(
    MangaDexChapter chapter, {
    String? mangaTitle,
    String? originalTitle,
  }) async {
    final primary = await getChapterPagesWithFallback(chapter.id);
    if (primary.dataUrls.isNotEmpty || primary.dataSaverUrls.isNotEmpty) {
      return primary;
    }

    if (chapter.id.startsWith('remanga:')) {
      final queries = buildNormalizedQueries(originalTitle, mangaTitle);
      final desuChapters = await _searchDesuChapters(queries);
      final matched = desuChapters.where((c) {
        if (chapter.chapterNumber != null && c.chapterNumber != null) {
          return (c.chapterNumber! - chapter.chapterNumber!).abs() < 0.01;
        }
        return c.chapterLabel == chapter.chapterLabel;
      }).toList();
      if (matched.isNotEmpty) {
        final urls = await _desu.getChapterPages(matched.first.id);
        if (urls.isNotEmpty) {
          return (dataUrls: urls, dataSaverUrls: const <String>[]);
        }
      }
    }
    return primary;
  }
}

