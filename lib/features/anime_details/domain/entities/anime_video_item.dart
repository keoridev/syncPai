import 'package:equatable/equatable.dart';

/// Видеоматериал по тайтлу (PV-тизеры, официальные трейлеры, промо-ролики).
class AnimeVideoItem extends Equatable {
  final String id;
  final String title;
  final String url;
  final String imageUrl;
  final String? playerUrl;
  final String kind; // 'pv', 'trailer', 'teaser'
  final String hosting; // 'youtube', 'other'
  final String? publishedAt;
  final String source;

  const AnimeVideoItem({
    required this.id,
    required this.title,
    required this.url,
    required this.imageUrl,
    this.playerUrl,
    this.kind = 'pv',
    this.hosting = 'youtube',
    this.publishedAt,
    this.source = 'YouTube',
  });

  @override
  List<Object?> get props => [
        id,
        title,
        url,
        imageUrl,
        playerUrl,
        kind,
        hosting,
        publishedAt,
        source,
      ];
}

