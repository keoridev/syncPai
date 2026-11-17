import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/anime_review.dart';
import '../../domain/entities/anime_video_item.dart';
import '../utils/review_text_sanitizer.dart';

class JikanAnimeScoreAndReviews {
  final double? malScore;
  final int malVotesCount;
  final List<AnimeReview> reviews;

  const JikanAnimeScoreAndReviews({
    this.malScore,
    this.malVotesCount = 0,
    this.reviews = const [],
  });
}

abstract class JikanRemoteDataSource {
  Future<JikanAnimeScoreAndReviews> getReviewsAndScore(int malId);
  Future<List<AnimeVideoItem>> getVideos(int malId);
}

class JikanRemoteDataSourceImpl implements JikanRemoteDataSource {
  final Dio _dio;

  static const String _baseUrl = 'https://api.jikan.moe/v4';

  // Ограничение частоты запросов к Jikan API: максимум 3 запроса в секунду (~350ms между запросами)
  static DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  // Сессионный негативный кэш и backoff при таймаутах/429, чтобы не спамить повторными запросами
  static final Set<int> _failedMalIds = {};
  static DateTime? _globalBackoffUntil;

  static bool _shouldSkip(int malId) {
    if (_failedMalIds.contains(malId)) return true;
    final until = _globalBackoffUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  static void _recordFailure(int malId, Object error) {
    _failedMalIds.add(malId);
    if (error is DioException &&
        (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.response?.statusCode == 429)) {
      _globalBackoffUntil = DateTime.now().add(const Duration(minutes: 2));
      return; // Тихий выход без шумных логов таймаута
    }
    debugPrint('[Jikan API] request failed ($malId): $error');
  }

  JikanRemoteDataSourceImpl({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 2),
                receiveTimeout: const Duration(seconds: 2),
                headers: {
                  if (!kIsWeb) 'User-Agent': 'SyncPai/1.0.0 (Anime Sync App; contact@syncpai.app)',
                  'Accept': 'application/json',
                },
              ),
            );

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequestTime).inMilliseconds;
    if (elapsed < 350) {
      await Future.delayed(Duration(milliseconds: 350 - elapsed));
    }
    _lastRequestTime = DateTime.now();
  }

  @override
  Future<JikanAnimeScoreAndReviews> getReviewsAndScore(int malId) async {
    if (malId <= 0 || _shouldSkip(malId)) {
      return const JikanAnimeScoreAndReviews();
    }

    double? malScore;
    int malVotesCount = 0;
    final reviews = <AnimeReview>[];

    try {
      await _throttle();

      // 1. Запрос отзывов тайтла
      final response = await _dio.get('/anime/$malId/reviews');
      if (response.statusCode == 200 &&
          response.data != null &&
          response.data.toString().trim().isNotEmpty) {
        dynamic rawData = response.data;
        if (rawData is String) {
          try {
            rawData = jsonDecode(rawData);
          } catch (_) {
            rawData = null;
          }
        }
        if (rawData is Map) {
          final data = rawData['data'] as List?;
          if (data != null) {
            for (final item in data) {
              if (item is! Map) continue;

              final rawText = item['review'] as String? ?? '';
              final sanitized = ReviewTextSanitizer.sanitize(rawText);
              if (sanitized.text.length < 15) continue;

              final user = item['user'] as Map?;
              final username = user?['username'] as String? ?? 'MAL User';
              final images = user?['images'] as Map?;
              final jpg = images?['jpg'] as Map?;
              final avatarUrl = jpg?['image_url'] as String?;

              final rawScore = item['score'];
              final double? score = rawScore != null ? (rawScore as num).toDouble() : null;

              final isSpoiler = (item['is_spoiler'] as bool?) ?? sanitized.containsSpoiler;
              final dateStr = item['date'] as String?;
              final createdAt = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();

              final url = item['url'] as String?;
              final reactions = item['reactions'] as Map?;
              final overallLikes = (reactions?['overall'] as num?)?.toInt() ?? 0;

              reviews.add(
                AnimeReview(
                  id: 'mal_${item['mal_id'] ?? DateTime.now().millisecondsSinceEpoch}',
                  source: ReviewSource.mal,
                  authorName: username,
                  authorAvatarUrl: avatarUrl,
                  score: score,
                  sentiment: ReviewSentiment.fromScore(score),
                  content: sanitized.text,
                  containsSpoiler: isSpoiler,
                  createdAt: createdAt,
                  originalUrl: url,
                  likes: overallLikes,
                ),
              );
            }
          }
        }
      }
    } on DioException catch (e) {
      _recordFailure(malId, e);
    } catch (e) {
      _recordFailure(malId, e);
    }

    if (_shouldSkip(malId)) {
      return JikanAnimeScoreAndReviews(
        malScore: malScore,
        malVotesCount: malVotesCount,
        reviews: reviews,
      );
    }

    // 2. Получение общего рейтинга и количества голосов на MyAnimeList
    try {
      await _throttle();
      final statsResponse = await _dio.get('/anime/$malId');
      if (statsResponse.statusCode == 200 &&
          statsResponse.data != null &&
          statsResponse.data.toString().trim().isNotEmpty) {
        dynamic rawStats = statsResponse.data;
        if (rawStats is String) {
          try {
            rawStats = jsonDecode(rawStats);
          } catch (_) {
            rawStats = null;
          }
        }
        if (rawStats is Map) {
          final animeData = rawStats['data'] as Map?;
          if (animeData != null) {
            final s = animeData['score'];
            if (s != null) {
              malScore = (s as num).toDouble();
            }
            final scoredBy = animeData['scored_by'];
            if (scoredBy != null) {
              malVotesCount = (scoredBy as num).toInt();
            }
          }
        }
      }
    } catch (_) {
      // Игнорируем ошибку при недоступности отдельного эндпоинта
    }

    return JikanAnimeScoreAndReviews(
      malScore: malScore,
      malVotesCount: malVotesCount,
      reviews: reviews,
    );
  }

  @override
  Future<List<AnimeVideoItem>> getVideos(int malId) async {
    if (malId <= 0 || _shouldSkip(malId)) return const [];
    final list = <AnimeVideoItem>[];
    try {
      await _throttle();
      final res = await _dio.get('/anime/$malId/videos');
      if (res.statusCode == 200 && res.data != null) {
        dynamic rawData = res.data;
        if (rawData is String) {
          try {
            rawData = jsonDecode(rawData);
          } catch (_) {
            rawData = null;
          }
        }
        if (rawData is Map) {
          final data = rawData['data'] as Map?;
          if (data != null) {
            final promo = data['promo'] as List?;
            if (promo != null) {
              for (final p in promo) {
                if (p is! Map) continue;
                final title = p['title'] as String? ?? 'Трейлер';
                final trailer = p['trailer'] as Map?;
                final url = trailer?['url'] as String? ?? '';
                if (url.isEmpty) continue;
                final images = trailer?['images'] as Map?;
                final imgUrl = images?['maximum_image_url'] as String? ??
                    images?['large_image_url'] as String? ??
                    images?['medium_image_url'] as String? ??
                    images?['image_url'] as String? ??
                    '';
                list.add(
                  AnimeVideoItem(
                    id: 'jikan_promo_${list.length}',
                    title: title,
                    url: url,
                    imageUrl: imgUrl,
                    playerUrl: trailer?['embed_url'] as String?,
                    kind: 'pv',
                    hosting: 'youtube',
                    source: 'YouTube',
                  ),
                );
              }
            }
            final musicVideos = data['music_videos'] as List?;
            if (musicVideos != null) {
              for (final m in musicVideos) {
                if (m is! Map) continue;
                final title = m['title'] as String? ?? 'Music Video';
                final video = m['video'] as Map?;
                final url = video?['url'] as String? ?? '';
                if (url.isEmpty) continue;
                final images = video?['images'] as Map?;
                final imgUrl = images?['maximum_image_url'] as String? ??
                    images?['large_image_url'] as String? ??
                    images?['medium_image_url'] as String? ??
                    images?['image_url'] as String? ??
                    '';
                final isOp = title.toLowerCase().contains('opening') || title.toLowerCase().contains('op');
                list.add(
                  AnimeVideoItem(
                    id: 'jikan_mv_${list.length}',
                    title: title,
                    url: url,
                    imageUrl: imgUrl,
                    playerUrl: video?['embed_url'] as String?,
                    kind: isOp ? 'op' : 'ed',
                    hosting: 'youtube',
                    source: 'YouTube',
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      _recordFailure(malId, e);
    }
    return list;
  }
}
