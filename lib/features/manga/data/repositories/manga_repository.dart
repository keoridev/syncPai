import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/manga_bridge.dart';
import '../datasources/desu_datasource.dart';
import '../datasources/mangadex_datasource.dart';
import '../datasources/remanga_datasource.dart';

/// Единый репозиторий манги и манхвы:
/// - Первичные русскоязычные источники: ReManga + Desu.uno
/// - Третичный fallback: MangaDex
/// - Дедупликация in-flight запросов + LRU кэш (12 страниц) + SharedPreferences (6ч TTL)
class MangaRepository {
  static final MangaRepository instance = MangaRepository();

  static const int maxMemoryPages = 12;
  static const Duration diskCacheTtl = Duration(hours: 6);
  static const String _diskPrefix = 'syncpai_manga_repo_cache_v1_';

  final RemangaDataSource _remanga;
  final DesuDataSource _desu;
  final MangaDexDataSource _mangadex;
  final SharedPreferences? _prefsOverride;

  final LinkedHashMap<String, List<MangaDexManga>> _memoryLru = LinkedHashMap();
  final Map<String, Future<List<MangaDexManga>>> _inFlight = {};

  MangaRepository({
    RemangaDataSource? remanga,
    DesuDataSource? desu,
    MangaDexDataSource? mangadex,
    SharedPreferences? prefs,
  })  : _remanga = remanga ?? RemangaDataSource(),
        _desu = desu ?? DesuDataSource(),
        _mangadex = mangadex ?? MangaDexDataSource(),
        _prefsOverride = prefs;

  Future<SharedPreferences> _getPrefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

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

  Future<List<MangaDexManga>> searchManga(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const []);
    final key = 'search_${trimmed.toLowerCase()}';
    return _inFlight.putIfAbsent(key, () async {
      try {
        final results = await Future.wait([
          _remanga.searchCatalog(trimmed, count: 25),
          _desu.browseCatalog(search: trimmed, limit: 25),
        ]);
        final merged = <MangaDexManga>[];
        final seenTitles = <String>{};
        for (final list in results) {
          for (final item in list) {
            final norm = item.title.trim().toLowerCase();
            if (seenTitles.add(norm)) {
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
    return _mangadex.getMangaById(id);
  }

  /// Загружает русские главы с автоматическим зеркалированием платных глав ReManga на Desu.uno.
  Future<List<MangaDexChapter>> getChapters(MangaDexManga manga) async {
    if (manga.id.startsWith('remanga:')) {
      final remangaChapters = await _remanga.getChaptersByDir(manga.id);
      final freeRemanga = remangaChapters.where((c) => !c.isPaid).toList();
      final hasPaidGaps =
          remangaChapters.any((c) => c.isPaid) || freeRemanga.isEmpty;

      if (!hasPaidGaps && freeRemanga.isNotEmpty) {
        return freeRemanga;
      }

      // Если на ReManga есть платные главы — подтягиваем бесплатные главы с Desu.uno
      final desuMatches = await _desu.browseCatalog(
        search: manga.title,
        limit: 5,
      );
      List<MangaDexChapter> desuChapters = const [];
      for (final match in desuMatches.take(2)) {
        desuChapters = await _desu.getChapters(match.id);
        if (desuChapters.isNotEmpty) break;
      }
      if (desuChapters.isEmpty &&
          manga.originalTitle != null &&
          manga.originalTitle!.trim().isNotEmpty) {
        final origMatches = await _desu.browseCatalog(
          search: manga.originalTitle!,
          limit: 5,
        );
        for (final match in origMatches.take(2)) {
          desuChapters = await _desu.getChapters(match.id);
          if (desuChapters.isNotEmpty) break;
        }
      }

      if (freeRemanga.isEmpty && desuChapters.isNotEmpty) {
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
        return merged;
      }
      if (freeRemanga.isNotEmpty) return freeRemanga;

      return _mangadex.getChapters(
        manga.id,
        title: manga.title,
        originalTitle: manga.originalTitle,
      );
    }

    if (manga.id.startsWith('desu:')) {
      final desuChapters = await _desu.getChapters(manga.id);
      if (desuChapters.isNotEmpty) return desuChapters;
      return _remanga.getChaptersByTitle(
        title: manga.title,
        originalTitle: manga.originalTitle,
      );
    }

    // Fallback для MangaDex ID: сначала пробуем MangaDex RU -> ReManga -> Desu -> MangaDex EN
    final mdChapters = await _mangadex.getChapters(
      manga.id,
      title: manga.title,
      originalTitle: manga.originalTitle,
    );
    if (mdChapters.isNotEmpty && mdChapters.first.translatedLanguage == 'ru') {
      return mdChapters;
    }
    final desuMatches = await _desu.browseCatalog(search: manga.title, limit: 3);
    for (final match in desuMatches.take(2)) {
      final desuCh = await _desu.getChapters(match.id);
      if (desuCh.isNotEmpty) return desuCh;
    }
    return mdChapters;
  }

  Future<({List<String> dataUrls, List<String> dataSaverUrls})>
      getChapterPagesWithFallback(String chapterId) async {
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
}

