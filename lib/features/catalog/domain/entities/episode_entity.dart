import 'package:equatable/equatable.dart';
import 'episode_item.dart';

/// Сущность серии с прямой ссылкой на видеопоток и расширенными метаданными (FHD/HD/SD, скипы, превью)
class EpisodeEntity extends Equatable {
  final int episode;
  final String link;
  final String? name;
  final String? fhd;
  final String? hd;
  final String? sd;
  final String? preview;
  final TimecodeRange? opening;
  final TimecodeRange? ending;

  const EpisodeEntity({
    required this.episode,
    required this.link,
    this.name,
    this.fhd,
    this.hd,
    this.sd,
    this.preview,
    this.opening,
    this.ending,
  });

  EpisodeItem toEpisodeItem() {
    return EpisodeItem(
      episode: episode,
      name: name,
      previewUrl: preview,
      sdUrl: sd ?? link,
      hdUrl: hd ?? link,
      fhdUrl: fhd ?? hd ?? link,
      opening: opening,
      ending: ending,
    );
  }

  @override
  List<Object?> get props => [
        episode,
        link,
        name,
        fhd,
        hd,
        sd,
        preview,
        opening,
        ending,
      ];
}

