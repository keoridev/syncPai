import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../domain/entities/user_anime_entry.dart';
import 'anixart_csv_parser.dart';

class AnixartImportResult {
  final List<UserAnimeEntry> entries;
  final int totalParsed;
  final int totalEpisodes;
  final String estimatedTimeSpent;

  const AnixartImportResult({
    required this.entries,
    required this.totalParsed,
    required this.totalEpisodes,
    required this.estimatedTimeSpent,
  });
}

abstract final class AnixartBackupParser {
  /// Распарсить сырой файл выгрузки Anixart (.csv, .txt или .json)
  static AnixartImportResult parse(String rawContent, {required String userId}) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) {
      return const AnixartImportResult(
        entries: [],
        totalParsed: 0,
        totalEpisodes: 0,
        estimatedTimeSpent: '0 мин.',
      );
    }

    // Если контент не похож на JSON — парсим через быстрый CSV-парсер
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return AnixartCsvParser.parseToResult(rawContent, userId: userId);
    }

    final List<UserAnimeEntry> entries = [];

    try {
      final decoded = jsonDecode(rawContent);
      List<dynamic> items = [];

      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('bookmarks') && decoded['bookmarks'] is List) {
          items = decoded['bookmarks'] as List;
        } else if (decoded.containsKey('releases') && decoded['releases'] is List) {
          items = decoded['releases'] as List;
        } else if (decoded.containsKey('history') && decoded['history'] is List) {
          items = decoded['history'] as List;
        } else if (decoded.containsKey('data') && decoded['data'] is List) {
          items = decoded['data'] as List;
        } else {
          // Попытка собрать все массивы из корня объекта
          for (final val in decoded.values) {
            if (val is List) {
              items.addAll(val);
            }
          }
        }
      }

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;

        final animeId = item['release_id'] as int? ??
            item['id'] as int? ??
            item['anime_id'] as int? ??
            int.tryParse('${item['id'] ?? ''}') ??
            DateTime.now().microsecondsSinceEpoch % 100000;

        final title = item['title_ru'] as String? ??
            item['title'] as String? ??
            item['name_ru'] as String? ??
            item['name'] as String? ??
            'Аниме #$animeId';

        final poster = item['poster_url'] as String? ??
            item['poster'] as String? ??
            item['image'] as String?;

        final rawStatus = item['status'] ?? item['category'] ?? item['type'];
        final status = _parseAnixartStatus(rawStatus);

        final lastEp = item['watched_episodes'] as int? ??
            item['last_episode'] as int? ??
            item['episode'] as int? ??
            1;

        final totalEp = item['episodes_total'] as int? ??
            item['total_episodes'] as int? ??
            item['episodes'] as int?;

        entries.add(UserAnimeEntry(
          id: 'imported_${animeId}_${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          animeId: animeId,
          titleRu: title,
          posterUrl: poster,
          status: status,
          lastEpisode: lastEp,
          episodesTotal: totalEp,
          updatedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Anixart JSON parsing failed, attempting CSV fallback: $e');
      return AnixartCsvParser.parseToResult(rawContent, userId: userId);
    }

    final stats = UserAnimeStats.compute(entries);

    return AnixartImportResult(
      entries: entries,
      totalParsed: entries.length,
      totalEpisodes: stats.totalEpisodesCompleted,
      estimatedTimeSpent: stats.formattedTime,
    );
  }

  static AnimeListStatus _parseAnixartStatus(dynamic val) {
    if (val == null) return AnimeListStatus.watching;

    if (val is int) {
      switch (val) {
        case 1:
          return AnimeListStatus.watching;
        case 2:
          return AnimeListStatus.planned;
        case 3:
          return AnimeListStatus.completed;
        case 4:
          return AnimeListStatus.dropped;
        default:
          return AnimeListStatus.watching;
      }
    }

    final str = val.toString().toLowerCase();
    if (str.contains('watch') || str.contains('смотр')) return AnimeListStatus.watching;
    if (str.contains('plan') || str.contains('план')) return AnimeListStatus.planned;
    if (str.contains('comp') || str.contains('просмотр') || str.contains('заверш')) return AnimeListStatus.completed;
    if (str.contains('drop') || str.contains('брош')) return AnimeListStatus.dropped;

    return AnimeListStatus.watching;
  }
}
