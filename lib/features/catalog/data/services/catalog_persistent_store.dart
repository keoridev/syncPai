import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/anime_title.dart';

String _encodeCatalogJson(List<Map<String, dynamic>> payload) =>
    jsonEncode(payload);

List<AnimeTitle> _decodeCatalogJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  final parsed = <AnimeTitle>[];
  for (final item in decoded) {
    if (item is Map) {
      parsed.add(AnimeTitle.fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return parsed;
}

/// Персистентное локальное хранилище метаданных каталога (Stale-While-Revalidate).
/// Отдаёт кэшированные релизы за 0 мс при запуске и переключении категорий,
/// а при поступлении свежей дельты (новые серии, обновлённые постеры) бесшовно сливает и сохраняет индекс.
class CatalogPersistentStore {
  static final CatalogPersistentStore instance = CatalogPersistentStore._();
  CatalogPersistentStore._();

  static const String _fileName = 'syncpai_catalog_index_v1.json';
  static const int _maxEntries = 2500;

  static const Duration signatureCacheTtl = Duration(days: 30);

  final Map<int, AnimeTitle> _byId = {};
  final List<int> _orderedIds = [];
  final Map<String, List<AnimeTitle>> _filteredPageCache = {};
  final Map<String, ({List<AnimeTitle> items, int page, bool hasMore, DateTime cachedAt})>
      _signatureCache = {};
  bool _initialized = false;
  File? _overrideFile;
  Timer? _persistDebounceTimer;

  /// Ключ кэша по канонической сигнатуре фильтра.
  String signatureStorageKey(String signature) => 'catalog_$signature';

  /// Сохраняет склеенный список и resume-page строго под сигнатурой фильтра (TTL 30 дней).
  void putBySignature(
    String signature,
    List<AnimeTitle> items, {
    required int page,
    required bool hasMore,
  }) {
    _signatureCache[signatureStorageKey(signature)] = (
      items: List<AnimeTitle>.unmodifiable(items),
      page: page,
      hasMore: hasMore,
      cachedAt: DateTime.now(),
    );
  }

  /// Возвращает кэш строго для данной сигнатуры (никогда не подмешивает общий кэш «Все»).
  ({List<AnimeTitle> items, int page, bool hasMore})? getBySignature(
    String signature,
  ) {
    final key = signatureStorageKey(signature);
    final entry = _signatureCache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.cachedAt) > signatureCacheTtl) {
      _signatureCache.remove(key);
      return null;
    }
    return (items: entry.items, page: entry.page, hasMore: entry.hasMore);
  }

  int getResumePage(String signature) =>
      getBySignature(signature)?.page ?? 1;

  /// Формирует изолированный ключ кэша с учётом всех активных фильтров и страницы.
  String buildFilterCacheKey({
    String? genre,
    String? status,
    String? type,
    String sort = 'updates',
    int page = 1,
  }) {
    final g = (genre ?? 'all').trim().toLowerCase();
    final st = (status ?? 'all').trim().toLowerCase();
    final tp = (type ?? 'all').trim().toLowerCase();
    return 'catalog_${g}_${sort}_${st}_${tp}_page_$page';
  }

  List<AnimeTitle>? getFilteredPage({
    String? genre,
    String? status,
    String? type,
    String sort = 'updates',
    int page = 1,
  }) =>
      _filteredPageCache[buildFilterCacheKey(
        genre: genre,
        status: status,
        type: type,
        sort: sort,
        page: page,
      )];

  void putFilteredPage(
    List<AnimeTitle> items, {
    String? genre,
    String? status,
    String? type,
    String sort = 'updates',
    int page = 1,
  }) {
    _filteredPageCache[buildFilterCacheKey(
      genre: genre,
      status: status,
      type: type,
      sort: sort,
      page: page,
    )] = List<AnimeTitle>.unmodifiable(items);
  }

  @visibleForTesting
  void setTestFile(File? file) {
    _overrideFile = file;
    _byId.clear();
    _orderedIds.clear();
    _filteredPageCache.clear();
    _signatureCache.clear();
    _initialized = false;
  }

  Future<File?> _resolveFile() async {
    if (_overrideFile != null) return _overrideFile;
    try {
      if (kIsWeb) return null;
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _resolveFile();
      if (file == null || !await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final parsed = await compute(_decodeCatalogJson, raw);
      for (final title in parsed) {
        if (!_byId.containsKey(title.id)) {
          _orderedIds.add(title.id);
        }
        _byId[title.id] = title;
      }
    } catch (e) {
      debugPrint('[CatalogPersistentStore] init error: $e');
    }
  }

  bool get isEmpty => _byId.isEmpty;
  int get length => _byId.length;

  /// Мгновенная синхронная выборка из локального индекса (0 мс).
  List<AnimeTitle> queryLocal({
    String? genre,
    String? status,
    String? type,
    String sort = 'updates',
    int limit = 40,
  }) {
    if (_byId.isEmpty) return const [];
    String norm(String s) =>
        s.trim().toLowerCase().replaceAll('ё', 'е').replaceAll('э', 'е');
    final cleanGenre = genre != null ? norm(genre) : null;
    final cleanStatus = status?.trim().toLowerCase();
    final cleanType = type?.trim().toLowerCase();

    final results = <AnimeTitle>[];
    for (final id in _orderedIds) {
      final t = _byId[id];
      if (t == null) continue;
      if (cleanGenre != null &&
          cleanGenre.isNotEmpty &&
          cleanGenre != 'все') {
        final hasGenre = t.genres.any((g) => norm(g) == cleanGenre);
        if (!hasGenre) continue;
      }
      if (cleanStatus != null && cleanStatus.isNotEmpty) {
        final st = t.status.toLowerCase();
        final isOngoing = st.contains('ongoing') ||
            st.contains('выходит') ||
            st.contains('онгоинг') ||
            st.contains('в работе') ||
            st.contains('процесс');
        final isAnnounced = st.contains('anons') ||
            st.contains('анонс') ||
            st.contains('скоро') ||
            st.contains('in_production');
        if (cleanStatus == 'ongoing' && (!isOngoing || isAnnounced)) {
          continue;
        }
        if (cleanStatus == 'released' && (isOngoing || isAnnounced)) {
          continue;
        }
        if ((cleanStatus == 'anons' || cleanStatus == 'anonses') &&
            !isAnnounced &&
            !(t.episodes.isEmpty && (t.episodesTotal ?? 0) == 0)) {
          continue;
        }
      }
      if (cleanType != null && cleanType.isNotEmpty) {
        final kind = (t.kind ?? '').trim().toLowerCase();
        if (cleanType == 'movie') {
          final isMovie = kind == 'movie' ||
              kind.contains('movie') ||
              kind.contains('фильм');
          if (!isMovie) continue;
        } else if (kind != cleanType) {
          continue;
        }
      }
      results.add(t);
    }

    if (sort == 'rating') {
      results.sort((a, b) {
        final cmp = (b.score ?? 0).compareTo(a.score ?? 0);
        if (cmp != 0) return cmp;
        return (b.episodesTotal ?? 0).compareTo(a.episodesTotal ?? 0);
      });
    } else if (sort == 'yearDesc') {
      results.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    } else if (sort == 'yearAsc') {
      results.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
    }

    return results.length > limit ? results.sublist(0, limit) : results;
  }

  /// Слияние свежих релизов/онгоингов с существующим индексом и запись на диск.
  /// Возвращает true, если появились новые тайтлы, новые серии или обновился постер.
  Future<bool> mergeAndPersist(List<AnimeTitle> incoming) async {
    if (incoming.isEmpty) return false;
    bool changed = false;

    for (final item in incoming) {
      final prev = _byId[item.id];
      if (prev == null) {
        _byId[item.id] = item;
        _orderedIds.remove(item.id);
        _orderedIds.add(item.id);
        changed = true;
      } else {
        final hasNewEpisode =
            (item.latestEpisode ?? 0) > (prev.latestEpisode ?? 0) ||
                (item.episodesTotal ?? 0) > (prev.episodesTotal ?? 0);
        final hasUpdatedPoster = item.posterMedium.isNotEmpty &&
            item.posterMedium != prev.posterMedium;
        if (hasNewEpisode ||
            hasUpdatedPoster ||
            (prev.description.isEmpty && item.description.isNotEmpty)) {
          _byId[item.id] = item;
          changed = true;
        }
      }
    }

    // Ограничиваем размер индекса (~5–10 МБ для 2500 релизов)
    while (_orderedIds.length > _maxEntries) {
      final oldestId = _orderedIds.removeLast();
      _byId.remove(oldestId);
      changed = true;
    }

    if (changed) {
      if (_overrideFile != null) {
        await _persistToDisk();
      } else {
        _schedulePersistToDisk();
      }
    }
    return changed;
  }

  void _schedulePersistToDisk() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_persistToDisk());
    });
  }

  Future<void> _persistToDisk() async {
    try {
      final file = await _resolveFile();
      if (file == null) return;
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final snapshot = _orderedIds
          .map((id) => _byId[id])
          .whereType<AnimeTitle>()
          .map((t) => t.toJson())
          .toList();
      final encoded = await compute(_encodeCatalogJson, snapshot);
      await file.writeAsString(encoded, flush: true);
    } catch (e) {
      debugPrint('[CatalogPersistentStore] persist error: $e');
    }
  }

  Future<void> clear() async {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = null;
    _byId.clear();
    _orderedIds.clear();
    try {
      final file = await _resolveFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
