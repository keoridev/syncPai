import 'package:equatable/equatable.dart';

/// Информация об адаптированной манге / манхве из Shikimori (/related, relation == 'Adaptation').
class AdaptedMangaInfo extends Equatable {
  final int shikimoriMangaId;
  final String russianTitle;
  final String englishTitle;
  final String? japaneseTitle;
  final int? malId;
  final String coverUrl;
  final double? score;
  final int? chaptersCount;
  final String kind;

  const AdaptedMangaInfo({
    required this.shikimoriMangaId,
    required this.russianTitle,
    required this.englishTitle,
    this.japaneseTitle,
    this.malId,
    required this.coverUrl,
    this.score,
    this.chaptersCount,
    this.kind = 'manga',
  });

  String get displayTitle =>
      russianTitle.isNotEmpty ? russianTitle : englishTitle;

  bool get isManhwaOrWebtoon {
    final k = kind.toLowerCase();
    return k.contains('manhwa') || k.contains('manhua') || k.contains('web');
  }

  @override
  List<Object?> get props => [
        shikimoriMangaId,
        russianTitle,
        englishTitle,
        japaneseTitle,
        malId,
        coverUrl,
        score,
        chaptersCount,
        kind,
      ];
}

/// Тайтл манги / манхвы в каталоге MangaDex.
class MangaDexManga extends Equatable {
  final String id;
  final String title;
  final String coverUrl;
  final String? originalLanguage;
  final String? malId;
  final List<String> availableTranslatedLanguages;

  const MangaDexManga({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.originalLanguage,
    this.malId,
    this.availableTranslatedLanguages = const [],
  });

  bool get isManhwaOrWebtoon =>
      originalLanguage == 'ko' || originalLanguage == 'zh';

  bool get hasRussianTranslation =>
      availableTranslatedLanguages.any((l) => l.toLowerCase() == 'ru');

  @override
  List<Object?> get props => [
        id,
        title,
        coverUrl,
        originalLanguage,
        malId,
        availableTranslatedLanguages,
      ];
}

/// Глава манги / манхвы из MangaDex feed.
class MangaDexChapter extends Equatable {
  final String id;
  final double? chapterNumber;
  final String chapterLabel;
  final String title;
  final String translatedLanguage;
  final int pagesCount;

  const MangaDexChapter({
    required this.id,
    this.chapterNumber,
    required this.chapterLabel,
    required this.title,
    required this.translatedLanguage,
    this.pagesCount = 0,
  });

  String get displayTitle {
    final trimmedLabel = chapterLabel.trim();
    final base = trimmedLabel.isEmpty
        ? 'Глава'
        : (trimmedLabel.startsWith('Глава') || trimmedLabel.startsWith('Спешл')
            ? trimmedLabel
            : 'Глава $trimmedLabel');
    if (title.trim().isNotEmpty) {
      return '$base — ${title.trim()}';
    }
    return base;
  }

  @override
  List<Object?> get props => [
        id,
        chapterNumber,
        chapterLabel,
        title,
        translatedLanguage,
        pagesCount,
      ];
}

/// Связка «Аниме -> Манга / Манхва» с точной главой продолжения после финала сезона.
class AnimeMangaBridge extends Equatable {
  final int anilibriaId;
  final int? shikimoriId;
  final String mangaDexId;
  final String mangaTitle;
  final String coverUrl;
  final int? mangaUpdatesEndChapter;
  final bool isManhwa;
  final int? chaptersCount;
  final double? score;

  const AnimeMangaBridge({
    required this.anilibriaId,
    this.shikimoriId,
    required this.mangaDexId,
    required this.mangaTitle,
    required this.coverUrl,
    this.mangaUpdatesEndChapter,
    this.isManhwa = false,
    this.chaptersCount,
    this.score,
  });

  int? get continueFromChapter =>
      mangaUpdatesEndChapter != null ? mangaUpdatesEndChapter! + 1 : null;

  @override
  List<Object?> get props => [
        anilibriaId,
        shikimoriId,
        mangaDexId,
        mangaTitle,
        coverUrl,
        mangaUpdatesEndChapter,
        isManhwa,
        chaptersCount,
        score,
      ];
}

