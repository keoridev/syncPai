import '../../domain/entities/translation_entity.dart';
import 'episode_model.dart';

/// DTO модели перевода и видеопотока из Supabase Edge Function
class TranslationModel {
  final String studioName;
  final String translationType;
  final bool isDirectStream;
  final List<EpisodeModel> episodes;
  final String? iframeUrl;

  const TranslationModel({
    required this.studioName,
    required this.translationType,
    required this.isDirectStream,
    this.episodes = const [],
    this.iframeUrl,
  });

  factory TranslationModel.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'] as List<dynamic>? ?? [];
    return TranslationModel(
      studioName: json['studio_name'] as String? ?? 'Озвучка',
      translationType: json['translation_type'] as String? ?? 'dub',
      isDirectStream: json['is_direct_stream'] as bool? ?? false,
      episodes: rawEpisodes
          .whereType<Map<String, dynamic>>()
          .map((e) => EpisodeModel.fromJson(e))
          .toList(),
      iframeUrl: json['iframe_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studio_name': studioName,
      'translation_type': translationType,
      'is_direct_stream': isDirectStream,
      'episodes': episodes.map((e) => e.toJson()).toList(),
      if (iframeUrl != null) 'iframe_url': iframeUrl,
    };
  }

  TranslationEntity toDomain() {
    return TranslationEntity(
      studioName: studioName,
      translationType: translationType,
      isDirectStream: isDirectStream,
      episodes: episodes.map((e) => e.toDomain()).toList(),
      iframeUrl: iframeUrl,
    );
  }
}
