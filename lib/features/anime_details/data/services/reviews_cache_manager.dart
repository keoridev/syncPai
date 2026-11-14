import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/anime_rating_aggregate.dart';
import '../../domain/entities/anime_review.dart';

/// Пакет кэшированных данных отзывов и агрегированного рейтинга
class CachedReviewsBundle {
  final List<AnimeReview> reviews;
  final AnimeRatingAggregate aggregate;
  final DateTime cachedAt;

  const CachedReviewsBundle({
    required this.reviews,
    required this.aggregate,
    required this.cachedAt,
  });

  bool get isExpired {
    // 6 часов TTL согласно ТЗ
    const ttl = Duration(hours: 6);
    return DateTime.now().difference(cachedAt) > ttl;
  }

  Map<String, dynamic> toJson() {
    return {
      'cached_at': cachedAt.toIso8601String(),
      'reviews': reviews.map((r) => r.toJson()).toList(),
      'aggregate': aggregate.toJson(),
    };
  }

  factory CachedReviewsBundle.fromJson(Map<String, dynamic> json) {
    final reviewsList = (json['reviews'] as List<dynamic>?)
            ?.map((e) => AnimeReview.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final aggregateData = json['aggregate'] != null
        ? AnimeRatingAggregate.fromJson(json['aggregate'] as Map<String, dynamic>)
        : const AnimeRatingAggregate();
    final cachedAt = json['cached_at'] != null
        ? DateTime.tryParse('${json['cached_at']}') ?? DateTime.now()
        : DateTime.now();

    return CachedReviewsBundle(
      reviews: reviewsList,
      aggregate: aggregateData,
      cachedAt: cachedAt,
    );
  }
}

/// Двухуровневый менеджер кэширования отзывов (In-Memory LRU + SharedPreferences 6h TTL)
class ReviewsCacheManager {
  static const int _maxMemoryEntries = 50;
  static const String _prefPrefix = 'reviews_cache_';
  static const Duration ttl = Duration(hours: 6);

  final SharedPreferences? _prefs;

  // LRU кэш в оперативной памяти
  final LinkedHashMap<String, CachedReviewsBundle> _memoryCache =
      LinkedHashMap<String, CachedReviewsBundle>();

  ReviewsCacheManager([this._prefs]);

  /// Получить данные из кэша (память -> постоянное хранилище)
  CachedReviewsBundle? get(String animeKey) {
    if (animeKey.isEmpty) return null;

    // 1. Проверяем память
    final memoryItem = _memoryCache[animeKey];
    if (memoryItem != null) {
      if (!memoryItem.isExpired) {
        // Перемещаем в конец как недавно использованный (LRU)
        _memoryCache.remove(animeKey);
        _memoryCache[animeKey] = memoryItem;
        return memoryItem;
      } else {
        _memoryCache.remove(animeKey);
      }
    }

    // 2. Проверяем SharedPreferences
    final prefs = _prefs;
    if (prefs != null) {
      try {
        final raw = prefs.getString('$_prefPrefix$animeKey');
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final bundle = CachedReviewsBundle.fromJson(decoded);
          if (!bundle.isExpired) {
            _putMemory(animeKey, bundle);
            return bundle;
          } else {
            // Кэш устарел, удаляем
            prefs.remove('$_prefPrefix$animeKey');
          }
        }
      } catch (e) {
        debugPrint('[ReviewsCache] Read error for $animeKey: $e');
      }
    }

    return null;
  }

  /// Сохранить пакет отзывов в двухуровневый кэш
  Future<void> put(String animeKey, CachedReviewsBundle bundle) async {
    if (animeKey.isEmpty) return;

    _putMemory(animeKey, bundle);

    final prefs = _prefs;
    if (prefs != null) {
      try {
        final jsonStr = jsonEncode(bundle.toJson());
        await prefs.setString('$_prefPrefix$animeKey', jsonStr);
      } catch (e) {
        debugPrint('[ReviewsCache] Write error for $animeKey: $e');
      }
    }
  }

  /// Сбросить кэш конкретного тайтла (при публикации нового отзыва)
  Future<void> invalidate(String animeKey) async {
    _memoryCache.remove(animeKey);
    final prefs = _prefs;
    if (prefs != null) {
      try {
        await prefs.remove('$_prefPrefix$animeKey');
      } catch (_) {}
    }
  }

  void _putMemory(String key, CachedReviewsBundle bundle) {
    if (_memoryCache.length >= _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = bundle;
  }
}

