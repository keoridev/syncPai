import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/anime_title.dart';

/// Персистентное локальное хранилище метаданных каталога (Stale-While-Revalidate).
/// Отдаёт кэшированные релизы за 0 мс при запуске и переключении категорий,
/// а при поступлении свежей дельты (новые серии, обновлённые постеры) бесшовно сливает и сохраняет индекс.
class CatalogPersistentStore {
  static final CatalogPersistentStore instance = CatalogPersistentStore._();
  CatalogPersistentStore._();

  static const String _fileName = 'syncpai_catalog_index_v1.json';
  static const int _maxEntries = 2500;

  final Map<int, AnimeTitle> _byId = {};
  final List<int> _orderedIds = [];
  bool _initialized = false;
  File? _overrideFile;

  @visibleForTesting
  void setTestFile(File? file) {
    _overrideFile = file;
    _byId.clear();
    _orderedIds.clear();
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
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final title = AnimeTitle.fromJson(Map<String, dynamic>.from(item));
            if (!_byId.containsKey(title.id)) {
              _orderedIds.add(title.id);
            }
            _byId[title.id] = title;
          }
        }
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
    String sort = 'updates',
    int limit = 40,
  }) {
    if (_byId.isEmpty) return const [];
    final cleanGenre = genre?.trim().toLowerCase();
    final cleanStatus = status?.trim().toLowerCase();

    final results = <AnimeTitle>[];
    for (final id in _orderedIds) {
      final t = _byId[id];
      if (t == null) continue;
      if (cleanGenre != null &&
          cleanGenre.isNotEmpty &&
          cleanGenre != 'все') {
        final hasGenre = t.genres.any(
          (g) => g.trim().toLowerCase() == cleanGenre,
        );
        if (!hasGenre) continue;
      }
      if (cleanStatus != null && cleanStatus.isNotEmpty) {
        final st = t.status.toLowerCase();
        if (cleanStatus == 'ongoing' && !st.contains('ongoing') && !st.contains('выходит') && !st.contains('онгоинг')) {
          continue;
        }
        if (cleanStatus == 'released' && (st.contains('ongoing') || st.contains('онгоинг'))) {
          continue;
        }
      }
      results.add(t);
    }

    if (sort == 'rating') {
      results.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
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
      await _persistToDisk();
    }
    return changed;
  }

  Future<void> _persistToDisk() async {
    try {
      final file = await _resolveFile();
      if (file == null) return;
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final payload = _orderedIds
          .map((id) => _byId[id])
          .whereType<AnimeTitle>()
          .map((t) => t.toJson())
          .toList();
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (e) {
      debugPrint('[CatalogPersistentStore] persist error: $e');
    }
  }

  Future<void> clear() async {
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
