import '../../domain/entities/anime_clip.dart';

/// Модель данных момента аниме (Anime Moment) из Supabase таблицы `anime_moments`
class AnimeMomentModel {
  final String id;
  final String animeId; // AniLibria ID для перехода к просмотру
  final String title; // Название аниме
  final String description; // Описание момента
  final int episode; // Номер серии
  final int startTimestamp; // Таймкод момента в секундах
  final String videoUrl; // Прямой URL к оптимизированному MP4 или HLS
  final String? youtubeId; // Исходный ID YouTube Shorts
  final int likesCount;

  const AnimeMomentModel({
    required this.id,
    required this.animeId,
    required this.title,
    required this.description,
    required this.episode,
    required this.startTimestamp,
    required this.videoUrl,
    this.youtubeId,
    this.likesCount = 0,
  });

  factory AnimeMomentModel.fromJson(Map<String, dynamic> json) {
    return AnimeMomentModel(
      id: json['id'].toString(),
      animeId: json['anime_id'].toString(),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      episode: (json['episode'] as num?)?.toInt() ?? 1,
      startTimestamp: (json['start_timestamp'] as num?)?.toInt() ?? 0,
      videoUrl: json['video_url'] as String? ?? '',
      youtubeId: json['youtube_id'] as String?,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'anime_id': animeId,
      'title': title,
      'description': description,
      'episode': episode,
      'start_timestamp': startTimestamp,
      'video_url': videoUrl,
      if (youtubeId != null) 'youtube_id': youtubeId,
      'likes_count': likesCount,
    };
  }

  /// Преобразование в сущность предметной области [AnimeClip]
  AnimeClip toDomain({String? posterUrl}) {
    final parsedId = int.tryParse(animeId) ?? 0;
    return AnimeClip(
      id: id,
      animeId: parsedId,
      animeTitle: title,
      englishTitle: '',
      posterUrl: posterUrl ??
          'https://desu.shikimori.one/system/animes/original/$animeId.jpg',
      episodeNumber: episode,
      targetTimestampSeconds: startTimestamp,
      caption: description,
      videoUrl: videoUrl,
      youtubeUrl: youtubeId != null && youtubeId!.isNotEmpty
          ? 'https://www.youtube.com/watch?v=$youtubeId'
          : null,
      youtubeId: youtubeId,
      likesCount: likesCount,
      authorName: 'SyncPai Moments',
      tags: const ['#аниме', '#моменты', '#shorts'],
    );
  }
}

