import 'package:equatable/equatable.dart';
import '../../../catalog/domain/entities/anime_title.dart';

/// Модель связанного релиза аниме (сезоны, фильмы, приквелы, сиквелы).
class RelatedAnimeRelease extends Equatable {
  final String id;
  final String title;
  final String? originalTitle;
  final String? year;
  final double? rating;
  final String kind; // 'Сериал', 'Фильм', 'OVA', 'Спешл', 'ONA'
  final String posterUrl;
  final String relation; // 'Продолжение', 'Предыстория', 'Основная история'
  final bool isCurrent;
  final AnimeTitle? resolvedTitle;

  const RelatedAnimeRelease({
    required this.id,
    required this.title,
    this.originalTitle,
    this.year,
    this.rating,
    this.kind = 'Сериал',
    required this.posterUrl,
    required this.relation,
    this.isCurrent = false,
    this.resolvedTitle,
  });

  @override
  List<Object?> get props => [
        id,
        title,
        originalTitle,
        year,
        rating,
        kind,
        posterUrl,
        relation,
        isCurrent,
      ];
}

