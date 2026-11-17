import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../catalog/domain/entities/anime_title.dart';
import '../../domain/entities/anime_rating_aggregate.dart';
import '../../domain/entities/anime_review.dart';
import '../../domain/entities/anime_video_item.dart';
import '../../domain/entities/related_anime_release.dart';
import '../../domain/entities/score_distribution_item.dart';
import '../../domain/entities/user_lists_stats.dart';

/// Запись общего edge-кэша метаданных аниме (`public.anime_meta_cache`).
class AnimeMetaCacheEntry {
  final String animeKey;
  final int? shikimoriId;
  final UserListsStats userStats;
  final List<String> screenshots;
  final List<AnimeVideoItem> videos;
  final List<RelatedAnimeRelease> relatedReleases;
  final List<ScoreDistributionItem> scoreDistribution;
  final Map<String, double> portalScores;
  final List<AnimeReview> externalReviews;
  final AnimeRatingAggregate? aggregate;
  final DateTime updatedAt;

  const AnimeMetaCacheEntry({
    required this.animeKey,
    this.shikimoriId,
    this.userStats = const UserListsStats(),
    this.screenshots = const [],
    this.videos = const [],
    this.relatedReleases = const [],
    this.scoreDistribution = const [],
    this.portalScores = const {},
    this.externalReviews = const [],
    this.aggregate,
    required this.updatedAt,
  });

  bool get isFresh =>
      DateTime.now().difference(updatedAt) < const Duration(hours: 24);

  Map<String, dynamic> toPayloadJson() {
    return {
      'shikimori_id': shikimoriId,
      'user_stats': {
        'watching': userStats.watching,
        'planned': userStats.planned,
        'on_hold': userStats.onHold,
        'dropped': userStats.dropped,
        'completed': userStats.completed,
      },
      'screenshots': screenshots,
      'videos': videos
          .map((v) => {
                'id': v.id,
                'title': v.title,
                'url': v.url,
                'image_url': v.imageUrl,
                'player_url': v.playerUrl,
                'kind': v.kind,
                'hosting': v.hosting,
                'published_at': v.publishedAt,
                'source': v.source,
              })
          .toList(),
      'related_releases': relatedReleases
          .map((r) => {
                'id': r.id,
                'title': r.title,
                'original_title': r.originalTitle,
                'year': r.year,
                'rating': r.rating,
                'kind': r.kind,
                'poster_url': r.posterUrl,
                'relation': r.relation,
                'is_current': r.isCurrent,
              })
          .toList(),
      'score_distribution': scoreDistribution
          .map((s) => {
                'score': s.score,
                'votes': s.votes,
                'percentage': s.percentage,
              })
          .toList(),
      'portal_scores': portalScores,
      'external_reviews': externalReviews.map((r) => r.toJson()).toList(),
      if (aggregate != null) 'aggregate': aggregate!.toJson(),
    };
  }

