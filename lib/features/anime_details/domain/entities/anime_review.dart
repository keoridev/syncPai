import 'package:equatable/equatable.dart';

/// Источник отзыва или рецензии
enum ReviewSource {
  syncpai,
  shikimori,
  mal,
  anilibria;

  String get displayName {
    switch (this) {
      case ReviewSource.syncpai:
        return 'SyncPai';
      case ReviewSource.shikimori:
        return 'Shikimori';
      case ReviewSource.mal:
        return 'MyAnimeList';
      case ReviewSource.anilibria:
        return 'AniLibria';
    }
  }

  static ReviewSource fromString(String? val) {
    if (val == null) return ReviewSource.shikimori;
    final lower = val.toLowerCase().trim();
    if (lower.contains('sync') || lower.contains('pai')) return ReviewSource.syncpai;
    if (lower.contains('mal') || lower.contains('myanimelist')) return ReviewSource.mal;
    if (lower.contains('anilibria') || lower.contains('либри')) return ReviewSource.anilibria;
    return ReviewSource.shikimori;
  }
}

/// Тональность отзыва
enum ReviewSentiment {
  positive,
  neutral,
  negative;

  String get displayName {
    switch (this) {
      case ReviewSentiment.positive:
        return 'Положительный';
      case ReviewSentiment.neutral:
        return 'Нейтральный';
      case ReviewSentiment.negative:
        return 'Критика';
    }
  }

  static ReviewSentiment fromScore(double? score) {
    if (score == null) return ReviewSentiment.neutral;
    if (score >= 7.0) return ReviewSentiment.positive;
    if (score < 5.0) return ReviewSentiment.negative;
    return ReviewSentiment.neutral;
  }

  static ReviewSentiment fromString(String? val) {
    if (val == null) return ReviewSentiment.neutral;
    final lower = val.toLowerCase().trim();
    if (lower.contains('pos') || lower.contains('положительн')) return ReviewSentiment.positive;
    if (lower.contains('neg') || lower.contains('критик') || lower.contains('отрицательн')) return ReviewSentiment.negative;
    return ReviewSentiment.neutral;
  }
}

/// Единая неизменяемая доменная модель отзыва зрителя (Shikimori, MAL, SyncPai)
class AnimeReview extends Equatable {
  final String id;
  final ReviewSource source;
  final String authorName;
  final String? authorAvatarUrl;
  final double? score; // Нормализованная оценка от 1.0 до 10.0
  final ReviewSentiment sentiment;
  final String content; // Санитизированный чистый текст
  final bool containsSpoiler;
  final DateTime createdAt;
  final String? originalUrl;
  final int likes;

  const AnimeReview({
    required this.id,
    required this.source,
    required this.authorName,
    this.authorAvatarUrl,
    this.score,
    required this.sentiment,
    required this.content,
    this.containsSpoiler = false,
    required this.createdAt,
    this.originalUrl,
    this.likes = 0,
  });

  // Геттеры для обратной совместимости с существующими виджетами
  String get author => authorName;
  String get avatar => authorAvatarUrl ?? '';
  String get text => content;
  double get scoreOrZero => score ?? 0.0;
  String get sourceName => source.displayName;
  bool get isSpoiler => containsSpoiler;

  /// Относительный формат даты публикации
  String get date {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes < 2) return 'Только что';
        return '${diff.inMinutes} мин. назад';
      }
      return '${diff.inHours} ч. назад';
    } else if (diff.inDays == 1) {
      return 'Вчера';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} дн. назад';
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks нед. назад';
    } else if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return '$months мес. назад';
    } else {
      return '${createdAt.day.toString().padLeft(2, '0')}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year}';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source.name,
      'author_name': authorName,
      'author_avatar_url': authorAvatarUrl,
      'score': score,
      'sentiment': sentiment.name,
      'content': content,
      'contains_spoiler': containsSpoiler,
      'is_spoiler': containsSpoiler,
      'created_at': createdAt.toIso8601String(),
      'original_url': originalUrl,
      'likes': likes,
    };
  }

  factory AnimeReview.fromJson(Map<String, dynamic> json) {
    final parsedScore = json['score'] != null ? (json['score'] as num).toDouble() : null;
    final sentimentStr = json['sentiment'] as String?;
    final sentiment = sentimentStr != null
        ? ReviewSentiment.fromString(sentimentStr)
        : ReviewSentiment.fromScore(parsedScore);

    DateTime parsedDate;
    if (json['created_at'] != null) {
      parsedDate = DateTime.tryParse('${json['created_at']}') ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return AnimeReview(
      id: '${json['id'] ?? ''}',
      source: ReviewSource.fromString(json['source'] as String?),
      authorName: json['author_name'] as String? ?? json['author'] as String? ?? 'Анонимный зритель',
      authorAvatarUrl: json['author_avatar_url'] as String? ?? json['avatar'] as String?,
      score: parsedScore,
      sentiment: sentiment,
      content: json['content'] as String? ?? json['text'] as String? ?? '',
      containsSpoiler: json['is_spoiler'] as bool? ?? json['contains_spoiler'] as bool? ?? false,
      createdAt: parsedDate,
      originalUrl: json['original_url'] as String?,
      likes: json['likes'] as int? ?? 0,
    );
  }

  AnimeReview copyWith({
    String? id,
    ReviewSource? source,
    String? authorName,
    String? authorAvatarUrl,
    double? score,
    ReviewSentiment? sentiment,
    String? content,
    bool? containsSpoiler,
    DateTime? createdAt,
    String? originalUrl,
    int? likes,
  }) {
    return AnimeReview(
      id: id ?? this.id,
      source: source ?? this.source,
      authorName: authorName ?? this.authorName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      score: score ?? this.score,
      sentiment: sentiment ?? this.sentiment,
      content: content ?? this.content,
      containsSpoiler: containsSpoiler ?? this.containsSpoiler,
      createdAt: createdAt ?? this.createdAt,
      originalUrl: originalUrl ?? this.originalUrl,
      likes: likes ?? this.likes,
    );
  }

  @override
  List<Object?> get props => [
        id,
        source,
        authorName,
        authorAvatarUrl,
        score,
        sentiment,
        content,
        containsSpoiler,
        createdAt,
        originalUrl,
        likes,
      ];
}
