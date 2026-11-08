import 'package:equatable/equatable.dart';

/// Сущность серии с прямой ссылкой на видеопоток
class EpisodeEntity extends Equatable {
  final int episode;
  final String link;

  const EpisodeEntity({
    required this.episode,
    required this.link,
  });

  @override
  List<Object?> get props => [episode, link];
}

