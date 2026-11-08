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

  const AnimeTitle({
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
    this.trailerUrl,
    this.shikimoriUrl,
  });

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
    String? code,
    String? russianTitle,
    String? englishTitle,
    String? posterSmall,
    String? posterMedium,
    String? posterOriginal,
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
  }) {
    return AnimeTitle(
      id: id ?? this.id,
      code: code ?? this.code,
      russianTitle: russianTitle ?? this.russianTitle,
      englishTitle: englishTitle ?? this.englishTitle,
      posterSmall: posterSmall ?? this.posterSmall,
      posterMedium: posterMedium ?? this.posterMedium,
      posterOriginal: posterOriginal ?? this.posterOriginal,
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

  @override
  List<Object?> get props => [
        id,
        code,
        russianTitle,
        englishTitle,
        posterSmall,
        posterMedium,
        posterOriginal,
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
      ];
}
