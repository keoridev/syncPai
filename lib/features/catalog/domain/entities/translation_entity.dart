import 'package:equatable/equatable.dart';
import 'episode_entity.dart';

/// Сущность варианта озвучки или субтитров от балансеров
class TranslationEntity extends Equatable {
  final String studioName;
  final String translationType; // 'dub' | 'sub' | 'raw'
  final bool isDirectStream;
  final List<EpisodeEntity> episodes;
  final String? iframeUrl;

  const TranslationEntity({
    required this.studioName,
    required this.translationType,
    required this.isDirectStream,
    this.episodes = const [],
    this.iframeUrl,
  });

  /// Быстрое получение ссылки на видеопоток для конкретной серии
  String? getStreamForEpisode(int episodeNum) {
    if (!isDirectStream || episodes.isEmpty) return null;
    final match = episodes.firstWhere(
      (e) => e.episode == episodeNum,
      orElse: () => episodes.first,
    );
    return match.link;
  }

  @override
  List<Object?> get props => [
        studioName,
        translationType,
        isDirectStream,
        episodes,
        iframeUrl,
      ];
}

