import '../../../../core/network/api_constants.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/entities/episode_item.dart';

class AnimeTitleDto {
  final int id;
  final String code;
  final String russianTitle;
  final String englishTitle;
  final String posterSmall;
  final String posterMedium;
  final String posterOriginal;
  final String fallbackPosterUrl;
  final int? episodesTotal;
  final int? latestEpisode;
  final String? season;
  final int? year;
  final List<String> genres;
  final String description;
  final String status;
  final String? playerHost;
  final List<EpisodeItem> episodes;
  final String? trailerUrl;
  final String? shikimoriUrl;

  const AnimeTitleDto({
    required this.id,
    required this.code,
    required this.russianTitle,
    required this.englishTitle,
    required this.posterSmall,
    required this.posterMedium,
    required this.posterOriginal,
    this.fallbackPosterUrl = '',
    this.episodesTotal,
    this.latestEpisode,
    this.season,
    this.year,
    required this.genres,
    required this.description,
    required this.status,
    this.playerHost,
    this.episodes = const [],
    this.trailerUrl,
    this.shikimoriUrl,
  });

  factory AnimeTitleDto.fromJson(Map<String, dynamic> json) {
    // 1. Названия (Поддержка API v1 "name: {main, english}" и legacy v3 "names: {ru, en}")
    String ruTitle = '';
    String enTitle = '';

    if (json['name'] is Map<String, dynamic>) {
      final nameMap = json['name'] as Map<String, dynamic>;
      ruTitle = nameMap['main'] as String? ?? '';
      enTitle = nameMap['english'] as String? ?? '';
    } else if (json['names'] is Map<String, dynamic>) {
      final namesMap = json['names'] as Map<String, dynamic>;
      ruTitle = namesMap['ru'] as String? ?? '';
      enTitle = namesMap['en'] as String? ?? '';
    }

    // 2. Идентификатор и алиас
    final id = json['id'] as int? ?? 0;
    final code = (json['alias'] as String?) ?? (json['code'] as String?) ?? '$id';

    // 3. Постеры
    String smallUrl = '';
    String mediumUrl = '';
    String origUrl = '';

    final posterObj = json['poster'];
    if (posterObj is Map<String, dynamic>) {
      final opt = posterObj['optimized'] as Map<String, dynamic>?;
      final optSrc = opt?['src'] as String?;
      final optThumb = opt?['thumbnail'] as String?;
      final rawSrc = posterObj['src'] as String?;
      final rawThumb = posterObj['thumbnail'] as String?;

      // Отдаём приоритет стандартному формату JPG (rawSrc) перед экспериментальным WebP (optSrc),
      // чтобы избежать системной ошибки декодирования Android HWUI 'unimplemented' ImageDecoder
      final bestSrc = rawSrc ?? optSrc;
      final bestThumb = rawThumb ?? rawSrc ?? optThumb ?? optSrc;

      origUrl = _formatPosterUrl(bestSrc);
      mediumUrl = _formatPosterUrl(bestSrc);
      smallUrl = _formatPosterUrl(bestThumb);
    } else if (json['posters'] is Map<String, dynamic>) {
      final posters = json['posters'] as Map<String, dynamic>;
      smallUrl = _formatPosterUrl(posters['small']?['url'] as String?);
      mediumUrl = _formatPosterUrl(posters['medium']?['url'] as String?);
      origUrl = _formatPosterUrl(posters['original']?['url'] as String?);
    }

    final int? shikiId = (json['shikimori'] is Map)
        ? (json['shikimori']['id'] as num?)?.toInt()
        : null;
    final String fallbackPoster = (shikiId != null && shikiId > 0)
        ? 'https://shikimori.io/system/animes/original/$shikiId.jpg'
        : (origUrl.isNotEmpty ? origUrl : mediumUrl);
    if ((origUrl.isEmpty && mediumUrl.isEmpty) && shikiId != null && shikiId > 0) {
      final shikiPoster = 'https://shikimori.io/system/animes/original/$shikiId.jpg';
      origUrl = shikiPoster;
      mediumUrl = shikiPoster;
    }

    // 4. Сезон и год
    int? year = json['year'] as int?;
    String? seasonStr;

    final seasonObj = json['season'];
    if (seasonObj is Map<String, dynamic>) {
      seasonStr = seasonObj['description'] as String? ?? seasonObj['value'] as String?;
      year ??= seasonObj['year'] as int?;
    } else if (seasonObj is String) {
      seasonStr = seasonObj;
    }

    // 5. Количество эпизодов
    int? episodesTotal = json['episodes_total'] as int?;
    if (episodesTotal == null && json['type'] is Map<String, dynamic>) {
      episodesTotal = (json['type'] as Map<String, dynamic>)['episodes'] as int?;
    }

    // 6. Жанры
    final genres = <String>[];
    final rawGenres = json['genres'] as List<dynamic>? ?? [];
    for (final g in rawGenres) {
      if (g is Map<String, dynamic>) {
        final name = g['name'] as String?;
        if (name != null && name.isNotEmpty) genres.add(name);
      } else if (g is String && g.isNotEmpty) {
        genres.add(g);
      }
    }

    // 7. Статус (Онгоинг / Завершен)
    String status = 'Завершен';
    if (json['is_ongoing'] == true || json['is_in_production'] == true) {
      status = 'Онгоинг';
    } else if (json['status'] is Map<String, dynamic>) {
      status = (json['status'] as Map<String, dynamic>)['name'] as String? ??
          (json['status'] as Map<String, dynamic>)['value'] as String? ??
          'Завершен';
    }

    // 8. Описание
    final description = (json['description'] as String? ?? '').trim();

    // 9. Shikimori & Трейлер
    final shikimoriObj = json['shikimori'] as Map<String, dynamic>?;
    final shikimoriUrl = shikimoriObj?['url'] as String?;
    String? trailerUrl;

    if (json['trailer'] is Map<String, dynamic>) {
      final t = json['trailer'] as Map<String, dynamic>;
      final yId = t['youtube_id'] as String?;
      trailerUrl = t['url'] as String? ?? (yId != null ? 'https://www.youtube.com/watch?v=$yId' : null);
    } else if (json['trailer'] is String) {
      trailerUrl = json['trailer'] as String;
    }

    // 10. Эпизоды с опенингами, эндингами и видеопотоками
    final episodes = <EpisodeItem>[];
    int? maxEpisode;

    // Вариант А: API v1 массив "episodes"
    final rawEpisodes = json['episodes'];
    if (rawEpisodes is List) {
      for (final item in rawEpisodes) {
        if (item is Map<String, dynamic>) {
          final ep = _parseV1Episode(item);
          if (ep != null) {
            episodes.add(ep);
            if (trailerUrl == null && ep.youtubeId != null && ep.youtubeId!.isNotEmpty) {
              trailerUrl = 'https://www.youtube.com/watch?v=${ep.youtubeId}';
            }
            final currentMax = maxEpisode;
            if (currentMax == null || ep.episode > currentMax) {
              maxEpisode = ep.episode;
            }
          }
        }
      }
    }

    // Вариант B: API v1 объект "latest_episode" из ленты новинок
    if (episodes.isEmpty && json['latest_episode'] is Map<String, dynamic>) {
      final ep = _parseV1Episode(json['latest_episode'] as Map<String, dynamic>);
      if (ep != null) {
        episodes.add(ep);
        maxEpisode = ep.episode;
        if (trailerUrl == null && ep.youtubeId != null && ep.youtubeId!.isNotEmpty) {
          trailerUrl = 'https://www.youtube.com/watch?v=${ep.youtubeId}';
        }
      }
    }

    // Вариант C: Legacy API v3 объект "player"
    final playerObj = json['player'];
    if (episodes.isEmpty && playerObj is Map<String, dynamic>) {
      final host = playerObj['host'] as String?;
      final rawList = playerObj['list'];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final ep = _parseLegacyEpisode(item, host);
            if (ep != null) {
              episodes.add(ep);
              final currentMax = maxEpisode;
              if (currentMax == null || ep.episode > currentMax) {
                maxEpisode = ep.episode;
              }
            }
          }
        }
      }
    }

    episodes.sort((a, b) => a.episode.compareTo(b.episode));

    return AnimeTitleDto(
      id: id,
      code: code,
      russianTitle: ruTitle,
      englishTitle: enTitle,
      posterSmall: smallUrl,
      posterMedium: mediumUrl,
      posterOriginal: origUrl,
      fallbackPosterUrl: fallbackPoster,
      episodesTotal: episodesTotal,
      latestEpisode: maxEpisode,
      season: seasonStr,
      year: year,
      genres: genres,
      description: description,
      status: status,
      playerHost: null,
      episodes: episodes,
      trailerUrl: trailerUrl,
      shikimoriUrl: shikimoriUrl,
    );
  }

  static EpisodeItem? _parseV1Episode(Map<String, dynamic> item) {
    final ordinal = item['ordinal'] as int? ?? (item['sort_order'] as int?) ?? 1;
    final name = item['name'] as String?;
    final hls1080 = item['hls_1080'] as String?;
    final hls720 = item['hls_720'] as String?;
    final hls480 = item['hls_480'] as String?;
    final youtubeId = item['youtube_id'] as String?;
    final rutubeId = item['rutube_id'] as String?;

    String? previewUrl;
    final prevObj = item['preview'];
    if (prevObj is Map<String, dynamic>) {
      final src = prevObj['src'] as String? ?? prevObj['thumbnail'] as String?;
      previewUrl = _formatPosterUrl(src);
    } else if (prevObj is String) {
      previewUrl = _formatPosterUrl(prevObj);
    }

    TimecodeRange? opening;
    final opObj = item['opening'];
    if (opObj is Map<String, dynamic>) {
      final start = opObj['start'] as int?;
      final stop = opObj['stop'] as int?;
      if (start != null && stop != null && stop > start) {
        opening = TimecodeRange(start: start, stop: stop);
      }
    }

    TimecodeRange? ending;
    final endObj = item['ending'];
    if (endObj is Map<String, dynamic>) {
      final start = endObj['start'] as int?;
      final stop = endObj['stop'] as int?;
      if (start != null && stop != null && stop > start) {
        ending = TimecodeRange(start: start, stop: stop);
      }
    }

    return EpisodeItem(
      episode: ordinal,
      name: name,
      previewUrl: previewUrl,
      sdUrl: _formatStreamUrl(hls480),
      hdUrl: _formatStreamUrl(hls720),
      fhdUrl: _formatStreamUrl(hls1080),
      opening: opening,
      ending: ending,
      youtubeId: youtubeId,
      rutubeId: rutubeId,
    );
  }

  static String? _formatStreamUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim();
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '${ApiConstants.posterBaseUrl}$cleanPath';
  }

  static EpisodeItem? _parseLegacyEpisode(Map<String, dynamic> item, String? host) {
    final epNum = item['episode'] as int? ?? 1;
    final name = item['name'] as String?;
    final hls = item['hls'] as Map<String, dynamic>? ?? {};

    String? buildStreamUrl(String? path) {
      if (path == null || path.isEmpty) return null;
      final trimmed = path.trim();
      if (trimmed.startsWith('//')) return 'https:$trimmed';
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
      if (host != null && host.isNotEmpty) {
        final cleanHost = host.startsWith('http') ? host : 'https://$host';
        final cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
        return '$cleanHost$cleanPath';
      }
      return '${ApiConstants.posterBaseUrl}/${trimmed.replaceFirst(RegExp(r'^/'), '')}';
    }

    return EpisodeItem(
      episode: epNum,
      name: name,
      sdUrl: buildStreamUrl(hls['sd'] as String?),
      hdUrl: buildStreamUrl(hls['hd'] as String?),
      fhdUrl: buildStreamUrl(hls['fhd'] as String?),
    );
  }

  static String _formatPosterUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    String fullUrl;
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      fullUrl = rawUrl;
    } else {
      final cleanPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
      fullUrl = '${ApiConstants.posterBaseUrl}$cleanPath';
    }
    return wrapCorsSafeUrl(fullUrl);
  }

  AnimeTitle toDomain() {
    return AnimeTitle(
      id: id,
      code: code,
      russianTitle: russianTitle,
      englishTitle: englishTitle,
      posterSmall: posterSmall,
      posterMedium: posterMedium,
      posterOriginal: posterOriginal,
      fallbackPosterUrl: fallbackPosterUrl.isNotEmpty ? fallbackPosterUrl : (posterMedium.isNotEmpty ? posterMedium : (posterOriginal.isNotEmpty ? posterOriginal : posterSmall)),
      episodesTotal: episodesTotal,
      latestEpisode: latestEpisode,
      season: season,
      year: year,
      genres: genres,
      description: description,
      status: status,
      playerHost: playerHost,
      episodes: episodes,
      trailerUrl: trailerUrl,
      shikimoriUrl: shikimoriUrl,
    );
  }
}