  factory AnimeMetaCacheEntry.fromRow(Map<String, dynamic> row) {
    final payload = (row['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final statsMap = (payload['user_stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawPortal = (payload['portal_scores'] as Map?) ?? {};
    final portalScores = <String, double>{};
    rawPortal.forEach((k, v) {
      final parsed = (v as num?)?.toDouble();
      if (parsed != null) portalScores['$k'] = parsed;
    });

    final videos = ((payload['videos'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) {
          final map = m.cast<String, dynamic>();
          return AnimeVideoItem(
            id: '${map['id'] ?? ''}',
            title: '${map['title'] ?? ''}',
            url: '${map['url'] ?? ''}',
            imageUrl: '${map['image_url'] ?? ''}',
            playerUrl: map['player_url'] as String?,
            kind: '${map['kind'] ?? 'pv'}',
            hosting: '${map['hosting'] ?? 'youtube'}',
            publishedAt: map['published_at'] as String?,
            source: '${map['source'] ?? 'YouTube'}',
          );
        })
        .toList();

    final related = ((payload['related_releases'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) {
          final map = m.cast<String, dynamic>();
          return RelatedAnimeRelease(
            id: '${map['id'] ?? ''}',
            title: '${map['title'] ?? ''}',
            originalTitle: map['original_title'] as String?,
            year: map['year'] as String?,
            rating: (map['rating'] as num?)?.toDouble(),
            kind: '${map['kind'] ?? 'Сериал'}',
            posterUrl: '${map['poster_url'] ?? ''}',
            relation: '${map['relation'] ?? ''}',
            isCurrent: map['is_current'] == true,
          );
        })
        .toList();

    final scores = ((payload['score_distribution'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) {
          final map = m.cast<String, dynamic>();
          return ScoreDistributionItem(
            score: (map['score'] as num?)?.toInt() ?? 0,
            votes: (map['votes'] as num?)?.toInt() ?? 0,
            percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
          );
        })
        .toList();

    final reviews = ((payload['external_reviews'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => AnimeReview.fromJson(m.cast<String, dynamic>()))
        .toList();

    final rawAgg = payload['aggregate'];
    final aggregate = rawAgg is Map
        ? AnimeRatingAggregate.fromJson(rawAgg.cast<String, dynamic>())
        : null;

    return AnimeMetaCacheEntry(
      animeKey: '${row['anime_key'] ?? ''}',
      shikimoriId: (row['shikimori_id'] as num?)?.toInt() ??
          (payload['shikimori_id'] as num?)?.toInt(),
      userStats: UserListsStats(
        watching: (statsMap['watching'] as num?)?.toInt() ?? 0,
        planned: (statsMap['planned'] as num?)?.toInt() ?? 0,
        onHold: (statsMap['on_hold'] as num?)?.toInt() ?? 0,
        dropped: (statsMap['dropped'] as num?)?.toInt() ?? 0,
        completed: (statsMap['completed'] as num?)?.toInt() ?? 0,
      ),
      screenshots: ((payload['screenshots'] as List?) ?? const [])
          .map((e) => '$e')
          .where((e) => e.isNotEmpty)
          .toList(),
      videos: videos,
      relatedReleases: related,
      scoreDistribution: scores,
      portalScores: portalScores,
      externalReviews: reviews,
      aggregate: aggregate,
      updatedAt:
          DateTime.tryParse('${row['updated_at'] ?? ''}') ?? DateTime.now(),
    );
  }
}

/// Общий кэш метаданных аниме в Supabase (`public.anime_meta_cache`, TTL 24 ч).
class AnimeMetaCacheService {
  static final AnimeMetaCacheService instance = AnimeMetaCacheService._();

  AnimeMetaCacheService._();

  static String buildAnimeKey(AnimeTitle title) {
    if (title.shikimoriId != null && title.shikimoriId! > 0) {
      return 'shiki_${title.shikimoriId}';
    }
    if (title.code.trim().isNotEmpty) {
      return 'code_${title.code.trim().toLowerCase()}';
    }
    if (title.id > 0) {
      return 'id_${title.id}';
    }
    return 'title_${title.displayTitle.trim().toLowerCase().hashCode.abs()}';
  }

  Future<AnimeMetaCacheEntry?> getFresh(AnimeTitle title) async {
    try {
      final client = Supabase.instance.client;
      final key = buildAnimeKey(title);
      final row = await client
          .from('anime_meta_cache')
          .select('anime_key, shikimori_id, payload, updated_at')
          .eq('anime_key', key)
          .maybeSingle()
          .timeout(const Duration(milliseconds: 1500));
      if (row == null) return null;
      final entry = AnimeMetaCacheEntry.fromRow(row);
      return entry.isFresh ? entry : null;
    } catch (e) {
      debugPrint('[AnimeMetaCache] lookup skipped: $e');
      return null;
    }
  }

  Future<void> upsert(AnimeTitle title, AnimeMetaCacheEntry entry) async {
    try {
      final client = Supabase.instance.client;
      final key = buildAnimeKey(title);
      await client.from('anime_meta_cache').upsert(
        {
          'anime_key': key,
          'shikimori_id': entry.shikimoriId ?? title.shikimoriId,
          'payload': entry.toPayloadJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'anime_key',
      );
    } catch (e) {
      debugPrint('[AnimeMetaCache] upsert skipped: $e');
    }
  }
}

