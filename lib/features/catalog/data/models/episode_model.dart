import '../../domain/entities/episode_entity.dart';

/// DTO модели серии с прямой ссылкой на видеопоток
class EpisodeModel {
  final int episode;
  final String link;

  const EpisodeModel({
    required this.episode,
    required this.link,
  });

  factory EpisodeModel.fromJson(Map<String, dynamic> json) {
    return EpisodeModel(
      episode: (json['episode'] as num?)?.toInt() ?? 1,
      link: json['link'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'episode': episode,
      'link': link,
    };
  }

  EpisodeEntity toDomain() {
    return EpisodeEntity(
      episode: episode,
      link: link,
    );
  }
}

