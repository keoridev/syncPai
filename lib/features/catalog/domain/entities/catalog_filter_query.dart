import '../../data/services/references_store.dart';
import 'catalog_filter.dart';

/// Единый канонический builder query-параметров и сигнатур для AniLibria v1 `/anime/catalog/releases`.
/// Все списковые фильтры сериализуются как CSV-строки (style: form, explode: false),
/// никогда не передаются как Dio List (чтобы избежать `f[...][]=...`), а пустые поля опускаются.
extension CatalogFilterQuery on CatalogFilter {
  Map<String, dynamic> toQueryParameters({
    required int page,
    required int limit,
  }) {
    final store = ReferencesStore.instance;
    store.assertValid('sorting', sorting.apiValue);

    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      'f[sorting]': sorting.apiValue,
    };

    if (genres.isNotEmpty) {
      final sorted = genres.toSet().toList()..sort();
      params['f[genres]'] = sorted.join(',');
    }

    if (types.isNotEmpty) {
      final sorted = types.map((e) => e.apiValue).toSet().toList()..sort();
      for (final v in sorted) {
        store.assertValid('types', v);
      }
      params['f[types]'] = sorted.join(',');
    }

    final cleanSeasons = seasons
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (cleanSeasons.isNotEmpty) {
      for (final v in cleanSeasons) {
        store.assertValid('seasons', v);
      }
      params['f[seasons]'] = cleanSeasons.join(',');
    }

    if (ageRatings.isNotEmpty) {
      final sorted = ageRatings.map((e) => e.apiValue).toSet().toList()..sort();
      for (final v in sorted) {
        store.assertValid('age_ratings', v);
      }
      params['f[age_ratings]'] = sorted.join(',');
    }

    if (publishStatuses.isNotEmpty) {
      final sorted =
          publishStatuses.map((e) => e.apiValue).toSet().toList()..sort();
      for (final v in sorted) {
        store.assertValid('publish_statuses', v);
      }
      params['f[publish_statuses]'] = sorted.join(',');
    }

    if (productionStatuses.isNotEmpty) {
      final sorted =
          productionStatuses.map((e) => e.apiValue).toSet().toList()..sort();
      for (final v in sorted) {
        store.assertValid('production_statuses', v);
      }
      params['f[production_statuses]'] = sorted.join(',');
    }

    if (yearFrom != null) {
      params['f[years][from_year]'] = yearFrom;
    }
    if (yearTo != null) {
      params['f[years][to_year]'] = yearTo;
    }

    final cleanSearch = search?.trim() ?? '';
    if (cleanSearch.isNotEmpty) {
      params['f[search]'] = cleanSearch;
    }

    return params;
  }

  /// Детерминированный канонический ключ фильтра для кэша, дедупликации и защиты от гонок.
  String get signature {
    final sortedGenres = genres.toSet().toList()..sort();
    final sortedTypes = types.map((e) => e.apiValue).toSet().toList()..sort();
    final sortedSeasons = seasons
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final sortedAges =
        ageRatings.map((e) => e.apiValue).toSet().toList()..sort();
    final sortedPub =
        publishStatuses.map((e) => e.apiValue).toSet().toList()..sort();
    final sortedProd =
        productionStatuses.map((e) => e.apiValue).toSet().toList()..sort();
    final yr = (yearFrom == null && yearTo == null)
        ? ''
        : '${yearFrom ?? ''}-${yearTo ?? ''}';
    final q = (search ?? '').trim();

    return 'sort=${sorting.apiValue}'
        '|gen=${sortedGenres.join(',')}'
        '|type=${sortedTypes.join(',')}'
        '|sea=${sortedSeasons.join(',')}'
        '|age=${sortedAges.join(',')}'
        '|pub=${sortedPub.join(',')}'
        '|prod=${sortedProd.join(',')}'
        '|yr=$yr'
        '|q=$q';
  }
}

extension CatalogTabSourceSignature on CatalogTabSource {
  /// Каноническая сигнатура с типом источника (`catalog` | `announced` | `schedule`),
  /// исключающая коллизии кэша между вкладками.
  String get signature {
    return switch (this) {
      AnilibriaCatalogSource(:final filter) => 'catalog|${filter.signature}',
      ShikimoriAnnouncedSource(:final season) => 'announced|season=$season',
      AniLibriaScheduleSource() => 'schedule|week',
    };
  }
}

