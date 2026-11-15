import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../domain/entities/user_anime_entry.dart';

class ImportEnrichmentMatch {
  final int oldAnimeId;
  final int? matchedAnimeId;
  final String posterUrl;
  final int? totalEpisodes;

  const ImportEnrichmentMatch({
    required this.oldAnimeId,
    this.matchedAnimeId,
    required this.posterUrl,
    this.totalEpisodes,
  });
}

/// Фоновый воркер для дозагрузки постеров, totalEpisodes и реального ID
/// импортированных карточек без постера (макс. 3 параллельных запроса с шагом 250мс).
class ImportPosterEnricher {
  ImportPosterEnricher._();
  static final ImportPosterEnricher instance = ImportPosterEnricher._();

  static const int maxConcurrent = 3;
  static const Duration spacing = Duration(milliseconds: 250);

  Future<void> enrichEntries(
    List<UserAnimeEntry> entries, {
    required Future<void> Function(ImportEnrichmentMatch match) onEnriched,
    Dio? dio,
  }) async {
    final pending = entries
        .where((e) => e.posterUrl == null || e.posterUrl!.trim().isEmpty)
        .toList();
    if (pending.isEmpty) return;

    final client = dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 8),
            headers: {
              if (!kIsWeb) 'User-Agent': 'SyncPai/1.0.0',
              'Accept': 'application/json',
            },
          ),
        );

    int cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (cursor >= pending.length) break;
        final entry = pending[cursor++];
        try {
          final match = await _lookupMetadata(client, entry);
          if (match != null) {
            await onEnriched(match);
          }
        } catch (e) {
          debugPrint('[ImportPosterEnricher] error for "${entry.titleRu}": $e');
        }
        await Future<void>.delayed(spacing);
      }
    }

    final workers = List.generate(
      pending.length < maxConcurrent ? pending.length : maxConcurrent,
      (_) => worker(),
    );
    await Future.wait(workers);
  }

  Future<ImportEnrichmentMatch?> _lookupMetadata(
    Dio client,
    UserAnimeEntry entry,
  ) async {
    final query = entry.titleRu.trim();
    if (query.isEmpty) return null;
    final encoded = Uri.encodeQueryComponent(query);

    // 1. AniLibria API v1
    try {
      final resp = await client.get<dynamic>(
        'https://anilibria.top/api/v1/anime/catalog/releases?f[search]=$encoded&limit=1',
      );
      final list = _extractList(resp.data);
      if (list.isNotEmpty && list.first is Map) {
        final item = Map<String, dynamic>.from(list.first as Map);
        final posterObj = item['poster'];
        String poster = '';
        if (posterObj is Map) {
          final opt = posterObj['optimized'];
          if (opt is Map && opt['src'] != null) {
            poster = opt['src'].toString();
          } else if (posterObj['src'] != null) {
            poster = posterObj['src'].toString();
          }
        }
        if (poster.startsWith('/')) {
          poster = 'https://anilibria.top$poster';
        }
        if (poster.isNotEmpty) {
          final id = item['id'] is int ? item['id'] as int : int.tryParse('${item['id']}');
          final epTotal = item['episodes_total'] is int
              ? item['episodes_total'] as int
              : int.tryParse('${item['episodes_total']}');
          return ImportEnrichmentMatch(
            oldAnimeId: entry.animeId,
            matchedAnimeId: id,
            posterUrl: poster,
            totalEpisodes: epTotal,
          );
        }
      }
    } catch (_) {}

    // 2. Fallback: Shikimori API
    try {
      final resp = await client.get<dynamic>(
        'https://shikimori.one/api/animes?search=$encoded&limit=1',
      );
      final list = _extractList(resp.data);
      if (list.isNotEmpty && list.first is Map) {
        final item = Map<String, dynamic>.from(list.first as Map);
        final imageObj = item['image'];
        String poster = '';
        if (imageObj is Map) {
          poster = (imageObj['original'] ?? imageObj['preview'] ?? '').toString();
        }
        if (poster.startsWith('/')) {
          poster = 'https://shikimori.one$poster';
        }
        if (poster.isNotEmpty) {
          final id = item['id'] is int ? item['id'] as int : int.tryParse('${item['id']}');
          final epTotal = item['episodes'] is int
              ? item['episodes'] as int
              : int.tryParse('${item['episodes']}');
          return ImportEnrichmentMatch(
            oldAnimeId: entry.animeId,
            matchedAnimeId: id,
            posterUrl: poster,
            totalEpisodes: epTotal,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    return const [];
  }
}

