import 'package:flutter/foundation.dart';
import '../datasources/catalog_references_datasource.dart';

/// Локальный и синхронизируемый справочник валидных значений фильтров AniLibria v1.
/// Используется runtime-guard'ом в `CatalogFilterQuery` перед отправкой запроса.
class ReferencesStore {
  static final ReferencesStore instance = ReferencesStore._();
  ReferencesStore._();

  /// Подтверждённые значения из OpenAPI AniLibria v1 (используются как fallback при офлайне).
  static const Map<String, Set<String>> fallbackValues = {
    'publish_statuses': {'IS_ONGOING', 'IS_NOT_ONGOING'},
    'production_statuses': {'IS_IN_PRODUCTION', 'IS_NOT_IN_PRODUCTION'},
    'types': {'TV', 'ONA', 'WEB', 'OVA', 'OAD', 'MOVIE', 'DORAMA', 'SPECIAL'},
    'seasons': {'winter', 'spring', 'summer', 'autumn'},
    'age_ratings': {'R0_PLUS', 'R6_PLUS', 'R12_PLUS', 'R16_PLUS', 'R18_PLUS'},
    'sorting': {
      'FRESH_AT_DESC',
      'FRESH_AT_ASC',
      'RATING_DESC',
      'RATING_ASC',
      'YEAR_DESC',
      'YEAR_ASC',
    },
  };

  final Map<String, Set<String>> _liveValues = {};
  bool _synced = false;

  @visibleForTesting
  void resetForTest() {
    _liveValues.clear();
    _synced = false;
  }

  @visibleForTesting
  void setValuesForTest(String field, Set<String> values) {
    _liveValues[field] = Set<String>.from(values);
  }

  /// Проверяет допустимость [value] для поля [field] против live-справочника или fallback.
  bool validate(String field, String value) {
    final allowed = _liveValues[field];
    if (allowed != null && allowed.isNotEmpty) {
      return allowed.contains(value);
    }
    final fb = fallbackValues[field];
    if (fb == null) return true;
    return fb.contains(value);
  }

  /// Бросает [StateError], если значение не проходит проверку против справочника references.
  void assertValid(String field, String value) {
    if (!validate(field, value)) {
      throw StateError(
        'Invalid AniLibria v1 catalog filter value "$value" for field "$field".',
      );
    }
  }

  /// Синхронизирует все справочники из `/api/v1/anime/catalog/references/*`.
  Future<void> syncAll(CatalogReferencesDataSource dataSource) async {
    if (_synced) return;
    const slugToField = <String, String>{
      'publish-statuses': 'publish_statuses',
      'production-statuses': 'production_statuses',
      'types': 'types',
      'seasons': 'seasons',
      'age-ratings': 'age_ratings',
      'sorting': 'sorting',
    };

    for (final entry in slugToField.entries) {
      try {
        final values = await dataSource.fetchReferenceValues(entry.key);
        if (values.isNotEmpty) {
          _liveValues[entry.value] = values;
        }
      } catch (e) {
        debugPrint(
          '[ReferencesStore] Fallback to hardcoded ${entry.value} (sync error: $e)',
        );
      }
    }
    _synced = true;
  }
}

