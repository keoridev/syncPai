import 'package:equatable/equatable.dart';
import 'anime_title.dart';

/// Сущность аниме из Supabase базы данных (таблица anime_catalog)
class AnimeEntity extends Equatable {
  final String id;
  final int shikimoriId;
  final String titleRu;
  final String titleEn;
  final String? posterUrl;
  final String? kind;
  final String status;
  final double score;
  final int episodesTotal;
  final DateTime? updatedAt;

  const AnimeEntity({
    required this.id,
    required this.shikimoriId,
    required this.titleRu,
    required this.titleEn,
    this.posterUrl,
    this.kind,
    required this.status,
    required this.score,
    required this.episodesTotal,
    this.updatedAt,
  });

  String get displayTitle => titleRu.isNotEmpty ? titleRu : titleEn;

  /// Преобразование в AnimeTitle для совместимости со всеми существующими UI-виджетами
  AnimeTitle toAnimeTitle() {
    return AnimeTitle(
      id: shikimoriId,
      code: titleEn.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      russianTitle: titleRu,
      englishTitle: titleEn,
      posterSmall: posterUrl ?? '',
      posterMedium: posterUrl ?? '',
      posterOriginal: posterUrl ?? '',
      episodesTotal: episodesTotal,
      genres: const [],
      description: '',
      status: status == 'ongoing' ? 'Онгоинг' : 'Завершен',
      shikimoriUrl: 'https://shikimori.me/animes/$shikimoriId',
    );
  }

  @override
  List<Object?> get props => [
        id,
        shikimoriId,
        titleRu,
        titleEn,
        posterUrl,
        kind,
        status,
        score,
        episodesTotal,
        updatedAt,
      ];
}
