import 'package:freezed_annotation/freezed_annotation.dart';
import 'anime_entity.dart';

part 'catalog_filter.freezed.dart';

/// Доступные значения сортировки `/api/v1/anime/catalog/references/sorting`.
enum CatalogSorting {
  freshAtDesc('FRESH_AT_DESC'),
  freshAtAsc('FRESH_AT_ASC'),
  ratingDesc('RATING_DESC'),
  ratingAsc('RATING_ASC'),
  yearDesc('YEAR_DESC'),
  yearAsc('YEAR_ASC');

  final String apiValue;
  const CatalogSorting(this.apiValue);
}

/// Типы релизов `/api/v1/anime/catalog/references/types`.
enum ReleaseType {
  tv('TV'),
  ona('ONA'),
  web('WEB'),
  ova('OVA'),
  oad('OAD'),
  movie('MOVIE'),
  dorama('DORAMA'),
  special('SPECIAL');

  final String apiValue;
  const ReleaseType(this.apiValue);

  static ReleaseType? fromApi(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final upper = raw.trim().toUpperCase();
    for (final v in ReleaseType.values) {
      if (v.apiValue == upper) return v;
    }
    return null;
  }
}

/// Возрастные рейтинги `/api/v1/anime/catalog/references/age-ratings`.
enum AgeRating {
  r0Plus('R0_PLUS'),
  r6Plus('R6_PLUS'),
  r12Plus('R12_PLUS'),
  r16Plus('R16_PLUS'),
  r18Plus('R18_PLUS');

  final String apiValue;
  const AgeRating(this.apiValue);
}

/// Статусы публикации `/api/v1/anime/catalog/references/publish-statuses`.
/// В AniLibria v1 допустимы только IS_ONGOING и IS_NOT_ONGOING.
enum PublishStatus {
  isOngoing('IS_ONGOING'),
  isNotOngoing('IS_NOT_ONGOING');

  final String apiValue;
  const PublishStatus(this.apiValue);
}

/// Статусы производства `/api/v1/anime/catalog/references/production-statuses`.
/// В AniLibria v1 допустимы только IS_IN_PRODUCTION и IS_NOT_IN_PRODUCTION.
enum ProductionStatus {
  isInProduction('IS_IN_PRODUCTION'),
  isNotInProduction('IS_NOT_IN_PRODUCTION');

  final String apiValue;
  const ProductionStatus(this.apiValue);
}

@freezed
class CatalogFilter with _$CatalogFilter {
  const factory CatalogFilter({
    @Default(CatalogSorting.freshAtDesc) CatalogSorting sorting,
    @Default(<int>[]) List<int> genres,
    @Default(<ReleaseType>[]) List<ReleaseType> types,
    @Default(<String>[]) List<String> seasons,
    @Default(<AgeRating>[]) List<AgeRating> ageRatings,
    @Default(<PublishStatus>[]) List<PublishStatus> publishStatuses,
    @Default(<ProductionStatus>[]) List<ProductionStatus> productionStatuses,
    int? yearFrom,
    int? yearTo,
    String? search,
  }) = _CatalogFilter;
}

/// Страница каталога, возвращаемая репозиторием для детерминированной пагинации.
class CatalogPage {
  final List<AnimeEntity> items;
  final int page;
  final bool hasMore;

  const CatalogPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });
}

/// Источник данных для вкладки каталога: каталог AniLibria, анонсы Shikimori или расписание AniLibria.
sealed class CatalogTabSource {
  const CatalogTabSource();
}

class AnilibriaCatalogSource extends CatalogTabSource {
  final CatalogFilter filter;
  const AnilibriaCatalogSource(this.filter);
}

class ShikimoriAnnouncedSource extends CatalogTabSource {
  final String season;
  const ShikimoriAnnouncedSource(this.season);
}

class AniLibriaScheduleSource extends CatalogTabSource {
  const AniLibriaScheduleSource();
}

