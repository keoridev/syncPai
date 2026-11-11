import '../../domain/entities/anime_entity.dart';

/// DTO модели таблицы anime_catalog в Supabase PostgreSQL / AniLiberty API
class AnimeCatalogModel {
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

  const AnimeCatalogModel({
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

  factory AnimeCatalogModel.fromShikimori(Map<dynamic, dynamic> json) {
    final shikiId = json['id'] is int
        ? json['id'] as int
        : int.tryParse(json['id']?.toString() ?? '') ?? 0;
    final russian = json['russian'] as String?;
    final name = json['name'] as String? ?? '';
    final titleRu = (russian != null && russian.trim().isNotEmpty) ? russian.trim() : name;

    String? posterUrl;
    if (json['image'] is Map) {
      final img = json['image'] as Map;
      final raw = (img['original'] ?? img['preview'] ?? img['x96'] ?? '')?.toString() ?? '';
      if (raw.isNotEmpty) {
        final withHost = raw.startsWith('http') ? raw : 'https://shikimori.io$raw';
        posterUrl = withHost
            .replaceFirst('https://shikimori.me', 'https://shikimori.io')
            .replaceFirst('https://shikimori.one', 'https://shikimori.io')
            .replaceFirst('http://shikimori.me', 'https://shikimori.io')
            .replaceFirst('http://shikimori.one', 'https://shikimori.io');
      }
    } else if (json['image'] is String) {
      final raw = json['image'] as String;
      if (raw.isNotEmpty) {
        final withHost = raw.startsWith('http') ? raw : 'https://shikimori.io$raw';
        posterUrl = withHost
            .replaceFirst('https://shikimori.me', 'https://shikimori.io')
            .replaceFirst('https://shikimori.one', 'https://shikimori.io')
            .replaceFirst('http://shikimori.me', 'https://shikimori.io')
            .replaceFirst('http://shikimori.one', 'https://shikimori.io');
      }
    } else if (json['poster_url'] is String) {
      final raw = json['poster_url'] as String;
      posterUrl = raw
          .replaceFirst('https://shikimori.me', 'https://shikimori.io')
          .replaceFirst('https://shikimori.one', 'https://shikimori.io')
          .replaceFirst('http://shikimori.me', 'https://shikimori.io')
          .replaceFirst('http://shikimori.one', 'https://shikimori.io');
    }

    final score = double.tryParse(json['score']?.toString() ?? '0.0') ?? 0.0;
    final episodes = json['episodes'] as int? ??
        (json['episodes_aired'] as int? ??
            ((json['episodes_total'] as num?)?.toInt() ?? 0));

    final fallback = shikiId > 0
        ? 'https://shikimori.io/system/animes/original/$shikiId.jpg'
        : (posterUrl ?? '');

    final int? year = (json['aired_on'] != null)
        ? DateTime.tryParse(json['aired_on'].toString())?.year
        : ((json['year'] as num?)?.toInt());
    final String description = json['description']?.toString() ?? '';
    final List<String> parsedShikiGenres = [];
    if (json['genres'] is List) {
      for (final g in json['genres'] as List) {
        if (g is Map && (g['russian'] ?? g['name']) != null) {
          parsedShikiGenres.add((g['russian'] ?? g['name']).toString());
        } else if (g is String && g.isNotEmpty) {
          parsedShikiGenres.add(g);
        }
      }
    }

    return AnimeCatalogModel(
      id: shikiId.toString(),
      shikimoriId: shikiId,
      titleRu: titleRu,
      titleEn: name,
      posterUrl: posterUrl,
      fallbackPosterUrl: fallback,
      kind: json['kind'] as String?,
      status: json['status'] as String? ?? 'ongoing',
      score: score,
      episodesTotal: episodes,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      year: year,
      description: description,
      genres: parsedShikiGenres,
    );
  }

  factory AnimeCatalogModel.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('image') && json['image'] is Map && !json.containsKey('poster') && !json.containsKey('shikimori')) {
      return AnimeCatalogModel.fromShikimori(json);
    }

    // 1. Извлечь ID Shikimori
    final int? shikiId = json['shikimori'] is Map
        ? (json['shikimori']['id'] as num?)?.toInt()
        : ((json['shikimori_id'] ?? json['shikimoriId']) as num?)?.toInt() ??
            int.tryParse(json['shikimori_id']?.toString() ?? '');
    final shikimoriId = shikiId ?? 0;

    // 2. Сформировать резервный постер (AniLibria):
    // Искать путь в json['poster']?['preview'] (или original)
    String aniLibriaPoster = '';
    if (json['poster'] is Map) {
      final pMap = json['poster'] as Map;
      final rawPath = pMap['preview'] ??
          (pMap['optimized'] is Map ? (pMap['optimized']['thumbnail'] ?? pMap['optimized']['url']) : null) ??
          (pMap['original'] is Map ? (pMap['original']['url'] ?? pMap['original']['src']) : pMap['original']) ??
          pMap['url'] ??
          pMap['src'];
      if (rawPath != null && rawPath.toString().isNotEmpty) {
        final pathStr = rawPath.toString();
        aniLibriaPoster = pathStr.startsWith('http') ? pathStr : 'https://anilibria.top$pathStr';
      }
    } else {
      final raw = (json['fallback_poster_url'] ?? json['poster_url'] ?? json['image'])?.toString();
      if (raw != null && raw.isNotEmpty) {
        aniLibriaPoster = raw.startsWith('http') ? raw : 'https://anilibria.top$raw';
      }
    }

    // 3. Сформировать основной и резервный постеры
    final String primaryPoster;
    if (json['poster_url'] != null && json['poster_url'].toString().isNotEmpty) {
      primaryPoster = json['poster_url'].toString();
    } else if (aniLibriaPoster.isNotEmpty) {
      primaryPoster = aniLibriaPoster;
    } else if (shikiId != null && shikiId > 0) {
      primaryPoster = 'https://shikimori.io/system/animes/original/$shikiId.jpg';
    } else {
      primaryPoster = '';
    }

    final String fallbackPoster = (shikiId != null && shikiId > 0)
        ? 'https://shikimori.io/system/animes/original/$shikiId.jpg'
        : (aniLibriaPoster.isNotEmpty ? aniLibriaPoster : primaryPoster);

    // 4. Заполнить названия: titleRu брать из json['name']?['main'], titleEn из json['name']?['english']
    final String titleRu;
    if (json['name'] is Map) {
      titleRu = json['name']['main']?.toString() ?? '';
    } else {
      titleRu = json['title_ru'] as String? ?? json['russian'] as String? ?? '';
    }

    final String titleEn;
    if (json['name'] is Map) {
      titleEn = json['name']['english']?.toString() ?? '';
    } else {
      titleEn = json['title_en'] as String? ?? json['name'] as String? ?? '';
    }

    // 5. Ссылку на плеер Kodik брать из json['external_player']
    final String? externalPlayer = json['external_player']?.toString();

    // 6. Парсинг года и описания
    final int? year = (json['year'] as num?)?.toInt() ??
        (json['season'] is Map ? (json['season']['year'] as num?)?.toInt() : null);
    final String description = json['description']?.toString() ?? '';

    // 7. Парсинг жанров (в AniLibria API v1 жанры приходят как список объектов [{"id": 21, "name": "Комедия"}])
    final List<String> parsedGenres = [];
    if (json['genres'] != null && json['genres'] is List) {
      for (var g in json['genres']) {
        if (g is String && g.isNotEmpty) {
          parsedGenres.add(g);
        } else if (g is Map && g['name'] != null) {
          parsedGenres.add(g['name'].toString());
        }
      }
    }

    final String nativeId = json['id'] != null
        ? json['id'].toString()
        : (shikimoriId > 0 ? shikimoriId.toString() : '0');

    return AnimeCatalogModel(
      id: nativeId,
      shikimoriId: shikimoriId,
      titleRu: titleRu,
      titleEn: titleEn,
      posterUrl: primaryPoster,
      fallbackPosterUrl: fallbackPoster,
      kind: json['kind'] as String?,
      status: json['status'] as String? ?? 'ongoing',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      episodesTotal: (json['episodes_total'] as num?)?.toInt() ??
          (json['episodes'] as num?)?.toInt() ??
          0,
      externalPlayer: externalPlayer,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      year: year,
      description: description,
      genres: parsedGenres,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shikimori_id': shikimoriId,
      'title_ru': titleRu,
      'title_en': titleEn,
      if (posterUrl != null) 'poster_url': posterUrl,
      'fallback_poster_url': fallbackPosterUrl,
      if (kind != null) 'kind': kind,
      'status': status,
      'score': score,
      'episodes_total': episodesTotal,
      if (externalPlayer != null) 'external_player': externalPlayer,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (year != null) 'year': year,
      if (description.isNotEmpty) 'description': description,
      if (genres.isNotEmpty) 'genres': genres,
    };
  }

  AnimeEntity toDomain() {
    return AnimeEntity(
      id: id,
      shikimoriId: shikimoriId,
      titleRu: titleRu,
      titleEn: titleEn,
      posterUrl: posterUrl,
      fallbackPosterUrl: fallbackPosterUrl,
      kind: kind,
      status: status,
      score: score,
      episodesTotal: episodesTotal,
      externalPlayer: externalPlayer,
      updatedAt: updatedAt,
      year: year,
      description: description,
      genres: genres,
    );
  }
}

