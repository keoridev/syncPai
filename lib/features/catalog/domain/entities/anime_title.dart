import 'package:equatable/equatable.dart';
import 'episode_item.dart';

class AnimeTitle extends Equatable {
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
  final int? shikimoriId;
  final double? score;
  final String? kind;
  final bool isAnnounced;

  const AnimeTitle({
    required this.id,
    this.shikimoriId,
    this.score,
    this.kind,
    this.isAnnounced = false,
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

  static bool isMissingPosterUrl(String? url) {
    if (url == null || url.trim().isEmpty) return true;
    final lower = url.toLowerCase();
    return lower.contains('missing_original') ||
        lower.contains('missing_preview') ||
        lower.contains('missing_x') ||
        lower.contains('missing_') ||
        lower.contains('no_image') ||
        lower.contains('noimage') ||
        lower.contains('/assets/globals/');
  }

  /// Основной постер (без 404/placeholder URL)
  String get posterUrl {
    if (!isMissingPosterUrl(posterMedium)) return posterMedium;
    if (!isMissingPosterUrl(posterOriginal)) return posterOriginal;
    if (!isMissingPosterUrl(posterSmall)) return posterSmall;
    return '';
  }

  /// Резервный постер при 404 японского постера Shikimori
  String get effectiveFallbackPoster {
    if (!isMissingPosterUrl(fallbackPosterUrl)) return fallbackPosterUrl;
    return posterUrl;
  }

  /// Отображаемое название (русское или fallback на английское)
  String get displayTitle => russianTitle.isNotEmpty ? russianTitle : englishTitle;

  /// Опенинг первого доступного эпизода
  TimecodeRange? get primaryOpening => episodes.isNotEmpty ? episodes.first.opening : null;

  /// Эндинг первого доступного эпизода
  TimecodeRange? get primaryEnding => episodes.isNotEmpty ? episodes.first.ending : null;

  /// Краткая строка серии: "12 эп." или "Выпуск завершен"
  String get episodesBadgeText {
    if (latestEpisode != null && latestEpisode! > 0) {
      if (episodesTotal != null && episodesTotal! > 0) {
        return '$latestEpisode / $episodesTotal эп.';
      }
      return '$latestEpisode эп.';
    }
    if (episodesTotal != null && episodesTotal! > 0) {
      return '$episodesTotal эп.';
    }
    return status;
  }

  AnimeTitle copyWith({
    int? id,
    int? shikimoriId,
    double? score,
    String? kind,
    String? code,
    String? russianTitle,
    String? englishTitle,
    String? posterSmall,
    String? posterMedium,
    String? posterOriginal,
    String? fallbackPosterUrl,
    int? episodesTotal,
    int? latestEpisode,
    String? season,
    int? year,
    List<String>? genres,
    String? description,
    String? status,
    String? playerHost,
    List<EpisodeItem>? episodes,
    String? trailerUrl,
    String? shikimoriUrl,
    bool? isAnnounced,
  }) {
    return AnimeTitle(
      id: id ?? this.id,
      shikimoriId: shikimoriId ?? this.shikimoriId,
      score: score ?? this.score,
      kind: kind ?? this.kind,
      isAnnounced: isAnnounced ?? this.isAnnounced,
      code: code ?? this.code,
      russianTitle: russianTitle ?? this.russianTitle,
      englishTitle: englishTitle ?? this.englishTitle,
      posterSmall: posterSmall ?? this.posterSmall,
      posterMedium: posterMedium ?? this.posterMedium,
      posterOriginal: posterOriginal ?? this.posterOriginal,
      fallbackPosterUrl: fallbackPosterUrl ?? this.fallbackPosterUrl,
      episodesTotal: episodesTotal ?? this.episodesTotal,
      latestEpisode: latestEpisode ?? this.latestEpisode,
      season: season ?? this.season,
      year: year ?? this.year,
      genres: genres ?? this.genres,
      description: description ?? this.description,
      status: status ?? this.status,
      playerHost: playerHost ?? this.playerHost,
      episodes: episodes ?? this.episodes,
      trailerUrl: trailerUrl ?? this.trailerUrl,
      shikimoriUrl: shikimoriUrl ?? this.shikimoriUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shikimoriId': shikimoriId,
        'score': score,
        'kind': kind,
        'code': code,
        'russianTitle': russianTitle,
        'englishTitle': englishTitle,
        'posterSmall': posterSmall,
        'posterMedium': posterMedium,
        'posterOriginal': posterOriginal,
        'fallbackPosterUrl': fallbackPosterUrl,
        'episodesTotal': episodesTotal,
        'latestEpisode': latestEpisode,
        'season': season,
        'year': year,
        'genres': genres,
        'description': description,
        'status': status,
        'playerHost': playerHost,
        'episodes': episodes.map((e) => e.toJson()).toList(),
        'trailerUrl': trailerUrl,
        'shikimoriUrl': shikimoriUrl,
        'isAnnounced': isAnnounced,
      };

  factory AnimeTitle.fromJson(Map<String, dynamic> json) => AnimeTitle(
        id: json['id'] as int? ?? 0,
        shikimoriId: json['shikimoriId'] as int?,
        score: (json['score'] as num?)?.toDouble(),
        kind: json['kind'] as String?,
        code: json['code'] as String? ?? '',
        russianTitle: json['russianTitle'] as String? ?? '',
        englishTitle: json['englishTitle'] as String? ?? '',
        posterSmall: json['posterSmall'] as String? ?? '',
        posterMedium: json['posterMedium'] as String? ?? '',
        posterOriginal: json['posterOriginal'] as String? ?? '',
        fallbackPosterUrl: json['fallbackPosterUrl'] as String? ?? '',
        episodesTotal: json['episodesTotal'] as int?,
        latestEpisode: json['latestEpisode'] as int?,
        season: json['season'] as String?,
        year: json['year'] as int?,
        genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        description: json['description'] as String? ?? '',
        status: json['status'] as String? ?? '',
        playerHost: json['playerHost'] as String?,
        episodes: (json['episodes'] as List?)
                ?.whereType<Map>()
                .map((e) => EpisodeItem.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        trailerUrl: json['trailerUrl'] as String?,
        shikimoriUrl: json['shikimoriUrl'] as String?,
        isAnnounced: json['isAnnounced'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [
        id,
        shikimoriId,
        code,
        russianTitle,
        englishTitle,
        posterSmall,
        posterMedium,
        posterOriginal,
        fallbackPosterUrl,
        episodesTotal,
        latestEpisode,
        season,
        year,
        genres,
        description,
        status,
        playerHost,
        episodes,
        trailerUrl,
        shikimoriUrl,
        score,
        kind,
        isAnnounced,
      ];
}
