import 'package:equatable/equatable.dart';
import 'anime_title.dart';

/// Сущность аниме из Supabase базы данных (таблица anime_catalog)
class AnimeEntity extends Equatable {
  final String id;
  final int shikimoriId;
  final String titleRu;
  final String titleEn;
  final String? posterUrl;
  final String fallbackPosterUrl;
  final String? kind;
  final String status;
  final double score;
  final int episodesTotal;
  final String? externalPlayer;
  final DateTime? updatedAt;
  final int? year;
  final String description;
  final List<String> genres;

  const AnimeEntity({
    required this.id,
    required this.shikimoriId,
    required this.titleRu,
    required this.titleEn,
    this.posterUrl,
    this.fallbackPosterUrl = '',
    this.kind,
    required this.status,
    required this.score,
    required this.episodesTotal,
    this.externalPlayer,
    this.updatedAt,
    this.year,
    this.description = '',
    this.genres = const [],
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
          .replaceFirst('https://desu.shikimori.one', 'https://shikimori.io')
          .replaceFirst('http://desu.shikimori.one', 'https://shikimori.io')
          .replaceFirst('https://shikimori.me', 'https://shikimori.io')
          .replaceFirst('https://shikimori.one', 'https://shikimori.io')
          .replaceFirst('http://shikimori.me', 'https://shikimori.io')
          .replaceFirst('http://shikimori.one', 'https://shikimori.io');
    }

    var cleanFallback = fallbackPosterUrl.trim();
    if (cleanFallback.isNotEmpty) {
      if (cleanFallback.startsWith('//')) {
        cleanFallback = 'https:$cleanFallback';
      } else if (!cleanFallback.startsWith('http')) {
        cleanFallback = 'https://shikimori.io$cleanFallback';
      }
      cleanFallback = cleanFallback
          .replaceFirst('https://desu.shikimori.one', 'https://shikimori.io')
          .replaceFirst('http://desu.shikimori.one', 'https://shikimori.io')
          .replaceFirst('https://shikimori.me', 'https://shikimori.io')
          .replaceFirst('https://shikimori.one', 'https://shikimori.io')
          .replaceFirst('http://shikimori.me', 'https://shikimori.io')
          .replaceFirst('http://shikimori.one', 'https://shikimori.io');
    } else {
      cleanFallback = cleanPoster;
    }

    final releaseId = int.tryParse(id) ?? (shikimoriId > 0 ? shikimoriId : 0);

    return AnimeTitle(
      id: releaseId,
      shikimoriId: shikimoriId > 0 ? shikimoriId : null,
      code: titleEn.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      russianTitle: titleRu,
      englishTitle: titleEn,
      posterSmall: cleanPoster,
      posterMedium: cleanPoster,
      posterOriginal: cleanPoster,
      fallbackPosterUrl: cleanFallback,
      episodesTotal: episodesTotal,
      year: year,
      description: description,
      genres: genres,
      status: (status.toLowerCase().contains('anons') || status.toLowerCase().contains('анонс'))
          ? 'Анонс'
          : (status.toLowerCase().contains('ongoing') || status.toLowerCase().contains('онгоинг') || status.toLowerCase().contains('процесс'))
              ? 'Онгоинг'
              : 'Завершен',
      shikimoriUrl: shikimoriId > 0 ? 'https://shikimori.one/animes/$shikimoriId' : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        shikimoriId,
        titleRu,
        titleEn,
        posterUrl,
        fallbackPosterUrl,
        kind,
        status,
        score,
        episodesTotal,
        externalPlayer,
        updatedAt,
        year,
        description,
        genres,
      ];
}
