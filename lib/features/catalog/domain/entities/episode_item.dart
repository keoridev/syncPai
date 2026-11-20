import 'package:equatable/equatable.dart';

/// Таймкоды фрагмента (опенинг или эндинг в секундах)
class TimecodeRange extends Equatable {
  final int start;
  final int stop;

  const TimecodeRange({
    required this.start,
    required this.stop,
  });

  /// Форматированная строка вида: "01:31 – 03:01"
  String get formattedRange {
    final startMin = (start ~/ 60).toString().padLeft(2, '0');
    final startSec = (start % 60).toString().padLeft(2, '0');
    final stopMin = (stop ~/ 60).toString().padLeft(2, '0');
    final stopSec = (stop % 60).toString().padLeft(2, '0');
    return '$startMin:$startSec – $stopMin:$stopSec';
  }

  Duration get startDuration => Duration(seconds: start);
  Duration get stopDuration => Duration(seconds: stop);

  Map<String, dynamic> toJson() => {
        'start': start,
        'stop': stop,
      };

  factory TimecodeRange.fromJson(Map<String, dynamic> json) => TimecodeRange(
        start: json['start'] as int? ?? 0,
        stop: json['stop'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [start, stop];
}

class EpisodeItem extends Equatable {
  final int episode;
  final String? name;
  final String? previewUrl;
  final String? sdUrl;
  final String? hdUrl;
  final String? fhdUrl;
  final TimecodeRange? opening;
  final TimecodeRange? ending;
  final String? youtubeId;
  final String? rutubeId;

  const EpisodeItem({
    required this.episode,
    this.name,
    this.previewUrl,
    this.sdUrl,
    this.hdUrl,
    this.fhdUrl,
    this.opening,
    this.ending,
    this.youtubeId,
    this.rutubeId,
  });

  /// Получить URL наилучшего доступного качества (FHD -> HD -> SD)
  String? get bestAvailableUrl => fhdUrl ?? hdUrl ?? sdUrl;

  /// Получить ссылку по указанному качеству (1080p FHD, 720p HD, 480p SD)
  String getUrlForQuality(String quality) {
    if (quality.contains('1080') || quality.toLowerCase().contains('fhd')) {
      return fhdUrl ?? hdUrl ?? sdUrl ?? '';
    } else if (quality.contains('720') || quality.toLowerCase().contains('hd')) {
      return hdUrl ?? fhdUrl ?? sdUrl ?? '';
    } else {
      return sdUrl ?? hdUrl ?? fhdUrl ?? '';
    }
  }

  Map<String, dynamic> toJson() => {
        'episode': episode,
        'name': name,
        'previewUrl': previewUrl,
        'sdUrl': sdUrl,
        'hdUrl': hdUrl,
        'fhdUrl': fhdUrl,
        'opening': opening?.toJson(),
        'ending': ending?.toJson(),
        'youtubeId': youtubeId,
        'rutubeId': rutubeId,
      };

  factory EpisodeItem.fromJson(Map<String, dynamic> json) => EpisodeItem(
        episode: json['episode'] as int? ?? 1,
        name: json['name'] as String?,
        previewUrl: json['previewUrl'] as String?,
        sdUrl: json['sdUrl'] as String?,
        hdUrl: json['hdUrl'] as String?,
        fhdUrl: json['fhdUrl'] as String?,
        opening: json['opening'] is Map
            ? TimecodeRange.fromJson(Map<String, dynamic>.from(json['opening'] as Map))
            : null,
        ending: json['ending'] is Map
            ? TimecodeRange.fromJson(Map<String, dynamic>.from(json['ending'] as Map))
            : null,
        youtubeId: json['youtubeId'] as String?,
        rutubeId: json['rutubeId'] as String?,
      );

  @override
  List<Object?> get props => [
        episode,
        name,
        previewUrl,
        sdUrl,
        hdUrl,
        fhdUrl,
        opening,
        ending,
        youtubeId,
        rutubeId,
      ];
}
