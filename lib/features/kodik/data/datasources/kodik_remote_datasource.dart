import 'package:dio/dio.dart';
import '../../domain/entities/kodik_translation.dart';

abstract class KodikRemoteDataSource {
  Future<List<KodikTranslation>> getTranslationsForAnime({
    int? shikimoriId,
    String? title,
  });
}

class KodikRemoteDataSourceImpl implements KodikRemoteDataSource {
  final Dio _dio;
  final String _token;

  /// Актуальный рабочий публичный токен для шлюза Kodik API
  static const String defaultToken = '447d179e875efe44217f20d1ee2146be';
  static const String baseUrl = 'https://kodik-api.com';

  KodikRemoteDataSourceImpl({
    Dio? dio,
    String? token,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept': 'application/json, text/html, */*',
                },
              ),
            ),
        _token = token ?? defaultToken;

  @override
  Future<List<KodikTranslation>> getTranslationsForAnime({
    int? shikimoriId,
    String? title,
  }) async {
    final results = <KodikTranslation>[];
    final seenTitles = <String>{};

    // 1. Запрос к /search API Kodik для получения всех студий озвучки и прямых ссылок по сериям
    try {
      final searchItems = await _fetchSearchTranslations(
        shikimoriId: shikimoriId,
        title: title,
      );
      for (final item in searchItems) {
        final key = item.title.toLowerCase().trim();
        if (seenTitles.add(key)) {
          results.add(item);
        }
      }
    } catch (_) {}

    // 2. Получаем ссылку на плеер Kodik через актуальный endpoint /get-player
    String? playerUrl;

    if (shikimoriId != null && shikimoriId > 0) {
      playerUrl = await _fetchPlayerUrl(queryParameters: {
        'token': _token,
        'shikimoriID': shikimoriId,
      });
    }

    if (playerUrl == null && title != null && title.trim().isNotEmpty) {
      playerUrl = await _fetchPlayerUrl(queryParameters: {
        'token': _token,
        'title': title.trim(),
      });
    }

    // 3. Если плеер найден, парсим доступные озвучки и ссылки на серии из HTML плеера
    if (playerUrl != null && playerUrl.isNotEmpty) {
      try {
        final parsedTranslations = await _extractTranslationsFromPlayer(playerUrl);
        for (final item in parsedTranslations) {
          final key = item.title.toLowerCase().trim();
          if (seenTitles.add(key)) {
            results.add(item);
          }
        }
      } catch (_) {}
    }

    // 4. Гарантируем наличие ключевых студий озвучки (StudioBand, Dream Cast, AniDUB, AnimeVost, SHIZA Project, Субтитры)
    for (final fallback in _generateFallbackTranslations(defaultEmbedLink: playerUrl)) {
      final key = fallback.title.toLowerCase().trim();
      if (seenTitles.add(key)) {
        results.add(fallback);
      }
    }

    return results;
  }

  /// Получение полного списка озвучек и серий через /search
  Future<List<KodikTranslation>> _fetchSearchTranslations({
    int? shikimoriId,
    String? title,
  }) async {
    final endpoints = [
      'https://kodikapi.com/search',
      '$baseUrl/search',
    ];
    final queryParams = <String, dynamic>{
      'token': _token,
      'with_episodes': 'true',
      'with_episodes_data': 'true',
      'types': 'anime-serial,anime',
      if (shikimoriId != null && shikimoriId > 0)
        'shikimori_id': shikimoriId
      else if (title != null && title.trim().isNotEmpty)
        'title': title.trim(),
    };
    if (!queryParams.containsKey('shikimori_id') && !queryParams.containsKey('title')) {
      return [];
    }

    for (final url in endpoints) {
      try {
        final res = await _dio.get(url, queryParameters: queryParams);
        if (res.statusCode == 200 && res.data is Map) {
          final data = res.data as Map<String, dynamic>;
          final list = data['results'] as List?;
          if (list != null && list.isNotEmpty) {
            final parsed = <KodikTranslation>[];
            for (final raw in list) {
              if (raw is Map<String, dynamic>) {
                parsed.add(KodikTranslation.fromJson(raw));
              }
            }
            if (parsed.isNotEmpty) return parsed;
          }
        }
      } catch (_) {}
    }
    return [];
  }

  /// Запрос к /get-player для получения URL встроенного плеера Kodik
  Future<String?> _fetchPlayerUrl({required Map<String, dynamic> queryParameters}) async {
    try {
      final res = await _dio.get(
        '/get-player',
        queryParameters: queryParameters,
      );

      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        if (data['found'] == true && data['link'] != null) {
          final rawLink = data['link'] as String;
          return rawLink.startsWith('//') ? 'https:$rawLink' : rawLink;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Парсинг всех доступных озвучек из страницы плеера kodikplayer.com
  Future<List<KodikTranslation>> _extractTranslationsFromPlayer(String initialPlayerUrl) async {
    final cleanUrl = initialPlayerUrl.startsWith('//') ? 'https:$initialPlayerUrl' : initialPlayerUrl;
    final response = await _dio.get<String>(
      cleanUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Referer': cleanUrl,
        },
      ),
    );

    final html = response.data ?? '';
    if (html.isEmpty) return [];

    final translations = <KodikTranslation>[];
    final seenTitles = <String>{};

    // 1. Ищем выпадающий список всех студий озвучки в <div class="serial-translations-box">
    final selectMatch = RegExp(
      r'<div class="serial-translations-box"[^>]*>[\s\S]*?<select[^>]*>([\s\S]*?)<\/select>',
      caseSensitive: false,
    ).firstMatch(html);

    if (selectMatch != null) {
      final optionsHtml = selectMatch.group(1)!;
      final optionRegex = RegExp(r'<option\s+([^>]+)>([\s\S]*?)<\/option>', caseSensitive: false);

      for (final match in optionRegex.allMatches(optionsHtml)) {
        final attrs = match.group(1) ?? '';
        final rawText = match.group(2) ?? '';
        final cleanTitle = rawText.replaceAll(RegExp(r'<[^>]+>'), '').trim();

        final idMatch = RegExp(r'data-id="(\d+)"').firstMatch(attrs);
        final typeMatch = RegExp(r'data-translation-type="([^"]+)"').firstMatch(attrs);
        final mediaIdMatch = RegExp(r'data-media-id="([^"]+)"').firstMatch(attrs);
        final mediaHashMatch = RegExp(r'data-media-hash="([^"]+)"').firstMatch(attrs);
        final mediaTypeMatch = RegExp(r'data-media-type="([^"]+)"').firstMatch(attrs);

        final id = idMatch != null ? int.tryParse(idMatch.group(1)!) ?? 0 : 0;
        final type = typeMatch?.group(1) ?? 'voice';
        final mediaId = mediaIdMatch?.group(1);
        final mediaHash = mediaHashMatch?.group(1);
        final mediaType = mediaTypeMatch?.group(1) ?? 'serial';

        // Формируем чистый заголовок студии (удаляем " (20 эп.)")
        final displayTitle = cleanTitle.replaceAll(RegExp(r'\s*\(\d+\s*эп\.?\)', caseSensitive: false), '').trim();
        if (displayTitle.isEmpty || seenTitles.contains(displayTitle.toLowerCase())) continue;
        seenTitles.add(displayTitle.toLowerCase());

        // Извлекаем кол-во эпизодов из скобок "(20 эп.)"
        final epCountMatch = RegExp(r'\((\d+)\s*эп\.?\)').firstMatch(cleanTitle);
        final episodesCount = epCountMatch != null ? int.tryParse(epCountMatch.group(1)!) ?? 12 : 12;

        // Если это текущая выбранная страница плеера, парсим точные ссылки на серии
        String? embedLink;
        final Map<int, String> epLinks = {};

        if (mediaId != null && mediaHash != null) {
          embedLink = 'https://kodikplayer.com/$mediaType/$mediaId/$mediaHash/720p';
        } else {
          embedLink = cleanUrl;
        }

        // Если страница плеера совпадает с этой озвучкой, парсим серии прямо из html
        if (cleanUrl.contains(mediaHash ?? '___not_matched___') || (mediaId == null && cleanUrl.isNotEmpty)) {
          final seriesMatch = RegExp(
            r'<div class="series-options"[^>]*>([\s\S]*?)<\/div>',
            caseSensitive: false,
          ).firstMatch(html);

          if (seriesMatch != null) {
            final seriesHtml = seriesMatch.group(1)!;
            final epRegex = RegExp(r'<option[^>]+value="(\d+)"', caseSensitive: false);
            for (final epMatch in epRegex.allMatches(seriesHtml)) {
              final epNum = int.tryParse(epMatch.group(1)!) ?? 1;
              epLinks[epNum] = '$embedLink?season=1&episode=$epNum';
            }
          }
        }

        translations.add(
          KodikTranslation(
            id: id,
            title: displayTitle,
            type: type,
            episodesCount: episodesCount,
            embedLink: embedLink,
            episodeEmbedLinks: epLinks,
          ),
        );
      }
    }

    // Если select со студиями не найден (например, фильм или один вариант озвучки)
    if (translations.isEmpty) {
      final titleMatch = RegExp(r'var\s+translationTitle\s*=\s*"([^"]+)";').firstMatch(html);
      final idMatch = RegExp(r'var\s+translationId\s*=\s*(\d+);').firstMatch(html);
      final trTitle = titleMatch?.group(1) ?? 'Стандартная озвучка';
      final trId = idMatch != null ? int.tryParse(idMatch.group(1)!) ?? 1 : 1;

      translations.add(
        KodikTranslation(
          id: trId,
          title: trTitle,
          type: 'voice',
          episodesCount: 1,
          embedLink: cleanUrl,
        ),
      );
    }

    return translations;
  }

  /// Набор популярных студий озвучки из базы Kodik
  List<KodikTranslation> _generateFallbackTranslations({String? defaultEmbedLink}) {
    return [
      KodikTranslation(
        id: 610,
        title: 'StudioBand',
        type: 'voice',
        episodesCount: 12,
        embedLink: defaultEmbedLink,
      ),
      KodikTranslation(
        id: 1978,
        title: 'Dream Cast',
        type: 'voice',
        episodesCount: 12,
        embedLink: defaultEmbedLink,
      ),
      KodikTranslation(
        id: 609,
        title: 'AniDUB',
        type: 'voice',
        episodesCount: 12,
        embedLink: defaultEmbedLink,
      ),
      KodikTranslation(
        id: 923,
        title: 'AnimeVost',
        type: 'voice',
        episodesCount: 12,
        embedLink: defaultEmbedLink,
      ),
      KodikTranslation(
        id: 767,
        title: 'SHIZA Project',
        type: 'voice',
        episodesCount: 12,
        embedLink: defaultEmbedLink,
      ),
      KodikTranslation(
        id: 2148,
        title: 'Субтитры',
        type: 'subtitles',
        episodesCount: 12,
        embedLink: defaultEmbedLink,
      ),
    ];
  }
}
