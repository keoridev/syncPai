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
  });

  /// Отображаемое название (русское или fallback на английское)
  String get displayTitle => russianTitle.isNotEmpty ? russianTitle : englishTitle;

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
      ];
}

