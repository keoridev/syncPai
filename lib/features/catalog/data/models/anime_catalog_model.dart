import '../../domain/entities/anime_entity.dart';

/// DTO модели таблицы anime_catalog в Supabase PostgreSQL
class AnimeCatalogModel {
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

  const AnimeCatalogModel({
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

  factory AnimeCatalogModel.fromShikimori(Map<String, dynamic> json) {
    final shikiId = json['id'] is int
        ? json['id'] as int
        : int.tryParse(json['id']?.toString() ?? '') ?? 0;
    final russian = json['russian'] as String?;
    final name = json['name'] as String? ?? '';
    final titleRu = (russian != null && russian.trim().isNotEmpty) ? russian.trim() : name;

    String? posterUrl;
    if (json['image'] is Map<String, dynamic>) {
      final img = json['image'] as Map<String, dynamic>;
      final raw = (img['original'] ?? img['preview'] ?? '') as String;
      if (raw.isNotEmpty) {
        posterUrl = raw.startsWith('http') ? raw : 'https://shikimori.me$raw';
      }
    } else if (json['image'] is String) {
      final raw = json['image'] as String;
      if (raw.isNotEmpty) {
        posterUrl = raw.startsWith('http') ? raw : 'https://shikimori.me$raw';
      }
    } else if (json['poster_url'] is String) {
      posterUrl = json['poster_url'] as String;
    }

    final score = double.tryParse(json['score']?.toString() ?? '0.0') ?? 0.0;
    final episodes = json['episodes'] as int? ??
        (json['episodes_aired'] as int? ??
            ((json['episodes_total'] as num?)?.toInt() ?? 0));

    return AnimeCatalogModel(
      id: shikiId.toString(),
      shikimoriId: shikiId,
      titleRu: titleRu,
      titleEn: name,
      posterUrl: posterUrl,
      kind: json['kind'] as String?,
      status: json['status'] as String? ?? 'ongoing',
      score: score,
      episodesTotal: episodes,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  factory AnimeCatalogModel.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('image') && json['image'] is Map) {
      return AnimeCatalogModel.fromShikimori(json);
    }
    final rawShikiId = json['shikimori_id'] ?? json['id'];
    final shikimoriId = (rawShikiId is num)
        ? rawShikiId.toInt()
        : int.tryParse(rawShikiId?.toString() ?? '') ?? 0;

    return AnimeCatalogModel(
      id: json['id']?.toString() ?? shikimoriId.toString(),
      shikimoriId: shikimoriId,
      titleRu: json['title_ru'] as String? ?? json['russian'] as String? ?? '',
      titleEn: json['title_en'] as String? ?? json['name'] as String? ?? '',
      posterUrl: json['poster_url'] as String? ?? json['image'] as String?,
      kind: json['kind'] as String?,
      status: json['status'] as String? ?? 'ongoing',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      episodesTotal: (json['episodes_total'] as num?)?.toInt() ??
          (json['episodes'] as num?)?.toInt() ??
          0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shikimori_id': shikimoriId,
      'title_ru': titleRu,
      'title_en': titleEn,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (kind != null) 'kind': kind,
      'status': status,
      'score': score,
      'episodes_total': episodesTotal,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  AnimeEntity toDomain() {
    return AnimeEntity(
      id: id,
      shikimoriId: shikimoriId,
      titleRu: titleRu,
      titleEn: titleEn,
      posterUrl: posterUrl,
      kind: kind,
      status: status,
      score: score,
      episodesTotal: episodesTotal,
      updatedAt: updatedAt,
    );
  }
}

