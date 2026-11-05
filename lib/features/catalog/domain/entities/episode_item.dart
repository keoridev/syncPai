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
