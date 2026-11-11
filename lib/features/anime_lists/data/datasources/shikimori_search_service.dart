import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Модель найденного тайтла из официального API Shikimori
class ShikimoriAnimeMatch {
  final int id;
  final String russianTitle;
  final String englishTitle;
  final String posterUrl;
  final int? episodesTotal;
  final double score;

  const ShikimoriAnimeMatch({
    required this.id,
    required this.russianTitle,
    required this.englishTitle,
    required this.posterUrl,
    this.episodesTotal,
    this.score = 0.0,
  });
}

/// Сервис умного поиска по официальному Shikimori API
/// с поддержкой точного матчинга, мягкого поиска подсезонов (OVA/ТВ-2/Рекап)
/// и кэширования результатов.
class ShikimoriSearchService {
  final Dio _dio;
  static const String _baseUrl = 'https://shikimori.io/api';
  static final Map<String, ShikimoriAnimeMatch?> _cache = {};

  ShikimoriSearchService({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 10),
                headers: {
                  if (!kIsWeb)
                    'User-Agent':
                        'SyncPai/1.0.0 (Anime Sync App; contact@syncpai.app)',
                  'Accept': 'application/json',
                },
              ),
            );

  /// Найти аниме на Shikimori по чистому названию
  Future<ShikimoriAnimeMatch?> findAnime(String rawTitle) async {
    final query = rawTitle.trim();
    if (query.isEmpty) return null;

    final cacheKey = query.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      // 1. Точный поиск по переданному названию
      var match = await _searchSingle(query);

      // 2. Мягкий поиск: убираем подсезоны, OVA, рекапы и спецвыпуски, если точный поиск не дал результатов
      if (match == null) {
        final simplified = _simplifyTitle(query);
        if (simplified.isNotEmpty && simplified.toLowerCase() != query.toLowerCase()) {
          match = await _searchSingle(simplified);
        }
      }

      _cache[cacheKey] = match;
      return match;
    } catch (e) {
      debugPrint('Shikimori search error for "$query": $e');
      return null;
    }
  }

  Future<ShikimoriAnimeMatch?> _searchSingle(String search) async {
    // 1. Приоритетный поиск через AniLibria API (красивые постеры, русские названия и привязка к shikimori_id)
    try {
      final anilibriaRes = await _dio.get(
        'https://anilibria.top/api/v1/app/search/releases',
        queryParameters: {'query': search},
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      final dynamic aData = anilibriaRes.data;
      List<dynamic> releases = [];
      if (aData is List) {
        releases = aData;
      } else if (aData is Map && aData['data'] is List) {
        releases = aData['data'] as List;
      }

      if (releases.isNotEmpty) {
        final firstRel = releases.first as Map<String, dynamic>;
        final relId = (firstRel['id'] as num?)?.toInt() ?? 0;
        final shikiObj = firstRel['shikimori'] as Map<String, dynamic>?;
        final shikiId = (shikiObj?['id'] as num?)?.toInt() ?? relId;

        final nameObj = firstRel['name'] as Map<String, dynamic>?;
        final ruTitle = nameObj?['main']?.toString() ?? search;
        final enTitle = nameObj?['english']?.toString() ?? '';

        String poster = '';
        if (firstRel['poster'] is Map) {
          final pMap = firstRel['poster'] as Map;
          final raw = pMap['preview'] ??
              (pMap['optimized'] is Map ? (pMap['optimized']['thumbnail'] ?? pMap['optimized']['url']) : null) ??
              pMap['src'] ??
              pMap['url'];
          if (raw != null && raw.toString().isNotEmpty) {
            final pathStr = raw.toString();
            poster = pathStr.startsWith('http') ? pathStr : 'https://anilibria.top$pathStr';
          }
        }

        if (poster.isEmpty && shikiId > 0) {
          poster = 'https://shikimori.io/system/animes/original/$shikiId.jpg';
        }

        final episodes = (firstRel['episodes_total'] as num?)?.toInt() ??
            (firstRel['type'] is Map ? (firstRel['type']['episodes'] as num?)?.toInt() : null);

        final score = (shikiObj?['rating'] as num?)?.toDouble() ?? 0.0;

        return ShikimoriAnimeMatch(
          id: shikiId > 0 ? shikiId : relId,
          russianTitle: ruTitle,
          englishTitle: enTitle,
          posterUrl: poster,
          episodesTotal: episodes,
          score: score,
        );
      }
    } catch (_) {}

    // 2. Резервный поиск через Shikimori API
    try {
      final response = await _dio.get(
        'https://shikimori.io/api/animes',
        queryParameters: {
          'search': search,
          'limit': 1,
        },
      );

      if (response.statusCode == 200 && response.data is List) {
        final list = response.data as List;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final id = first['id'] as int?;
          if (id != null) {
            final imageObj = first['image'] as Map<String, dynamic>?;
            final rawOriginal = imageObj?['original'] as String? ?? imageObj?['preview'] as String? ?? '';
            final poster = rawOriginal.isNotEmpty
                ? (rawOriginal.startsWith('http') ? rawOriginal : 'https://shikimori.io$rawOriginal')
                : 'https://shikimori.io/system/animes/original/$id.jpg';

            final russian = (first['russian'] as String?)?.trim();
            final name = (first['name'] as String?)?.trim() ?? '';
            final effectiveRussian = (russian != null && russian.isNotEmpty) ? russian : name;
            final episodes = first['episodes'] as int?;
            final score = double.tryParse('${first['score'] ?? ''}') ?? 0.0;

            return ShikimoriAnimeMatch(
              id: id,
              russianTitle: effectiveRussian.isNotEmpty ? effectiveRussian : search,
              englishTitle: name,
              posterUrl: poster,
              episodesTotal: episodes,
              score: score,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Упрощение названий тайтлов для мягкого поиска:
  /// - «Арифурэта: Сильнейший ремесленник в мире — Дополнительные эпизоды» -> «Арифурэта»
  /// - «Ванпанчмен 2: Спецвыпуски» -> «Ванпанчмен 2»
  /// - «Магическая битва 2: Рекап» -> «Магическая битва 2»
  /// - «Старшая школа DxD OVA» -> «Старшая школа DxD»
  static String _simplifyTitle(String title) {
    String cleaned = title
        .replaceAll(
          RegExp(
            r'(\s*[—–-]\s*(Дополнительные эпизоды|Рекап|Часть\s*\d+|Узы|Кровавая тюрьма|Потерянная башня|Смертельная миграция|Наследники воли огня|Путь ниндзя|Адепты Тёмного царства|Битва с яичницей-глазуньей|Битва при Огненной Деревне|Спортивный фестиваль Конохи|Восстаньте из тени|Как стать сильнее|Корона гоблина|Сезон \d+|Эпизод \d+|Фильм|The Movie).*$)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'(:\s*(Спецвыпуски|Тиби|Мини-аниме!?|Памятный эпизод|Рекап|Турнир трёх магий.*|Экзамен на звание.*|Мэш Бёрндэд.*|Поднебесье|Рождественская битва).*$)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s*(OVA|ONA|ТВ-\d+|Спецвыпуски).*$', caseSensitive: false), '')
        .trim();

    // Если всё ещё содержит двоеточие и очень длинное:
    if (cleaned.contains(': ') && cleaned.length > 35) {
      final parts = cleaned.split(': ');
      if (parts.first.length > 5) {
        cleaned = parts.first.trim();
      }
    }

    return cleaned.trim();
  }
}

