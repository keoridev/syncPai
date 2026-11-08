import '../../domain/entities/translation_entity.dart';
import 'episode_model.dart';
import 'translation_model.dart';

/// DTO ответа Edge Function get_anime_player_data
class AnimePlayerDataModel {
  final int shikimoriId;
  final String source;
  final String? title;
  final List<EpisodeModel> episodes;
  final List<TranslationModel> translations;
  final String? error;

  const AnimePlayerDataModel({
    required this.shikimoriId,
    this.source = 'anilibria',
    this.title,
    this.episodes = const [],
    required this.translations,
    this.error,
  });

  factory AnimePlayerDataModel.fromJson(Map<String, dynamic> json) {
    final rawTranslations = json['translations'] as List<dynamic>? ?? [];
    final rawEpisodes = json['episodes'] as List<dynamic>? ?? [];
    final episodes = rawEpisodes
        .whereType<Map<String, dynamic>>()
        .map((e) => EpisodeModel.fromJson(e))
        .toList();

    return AnimePlayerDataModel(
      shikimoriId: (json['shikimori_id'] as num?)?.toInt() ?? 0,
      source: (json['source'] as String?) ?? 'anilibria',
      title: json['title'] as String?,
      episodes: episodes,
      translations: rawTranslations
          .whereType<Map<String, dynamic>>()
          .map((t) => TranslationModel.fromJson(t))
          .toList(),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shikimori_id': shikimoriId,
      'source': source,
      if (title != null) 'title': title,
      'episodes': episodes.map((e) => e.toJson()).toList(),
      'translations': translations.map((t) => t.toJson()).toList(),
      if (error != null) 'error': error,
    };
  }

  List<TranslationEntity> toDomain() {
    return translations.map((t) => t.toDomain()).toList();
  }
}

