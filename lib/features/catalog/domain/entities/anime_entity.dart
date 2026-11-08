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
    var cleanPoster = (posterUrl ?? '').trim();
    if (cleanPoster.isNotEmpty) {
      if (cleanPoster.startsWith('//')) {
        cleanPoster = 'https:$cleanPoster';
      } else if (!cleanPoster.startsWith('http')) {
        cleanPoster = 'https://shikimori.io$cleanPoster';
      }
      cleanPoster = cleanPoster
          .replaceFirst('https://shikimori.me', 'https://shikimori.io')
          .replaceFirst('https://shikimori.one', 'https://shikimori.io')
          .replaceFirst('http://shikimori.me', 'https://shikimori.io')
          .replaceFirst('http://shikimori.one', 'https://shikimori.io');
    }

    return AnimeTitle(
      id: shikimoriId,
      code: titleEn.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      russianTitle: titleRu,
      englishTitle: titleEn,
      posterSmall: cleanPoster,
      posterMedium: cleanPoster,
      posterOriginal: cleanPoster,
      episodesTotal: episodesTotal,
      genres: const [],
      description: '',
      status: status == 'ongoing' ? 'Онгоинг' : 'Завершен',
      shikimoriUrl: 'https://shikimori.one/animes/$shikimoriId',
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
