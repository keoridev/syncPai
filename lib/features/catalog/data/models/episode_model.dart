import '../../domain/entities/episode_entity.dart';
import '../../domain/entities/episode_item.dart';

/// DTO модели серии с прямой ссылкой на видеопоток и расширенными метаданными AniLibria
class EpisodeModel {
  final int episode;
  final String link;
  final String? name;
  final String? fhd;
  final String? hd;
  final String? sd;
  final String? preview;
  final TimecodeRange? opening;
  final TimecodeRange? ending;

  const EpisodeModel({
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

  factory EpisodeModel.fromJson(Map<String, dynamic> json) {
    TimecodeRange? opRange;
    TimecodeRange? edRange;
    final skips = json['skips'] as Map?;
    if (skips != null) {
      final op = skips['opening'] as List?;
      if (op != null && op.length >= 2) {
        opRange = TimecodeRange(
          start: (op[0] as num).toInt(),
          stop: (op[1] as num).toInt(),
        );
      }
      final ed = skips['ending'] as List?;
      if (ed != null && ed.length >= 2) {
        edRange = TimecodeRange(
          start: (ed[0] as num).toInt(),
          stop: (ed[1] as num).toInt(),
        );
      }
    } else {
      if (json['opening'] is Map) {
        final op = json['opening'] as Map;
        if (op['start'] != null && op['stop'] != null) {
          opRange = TimecodeRange(
            start: (op['start'] as num).toInt(),
            stop: (op['stop'] as num).toInt(),
          );
        }
      }
      if (json['ending'] is Map) {
        final ed = json['ending'] as Map;
        if (ed['start'] != null && ed['stop'] != null) {
          edRange = TimecodeRange(
            start: (ed['start'] as num).toInt(),
            stop: (ed['stop'] as num).toInt(),
          );
        }
      }
    }

    final link = (json['link'] ?? json['fhd'] ?? json['hd'] ?? json['sd'] ?? '') as String;

    final previewPath = (json['preview'] ?? json['preview_url'] ?? json['thumbnail'] ?? (json['poster'] is Map ? (json['poster']['preview'] ?? json['poster']['src']) : null))?.toString();
    final fullPreviewUrl = (previewPath != null && previewPath.isNotEmpty)
        ? (previewPath.startsWith('http') ? previewPath : 'https://anilibria.top$previewPath')
        : null;

    return EpisodeModel(
      episode: (json['episode'] as num?)?.toInt() ?? (json['ordinal'] as num?)?.toInt() ?? 1,
      link: link,
      name: json['name'] as String?,
      fhd: json['fhd'] as String?,
      hd: json['hd'] as String?,
      sd: json['sd'] as String?,
      preview: fullPreviewUrl,
      opening: opRange,
      ending: edRange,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'episode': episode,
      'link': link,
      if (name != null) 'name': name,
      if (fhd != null) 'fhd': fhd,
      if (hd != null) 'hd': hd,
      if (sd != null) 'sd': sd,
      if (preview != null) 'preview': preview,
      if (opening != null)
        'skips': {
          'opening': [opening!.start, opening!.stop],
          if (ending != null) 'ending': [ending!.start, ending!.stop],
        },
    };
  }

  EpisodeEntity toDomain() {
    return EpisodeEntity(
      episode: episode,
      link: link,
      name: name,
      fhd: fhd,
      hd: hd,
      sd: sd,
      preview: preview,
      opening: opening,
      ending: ending,
    );
  }
}

