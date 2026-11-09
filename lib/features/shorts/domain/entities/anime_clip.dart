import 'package:equatable/equatable.dart';

/// Модель аниме-клипа / шортса для «Ленты моментов»
class AnimeClip extends Equatable {
  final String id;
  final int animeId;
  final String animeTitle;
  final String englishTitle;
  final String posterUrl;
  final int episodeNumber;
  final int targetTimestampSeconds;
  final String caption;
  final String videoUrl;
  final String? youtubeUrl;
  final String? youtubeId;
  final int likesCount;
  final String authorName;
  final List<String> tags;
  final bool isLiked;
  final bool isBookmarked;

  const AnimeClip({
    required this.id,
    required this.animeId,
    required this.animeTitle,
    required this.englishTitle,
    required this.posterUrl,
    required this.episodeNumber,
    required this.targetTimestampSeconds,
    required this.caption,
    required this.videoUrl,
    this.youtubeUrl,
    this.youtubeId,
    this.likesCount = 0,
    this.authorName = 'SyncPai Moments',
    this.tags = const [],
    this.isLiked = false,
    this.isBookmarked = false,
  });

  /// Форматированный таймкод в формате ММ:СС или ЧЧ:ММ:СС
  String get formattedTimestamp {
    final d = Duration(seconds: targetTimestampSeconds);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  /// Понятный текстовый бейдж серии и времени
  String get timecodeLabel => 'Серия $episodeNumber • $formattedTimestamp';

  AnimeClip copyWith({
    String? id,
    int? animeId,
    String? animeTitle,
    String? englishTitle,
    String? posterUrl,
    int? episodeNumber,
    int? targetTimestampSeconds,
    String? caption,
    String? videoUrl,
    String? youtubeUrl,
    String? youtubeId,
    int? likesCount,
    String? authorName,
    List<String>? tags,
    bool? isLiked,
    bool? isBookmarked,
  }) {
    return AnimeClip(
      id: id ?? this.id,
      animeId: animeId ?? this.animeId,
      animeTitle: animeTitle ?? this.animeTitle,
      englishTitle: englishTitle ?? this.englishTitle,
      posterUrl: posterUrl ?? this.posterUrl,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      targetTimestampSeconds: targetTimestampSeconds ?? this.targetTimestampSeconds,
      caption: caption ?? this.caption,
      videoUrl: videoUrl ?? this.videoUrl,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      youtubeId: youtubeId ?? this.youtubeId,
      likesCount: likesCount ?? this.likesCount,
      authorName: authorName ?? this.authorName,
      tags: tags ?? this.tags,
      isLiked: isLiked ?? this.isLiked,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'animeId': animeId,
      'animeTitle': animeTitle,
      'englishTitle': englishTitle,
      'posterUrl': posterUrl,
      'episodeNumber': episodeNumber,
      'targetTimestampSeconds': targetTimestampSeconds,
      'caption': caption,
      'videoUrl': videoUrl,
      'youtubeUrl': youtubeUrl,
      if (youtubeId != null) 'youtubeId': youtubeId,
      'likesCount': likesCount,
      'authorName': authorName,
      'tags': tags,
      'isLiked': isLiked,
      'isBookmarked': isBookmarked,
    };
  }

  factory AnimeClip.fromJson(Map<String, dynamic> json) {
    return AnimeClip(
      id: json['id'] as String? ?? '',
      animeId: (json['animeId'] as num?)?.toInt() ?? 0,
      animeTitle: json['animeTitle'] as String? ?? '',
      englishTitle: json['englishTitle'] as String? ?? '',
      posterUrl: json['posterUrl'] as String? ?? '',
      episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 1,
      targetTimestampSeconds: (json['targetTimestampSeconds'] as num?)?.toInt() ?? 0,
      caption: json['caption'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      youtubeUrl: json['youtubeUrl'] as String?,
      youtubeId: json['youtubeId'] as String?,
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      authorName: json['authorName'] as String? ?? 'SyncPai Moments',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      isLiked: json['isLiked'] as bool? ?? false,
      isBookmarked: json['isBookmarked'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        animeId,
        animeTitle,
        englishTitle,
        posterUrl,
        episodeNumber,
        targetTimestampSeconds,
        caption,
        videoUrl,
        youtubeUrl,
        youtubeId,
        likesCount,
        authorName,
        tags,
        isLiked,
        isBookmarked,
      ];
}
