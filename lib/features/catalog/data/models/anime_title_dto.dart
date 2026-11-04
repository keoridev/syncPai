import '../../../../core/network/api_constants.dart';
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
  final int? episodesTotal;
  final int? latestEpisode;
  final String? season;
  final int? year;
  final List<String> genres;
  final String description;
  final String status;
  final String? playerHost;
  final List<EpisodeItem> episodes;

  const AnimeTitleDto({
    required this.id,
    required this.code,
    required this.russianTitle,
    required this.englishTitle,
    required this.posterSmall,
    required this.posterMedium,
    required this.posterOriginal,
    this.episodesTotal,
    this.latestEpisode,
    this.season,
    this.year,
    required this.genres,
    required this.description,
    required this.status,
    this.playerHost,
    this.episodes = const [],
  });

  factory AnimeTitleDto.fromJson(Map<String, dynamic> json) {
    // Названия
    final names = json['names'] as Map<String, dynamic>? ?? {};
    final ruTitle = names['ru'] as String? ?? '';
    final enTitle = names['en'] as String? ?? '';

    // Постеры
    final posters = json['posters'] as Map<String, dynamic>? ?? {};
    final smallUrl = _formatPosterUrl(posters['small']?['url'] as String?);
    final mediumUrl = _formatPosterUrl(posters['medium']?['url'] as String?);
    final origUrl = _formatPosterUrl(posters['original']?['url'] as String?);

    // Серии и тип
    final type = json['type'] as Map<String, dynamic>? ?? {};
    final episodesTotal = type['episodes'] as int?;

    // Сезон / год
    final seasonObj = json['season'] as Map<String, dynamic>?;
    final seasonStr = seasonObj?['string'] as String?;
    final year = seasonObj?['year'] as int?;

    // Жанры
    final rawGenres = json['genres'] as List<dynamic>? ?? [];
    final genres = rawGenres.map((g) => g.toString()).toList();

    // Статус
    final statusObj = json['status'] as Map<String, dynamic>?;
    final status = statusObj?['string'] as String? ?? 'Неизвестно';

    // Описание
    final description = (json['description'] as String? ?? '').trim();

    // Плеер
    final player = json['player'] as Map<String, dynamic>? ?? {};
    final host = player['host'] as String?;
    final episodes = <EpisodeItem>[];
    int? maxEpisode;

    final rawList = player['list'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          final ep = _parseEpisode(item, host);
          if (ep != null) {
            episodes.add(ep);
            final currentMax = maxEpisode;
            if (currentMax == null || ep.episode > currentMax) {
              maxEpisode = ep.episode;
            }
          }
        }
      }
    } else if (rawList is Map<String, dynamic>) {
      rawList.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final ep = _parseEpisode(value, host);
          if (ep != null) {
            episodes.add(ep);
            final currentMax = maxEpisode;
            if (currentMax == null || ep.episode > currentMax) {
              maxEpisode = ep.episode;
            }
          }
        }
      });
    }

    episodes.sort((a, b) => a.episode.compareTo(b.episode));

    return AnimeTitleDto(
      id: json['id'] as int? ?? 0,
      code: json['code'] as String? ?? '',
      russianTitle: ruTitle,
      englishTitle: enTitle,
      posterSmall: smallUrl,
      posterMedium: mediumUrl,
      posterOriginal: origUrl,
      episodesTotal: episodesTotal,
      latestEpisode: maxEpisode,
      season: seasonStr,
      year: year,
      genres: genres,
      description: description,
      status: status,
      playerHost: host,
      episodes: episodes,
    );
  }

  static EpisodeItem? _parseEpisode(Map<String, dynamic> item, String? host) {
    final epNum = item['episode'] as int? ?? (item['ordinal'] as int?) ?? 1;
    final name = item['name'] as String?;
    final hls = item['hls'] as Map<String, dynamic>? ?? {};

    String? buildStreamUrl(String? path) {
      if (path == null || path.isEmpty) return null;
      if (path.startsWith('http://') || path.startsWith('https://')) return path;
      if (host != null && host.isNotEmpty) {
        final cleanHost = host.startsWith('http') ? host : 'https://$host';
        final cleanPath = path.startsWith('/') ? path : '/$path';
        return '$cleanHost$cleanPath';
      }
      return path;
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
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    final cleanPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
    return '${ApiConstants.posterBaseUrl}$cleanPath';
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
      episodesTotal: episodesTotal,
      latestEpisode: latestEpisode,
      season: season,
      year: year,
      genres: genres,
      description: description,
      status: status,
      playerHost: playerHost,
      episodes: episodes,
    );
  }
}
